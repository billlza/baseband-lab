function waveform = ofdmModulate(grid, config)
%OFDMMODULATE OFDM symbols with their cyclic prefixes, from a grid.
%   WAVEFORM = baseband.ofdmModulate(GRID, CONFIG) turns each column of
%   GRID, the values of one symbol on CONFIG.UsedSubcarriers, into
%   FftLength samples by the inverse FFT, scaled by sqrt(FftLength) so that
%   a symbol's energy in time equals its energy on the subcarriers, and
%   puts its last CyclicPrefixLength samples before it. WAVEFORM is the
%   column of the symbols one after the other. The DC and guard
%   subcarriers carry nothing.
%
%   See also baseband.ofdmDemodulate, baseband.transmit.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        grid (:,:) {mustBeNumeric}
        config (1,1) baseband.OfdmConfig
    end
    if size(grid, 1) ~= numel(config.UsedSubcarriers)
        error("baseband:ofdmModulate:rows", ...
            "GRID has %d rows; the configuration uses %d subcarriers.", ...
            size(grid, 1), numel(config.UsedSubcarriers));
    end
    bins = zeros(config.FftLength, size(grid, 2));
    bins(config.binsOf(config.UsedSubcarriers), :) = grid;
    symbols = ifft(bins) * sqrt(config.FftLength);
    withPrefix = [symbols(end - config.CyclicPrefixLength + 1:end, :); symbols];
    waveform = withPrefix(:);
end
