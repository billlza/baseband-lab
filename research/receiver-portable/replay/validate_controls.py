"""Fixed synthetic controls for acquisition, CFO units, integrity gating and grouping."""

import json
from pathlib import Path
import struct
import zlib
import numpy as np

import ofdm_research as rx
import repeat_study as reps
import source_phy as phy
import source_fixture as fixture


def known_header(payload):
    b = struct.pack("<4sHHH", b"AIS1", 0, 1, len(payload)) + payload
    return b + struct.pack("<I", zlib.crc32(b))


def soft_observation(frame):
    scrambled = phy.descramble(np.unpackbits(np.frombuffer(frame, dtype=np.uint8)))
    return [(frame, np.empty(0), {"llr": 1.0 - 2 * scrambled.astype(float)})]


def run():
    channels = [(241, "qpsk", 321, -2400, False), (872, "qam16", 1473, 4500, True)]
    result = {"synthetic_time_and_cfo": [], "negative_controls": {}}
    for seed, mod, start, cfo, conjugate in channels:
        rng = np.random.default_rng(seed)
        payload = rng.integers(0, 256, 512, dtype=np.uint8).tobytes()
        tx, _ = fixture.frame(mod, payload, False)
        tx = np.asarray(tx)
        cfg = dict(
            bps=2 if mod == "qpsk" else 4,
            ref_len=512,
            chunk_bytes=512,
            repeat=1,
            modulation=mod,
            stf_repeats=6,
            ltf_symbols=4,
            fs=3e6,
        )
        taps = np.array([1, 0.14 + 0.08j, 0, -0.05j])
        wave = np.convolve(tx.conj() if conjugate else tx, taps)
        raw = np.zeros(start + len(wave) + 1300, complex)
        raw[start : start + len(wave)] = wave
        raw *= np.exp(2j * np.pi * cfo * np.arange(len(raw)) / cfg["fs"] + 0.35j)
        raw += 0.010 * (rng.normal(size=len(raw)) + 1j * rng.normal(size=len(raw)))
        found = rx.acquire(raw, cfg)
        assert len(found) == 1 and abs(found[0][0] - start) <= rx.CP
        chosen, meta = rx.demodulate(raw, found[0][0], cfg)
        assert len(chosen["phase"]) == 1
        obs = phy.payload_result(chosen["phase"][0][0], payload)
        assert obs["bit_errors"] == 0 and obs["crc32_pass"]
        assert abs(meta["cfo_hz"] - cfo) < 100
        result["synthetic_time_and_cfo"].append(
            dict(
                seed=seed,
                start_injected=start,
                start_found=found[0][0],
                cfo_injected_hz=cfo,
                cfo_estimated_hz=meta["cfo_hz"],
                modulation=mod,
                payload_errors=0,
                crc32=True,
            )
        )
    cfg.update(bps=2, modulation="qpsk")
    st, lt, _ = rx.training()
    short = np.r_[st[-16:], np.tile(st, 6)]
    long = np.tile(lt, 4)
    rng = np.random.default_rng(208391)
    for name, burst in [
        ("silence", None),
        ("gaussian", None),
        ("short_training_only", short),
        ("long_training_only", long),
    ]:
        raw = np.zeros(12000, complex)
        if name != "silence":
            raw += 0.025 * (rng.normal(size=len(raw)) + 1j * rng.normal(size=len(raw)))
        if burst is not None:
            raw[1500 : 1500 + len(burst)] += burst
        peaks = rx.acquire(raw, cfg)
        assert len(peaks) == 0, (name, peaks)
        result["negative_controls"][name] = len(peaks)
    payload = rng.integers(0, 256, 512, dtype=np.uint8).tobytes()
    good = known_header(payload)
    errors = []
    for pos in (0, 9, 121, 598):
        bad = bytearray(good)
        bad[10 + pos // 8] ^= 1 << (7 - pos % 8)
        errors.append(bytes(bad))
    copies = [soft_observation(x) for x in errors]
    merged, status = reps.decide_four(copies)
    assert status == "identified" and merged == good
    delivered, rule = reps.verified_delivery(copies, merged)
    assert delivered == good and rule == "combined_crc"
    repeated = [soft_observation(errors[0])] * 4
    bad, _ = reps.decide_four(repeated)
    assert bad == errors[0]
    assert reps.verified_delivery(repeated, bad) == (None, "unresolved") and not reps.crc_ok(bad)
    assert reps.verified_delivery([soft_observation(good), *repeated[:3]], bad) == (good, "single_copy_crc")
    different = bytearray(payload)
    different[0] ^= 1
    other = known_header(bytes(different))
    assert reps.verified_delivery([soft_observation(good), soft_observation(other), *copies[:2]], None) == (
        None,
        "conflicting_crc_valid_copies",
    )
    assert (
        phy.payload_result(good, bytes(different))["bit_errors"] == 1
        and phy.payload_result(good, bytes(different))["crc32_pass"]
    )
    assert reps.decide_four([[], *copies[:3]]) == (None, "missing_or_ambiguous_header")
    result["four_copy_controls"] = [
        "disjoint_errors_recovered",
        "common_error_rejected",
        "valid_single_preserved",
        "conflicting_valid_rejected",
        "independent_truth_changes_BER_only",
        "missing_header_not_scored",
    ]
    return result


if __name__ == "__main__":
    import argparse

    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("output", type=Path)
    a = p.parse_args()
    result = run()
    a.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n")
    print(json.dumps(result))
