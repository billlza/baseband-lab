function [symbols, gain, noise] = equalize(received, channel, noiseVariance, method)
%EQUALIZE One-tap equalisation of each subcarrier.
%   [SYMBOLS, GAIN, NOISE] = baseband.equalize(RECEIVED, CHANNEL,
%   NOISEVARIANCE, METHOD) equalises the received values y = h*s + w, w of
%   variance NOISEVARIANCE, with the channel estimates h of the same size:
%
%     "zf"    zero forcing: SYMBOLS = y/h, GAIN = 1,
%             NOISE = NOISEVARIANCE/|h|^2;
%     "mmse"  minimum mean square error (the default):
%             SYMBOLS = conj(h) y / (|h|^2 + NOISEVARIANCE), which is
%             GAIN*s plus noise, GAIN = |h|^2 / (|h|^2 + NOISEVARIANCE) and
%             NOISE = GAIN*(1 - GAIN) its variance.
%
%   SYMBOLS, GAIN and NOISE have the size of RECEIVED, and are what
%   baseband.qamLlr takes. MMSE symbols are closer to the sent ones in the
%   mean, ZF ones unbiased; with one antenna, both give the same LLRs.
%
%   See also baseband.qamLlr, baseband.receive.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        received double
        channel double
        noiseVariance (1,1) double {mustBeReal, mustBeNonnegative}
        method (1,1) string {mustBeMember(method, ["zf", "mmse"])} = "mmse"
    end
    if ~isequal(size(received), size(channel))
        error("baseband:equalize:size", "RECEIVED and CHANNEL must have the same size.");
    end
    power = abs(channel).^2;
    if method == "zf"
        symbols = received ./ channel;
        gain = ones(size(received));
        noise = noiseVariance ./ power;
    else
        symbols = conj(channel) .* received ./ (power + noiseVariance);
        gain = power ./ (power + noiseVariance);
        noise = gain .* (1 - gain);
    end
end
