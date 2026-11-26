"""Local, timing-hint-free replay of registered RF-Stream-PHY coax recordings."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import zlib

import numpy as np
import source_phy as phy


ACQUISITION_THRESHOLD = 0.18
METHODS = ("phase", "pilot_complex_ls")
N, CP, USED, PILOTS, DATA = phy.N, phy.CP, phy.USED, phy.PILOTS, phy.DATA


def waveform_layout(cfg):
    if (cfg["bps"], cfg["ref_len"], cfg["repeat"], cfg["ref_len"] == cfg["chunk_bytes"]) != (
        {"qpsk": 2, "qam16": 4}[cfg["modulation"]],
        512,
        1,
        True,
    ):
        raise ValueError("unsupported source packet layout")
    short = CP + N * cfg["stf_repeats"]
    data_symbols = math.ceil(8 * (cfg["ref_len"] + 14) / (len(DATA) * cfg["bps"]))
    preamble = short + (N + CP) * cfg["ltf_symbols"]
    return short, preamble, data_symbols


def training():
    even = USED[USED % 2 == 0]
    spectrum = np.zeros(N, complex)
    spectrum[even % N] = np.random.default_rng(42).choice([-1.0, 1.0], size=len(even))
    short = np.fft.ifft(np.fft.ifftshift(spectrum)) * np.sqrt(N)
    signs = (-1.0) ** np.arange(len(USED))
    spectrum[:] = 0
    spectrum[USED % N] = signs
    long = np.fft.ifft(np.fft.ifftshift(spectrum)) * np.sqrt(N)
    return short, np.r_[long[-CP:], long], signs


def normalized_correlation_power(x, template, cumulative_power):
    length = len(template)
    correlation = np.correlate(x, template, mode="valid")
    denominator = (cumulative_power[length:] - cumulative_power[:-length]) * np.vdot(template, template).real
    return np.divide(
        abs(correlation) ** 2, denominator, out=np.zeros(len(correlation)), where=denominator > 0
    ).clip(0, 1)


def acquire(raw, cfg):
    """Only the receive buffer, numerology and source preamble enter this detector."""
    x = np.asarray(raw, dtype=np.complex128)
    if x.ndim != 1 or not np.isfinite(x).all():
        raise ValueError("invalid receive samples")
    short, preamble, data_symbols = waveform_layout(cfg)
    n = len(x) - preamble - (N + CP) * data_symbols - CP + 1
    if n <= 0:
        return []
    cumulative = np.r_[0.0, np.cumsum(x.real * x.real + x.imag * x.imag)]
    st, lt, _ = training()
    score = np.zeros(n)
    for conjugated in (False, True):
        short_scores = normalized_correlation_power(x, np.conj(st) if conjugated else st, cumulative)
        long_scores = normalized_correlation_power(x, np.conj(lt) if conjugated else lt, cumulative)
        st_mean = (
            sum(short_scores[CP + j * N : CP + j * N + n] for j in range(cfg["stf_repeats"]))
            / cfg["stf_repeats"]
        )
        lt_mean = (
            sum(
                long_scores[short + j * (N + CP) : short + j * (N + CP) + n]
                for j in range(cfg["ltf_symbols"])
            )
            / cfg["ltf_symbols"]
        )
        score = np.maximum(score, np.minimum(st_mean, lt_mean))
    maxima = np.flatnonzero(
        (score >= ACQUISITION_THRESHOLD)
        & (score >= np.r_[-1.0, score[:-1]])
        & (score > np.r_[score[1:], -1.0])
    )
    suppressed = np.zeros(n, dtype=bool)
    starts = []
    for i in maxima[np.argsort(-score[maxima], kind="stable")]:
        if suppressed[i]:
            continue
        starts.append((int(i), float(score[i])))
        suppressed[max(0, i - preamble + 1) : min(n, i + preamble)] = True
    return sorted(starts)


def demodulate(raw, start, cfg, *, collect_soft=False):
    """Choose a unique source header without accepting/rejecting on CRC or reference payload."""
    short, _, data_count = waveform_layout(cfg)
    length = cfg["ref_len"]
    header = phy.HEADER.pack(b"AIS1", 0, 1, length)
    frame_bits = (length + 14) * 8
    ltf_count = cfg["ltf_symbols"]
    needed = (ltf_count + data_count) * (N + CP)
    left = max(0, start - CP)
    x = np.asarray(raw[left : start + short + needed + CP], dtype=np.complex128)
    st = start - left
    s = x[st : st + short]
    omega = np.angle(np.vdot(s[:-32], s[32:])) / 32
    corrected = x * np.exp(-1j * omega * np.arange(len(x)))
    _, template, signs = training()
    ltf_region = corrected[st + short - CP : st + short + CP + len(template)]
    power = np.r_[0.0, np.cumsum(abs(ltf_region) ** 2)]
    peaks = normalized_correlation_power(ltf_region, template, power)
    ltf_offset = int(np.argmax(peaks)) - CP
    ltf0 = st + short + ltf_offset
    raw_symbols = corrected[ltf0 : ltf0 + needed].reshape(ltf_count + data_count, N + CP)[:, CP:]
    pilots = (-1.0) ** np.arange(data_count)[:, None] * phy.POLARITY
    constellation = phy.source_constellation(cfg["modulation"])
    width = cfg["bps"]
    result = {method: [] for method in METHODS}
    data_rows = np.flatnonzero(np.isin(USED, DATA))
    pilot_rows = np.flatnonzero(np.isin(USED, PILOTS))
    for conjugated in (False, True):
        y = np.fft.fftshift(np.fft.fft(raw_symbols.conj() if conjugated else raw_symbols, axis=1), axes=1)[
            :, USED % N
        ]
        repeated = y[:ltf_count]
        mean_training = repeated.mean(axis=0)
        h = mean_training / signs
        if np.any(abs(h) < 1e-12):
            continue
        residual = float((abs(repeated - mean_training) ** 2).sum() / ((ltf_count - 1) * len(USED)))
        signal = float(np.mean(abs(mean_training) ** 2) - residual / ltf_count)
        repeat_snr = 10 * math.log10(signal / residual) if signal > 0 and residual > 0 else None
        eq = y[ltf_count:] / h
        pilot_phase = np.angle((eq[:, pilot_rows] * pilots.conj()).sum(axis=1))
        by_method = {"phase": eq[:, data_rows] * np.exp(-1j * pilot_phase[:, None])}
        pilot_channel = pilots * h[pilot_rows]
        g = (pilot_channel.conj() * y[ltf_count:, pilot_rows]).sum(axis=1) / (abs(pilot_channel) ** 2).sum(
            axis=1
        )
        if np.all(abs(g) > 1e-12):
            by_method["pilot_complex_ls"] = eq[:, data_rows] / g[:, None]
        for method, symbols in by_method.items():
            for q in range(4):
                z = symbols.ravel() * (1j**q)
                nearest = np.argmin(abs(z[:, None] - constellation), axis=1)
                bits = ((nearest[:, None] >> np.arange(width - 1, -1, -1)) & 1).astype(np.uint8).ravel()
                if np.packbits(phy.descramble(bits[:80])).tobytes() != header:
                    continue
                frame = np.packbits(phy.descramble(bits[:frame_bits])).tobytes()
                detail = dict(conjugated=conjugated, quarter_turn=q, ltf_repeat_snr_db=repeat_snr)
                if collect_soft and method == "phase" and residual > 0 and math.isfinite(residual):
                    squared = abs(z[:, None] - constellation[None, :]) ** 2
                    reliable = np.tile(abs(h[data_rows]) ** 2 / residual, data_count)
                    label_bits = (
                        (np.arange(len(constellation))[:, None] >> np.arange(width - 1, -1, -1)) & 1
                    ) != 0
                    llr = np.column_stack(
                        [
                            (squared[:, one].min(axis=1) - squared[:, ~one].min(axis=1)) * reliable
                            for one in label_bits.T
                        ]
                    ).ravel()[:frame_bits]
                    if np.isfinite(llr).all():
                        detail["llr"] = llr
                result[method].append((frame, z[80 // width : (80 + 8 * length) // width], detail))
    meta = dict(cfo_hz=float(omega * cfg["fs"] / (2 * np.pi)), ltf_offset=ltf_offset)
    return result, meta


def source_reference(cfg):
    payload = (
        np.random.default_rng(cfg["ref_seed"]).integers(0, 256, cfg["ref_len"], dtype=np.uint8).tobytes()
    )
    body = phy.HEADER.pack(b"AIS1", 0, 1, len(payload)) + payload
    bits = phy.descramble(
        np.unpackbits(np.frombuffer(body + zlib.crc32(body).to_bytes(4, "little"), dtype="u1"))
    )
    width = cfg["bps"]
    labels = bits[80 : 80 + len(payload) * 8].reshape(-1, width) @ (2 ** np.arange(width - 1, -1, -1))
    return payload, phy.source_constellation(cfg["modulation"])[labels]


def measure(hypotheses, truth, transmitted):
    if len(hypotheses) != 1:
        return dict(
            status="unidentified" if not hypotheses else "ambiguous",
            bits=0,
            bit_errors=None,
            ber=None,
            crc32_pass=None,
            crc32_received=None,
            crc32_computed=None,
            evm_rms_percent=None,
        )
    frame, z, detail = hypotheses[0]
    result = phy.payload_result(frame, truth)
    if len(z) != len(transmitted):
        raise ValueError("incomplete payload symbols")
    power_error = float(np.vdot(z - transmitted, z - transmitted).real)
    power_ref = float(np.vdot(transmitted, transmitted).real)
    return dict(
        status="identified",
        **result,
        **detail,
        ber=result["bit_errors"] / result["bits"],
        evm_rms_percent=100 * math.sqrt(power_error / power_ref),
        error_vector_energy=power_error,
        reference_energy=power_ref,
    )


def stitched_windows(folder, records, cfg):
    hop = cfg["proc_hop"]
    segments = []
    locations = {}
    for record in sorted(records, key=lambda r: int(Path(r["path"]).name.split("_")[1])):
        name = Path(record["path"]).name
        p = folder / name
        if hashlib.sha256(p.read_bytes()).hexdigest() != record["sha256"]:
            raise ValueError(f"changed input {name}")
        with np.load(p, allow_pickle=False) as f:  # Detector never sees the author's annotations.
            x = f["rxw"]
        if x.dtype != np.complex64 or x.shape != (cfg["proc_window"],) or not np.isfinite(x).all():
            raise ValueError(f"unexpected samples in {name}")
        overlap = 0
        if segments:
            prev = segments[-1]
            for n in range(len(x), 0, -hop):
                if len(prev) >= n and prev[-n:].tobytes() == x[:n].tobytes():
                    overlap = n
                    break
        if overlap:
            offset = len(segments[-1]) - overlap
            segments[-1] = np.concatenate((segments[-1], x[overlap:]))
        else:
            segments.append(x)
            offset = 0
        locations[name] = dict(
            segment=len(segments) - 1, offset=offset, overlap_with_preceding_samples=overlap, length=len(x)
        )
    return segments, locations


def run(folder):
    manifest = json.loads((folder / "manifest.json").read_bytes())
    result = dict(source_revision=manifest["revision"], detector_threshold=ACQUISITION_THRESHOLD, runs={})
    for mod, origin in manifest["runs"].items():
        group = folder / mod
        cfg = json.loads((group / "rx_config.json").read_bytes())
        if cfg["modulation"] != mod:
            raise ValueError("modulation mismatch")
        records = [r for r in manifest["files"] if r["modulation"] == mod]
        segments, locations = stitched_windows(group, records, cfg)
        events = []
        for seg, x in enumerate(segments):
            peaks = acquire(x, cfg)
            for pos, score in peaks:
                decoded, meta = demodulate(x, pos, cfg)
                # Truth enters after signal processing and orientation selection.
                truth, ref_symbols = source_reference(cfg)
                event = dict(segment=seg, start=pos, preamble_score=score, **meta)
                for method in METHODS:
                    event[method] = measure(decoded[method], truth, ref_symbols)
                events.append(event)
        result["runs"][mod] = dict(
            source=origin,
            configured_center_hz=cfg["fc"],
            sample_rate_hz=cfg["fs"],
            segment_lengths=[len(s) for s in segments],
            locations=locations,
            events=events,
        )
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = run(args.inputs)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n")
    for mod, r in result["runs"].items():
        print(
            mod,
            r["segment_lengths"],
            len(r["events"]),
            {m: sum(e[m]["status"] == "identified" for e in r["events"]) for m in METHODS},
        )
