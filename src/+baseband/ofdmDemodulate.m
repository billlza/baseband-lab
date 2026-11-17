function bins = ofdmDemodulate(samples, start, count, config)
%OFDMDEMODULATE The FFT bins of consecutive OFDM symbols.
%   BINS = baseband.ofdmDemodulate(SAMPLES, START, COUNT, CONFIG) takes
%   COUNT symbols from the column SAMPLES, the first one's FFT window
%   beginning at sample START (after its cyclic prefix) and each next one
%   SymbolLength samples later, and gives their FFTs scaled by
%   1/sqrt(FftLength), the inverse of baseband.ofdmModulate's scaling: one
%   column a symbol, all FftLength bins (CONFIG.binsOf picks subcarriers).
%   It refuses windows that do not lie inside SAMPLES.
%
%   See also baseband.ofdmModulate, baseband.receive.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        samples (:,1) double
        start (1,1) double {mustBeInteger, mustBePositive}
        count (1,1) double {mustBeInteger, mustBePositive}
        config (1,1) baseband.OfdmConfig
    end
    last = start + (count - 1) * config.SymbolLength + config.FftLength - 1;
    if last > numel(samples)
        error("baseband:ofdmDemodulate:outside", ...
            "%d symbols from sample %d need %d samples; there are %d.", ...
            count, start, last, numel(samples));
    end
    index = start + (0:config.FftLength - 1)' + (0:count - 1) * config.SymbolLength;
    bins = fft(samples(index)) / sqrt(config.FftLength);
end
