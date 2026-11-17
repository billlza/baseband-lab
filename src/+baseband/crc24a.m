function parity = crc24a(bits)
%CRC24A The 24 parity bits of CRC-24A.
%   PARITY = baseband.crc24a(BITS) is the CRC-24A of 3GPP TS 38.212
%   section 5.1 over the column of bits BITS (0 or 1), the first bit the
%   most significant: generator 0x864CFB, the register starting at zero,
%   nothing reflected or inverted. PARITY is a column of 24 bits, the most
%   significant first. BITS followed by PARITY has the parity zero, which
%   is how the receiver checks a frame.
%
%   See also baseband.transmit, baseband.receive.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        bits (:,1) double {mustBeMember(bits, [0 1])}
    end
    generator = uint32(0x864CFB);
    register = uint32(0);
    for index = 1:numel(bits)
        feedback = bitxor(bitshift(register, -23), uint32(bits(index)));
        register = bitand(bitshift(register, 1), uint32(0xFFFFFF));
        if feedback
            register = bitxor(register, generator);
        end
    end
    parity = double(bitget(register, 24:-1:1))';
end
