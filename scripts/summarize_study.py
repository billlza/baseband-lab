# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate and summarize the pre-specified frame-level receiver study (NumPy)."""
import argparse
import csv
import json
import math
from pathlib import Path
from statistics import NormalDist

import numpy as np


ARMS = ("coherent", "projected-mmse", "projected-zf", "ls-mmse", "ls-zf")
SEEDS = (2601, 2602)
FRAMES = 200
DRAWS = 4000
FIELDS = ("Detected", "Bits", "BitErrors", "CrcBlockError", "PayloadBlockError", "BitDisagreements")
CONDITIONS = [
    (channel, order, snr)
    for order, channels, points in [
        (4, ("awgn", "multipath"), (-6, 6, 12)),
        (16, ("awgn", "multipath"), (6, 12, 18)),
        (64, ("awgn",), (16, 20, 24)),
    ]
    for channel in channels for snr in points
]
PAIRS = ((1, 0), (1, 3), (2, 1), (4, 3))


def zero_upper(n):
    return -math.expm1(math.log(0.025) / n)


def wilson(events, total):
    if not total:
        return None
    z = NormalDist().inv_cdf(0.975)
    p = events / total
    center = (p + z*z / (2*total)) / (1 + z*z / total)
    half = z * math.sqrt(p*(1-p) / total + z*z / (4*total*total)) / (1 + z*z / total)
    return [0.0 if events == 0 else center-half, 1.0 if events == total else center+half]


def parse_counts(text):
    return math.nan if text.strip().lower() in ("", "nan") else float(text)


def load_trials(path):
    trials = {key: np.full((len(SEEDS), FRAMES, len(ARMS), len(FIELDS)), np.nan) for key in CONDITIONS}
    theory = {}
    seen = set()
    with path.open(encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            key = (row["Channel"], int(row["Order"]), int(row["EsN0dB"]))
            arm = ARMS.index(row["Receiver"])
            batch, frame = int(row["Batch"]), int(row["Frame"])
            idx = (key, batch, frame, arm)
            if key not in trials or batch not in SEEDS or not 1 <= frame <= FRAMES or idx in seen:
                raise ValueError(f"unknown or repeated trial {idx}")
            if int(row["StreamSeed"]) != 100*batch + CONDITIONS.index(key) + 1:
                raise ValueError(f"unregistered random stream {idx}")
            seen.add(idx)
            counts = [parse_counts(row[name]) for name in FIELDS]
            detected, bits, errors, crc, payload_error, disagreement = counts
            length = 46 * 12 * int(math.log2(key[1])) - 24
            if (detected not in (0, 1) or crc not in (0, 1) or payload_error not in (0, 1)
                    or bits != detected*length):
                raise ValueError(f"invalid frame counts {idx}")
            if detected:
                if not errors.is_integer() or not 0 <= errors <= bits or payload_error != int(errors > 0):
                    raise ValueError(f"invalid scored payload {idx}")
            elif not math.isnan(errors) or crc != 1 or payload_error != 1 or arm == 0:
                raise ValueError(f"miss recorded as a scored payload {idx}")
            if not math.isnan(disagreement) and (arm not in (2, 4) or not detected
                    or not disagreement.is_integer() or not 0 <= disagreement <= bits):
                raise ValueError(f"invalid paired hard-decision count {idx}")
            reference = float(row["TheoryBER"])
            if not 0 <= reference <= 0.5 or theory.setdefault(key, reference) != reference:
                raise ValueError(f"invalid theory for {key}")
            trials[key][SEEDS.index(batch), frame-1, arm] = counts
    if len(seen) != len(CONDITIONS)*len(SEEDS)*FRAMES*len(ARMS):
        raise ValueError("missing pre-specified trials")
    for key, cells in trials.items():
        for zf in (2, 4):
            jointly_detected = (cells[:, :, zf, 0] == 1) & (cells[:, :, zf-1, 0] == 1)
            if not np.array_equal(np.isfinite(cells[:, :, zf, 5]), jointly_detected):
                raise ValueError(f"paired decision evidence missing or misattributed in {key}")
        if key[1] == 4:
            esn0 = 10**(key[2]/10)
            ref = (0.5*math.erfc(math.sqrt(esn0/2)) if key[0] == "awgn"
                   else 0.5*(1 - math.sqrt(esn0/(esn0+2))))
            if not math.isclose(ref, theory[key], rel_tol=1e-12):
                raise ValueError(f"independent QPSK theory check failed in {key}")
    return trials, theory


def weights(batch_count, rng):
    # Each row describes one stratified resample of whole frames. All receivers
    # share the row, including frames excluded by a detector.
    each = [rng.multinomial(FRAMES, np.full(FRAMES, 1/FRAMES), size=DRAWS)
            for _ in range(batch_count)]
    return np.concatenate(each, axis=1).astype(float)


def ratio_interval(numerator, denominator, w, *, difference=False):
    observed = denominator > 0
    n = int(observed.sum())
    if not n:
        return None, None, "no detected frames"
    total = float(numerator.sum() / denominator.sum())
    if np.all(numerator[observed] == 0):
        upper = zero_upper(n)
        return total, [-upper if difference else 0., upper], "exact frame-event upper bound"
    if not difference and np.array_equal(numerator[observed], denominator[observed]):
        return total, [1-zero_upper(n), 1.], "exact frame-event lower bound"
    den = w @ denominator
    usable = den > 0
    if np.count_nonzero(usable) < 0.975*len(w):
        return total, [-1. if difference else 0., 1.], "sparse conditional sample"
    ratios = (w@numerator)[usable] / den[usable]
    return total, np.quantile(ratios, [.025, .975]).tolist(), "stratified frame bootstrap"


def summarize(cells, w):
    n = len(cells)
    detected, bits, errors, crc, payload, disagree = np.moveaxis(cells, -1, 0)
    errors = np.nan_to_num(errors, nan=0)
    arms = {}
    for idx, name in enumerate(ARMS):
        ber, ci, method = ratio_interval(errors[:, idx], bits[:, idx], w)
        found = int(detected[:, idx].sum())
        blocks = int(crc[:, idx].sum())
        arms[name] = dict(
            frames=n, detected=found, missed=n-found, missed_rate=(n-found)/n,
            missed_ci95=wilson(n-found, n), bit_errors=int(errors[:, idx].sum()), bits=int(bits[:, idx].sum()),
            ber=ber, ber_ci95=ci, ber_ci_method=method, crc_block_errors=blocks, bler=blocks/n,
            bler_ci95=wilson(blocks, n), payload_block_errors=int(payload[:, idx].sum()),
            crc_pass_wrong_payload=int(np.sum((crc[:, idx] == 0) & (payload[:, idx] == 1))),
        )
    pairs = {}
    for i, j in PAIRS:
        both = (detected[:, i] == 1) & (detected[:, j] == 1)
        value, ci, method = ratio_interval((errors[:, i]-errors[:, j])*both, bits[:, i]*both, w, difference=True)
        db, bi, bm = ratio_interval(crc[:, i]-crc[:, j], np.ones(n), w, difference=True)
        pair = dict(common_frames=int(both.sum()), common_bits=int(bits[both, i].sum()),
                    detection_discordant_frames=int(np.sum(detected[:, i] != detected[:, j])),
                    delta_ber=value, delta_ber_ci95=ci, delta_ber_ci_method=method,
                    delta_bler=db, delta_bler_ci95=bi, delta_bler_ci_method=bm)
        if i in (2, 4) and j == i-1:
            disagreements = disagree[both, i]
            count = int(np.count_nonzero(disagreements))
            pair.update(disagreeing_payload_bits=int(disagreements.sum()), disagreeing_frames=count,
                        zero_disagreement_frame_upper95=zero_upper(len(disagreements)) if len(disagreements) and not count else None)
        pairs[f"{ARMS[i]} minus {ARMS[j]}"] = pair
    return {"arms": arms, "pairs": pairs}


def study(path):
    trials, theory = load_trials(path)
    points = []
    for index, key in enumerate(CONDITIONS, 1):
        cell = trials[key]
        estimates = {}
        groups = [(str(seed), cell[b:b+1]) for b, seed in enumerate(SEEDS)] + [("pooled", cell)]
        for group, (label, sample) in enumerate(groups):
            w = weights(len(sample), np.random.default_rng(20261126 + index*10 + group))
            estimates[label] = summarize(sample.reshape(-1, len(ARMS), len(FIELDS)), w)
        points.append(dict(channel=key[0], order=key[1], esn0_db=key[2], theory_ber=theory[key],
                           estimates=estimates))
    return dict(frames_per_seed=FRAMES, seeds=list(SEEDS), bootstrap_draws=DRAWS,
                numpy=np.__version__, conditions=points)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frames", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.write_text(json.dumps(study(args.frames), indent=2, allow_nan=False)+"\n", encoding="utf-8")
