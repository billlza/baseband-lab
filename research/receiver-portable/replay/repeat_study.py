"""Compare four-copy soft decisions with the first reception in each fixed group."""

import argparse
import hashlib
import json
from pathlib import Path
import zlib
import numpy as np
import ofdm_research as rx
import source_phy as phy


def decide_four(copies):
    if len(copies) != 4 or any(len(hypotheses) != 1 for hypotheses in copies):
        return None, "missing_or_ambiguous_header"
    entries = [hypotheses[0] for hypotheses in copies]
    first = entries[0][0]
    if any(
        frame[: phy.HEADER.size] != first[: phy.HEADER.size] or len(frame) != len(first)
        for frame, _, _ in entries
    ):
        return None, "frame_identity_or_length_differs"
    if any("llr" not in info for _, _, info in entries):
        return None, "noise_estimate_unavailable"
    soft = np.stack([info["llr"] for _, _, info in entries])
    if soft.shape != (4, 8 * len(first)) or not np.isfinite(soft).all():
        raise ValueError("invalid soft observations")
    sums = soft.sum(axis=0)
    bits = np.where(sums == 0, soft[0] < 0, sums < 0).astype(np.uint8)
    combined = np.packbits(phy.descramble(bits)).tobytes()
    if combined[: phy.HEADER.size] != first[: phy.HEADER.size]:
        return None, "combined_header_invalid"
    return combined, "identified"


def crc_ok(frame):
    return (
        frame is not None
        and len(frame) >= 14
        and zlib.crc32(frame[:-4]) == int.from_bytes(frame[-4:], "little")
    )


def verified_delivery(copies, combined):
    """CRC of received bytes controls delivery; the transmitted payload is not an argument."""
    seen = [items[0][0] for items in copies if len(items) == 1]
    if len({r[: phy.HEADER.size] for r in seen}) > 1:
        return None, "conflicting_identity"
    valid = {r for r in seen if crc_ok(r)}
    if len(valid) > 1:
        return None, "conflicting_crc_valid_copies"
    if valid:
        winner = next(iter(valid))
        if crc_ok(combined) and combined != winner:
            return None, "conflicting_crc_valid_combination"
        return winner, "single_copy_crc"
    if crc_ok(combined):
        return combined, "combined_crc"
    return None, "unresolved"


def run(root, blind):
    recorded = json.loads(blind.read_text())
    manifest = json.loads((root / "manifest.json").read_text())
    if manifest["revision"] != recorded["source_revision"]:
        raise ValueError("source revision mismatch")
    results = {}
    for mod, run in recorded["runs"].items():
        cfg = json.loads((root / mod / "rx_config.json").read_bytes())
        # This pairing applies only to the documented repeated, one-chunk reference runs.
        if cfg["ref_len"] != 512 or cfg["chunk_bytes"] != 512 or cfg["ref_seed"] != 42 or cfg["repeat"] != 1:
            raise ValueError("identical payload across transmissions is not established")
        segs, locations = rx.stitched_windows(
            root / mod, [r for r in manifest["files"] if r["modulation"] == mod], cfg
        )
        if locations != run["locations"]:
            raise ValueError("candidate coordinates changed")
        groups = []
        tails = []
        hashes = set()
        for seg, raw in enumerate(segs):
            events = sorted((e for e in run["events"] if e["segment"] == seg), key=lambda e: e["start"])
            _, pre, ndata = rx.waveform_layout(cfg)
            span = pre + ndata * (rx.N + rx.CP)
            for ev in events:
                key = hashlib.sha256(raw[ev["start"] : ev["start"] + span].tobytes()).hexdigest()
                if key in hashes:
                    raise ValueError("one candidate would be counted twice")
                hashes.add(key)
            size = len(events) // 4 * 4
            for off in range(0, size, 4):
                group = events[off : off + 4]
                observations = [
                    rx.demodulate(raw, e["start"], cfg, collect_soft=True)[0]["phase"] for e in group
                ]
                frame, status = decide_four(observations)
                delivered, delivery_status = verified_delivery(observations, frame)
                truth, _ = rx.source_reference(cfg)  # Only start scoring after choosing the combined bytes.
                f0 = phy.payload_result(observations[0][0][0], truth) if len(observations[0]) == 1 else None
                score = phy.payload_result(frame, truth) if frame is not None else None
                groups.append(
                    dict(
                        segment=seg,
                        members=[e["start"] for e in group],
                        status=status,
                        first=f0,
                        combined=score,
                        delivery_policy=delivery_status,
                        delivered=phy.payload_result(delivered, truth) if delivered is not None else None,
                    )
                )
            tails.extend(dict(segment=seg, start=e["start"]) for e in events[size:])
        valid = [g for g in groups if g["combined"] is not None]
        summary = {}
        for key in ("first", "combined"):
            vals = [g[key] for g in valid]
            bits = sum(r["bits"] for r in vals)
            errors = sum(r["bit_errors"] for r in vals)
            summary[key] = dict(
                bits=bits,
                errors=errors,
                ber=errors / bits if bits else None,
                crc_pass=sum(r["crc32_pass"] for r in vals),
                crc_fail=sum(not r["crc32_pass"] for r in vals),
            )
        delivered = [g["delivered"] for g in groups if g["delivered"] is not None]
        summary["delivery_policy"] = dict(
            scheduled_groups=len(groups),
            accepted=len(delivered),
            unresolved=len(groups) - len(delivered),
            delivered_bits=sum(v["bits"] for v in delivered),
            observed_delivered_errors=sum(v["bit_errors"] for v in delivered),
        )
        results[mod] = dict(
            groups=groups, distinct_sample_sequences=len(hashes), unpaired_tail=tails, summary=summary
        )
    return dict(
        blind_output_sha256=hashlib.sha256(blind.read_bytes()).hexdigest(), group_size=4, runs=results
    )


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("archive", type=Path)
    p.add_argument("blind", type=Path)
    p.add_argument("result", type=Path)
    a = p.parse_args()
    r = run(a.archive, a.blind)
    a.result.write_text(json.dumps(r, indent=2, allow_nan=False) + "\n")
    for k, d in r["runs"].items():
        print(k, "groups", len(d["groups"]), "tail", len(d["unpaired_tail"]), d["summary"])
        print(
            [
                (g["first"]["bit_errors"], g["combined"]["bit_errors"], g["combined"]["crc32_pass"])
                for g in d["groups"]
                if g["combined"]
            ]
        )
