function result = receive(samples, sampleRate, config, options)
%RECEIVE Find, synchronise and decode one frame in complex baseband samples.
%   RESULT = baseband.receive(SAMPLES, SAMPLERATE, CONFIG) looks for a frame
%   of CONFIG in SAMPLES, a column of complex baseband samples (I + jQ) at
%   SAMPLERATE Hz, which must be CONFIG.SampleRate: this receiver does not
%   resample. The samples may be of any numeric class (an SDR's int16, for
%   example) and any scale. It decodes the first frame it finds:
%
%     1. the first training symbol's Schmidl-Cox metric: a coarse start
%        and the frequency offset modulo 2 subcarrier spacings
%        (baseband.detectFrame);
%     2. the offset's whole part from the two training symbols
%        (baseband.integerOffset), within CfoRange subcarrier spacings;
%     3. the FFT window from the first path (baseband.fineTiming), and
%        the offset again there (baseband.refineOffset);
%     4. the noise from the first training symbol's empty subcarriers
%        (baseband.estimateNoise), the channel from the second
%        (baseband.trainingChannel), each data symbol's phase from its
%        pilots (baseband.estimateChannel);
%     5. one-tap equalisation (baseband.equalize), max-log LLRs
%        (baseband.qamLlr), hard decisions and the CRC-24A check.
%
%   Name-value options:
%     Threshold   the Schmidl-Cox metric a frame must reach (0.4)
%     CfoRange    the largest frequency offset looked for, in subcarrier
%                 spacings, up to FftLength/4 (4)
%     Equalizer   "mmse" (default) or "zf"
%     Projection  whether the channel estimate is projected onto impulse
%                 responses within the cyclic prefix (true)
%
%   RESULT is a struct:
%     Detected       whether a whole frame was found
%     Payload        the decoded payload bits (empty without a frame)
%     CrcPassed      whether the decoded bits pass the CRC
%     Llr            the LLRs of all the frame's bits, CRC included
%     Start          the first training symbol's FFT window, in samples
%     Cfo, CfoHz     the frequency offset estimate, in subcarrier spacings
%                    and in Hz
%     NoiseVariance  the estimated noise variance of a subcarrier
%     Channel        the channel estimate (baseband.estimateChannel)
%     Symbols        the equalised data symbols, one column a data symbol
%     Peak           the Schmidl-Cox metric's largest value
%   Without a frame, the numbers are NaN and the arrays empty.
%
%   See also baseband.transmit, baseband.simulateLink, baseband.OfdmConfig.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        samples (:,1) {mustBeNumeric, mustBeFinite}
        sampleRate (1,1) double {mustBePositive, mustBeFinite}
        config (1,1) baseband.OfdmConfig
        options.Threshold (1,1) double {mustBePositive, mustBeLessThanOrEqual(options.Threshold, 1)} = 0.4
        options.CfoRange (1,1) double {mustBeNonnegative, mustBeFinite} = 4
        options.Equalizer (1,1) string {mustBeMember(options.Equalizer, ["zf", "mmse"])} = "mmse"
        options.Projection (1,1) logical = true
    end
    if abs(sampleRate - config.SampleRate) > 1e-9 * config.SampleRate
        error("baseband:receive:sampleRate", ...
            "The samples are at %g Hz, the configuration's rate is %g Hz.", sampleRate, config.SampleRate);
    end
    if options.CfoRange > config.FftLength / 4
        error("baseband:receive:cfoRange", ...
            "CfoRange (%g) must not exceed FftLength/4 (%g) subcarrier spacings.", ...
            options.CfoRange, config.FftLength / 4);
    end
    samples = double(samples);
    [coarse, fraction, peak] = baseband.detectFrame(samples, config, options.Threshold);
    result = noFrame(peak);
    if isempty(coarse)
        return
    end

    corrected = baseband.frequencyOffset(samples, -fraction, config.FftLength);
    training = baseband.ofdmDemodulate(corrected, coarse, 2, config);
    shift = baseband.integerOffset(training(:, 1), training(:, 2), config, ceil(options.CfoRange / 2));
    offset = fraction + 2 * shift;
    corrected = baseband.frequencyOffset(samples, -offset, config.FftLength);
    start = baseband.fineTiming(corrected, coarse, config);
    if start < 1 || start + config.FrameLength - config.CyclicPrefixLength - 1 > numel(samples)
        return
    end
    offset = baseband.refineOffset(samples, start, offset, config);
    corrected = baseband.frequencyOffset(samples, -offset, config.FftLength);

    bins = baseband.ofdmDemodulate(corrected, start, config.DataSymbols + 2, config);
    noiseVariance = baseband.estimateNoise(bins(:, 1), config);
    channel = baseband.estimateChannel(bins(:, 2), bins(:, 3:end), config, ...
        Projection=options.Projection);
    received = bins(config.binsOf(config.DataSubcarriers), 3:end);
    [symbols, gain, noise] = baseband.equalize(received, channel, noiseVariance, options.Equalizer);
    llr = baseband.qamLlr(symbols(:), gain(:), noise(:), config.ModulationOrder);
    bits = double(llr < 0);

    result.Detected = true;
    result.Payload = bits(1:config.PayloadBits);
    result.CrcPassed = ~any(baseband.crc24a(bits));
    result.Llr = llr;
    result.Start = start;
    result.Cfo = offset;
    result.CfoHz = offset * config.SubcarrierSpacing;
    result.NoiseVariance = noiseVariance;
    result.Channel = channel;
    result.Symbols = symbols;
end

function result = noFrame(peak)
% The result without a frame.
    result = struct("Detected", false, "Payload", zeros(0, 1), "CrcPassed", false, ...
        "Llr", zeros(0, 1), "Start", NaN, "Cfo", NaN, "CfoHz", NaN, "NoiseVariance", NaN, ...
        "Channel", zeros(0, 0), "Symbols", zeros(0, 0), "Peak", peak);
end
