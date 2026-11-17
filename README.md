# baseband-lab

An OFDM baseband transmitter, channel and receiver in MATLAB, with the
tests that hold each stage to its theory. It needs base MATLAB only, R2024b
or newer, and no toolbox. Everything here is simulation; the receiver takes
complex baseband samples and their sample rate, so samples captured by a
software-defined radio can be decoded by the same code.

## The frame

The default `baseband.OfdmConfig()`:

| | |
|---|---|
| FFT | 64 points, unitary scaling, 2 MHz sampling, 31.25 kHz subcarrier spacing |
| Cyclic prefix | 16 samples (8 µs) |
| Subcarriers | -26 to 26 without DC: 46 data, 6 pilots at ±2, ±14, ±26 |
| Modulation | Gray QAM of 3GPP TS 38.211 §5.1: QPSK, 16QAM or 64QAM, unit mean power |
| Frame | two training symbols, then 12 data symbols, 1120 samples (560 µs) |
| Payload | the data bits less a CRC-24A (TS 38.212): 2184 bits at 16QAM |

The first training symbol carries a known BPSK sequence on the even
subcarriers only, so its two halves are equal in time; the second carries
one on every used subcarrier. The pilots of the data symbols are known BPSK
too. All three sequences are cuts of one PRBS9, so the two ends share
nothing but the configuration. Every property can be set by name, as in
`baseband.OfdmConfig(ModulationOrder=64, DataSymbols=6)`; the constructor
refuses a combination the frame cannot carry.

## The receiver

`baseband.receive` decodes the first frame it finds:

1. **Detection and fractional frequency offset**: the Schmidl-Cox metric of
   the first training symbol. The middle of its plateau over the cyclic
   prefix, the prefix-long stretch of starts with the largest metric sum,
   gives a coarse start, and the correlation's angle there the offset
   modulo two subcarrier spacings.
2. **Integer frequency offset**: the differential correlation of the two
   training symbols on the even subcarriers (Schmidl and Cox), which neither
   the channel nor the timing within the prefix disturbs.
3. **Timing**: a cross-correlation with the second training symbol; the
   first lag within a prefix before the strongest that reaches a fifth of
   its power is the first path, and the window starts a quarter of the
   prefix before it. The fractional offset is measured again there.
4. **Estimation**: the noise from the first training symbol's empty odd
   subcarriers; the channel by least squares from the second training
   symbol, projected onto the impulse responses that fit within the cyclic
   prefix, which keeps 16/52 of the estimate's noise; the common phase of
   each data symbol from its pilots.
5. **Decisions**: one-tap MMSE or zero-forcing equalisation, max-log LLRs,
   hard decisions and the CRC.

The result holds the payload, whether its CRC passes, the LLRs, the start,
the frequency offset, the noise and channel estimates, the equalised
symbols and the metric's peak.

## Samples in

```matlab
result = baseband.receive(samples, sampleRate, config)
```

* `samples`: a column of complex baseband samples, I + jQ, of any numeric
  class (an SDR's `int16`, for example) and any scale. A row is read as a
  column.
* `sampleRate`: in Hz, and it must be `config.SampleRate`; the receiver
  does not resample.
* The receiver's windows start 4 samples before each symbol's first path,
  so the samples must hold the frame from the last 4 samples of its first
  cyclic prefix to its last symbol's end less 4 samples.
* The frequency offset may reach `CfoRange` subcarrier spacings (4 by
  default, ±125 kHz at 2 MHz; at most `FftLength/4`).
* Remove a DC offset first, for example by subtracting the mean of the
  samples: a constant makes both halves of every window equal, and so the
  timing metric one everywhere. Nothing corrects IQ imbalance or a sample
  clock offset; a 20 ppm clock error moves a frame's last sample by 0.02
  samples.

`result.Detected` is false when no frame is found, and the numbers are then
NaN and the arrays empty.

## An example

```matlab
addpath("src")
config = baseband.OfdmConfig(ModulationOrder=16);
stream = RandStream("twister", "Seed", 1);
payload = randi(stream, [0 1], config.PayloadBits, 1);
samples = [zeros(100, 1); baseband.transmit(payload, config); zeros(64, 1)];
samples = baseband.frequencyOffset(samples, 1.3, config.FftLength);
samples = baseband.addNoise(samples, 10^(-25 / 10), stream);
result = baseband.receive(samples, config.SampleRate, config);
isequal(result.Payload, payload)
```

`baseband.simulateLink` runs frames through white noise or a random Rayleigh
multipath channel, with a random delay and frequency offset, and counts bit
and block errors; `examples/linkCurves.m` sets them beside
`baseband.theoryBer`, the exact rates of Cho and Yoon for white noise and
their average over Rayleigh fading:

```matlab
addpath("src", "examples"); disp(linkCurves())
```

## Tests

```matlab
addpath("src"); results = runtests("tests"); table(results)
```

The tests check the mapping against the standard's points, the PRBS9 and
CRC-24A against their definitions, each estimator against its exact value
on a clean signal and its known statistics on a noisy one, the receiver
end to end through multipath, and the link's error rates against the
theory: in white noise within 2.5 dB of it, through Rayleigh multipath
within 3 dB. The Code Analyzer must find nothing in the repository. The
`matlab` workflow runs them on R2024b and R2026b, treats a warning as a
failure, and holds the package to 95 % line coverage.

## Limits

* One antenna, one frame a call, a channel static over the frame.
* The channel and the timing must fit within the cyclic prefix; a longer
  channel brings interference the receiver does not model.
* The projection of the channel estimate assumes that too.
* Where the first paths are nearly as strong as the strongest, the
  sidelobes of the paths' correlations can hide them from the timing,
  which then starts the window a sample after the first path: about one
  channel in 50,000 of the tests' 8-tap channels.
* A frame is found where the metric reaches 0.4, which noise alone
  sometimes does; a frame decoded from noise passes its CRC with a
  probability of 2^-24.

Over the air, transmit only in a band and at a power you are allowed to
use; a coaxial cable with attenuators between two radios radiates nothing.

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).
