function [buffer, payload, truth] = impairedFrame(config, stream, options)
%IMPAIREDFRAME A random frame through a chosen channel, and what was done.
%   [BUFFER, PAYLOAD, TRUTH] = impairedFrame(CONFIG, STREAM, Name=Value)
%   sends a random PAYLOAD from STREAM through the taps Taps (one sample
%   apart; 1, no multipath, by default), after Delay zero samples (37) and
%   before Tail ones (64), with the frequency offset Offset (0 subcarrier
%   spacings) and noise of variance Variance (0, none) over the whole
%   BUFFER. TRUTH.Start is the first path's first training symbol window,
%   TRUTH.Offset the offset.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        config (1,1) baseband.OfdmConfig
        stream (1,1) RandStream
        options.Delay (1,1) double {mustBeInteger, mustBeNonnegative} = 37
        options.Tail (1,1) double {mustBeInteger, mustBeNonnegative} = 64
        options.Offset (1,1) double {mustBeReal} = 0
        options.Taps (:,1) double = 1
        options.Variance (1,1) double {mustBeNonnegative} = 0
    end
    payload = randi(stream, [0 1], config.PayloadBits, 1);
    waveform = conv(baseband.transmit(payload, config), options.Taps);
    buffer = [zeros(options.Delay, 1); waveform; zeros(options.Tail, 1)];
    buffer = baseband.frequencyOffset(buffer, options.Offset, config.FftLength);
    if options.Variance > 0
        buffer = baseband.addNoise(buffer, options.Variance, stream);
    end
    truth = struct("Start", options.Delay + config.CyclicPrefixLength + 1, "Offset", options.Offset);
end
