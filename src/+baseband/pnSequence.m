function bits = pnSequence(count, seed)
%PNSEQUENCE Bits of the PRBS9 pseudo-noise sequence.
%   BITS = baseband.pnSequence(COUNT, SEED) gives COUNT bits, a column of 0
%   and 1, of the sequence a(n) = a(n-9) XOR a(n-5), whose period is 511,
%   from the nonzero 9-bit state SEED (1 to 511). The training symbols and
%   the pilots take their values from it, so that the transmitter and the
%   receiver know them without sharing anything else.
%
%   See also baseband.trainingSymbols, baseband.pilotValues.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        count (1,1) double {mustBeInteger, mustBeNonnegative}
        seed (1,1) double {mustBeInteger, mustBePositive, mustBeLessThanOrEqual(seed, 511)}
    end
    state = uint16(seed);
    bits = zeros(count, 1);
    for index = 1:count
        bit = bitand(bitxor(bitshift(state, -8), bitshift(state, -4)), uint16(1));
        state = bitand(bitor(bitshift(state, 1), bit), uint16(511));
        bits(index) = double(bit);
    end
end
