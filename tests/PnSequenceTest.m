classdef PnSequenceTest < matlab.unittest.TestCase
%PNSEQUENCETEST The PRBS9 sequence: its recurrence, period and seeds.

% SPDX-License-Identifier: GPL-3.0-or-later

    methods (Test)
        function itFollowsItsRecurrence(testCase)
            bits = baseband.pnSequence(600, 77);
            n = (10:600)';
            testCase.verifyEqual(bits(n), double(xor(bits(n - 9), bits(n - 5))));
        end

        function itRepeatsEvery511BitsAndNoSooner(testCase)
            bits = baseband.pnSequence(1022, 1);
            testCase.verifyEqual(bits(1:511), bits(512:1022));
            % 511 is 7 times 73.
            for period = [1 7 73]
                testCase.verifyNotEqual(bits(1:511), circshift(bits(1:511), period));
            end
            testCase.verifyEqual(nnz(bits(1:511)), 256);
        end

        function theFirstBitsOfSeedOneAreKnown(testCase)
            testCase.verifyEqual(baseband.pnSequence(16, 1)', [0 0 0 0 1 0 0 0 1 1 0 0 0 0 1 0]);
        end

        function anotherSeedStartsElsewhereInTheSameSequence(testCase)
            one = baseband.pnSequence(511, 1);
            other = baseband.pnSequence(511, 300);
            matches = arrayfun(@(shift) isequal(circshift(one, -shift), other), 0:510);
            testCase.verifyEqual(find(matches) - 1, 186);
        end

        function noBitsOrABadSeed(testCase)
            testCase.verifyEqual(baseband.pnSequence(0, 5), zeros(0, 1));
            testCase.verifyError(@() baseband.pnSequence(4, 0), "MATLAB:validators:mustBePositive");
            testCase.verifyError(@() baseband.pnSequence(4, 512), "MATLAB:validators:mustBeLessThanOrEqual");
        end
    end
end
