function symbols = qamModulate(bits, order)
%QAMMODULATE Gray-mapped square QAM of unit mean power.
%   SYMBOLS = baseband.qamModulate(BITS, ORDER) maps the column of bits
%   BITS, LOG2(ORDER) of them a symbol, to a column of QPSK, 16QAM or 64QAM
%   symbols (ORDER 4, 16 or 64) as 3GPP TS 38.211 section 5.1 maps them:
%   of a symbol's bits b(1), b(2), b(3), ..., the odd ones give the real
%   part and the even ones the imaginary part, the first of each its sign.
%   For 16QAM, for example,
%
%     s = ((1-2b1)(2-(1-2b3)) + j(1-2b2)(2-(1-2b4))) / sqrt(10).
%
%   Neighbouring points differ in one bit, and the mean power over the
%   constellation is one.
%
%   See also baseband.qamLlr, baseband.theoryBer.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        bits (:,1) double {mustBeMember(bits, [0 1])}
        order (1,1) double {mustBeMember(order, [4 16 64])}
    end
    width = log2(order);
    if mod(numel(bits), width) ~= 0
        error("baseband:qamModulate:bitCount", ...
            "%d bits do not make whole symbols of %d bits.", numel(bits), width);
    end
    grouped = reshape(bits, width, []);
    inPhase = amplitude(grouped(1:2:end, :));
    quadrature = amplitude(grouped(2:2:end, :));
    symbols = ((inPhase + 1j * quadrature) / sqrt(2 * (order - 1) / 3)).';
end

function value = amplitude(levels)
% One dimension's amplitudes, one column of bits a symbol, the sign bit
% first: 1, 3, 5 or 7 times the sign, nested as TS 38.211 writes them.
    count = size(levels, 1);
    value = ones(1, size(levels, 2));
    for level = count:-1:2
        value = 2^(count - level + 1) - (1 - 2 * levels(level, :)) .* value;
    end
    value = (1 - 2 * levels(1, :)) .* value;
end
