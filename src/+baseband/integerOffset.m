function [shift, score] = integerOffset(first, second, config, searchRange)
%INTEGEROFFSET The frequency offset's whole part, in pairs of subcarriers.
%   [SHIFT, SCORE] = baseband.integerOffset(FIRST, SECOND, CONFIG,
%   SEARCHRANGE) takes the FFT bins (all FftLength of them, as
%   baseband.ofdmDemodulate gives them) of the two received training
%   symbols, already corrected for the fractional offset, so that what
%   offset remains is an even number 2g of subcarriers. For each g from
%   -SEARCHRANGE to SEARCHRANGE it correlates the bins 2g above the even
%   subcarriers with the known products of the two symbols there
%   (Schmidl and Cox, 1997):
%
%     B(g) = |sum over even k of conj(v(k)) conj(X1(k+2g)) X2(k+2g)|^2 /
%            (sum |v(k) X1(k+2g)|^2 * sum |X2(k+2g)|^2),
%
%   with v = conj(FIRST symbol) .* SECOND symbol. The channel and the
%   timing within the cyclic prefix act alike on both symbols and cancel.
%   SHIFT is the g of the largest B, the first of equal ones, and SCORE
%   that B, between 0 and 1.
%
%   See also baseband.receive, baseband.trainingSymbols.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        first (:,1) double
        second (:,1) double
        config (1,1) baseband.OfdmConfig
        searchRange (1,1) double {mustBeInteger, mustBeNonnegative}
    end
    if numel(first) ~= config.FftLength || numel(second) ~= config.FftLength
        error("baseband:integerOffset:bins", ...
            "FIRST and SECOND must hold all %d FFT bins.", config.FftLength);
    end
    [known1, known2] = baseband.trainingSymbols(config);
    k = config.UsedSubcarriers;
    even = mod(k, 2) == 0;
    product = conj(known1(even)) .* known2(even);
    shifts = (-searchRange:searchRange)';
    scores = zeros(size(shifts));
    for index = 1:numel(shifts)
        bins = config.binsOf(k(even) + 2 * shifts(index));
        x1 = first(bins);
        x2 = second(bins);
        denominator = sum(abs(product .* x1).^2) * sum(abs(x2).^2);
        if denominator > 0
            scores(index) = abs(sum(conj(product) .* conj(x1) .* x2))^2 / denominator;
        end
    end
    [score, best] = max(scores);
    shift = shifts(best);
end
