<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Scoring a captured known OFDM frame

Save one contiguous receiver block containing a single isolated frame and its guard samples. Keep the unmodified acquisition file and the separately known transmitted payload. Record the radio model, acquisition time, software versions, coax/attenuation, manual receive gain, transmit gain and reference-clock configuration beside it. Keep device identifiers and real captures local. ADC rail checks can detect hard clipping but do not exclude analogue compression.

The MATLAB MAT file contains a scalar struct named `capture`. Its fields are:

| Field | Meaning |
|---|---|
| `Source` | `"sdr-capture"` for actual acquired samples; `"synthetic-control"` for generated samples |
| `IQ` | N by 2 real int16, I then Q. The Pluto's signed 12-bit acquisition range is −2048 to 2047. Preserve the original counts. |
| `SampleRateHz`, `CenterFrequencyHz`, `RxGainDb` | Actual acquisition settings as scalar doubles |
| `DataValid`, `Overflow` | The logical flags from the acquisition of **this** block |
| `Config` | Scalar struct with the transmitter's `baseband.OfdmConfig` name/value settings, including its sample rate |
| `Payload` | Column of the bits actually transmitted, stored separately from receiver decisions |

With a connected research radio, the native Pluto receive interface returns `[raw, valid, overflow] = rx()` for `OutputDataType="int16"`. Store `[real(raw), imag(raw)]` before removing any DC offset. Keep acquisitions that were invalid, overflowed or clipped in the raw record with their flags. Replay rejects them for the clean-frame comparison. The reference payload must be known independently; router signal summaries have no complex samples or payload reference. [MathWorks Pluto receiver documentation](https://www.mathworks.com/help/comm/plutoradio/ref/comm.sdrrxpluto-system-object.html)

Run `addpath("src","examples"); summary = replayKnownCapture("capture.mat")`. A missed frame yields zero scored bits and undefined BER. A successful CRC and the comparison to the reference are reported separately. A physical result needs the original acquisition and its provenance. The synthetic regression exercises the very same file and decoding interface.
