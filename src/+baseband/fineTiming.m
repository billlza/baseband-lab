function start = fineTiming(samples, coarse, config)
%FINETIMING The FFT window from the frame's first path.
%   START = baseband.fineTiming(SAMPLES, COARSE, CONFIG) refines the coarse
%   start COARSE of baseband.detectFrame. SAMPLES must already be corrected
%   for the frequency offset. It correlates them with the second training
%   symbol's samples (its FFT window, without the cyclic prefix) at every
%   lag within FftLength/2 of where COARSE puts that symbol, takes the
%   strongest lag, and, since a channel within the cyclic prefix puts its
%   first path less than CyclicPrefixLength samples before its strongest,
%   the first lag of the CyclicPrefixLength before it whose correlation
%   power reaches 0.2 of the strongest's: the first path. START is the
%   first training symbol's window that puts the first path a quarter of
%   the cyclic prefix into the prefix, the margin against an early path
%   missed. It may lie outside SAMPLES; the caller judges that.
%
%   See also baseband.receive, baseband.detectFrame.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        samples (:,1) double
        coarse (1,1) double {mustBeInteger, mustBePositive}
        config (1,1) baseband.OfdmConfig
    end
    [~, second] = baseband.trainingSymbols(config);
    bins = zeros(config.FftLength, 1);
    bins(config.binsOf(config.UsedSubcarriers)) = second;
    template = ifft(bins) * sqrt(config.FftLength);

    centre = coarse + config.SymbolLength;
    reach = config.FftLength / 2;
    lags = (max(1, centre - reach):min(numel(samples) - config.FftLength + 1, centre + reach))';
    if isempty(lags)
        error("baseband:fineTiming:outside", ...
            "No lag near sample %d leaves room for a symbol in %d samples.", centre, numel(samples));
    end
    windows = samples(lags.' + (0:config.FftLength - 1)');
    power = abs(template' * windows).^2;
    [largest, strongest] = max(power);
    earliest = max(1, strongest - config.CyclicPrefixLength);
    first = earliest - 1 + find(power(earliest:strongest) >= 0.2 * largest, 1);
    start = lags(first) - floor(config.CyclicPrefixLength / 4) - config.SymbolLength;
end
