function variance = estimateNoise(first, config)
%ESTIMATENOISE The noise variance from the first training symbol's nulls.
%   VARIANCE = baseband.estimateNoise(FIRST, CONFIG) takes the FFT bins of
%   the received first training symbol, corrected for the frequency
%   offset, and gives the mean power of its odd used subcarriers, which the
%   transmitter leaves empty: the noise variance a subcarrier carries. It
%   sees whatever else falls there too, such as interference from a
%   residual frequency offset.
%
%   See also baseband.receive, baseband.trainingSymbols.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        first (:,1) double
        config (1,1) baseband.OfdmConfig
    end
    if numel(first) ~= config.FftLength
        error("baseband:estimateNoise:bins", "FIRST must hold all %d FFT bins.", config.FftLength);
    end
    k = config.UsedSubcarriers;
    odd = k(mod(k, 2) ~= 0);
    variance = mean(abs(first(config.binsOf(odd))).^2);
end
