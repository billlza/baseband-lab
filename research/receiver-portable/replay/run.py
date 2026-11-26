"""Run the pinned public I/Q study from local originals or the author's archive."""
import argparse
import json
import math
from pathlib import Path
import platform
import subprocess
import sys
from tempfile import TemporaryDirectory

import numpy as np

import fetch_primary
import ofdm_research
import repeat_study


def write_json(path, data):
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(data, stream, indent=2, allow_nan=False)
        stream.write("\n")


def frame_values(blind):
    frames = []
    for modulation, run in sorted(blind["runs"].items()):
        for event in run["events"]:
            frame = event["phase"]
            frames.append({
                "modulation": modulation, "segment": event["segment"], "sample": event["start"],
                "bits": frame["bits"], "errors": frame["bit_errors"], "ber": frame["ber"],
                "received_crc32": frame["crc32_received"], "computed_crc32": frame["crc32_computed"],
                "crc_ok": frame["crc32_pass"], "cfo_hz": event["cfo_hz"], "evm_percent": frame["evm_rms_percent"],
            })
    return frames


def verify_frames(rows, baseline):
    if len(rows) != len(baseline):
        raise ValueError("Number of detected packets changed")
    delta = {"cfo_hz": 0.0, "evm_percent": 0.0}
    for actual, expected in zip(rows, baseline, strict=True):
        for field, target in expected.items():
            value = actual[field]
            if field in delta:
                delta[field] = max(delta[field], abs(value - target))
                if not math.isclose(value, target, rel_tol=1e-9, abs_tol=1e-7):
                    raise ValueError(f"{field} differs at {actual['modulation']} sample {actual['sample']}")
            elif value != target:
                raise ValueError(f"{field} differs at {actual['modulation']} sample {actual['sample']}")
    return delta


def replay(original, output):
    output = output.resolve()
    if output.exists():
        raise FileExistsError(f"Choose a new results directory: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    scripts = Path(__file__).resolve().parent
    with TemporaryDirectory(dir=output.parent) as temp:
        folder = Path(temp) / "results"
        folder.mkdir()
        blind = ofdm_research.run(original)
        write_json(folder / "blind.json", blind)
        subprocess.run([sys.executable, str(scripts / "score_study.py"), str(original), str(folder / "blind.json"),
                        str(scripts / "primary-assisted.json"), str(folder / "score.json"), str(folder / "frames.csv")], check=True)
        repeat = repeat_study.run(original, folder / "blind.json")
        write_json(folder / "repeated.json", repeat)
        scored = json.loads((folder / "score.json").read_bytes())
        labels = [item for group in scored["runs"].values() for item in group["annotations"]]
        if len(labels) != 16 or not all(label["sample_error"] == 0 and label["same_baseline_metrics"] for label in labels):
            raise ValueError("The registered window or its measured BER/CRC differs")
        frames = frame_values(blind)
        fixed = json.loads((scripts / "public-reference.json").read_bytes())
        differences = verify_frames(frames, fixed["frames"])
        groups = {mod: group["summary"]["delivery_policy"] for mod, group in repeat["runs"].items()}
        if groups != fixed["four_copy"]:
            raise ValueError("Four-copy delivery outcome differs")
        verification = {"os": platform.system(), "arch": platform.machine(), "python": platform.python_version(),
                        "numpy": np.__version__, "revision": blind["source_revision"], "registered_exact": len(labels),
                        "distinct_packets": len(frames), "max_abs_delta_from_reference": differences,
                        "frames": frames, "four_copy": groups}
        write_json(folder / "verification.json", verification)
        folder.rename(output)
    print(f"{len(labels)} annotated windows and {len(frames)} distinct packets verified. {output}")


if __name__ == "__main__":
    arg = argparse.ArgumentParser(description=__doc__)
    arg.add_argument("--data", type=Path, required=True, help="Directory of the 16 pinned public captures")
    arg.add_argument("--from-author", action="store_true", help="Fetch the pinned archives into --data and verify their checksums")
    arg.add_argument("--out", type=Path, required=True, help="New directory for results")
    args = arg.parse_args()
    if args.from_author:
        fetch_primary.fetch(args.data)
    replay(args.data, args.out)
