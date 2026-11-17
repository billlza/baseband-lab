function [correlation, metric] = schmidlCox(samples, config)
%SCHMIDLCOX The Schmidl-Cox timing metric of every possible frame start.
%   [CORRELATION, METRIC] = baseband.schmidlCox(SAMPLES, CONFIG) computes,
%   for each start d at which a whole frame fits in the column SAMPLES
%   (d = 1, 2, ..., numel(SAMPLES) - FrameLength + CyclicPrefixLength + 1),
%   with L = FftLength/2,
%
%     CORRELATION(d) = sum over m = 0..L-1 of conj(y(d+m)) * y(d+m+L),
%     METRIC(d)      = |CORRELATION(d)|^2 / R(d)^2,
%     R(d)           = sum over m = 0..L-1 of |y(d+m+L)|^2,
%
%   (Schmidl and Cox, IEEE Trans. Commun., 1997). Over the first training
%   symbol, whose two halves are equal, METRIC is near one; the angle of
%   CORRELATION there is pi times the frequency offset in subcarrier
%   spacings, modulo 2 spacings. METRIC is zero where R is. Both are
%   empty columns when SAMPLES are shorter than a frame.
%
%   See also baseband.detectFrame, baseband.refineOffset.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        samples (:,1) double
        config (1,1) baseband.OfdmConfig
    end
    half = config.FftLength / 2;
    starts = numel(samples) - (config.FrameLength - config.CyclicPrefixLength) + 1;
    if starts < 1
        correlation = complex(zeros(0, 1));
        metric = zeros(0, 1);
        return
    end
    products = conj(samples(1:end - half)) .* samples(1 + half:end);
    energies = abs(samples(1 + half:end)).^2;
    window = ones(half, 1);
    sums = filter(window, 1, products);
    powers = filter(window, 1, energies);
    correlation = sums(half:half + starts - 1);
    power = powers(half:half + starts - 1);
    metric = zeros(starts, 1);
    positive = power > 0;
    metric(positive) = abs(correlation(positive)).^2 ./ power(positive).^2;
end
