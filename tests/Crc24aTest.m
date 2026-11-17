classdef Crc24aTest < matlab.unittest.TestCase
%CRC24ATEST CRC-24A: the catalogue's check value and the errors it catches.

% SPDX-License-Identifier: GPL-3.0-or-later

    methods (Test)
        function theCheckValueIsTheCataloguesOne(testCase)
            % CRC-24/LTE-A of the ASCII digits 1 to 9, most significant bit
            % first, is 0xCDE703.
            message = reshape(dec2bin(double('123456789'), 8).' == '1', [], 1);
            parity = baseband.crc24a(double(message));
            testCase.verifyEqual(parity', double(dec2bin(hex2dec('CDE703'), 24) == '1'));
        end

        function bitsWithTheirParityHaveParityZero(testCase)
            stream = RandStream("twister", "Seed", 3);
            bits = randi(stream, [0 1], 500, 1);
            testCase.verifyEqual(baseband.crc24a([bits; baseband.crc24a(bits)]), zeros(24, 1));
        end

        function everySingleErrorAndEveryShortBurstIsCaught(testCase)
            stream = RandStream("twister", "Seed", 4);
            bits = randi(stream, [0 1], 200, 1);
            frame = [bits; baseband.crc24a(bits)];
            for position = 1:numel(frame)
                flipped = frame;
                flipped(position) = 1 - flipped(position);
                testCase.verifyTrue(any(baseband.crc24a(flipped)), sprintf("bit %d", position));
            end
            for first = 1:7:numel(frame) - 23
                burst = frame;
                burst(first:first + 23) = 1 - burst(first:first + 23);
                testCase.verifyTrue(any(baseband.crc24a(burst)), sprintf("burst from %d", first));
            end
        end

        function nothingHasParityZeroAndOnlyBitsAreTaken(testCase)
            testCase.verifyEqual(baseband.crc24a(zeros(0, 1)), zeros(24, 1));
            testCase.verifyError(@() baseband.crc24a([0; 2]), "MATLAB:validators:mustBeMember");
        end
    end
end
