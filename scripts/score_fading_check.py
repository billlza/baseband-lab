# SPDX-License-Identifier: GPL-3.0-or-later
"""Separate the realized-channel and receiver contributions at 16-QAM, 18 dB."""
import argparse
import csv
import json
import math
from pathlib import Path

import numpy as np

from summarize_study import load_trials


BATCHES = {260112: 200, 260212: 200, 921607: 2000, 921608: 2000}
PAYLOAD_BITS = 2184
ES_N0 = 10**1.8
DRAWS = 4000
DATA = np.array([k for k in range(-26, 27) if abs(k) not in {0, 2, 14, 26}])
# Payload occupies consecutive symbols in the column-major OFDM grid. Six
# final 16-QAM symbols hold the CRC; their subcarriers carry one fewer payload.
CARRIER_WEIGHTS = np.bincount(np.arange(PAYLOAD_BITS//4) % len(DATA), minlength=len(DATA))


def gray_pam_ber(cdf):
    """Average Hamming distance over equiprobable 4-PAM inputs and decisions.

    Each quadrature has two Gray bits. Boundaries and levels are given before
    the square constellation's normalization by sqrt(10).
    """
    gray = (0, 1, 3, 2)
    ber = 0.
    for src, level in enumerate((-3, -1, 1, 3)):
        left = 0.
        for dest, boundary in enumerate((-2, 0, 2, math.inf)):
            right = 1. if dest == 3 else cdf(boundary-level)
            ber += (gray[src] ^ gray[dest]).bit_count() * (right-left) / 8
            left = right
    return ber


def conditional_ber(magnitude):
    scale = np.asarray(magnitude) * math.sqrt(ES_N0/10)
    erfc = np.vectorize(math.erfc, otypes=[float])
    return gray_pam_ber(lambda offset: .5 * erfc(-offset*scale))


def rayleigh_ber():
    def averaged_cdf(offset):
        v = offset * math.sqrt(ES_N0/10)
        return .5*(1 + v / math.hypot(1, v))
    return gray_pam_ber(averaged_cdf)


def load_frames(path):
    frames = {seed: {} for seed in BATCHES}
    with path.open(newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            seed, frame = int(row["StreamSeed"]), int(row["Frame"])
            if seed not in BATCHES or not 1 <= frame <= BATCHES[seed] or frame in frames[seed]:
                raise ValueError(f"unregistered or repeated fading frame {seed}/{frame}")
            taps = [complex(float(row[f"TapI{i}"]), float(row[f"TapQ{i}"])) for i in range(1,9)]
            errors = int(row["BitErrors"])
            if int(row["PayloadBits"]) != PAYLOAD_BITS or not 0 <= errors <= PAYLOAD_BITS or not np.all(np.isfinite(taps)):
                raise ValueError(f"invalid fading observation {seed}/{frame}")
            frames[seed][frame] = (errors, taps)
    batches = {}
    for seed, stream in frames.items():
        if len(stream) != BATCHES[seed]:
            raise ValueError(f"incomplete stream {seed}")
        errors, taps = zip(*(stream[k] for k in sorted(stream)))
        bins = np.fft.fft(taps, n=64, axis=1)[:, DATA % 64]
        means = np.average(conditional_ber(np.abs(bins)), axis=1, weights=CARRIER_WEIGHTS)
        batches[seed] = (np.array(errors), means)
    return batches


def summarize(streams, rng):
    total_frames = sum(len(errors) for errors, _ in streams)
    replicates = np.zeros((DRAWS, 3))
    totals = np.zeros(3)
    for errors, conditional in streams:
        observed = errors/PAYLOAD_BITS
        values = np.column_stack((observed, conditional, observed-conditional))
        n = len(errors)
        totals += values.sum(axis=0)
        for start in range(0, DRAWS, 100):
            indices = rng.integers(n, size=(100, n))
            replicates[start:start+100] += values[indices].sum(axis=1)
    bounds = np.quantile(replicates/total_frames, [.025, .975], axis=0)
    result = {name: {"rate": float(totals[i]/total_frames), "ci95": bounds[:,i].tolist()}
              for i,name in enumerate(("observed", "given_taps", "observed_minus_given_taps"))}
    result.update(frames=total_frames, payload_bits=total_frames*PAYLOAD_BITS,
                  bit_errors=sum(int(errors.sum()) for errors, _ in streams))
    return result


def analyze(frames, primary):
    batches = load_frames(frames)
    full, theory = load_trials(primary)
    key = ("multipath", 16, 18)
    for i, seed in enumerate((260112, 260212)):
        if not np.array_equal(batches[seed][0], full[key][i, :, 0, 2]):
            raise ValueError("regenerated errors disagree with the primary trial")
    reference = rayleigh_ber()
    if not math.isclose(theory[key], reference, rel_tol=1e-12):
        raise ValueError("the independent Gray-PAM Rayleigh integral disagrees with the grid")
    groups = {str(seed): [seed] for seed in BATCHES}
    groups.update(original=[260112,260212], fresh=[921607,921608])
    estimates = {k: summarize([batches[seed] for seed in group], np.random.default_rng(2026112600+i))
                 for i,(k,group) in enumerate(groups.items())}
    return dict(rayleigh_ensemble_ber=reference, matched_original_frames=400,
                bootstrap_draws=DRAWS, numpy=np.__version__, estimates=estimates)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for arg in ("fading", "primary", "output"):
        parser.add_argument(arg, type=Path)
    args = parser.parse_args()
    args.output.write_text(json.dumps(analyze(args.fading, args.primary), indent=2, allow_nan=False)+"\n")
