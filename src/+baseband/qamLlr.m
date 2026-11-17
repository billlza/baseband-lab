function llr = qamLlr(symbols, gain, noise, order)
%QAMLLR Max-log bit log-likelihood ratios of received QAM symbols.
%   LLR = baseband.qamLlr(SYMBOLS, GAIN, NOISE, ORDER) gives, of each
%   received symbol y = GAIN*s + w, with s a point of baseband.qamModulate
%   and w complex Gaussian noise of variance NOISE, the log-likelihood
%   ratio log(P(b=0)/P(b=1)) of each of its bits by the max-log rule:
%
%     (min over s with b=1 of |y-GAIN*s|^2 - min over s with b=0 of
%      |y-GAIN*s|^2) / NOISE.
%
%   LLR is a column, the first symbol's bits first, in the order
%   baseband.qamModulate takes them, so a negative LLR decides a 1. GAIN
%   and NOISE are real and nonnegative, columns as long as SYMBOLS or
%   scalars. A zero NOISE gives infinite LLRs, the noiseless limit.
%
%   See also baseband.qamModulate, baseband.equalize.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        symbols (:,1) {mustBeNumeric}
        gain (:,1) double {mustBeReal, mustBeNonnegative}
        noise (:,1) double {mustBeReal, mustBeNonnegative}
        order (1,1) double {mustBeMember(order, [4 16 64])}
    end
    count = numel(symbols);
    if ~(isscalar(gain) || numel(gain) == count) || ~(isscalar(noise) || numel(noise) == count)
        error("baseband:qamLlr:size", ...
            "GAIN and NOISE must be scalars or as long as SYMBOLS (%d).", count);
    end
    width = log2(order);
    labels = dec2bin(0:order - 1, width) == '1';
    points = baseband.qamModulate(double(reshape(labels.', [], 1)), order);
    distances = abs(symbols.' - gain.' .* points).^2;
    llr = zeros(width, count);
    for bit = 1:width
        one = labels(:, bit);
        llr(bit, :) = (min(distances(one, :), [], 1) - min(distances(~one, :), [], 1)) ./ noise.';
    end
    llr = llr(:);
end
