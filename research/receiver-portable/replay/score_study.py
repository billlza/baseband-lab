"""Compare frozen sample-only detections to the public hints, then score paired receivers."""

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import statistics

import numpy as np

import ofdm_research as research
import source_phy as phy


def summary(events):
    scores = {}
    for method in research.METHODS:
        rows = [e[method] for e in events if e[method]["status"] == "identified"]
        n = sum(r["bits"] for r in rows)
        errors = sum(r["bit_errors"] for r in rows)
        ev = sum(r["error_vector_energy"] for r in rows)
        ref = sum(r["reference_energy"] for r in rows)
        repeat = [r["ltf_repeat_snr_db"] for r in rows if r["ltf_repeat_snr_db"] is not None]
        scores[method] = dict(
            candidates=len(events),
            identified=len(rows),
            unidentified=len(events) - len(rows),
            payload_bits=n,
            bit_errors=errors,
            ber=errors / n if n else None,
            crc_pass=sum(r["crc32_pass"] for r in rows),
            crc_fail=sum(not r["crc32_pass"] for r in rows),
            evm_rms_percent=100 * math.sqrt(ev / ref) if ref else None,
            median_training_signal_to_residual_db=statistics.median(repeat) if repeat else None,
        )
    both = [e for e in events if all(e[m]["status"] == "identified" for m in research.METHODS)]
    scores["joint"] = dict(
        candidates=len(both),
        bits=sum(e["phase"]["bits"] for e in both),
        phase_errors=sum(e["phase"]["bit_errors"] for e in both),
        candidate_errors=sum(e["pilot_complex_ls"]["bit_errors"] for e in both),
        improved=sum(e["phase"]["bit_errors"] > e["pilot_complex_ls"]["bit_errors"] for e in both),
        worsened=sum(e["phase"]["bit_errors"] < e["pilot_complex_ls"]["bit_errors"] for e in both),
        unchanged=sum(e["phase"]["bit_errors"] == e["pilot_complex_ls"]["bit_errors"] for e in both),
    )
    offsets = [e["cfo_hz"] for e in events if e["phase"]["status"] == "identified"]
    scores["cfo_hz_min_median_max"] = (
        [min(offsets), statistics.median(offsets), max(offsets)] if offsets else None
    )
    return scores


def validate(archive, result, prior):
    manifest = json.loads((archive / "manifest.json").read_text())
    saved = json.loads(result.read_text())
    old = json.loads(prior.read_text())
    if manifest["revision"] != old["revision"] or saved["source_revision"] != old["revision"]:
        raise ValueError("source revision mismatch")
    refs = {(r["modulation"], r["file"]): r for r in old["windows"]}
    report = {
        "source_revision": old["revision"],
        "blind_output_sha256": hashlib.sha256(result.read_bytes()).hexdigest(),
        "runs": {},
    }
    table = []
    for mod, run in saved["runs"].items():
        folder = archive / mod
        cfg = json.loads((folder / "rx_config.json").read_text())
        assocs = {}
        checks = []
        # Only this retrospective evaluator opens capture annotations.
        for name, loc in run["locations"].items():
            with np.load(folder / name, allow_pickle=False) as f:
                hint = int(json.loads(f["meta_json"].item())["stf_idx"])
            target = loc["offset"] + hint
            matches = [
                (i, e)
                for i, e in enumerate(run["events"])
                if e["segment"] == loc["segment"] and abs(e["start"] - target) <= research.CP
            ]
            row = dict(file=name, matched=len(matches) == 1, sample_error=None, same_baseline_metrics=None)
            if len(matches) == 1:
                i, e = matches[0]
                assocs.setdefault(i, []).append(name)
                r = e["phase"]
                a = refs[mod, name]
                row.update(
                    sample_error=e["start"] - target,
                    same_baseline_metrics=all(
                        r[k] == a[k]
                        for k in ("bits", "bit_errors", "crc32_pass", "crc32_received", "crc32_computed")
                    ),
                )
            checks.append(row)
        selected = [e for i, e in enumerate(run["events"]) if i in assocs]
        other = [e for i, e in enumerate(run["events"]) if i not in assocs]
        segments, _ = research.stitched_windows(
            folder, [r for r in manifest["files"] if r["modulation"] == mod], cfg
        )
        previous_matches = 0
        for i, e in enumerate(run["events"]):
            payload_ref, _ = research.source_reference(cfg)
            _, preamble, data_symbols = research.waveform_layout(cfg)
            stop = e["start"] + preamble + data_symbols * (research.N + research.CP) + research.CP
            covering = [
                (name, loc)
                for name, loc in run["locations"].items()
                if loc["segment"] == e["segment"]
                and loc["offset"] <= e["start"]
                and loc["offset"] + loc["length"] >= stop
            ]
            if not covering:
                raise ValueError("no individual original capture contains the full scoring interval")
            name, loc = covering[0]
            with np.load(folder / name, allow_pickle=False) as archive_file:
                raw = archive_file["rxw"]
            relative = e["start"] - loc["offset"]
            if (
                raw[relative : relative + stop - e["start"]].tobytes()
                != segments[e["segment"]][e["start"] : stop].tobytes()
            ):
                raise ValueError("stitched samples differ from a complete original source interval")
            decoded, _ = phy.decode(raw, relative, cfg)
            if decoded is None:
                same = e["phase"]["status"] != "identified"
            else:
                compare = phy.payload_result(decoded, payload_ref)
                same = all(v == e["phase"][k] for k, v in compare.items())
            previous_matches += same
            rec = dict(
                modulation=mod,
                segment=e["segment"],
                start_sample=e["start"],
                original_file=name,
                original_start=relative,
                annotated_files="|".join(assocs.get(i, [])),
                preamble_score=e["preamble_score"],
                cfo_hz=e["cfo_hz"],
                ltf_offset=e["ltf_offset"],
            )
            for m in research.METHODS:
                for k in (
                    "status",
                    "bits",
                    "bit_errors",
                    "ber",
                    "crc32_pass",
                    "evm_rms_percent",
                    "ltf_repeat_snr_db",
                ):
                    rec[m + "_" + k] = e[m].get(k)
            table.append(rec)
        run_summary = dict(
            annotations=checks,
            known_windows=len(checks),
            timing_matches=sum(r["matched"] for r in checks),
            exact_baseline_on_known=sum(r["same_baseline_metrics"] is True for r in checks),
            baseline_replay_matches=previous_matches,
            known_distinct=summary(selected),
            other_candidates=summary(other),
            all_candidates=summary(run["events"]),
            segment_lengths=run["segment_lengths"],
        )
        report["runs"][mod] = run_summary
    return report, table


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("inputs", type=Path)
    ap.add_argument("blind", type=Path)
    ap.add_argument("previous", type=Path)
    ap.add_argument("summary", type=Path)
    ap.add_argument("csv", type=Path)
    args = ap.parse_args()
    report, table = validate(args.inputs, args.blind, args.previous)
    args.summary.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
    with args.csv.open("w", encoding="utf-8-sig", newline="") as f:
        cols = [
            "modulation",
            "segment",
            "start_sample",
            "original_file",
            "original_start",
            "annotated_files",
            "preamble_score",
            "cfo_hz",
            "ltf_offset",
        ] + [
            m + "_" + k
            for m in research.METHODS
            for k in (
                "status",
                "bits",
                "bit_errors",
                "ber",
                "crc32_pass",
                "evm_rms_percent",
                "ltf_repeat_snr_db",
            )
        ]
        writer = csv.DictWriter(f, cols, lineterminator="\n")
        writer.writeheader()
        writer.writerows(table)
    for mod, run in report["runs"].items():
        print(
            mod,
            "registered positions",
            run["timing_matches"],
            run["exact_baseline_on_known"],
            [r["sample_error"] for r in run["annotations"]],
        )
        for part in ("known_distinct", "other_candidates", "all_candidates"):
            s = run[part]
            print(
                part,
                [
                    (
                        m,
                        s[m]["bit_errors"],
                        s[m]["payload_bits"],
                        s[m]["crc_pass"],
                        round(s[m]["evm_rms_percent"], 4) if s[m]["evm_rms_percent"] is not None else None,
                    )
                    for m in research.METHODS
                ],
                s["joint"],
            )
