<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Paired OFDM receiver study

## Fixed experiment

Each condition has two independent batches of 200 frames. The batch seeds are 2601 and 2602. Number the conditions from one in the order below, visiting white noise then multipath for each order and increasing the SNR within each channel. Seed MATLAB's twister stream with 100 times the batch seed plus the condition number. Use the default FFT, cyclic prefix, pilots, payload layout and 2 MHz sampling rate. Draw a fresh payload, delay (0–64 samples), frequency offset (uniform within ±4 subcarrier spacings) and complex noise for each frame. Multipath uses eight independently drawn complex Gaussian taps with exponential power decay of two samples and unit total mean power. Keep the same buffer for all five decoders.

| Modulation | Channel | Es/N0 per used subcarrier (dB) |
| --- | --- | --- |
| QPSK | AWGN, eight-tap Rayleigh | −6, 6, 12 |
| 16-QAM | AWGN, eight-tap Rayleigh | 6, 12, 18 |
| 64-QAM | AWGN | 16, 20, 24 |

The coherent reference uses the generated data samples, correct FFT position, known carrier offset, exact FFT of the generated taps, and the known noise variance. It must decode a clean frame with nonzero delay, offset and complex multipath. The four practical arms call the package receiver end to end and vary only channel projection on/off and MMSE/ZF. Measure hard-decision disagreements between the equalizers on the same detected frames. The single-antenna gain-aware demapper predicts identical hard decisions away from exact ties.

## Endpoints and uncertainty

The primary calibration is coherent QPSK in AWGN at 6 dB. The target is erfc(sqrt(10^0.6/2))/2. Report both seeds and their pooled result. Two independent seed intervals excluding the target on the same side count as a replicated calibration discrepancy. Publish the outcome with its direction either way. The primary receiver comparisons are projection on versus off at QPSK 6 dB in both channels, and paired MMSE/ZF decision disagreement. The remaining grid gives descriptive curves with pointwise intervals. A match across MATLAB versions checks reproducibility and adds no independent frames.

For each frame and receiver retain detection, payload errors and bits scored, CRC failure, and payload block error including misses. A missed frame contributes one block error and zero scored bits. Conditional BER is the ratio of total bit errors to scored payload bits. CRC-based BLER and missed-frame rate use every transmitted frame. For paired BER differences restrict both arms to jointly detected frames; paired BLER uses all frames. Positive differences mean the first arm has more errors.

Calculate 95% pointwise BER intervals by resampling whole independent frames within each seed, with 4,000 stratified bootstrap draws. Pair resampling indices across arms. For zero BER, the upper limit uses the exact two-sided 95% zero-event bound on the probability of any bit error in a detected frame, which conservatively bounds its mean BER. A group with no detections has undefined BER. Use frame-binomial Wilson intervals for BLER and misses. If no paired frames disagree, also report the exact upper bound on the probability of frame-level disagreement. Record seeds, release, counts, per-frame outcomes, theory, and both unchanged and adverse comparisons.

Run `python3 scripts/summarize_study.py study-output/frames.csv estimates.json` with NumPy installed. Each condition has separate seed estimates and a stratified pooled estimate. A missing BER field in the JSON means its detection-conditioned denominator was empty.
