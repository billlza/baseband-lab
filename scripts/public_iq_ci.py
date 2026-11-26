# SPDX-License-Identifier: GPL-3.0-or-later
"""Replay inputs and per-window parity for the pinned public CoaxSweep recordings."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile


BASELINE = Path(__file__).with_name("public_iq_reference.json")


def load_json(path):
    return json.loads(path.read_bytes())


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def baseline():
    ref = load_json(BASELINE)
    if set(ref["runs"]) != {"qpsk", "qam16"}:
        raise ValueError("expected the two registered source runs")
    for group in ref["runs"].values():
        names = [w["file"] for w in group["windows"]]
        if len(names) != 8 or len(set(names)) != 8:
            raise ValueError("expected eight distinct windows per run")
    return ref


def fetch(root, relative, dest, size, digest):
    subprocess.run(
        ["curl", "--fail", "--silent", "--show-error", "--location", "--proto", "=https",
         "--proto-redir", "=https", "--connect-timeout", "15", "--max-time", "75",
         "--retry", "2", "--retry-max-time", "100", "--max-filesize", str(size),
         "--output", str(dest), f"{root}/{relative}"], check=True)
    observed = hashlib.sha256(dest.read_bytes()).hexdigest()
    if dest.stat().st_size != size or observed != digest:
        raise ValueError(f"source size or SHA-256 mismatch for {relative}")
    return observed


def prepare(ref, dest):
    import numpy as np

    root = f"https://huggingface.co/datasets/{ref['dataset']}/resolve/{ref['revision']}"
    dest.mkdir(parents=True, exist_ok=False)
    index = []
    with tempfile.TemporaryDirectory(dir=dest.parent) as staging:
        scratch = Path(staging)
        for mod, group in ref["runs"].items():
            prefix = group["source"]
            config_file = scratch / "rx_config.json"
            fetch(root, f"{prefix}/rx_config.json", config_file, group["config_bytes"], group["config_sha256"])
            cfg = load_json(config_file)
            if (cfg["modulation"], cfg["bps"], cfg["ref_len"], cfg["chunk_bytes"], cfg["repeat"]) != (
                    mod, {"qpsk": 2, "qam16": 4}[mod], 512, 512, 1):
                raise ValueError(f"unexpected source framing for {mod}")
            truth = np.random.default_rng(cfg["ref_seed"]).integers(0, 256, cfg["ref_len"], dtype=np.uint8).tobytes()
            if hashlib.sha256(truth).hexdigest() != ref["reference_sha256"]:
                raise ValueError(f"TX reference does not reproduce for {mod}")
            (dest / f"{mod}.bin").write_bytes(truth)
            symbols = math.ceil((10 + len(truth) + 4) * 8 / (48 * cfg["bps"]))
            frame_length = 16 + 64 * cfg["stf_repeats"] + 80 * (cfg["ltf_symbols"] + symbols)
            for w in group["windows"]:
                name = w["file"]
                public_file = scratch / "capture.npz"
                measured_sha = fetch(root, f"{prefix}/{name}", public_file, w["bytes"], w["sha256"])
                with np.load(public_file, allow_pickle=False) as capture:
                    x = capture["rxw"]
                    hint = json.loads(capture["meta_json"].item())["stf_idx"]
                    if (x.dtype != np.complex64 or x.shape != (cfg["proc_window"],)
                            or not np.isfinite(x).all() or type(hint) is not int
                            or hint < 0 or hint + frame_length + 16 > len(x)):
                        raise ValueError(f"invalid I/Q or incomplete candidate in {name}")
                    left = max(0, hint - 64)
                    right = min(len(x), hint + frame_length + 64)
                    sample_bytes = x[left:right].astype("<c8", copy=False).tobytes()
                candidate_sha = hashlib.sha256(sample_bytes).hexdigest()
                if candidate_sha != w["candidate_sha256"]:
                    raise ValueError(f"converted window differs from the local input for {name}")
                iq_file = f"{mod}-{Path(name).stem}.cf32"
                (dest / iq_file).write_bytes(sample_bytes)
                index.append(dict(file=iq_file, source=name, modulation=mod, order=2**cfg["bps"],
                                  sampleRateHz=cfg["fs"], stf=hint-left+1, stfRepeats=cfg["stf_repeats"],
                                  ltfs=cfg["ltf_symbols"], symbols=symbols, reference=f"{mod}.bin",
                                  sourceSha256=measured_sha, candidateSha256=candidate_sha))
    write_json(dest / "index.json", index)
    print(f"Verified and prepared {len(index)} upstream windows.")


def keyed(rows, mod_field, file_field):
    indexed = {}
    for row in rows:
        key = (row[mod_field], row[file_field])
        if key in indexed:
            raise ValueError(f"duplicate frame {key}")
        indexed[key] = row
    return indexed


def crc_outcome(value):
    if value is None:
        return None
    if type(value) not in (int, bool) or value not in (0, 1):
        raise ValueError(f"invalid MATLAB CRC result {value!r}")
    return bool(value)


def check(ref, index, rows, matlab_version):
    keys = {(mod, w["file"]): w for mod, g in ref["runs"].items() for w in g["windows"]}
    source = keyed(index, "modulation", "source")
    matlab = keyed(rows, "Modulation", "File")
    if set(source) != set(keys) or set(matlab) != set(keys):
        raise ValueError("missing or unexpected frame identities in the inputs or the MATLAB output")
    verified = []
    for key, w in keys.items():
        mod, name = key
        measured = matlab[key]
        evidence = source[key]
        if evidence["sourceSha256"] != w["sha256"] or evidence["candidateSha256"] != w["candidate_sha256"]:
            raise ValueError(f"unverified source identity for {key}")
        if any(type(measured[f]) is not bool for f in ("Identified", "NativeDetected", "NativeCrc24Passed")):
            raise ValueError(f"invalid frame flags for {key}")
        if type(measured["Bits"]) is not int or (measured["Identified"] and
                (type(measured["BitErrors"]) is not int or type(measured["Ber"]) not in (int, float))):
            raise ValueError(f"invalid payload counts for {key}")
        actual = dict(bits=measured["Bits"], bit_errors=measured["BitErrors"], ber=measured["Ber"],
                      crc32_received_hex=measured["Crc32ReceivedHex"] or None,
                      crc32_computed_hex=measured["Crc32ComputedHex"] or None,
                      crc32_pass=crc_outcome(measured["Crc32Passed"]))
        checks = {k: actual[k] == value for k, value in w["python"].items()}
        checks["identified"] = measured["Identified"]
        verified.append(dict(modulation=mod, file=name, source_sha256=evidence["sourceSha256"],
                             candidate_sha256=evidence["candidateSha256"], python=w["python"], matlab=actual,
                             checks=checks, match=all(checks.values()), native_detected=measured["NativeDetected"],
                             native_crc24a_pass=measured["NativeCrc24Passed"]))
    return dict(dataset=ref["dataset"], revision=ref["revision"], matlab_version=matlab_version,
                python_result_sha256=ref["python_result_sha256"], python_decoder_sha256=ref["python_decoder_sha256"],
                transmit_reference_sha256=ref["reference_sha256"], windows=verified,
                distinct_candidate_windows=len({row["candidate_sha256"] for row in verified}),
                matches=sum(row["match"] for row in verified), passed=all(row["match"] for row in verified))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    cmds = parser.add_subparsers(dest="command", required=True)
    prep = cmds.add_parser("prepare")
    prep.add_argument("inputs", type=Path)
    verify = cmds.add_parser("check")
    verify.add_argument("scratch", type=Path)
    verify.add_argument("release", choices=["R2024b", "R2026b"])
    verify.add_argument("output", type=Path)
    args = parser.parse_args()
    ref = baseline()
    if args.command == "prepare":
        prepare(ref, args.inputs)
        return
    version = load_json(args.scratch / "version.json")
    if version["release"] != args.release:
        raise ValueError(f"expected {args.release}, got {version['release']}")
    receipt = check(ref, load_json(args.scratch / "inputs/index.json"),
                    load_json(args.scratch / "matlab.json"), version)
    receipt.update(commit=os.environ["GITHUB_SHA"], run_id=os.environ["GITHUB_RUN_ID"],
                   run_attempt=os.environ["GITHUB_RUN_ATTEMPT"])
    write_json(args.output, receipt)
    print(f"{args.release}: {receipt['matches']}/{len(receipt['windows'])} frames match the local Python reference")
    if not receipt["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
