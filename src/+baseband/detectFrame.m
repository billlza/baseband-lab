function [start, fraction, peak] = detectFrame(samples, config, threshold)
%DETECTFRAME The coarse start and fractional frequency offset of a frame.
%   [START, FRACTION, PEAK] = baseband.detectFrame(SAMPLES, CONFIG,
%   THRESHOLD) finds the first training symbol by its Schmidl-Cox metric
%   (baseband.schmidlCox). PEAK is the metric's largest value. When it
%   reaches THRESHOLD, the CyclicPrefixLength+1 consecutive starts over
%   which the metric's sum is largest mark the cyclic prefix's plateau;
%   START is their middle, a coarse estimate of the first training
%   symbol's FFT window in samples, and FRACTION is the frequency offset
%   modulo 2 subcarrier spacings, in (-1, 1], from the correlation's angle
%   there. Unlike the run of values near PEAK, which noise can cut short,
%   the sum keeps START near the plateau's middle, and so the windows of
%   baseband.integerOffset free of the next symbol. Otherwise, or when
%   SAMPLES are shorter than a frame, START and FRACTION are empty: no
%   frame.
%
%   See also baseband.receive, baseband.fineTiming, baseband.integerOffset.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        samples (:,1) double
        config (1,1) baseband.OfdmConfig
        threshold (1,1) double {mustBePositive, mustBeLessThanOrEqual(threshold, 1)}
    end
    [correlation, metric] = baseband.schmidlCox(samples, config);
    start = [];
    fraction = [];
    peak = 0;
    if isempty(metric)
        return
    end
    peak = max(metric);
    if peak < threshold
        return
    end
    width = min(config.CyclicPrefixLength + 1, numel(metric));
    sums = filter(ones(width, 1), 1, metric);
    [~, first] = max(sums(width:end));
    start = first + floor((width - 1) / 2);
    fraction = angle(correlation(start)) / pi;
end
