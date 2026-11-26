<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Acquiring a known RF frame on a conducted link

Generate the TX references on a research machine with base MATLAB. The four numbered payloads have different identifiers and contents. Each .bin contains the 273 original bytes, MSB first. Each .cf32 holds one period of 1,120 complex samples at nominal 2 MS/s, float32 little-endian I followed by Q. Each .mat contains the same bytes as bits, the transmitter configuration and the waveform produced by baseband.transmit. The maximum complex amplitude is 0.5 full scale. Archive and hash these files before acquisition.

```matlab
addpath("src","examples")
writeBenchReferences("refs")
benchDigitalControls("refs","digital-controls")
```

## Physical setup

Use a full-duplex Pluto in its normal RF transmit and receive configuration, with the physical TX port connected to the physical RX port through 50 Ω coax and a characterized fixed attenuator. Verify the complete path at the chosen center frequency before enabling transmit. Record cable and pad loss, their power ratings, and the upper bound on TX output power. Upper-bound the RX input power by subtracting the minimum path loss from the maximum TX output in dBm and allow margin below the linear operating limit as well as the absolute maximum. Begin with low TX gain and manual RX gain. Record overload and gain settings even on failures. An absence of samples at an ADC rail cannot exclude analogue compression. Use a second planned gain/attenuation setting to test sensitivity. Retain the initial setting's trial records. [Analog Devices RF input guidance](https://wiki.analog.com/resources/eval/user-guides/circuits-from-the-lab/cn0417)

The recorder requires Communications Toolbox and its Pluto support package. Provide the frequency, gains and physical path for the actual equipment. The example uses variables for these locally determined settings. A single board shares its reference clock and tests a conducted link; separate radios have additional oscillator and synchronization effects. [MathWorks Pluto receiver](https://www.mathworks.com/help/comm/plutoradio/ref/comm.sdrrxpluto-system-object.html)

```matlab
result = recordPlutoBenchTrial("refs/frame-01.mat","trial-001", ...
    RadioID=radioID, CenterFrequencyHz=fcHz, TxGainDb=txGainDb, ...
    RxGainDb=rxGainDb, PathLossDb=measuredLossDb, PathDescription=pathNotes)
```

The operator associates each fresh trial directory with its numbered TX file before capture. The recorder saves this intent first, uses the TX/RX hardware readbacks and archives those settings. It starts repeating just that frame, takes one 2,304-sample RX block and releases the radios. MATLAB cleanup guards release both objects on exceptions. If the host is terminated during continuous transmission, stop or power down the research radio before disconnecting the coax. [MathWorks transmitRepeat](https://www.mathworks.com/help/comm/plutoradio/ref/comm.sdrtxpluto.transmitrepeat.html)

The whole native block goes to native.mat in original signed ADC counts together with acquisition time, actual sample rate and center frequency, requested manual gain and data-valid/overflow flags. The reference configuration retained in intent.mat records the requested rate. The capture configuration uses the transmitter's actual sample clock after checking agreement with the receiver's readback. Track an intent with no native file as an acquisition failure. Leave invalid, clipped and overflowed acquisitions in place.

The scoring prefix is fixed before the run and has 2,223 samples. The receiver examines 1,120 possible coarse FFT starts, one complete period. It receives all of those samples without a timing hint, trial selection by CRC, or a search for another copy. Score each planned trial once. Acquisition errors, misses, identified CRC failures and CRC passes have separate counts. Payload BER is total erroneous bits divided by scored payload bits; a missed frame contributes no scored bits. For detected frames, compare against the saved TX bytes even if CRC fails. A separate capture with the transmitter off checks false detection. Keep a record of each planned trial and all raw files, hashes and versions. A first pass with four frames establishes that the chain works; characterizing BER requires enough independent trials for the required precision.
