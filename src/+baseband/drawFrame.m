function [samples, payload, truth] = drawFrame(config, variance, stream, options)
%DRAWFRAME Draw one simulated frame with its original timing, offset and taps.
%   The random draw order matches simulateLink. The FFT start indexes the
%   first training symbol immediately after its cyclic prefix (one based).

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        config (1,1) baseband.OfdmConfig
        variance (1,1) double {mustBeReal, mustBeNonnegative, mustBeFinite}
        stream (1,1) RandStream
        options.Channel (1,1) string {mustBeMember(options.Channel, ["awgn", "multipath"])} = "awgn"
        options.Taps (1,1) double {mustBeInteger, mustBePositive} = 8
        options.Decay (1,1) double {mustBePositive, mustBeFinite} = 2
        options.CfoRange (1,1) double {mustBeNonnegative, mustBeFinite} = 4
        options.MaxDelay (1,1) double {mustBeInteger, mustBeNonnegative} = 64
    end
    payload = randi(stream, [0 1], config.PayloadBits, 1);
    waveform = baseband.transmit(payload, config);
    taps = 1;
    if options.Channel == "multipath"
        taps = baseband.multipathTaps(options.Taps, options.Decay, stream);
        waveform = conv(waveform, taps);
    end
    delay = randi(stream, [0 options.MaxDelay]);
    samples = [zeros(delay, 1); waveform; zeros(config.FftLength, 1)];
    offset = options.CfoRange * (2 * rand(stream) - 1);
    samples = baseband.frequencyOffset(samples, offset, config.FftLength);
    samples = baseband.addNoise(samples, variance, stream);
    truth = struct("Start", delay + config.CyclicPrefixLength + 1, ...
        "Offset", offset, "Taps", taps, "NoiseVariance", variance);
end
