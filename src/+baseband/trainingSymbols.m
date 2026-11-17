function [first, second] = trainingSymbols(config)
%TRAININGSYMBOLS The frame's two known training symbols.
%   [FIRST, SECOND] = baseband.trainingSymbols(CONFIG) gives the values of
%   the two training symbols on CONFIG.UsedSubcarriers, real columns in
%   that order:
%
%     FIRST   sqrt(2) times a PN BPSK sequence on the even subcarriers and
%             zero on the odd ones, so that the symbol's two halves are
%             equal in time and its power is about that of a full symbol;
%     SECOND  a PN BPSK sequence on every used subcarrier.
%
%   The sequences are baseband.pnSequence's from the seeds 29 and 101.
%
%   See also baseband.transmit, baseband.schmidlCox, baseband.integerOffset.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        config (1,1) baseband.OfdmConfig
    end
    k = config.UsedSubcarriers;
    even = mod(k, 2) == 0;
    first = zeros(size(k));
    first(even) = sqrt(2) * (1 - 2 * baseband.pnSequence(nnz(even), 29));
    second = 1 - 2 * baseband.pnSequence(numel(k), 101);
end
