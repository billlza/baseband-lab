classdef TheoryBerTest < matlab.unittest.TestCase
%THEORYBERTEST The exact QAM bit error rates, in white noise and in Rayleigh fading.

% SPDX-License-Identifier: GPL-3.0-or-later

    properties (TestParameter)
        Channel = {"awgn", "rayleigh"}
    end

    methods (Test)
        function qpskIsTheErfcOfHalfTheSnr(testCase)
            esn0 = (0:2:14)';
            testCase.verifyEqual(baseband.theoryBer(4, esn0), erfc(sqrt(10.^(esn0 / 10) / 2)) / 2, ...
                "RelTol", 1e-12);
        end

        function sixteenQamIsItsKnownClosedForm(testCase)
            esn0 = (0:3:24)';
            a = sqrt(10.^(esn0 / 10) / 10);
            expected = 3 / 8 * erfc(a) + 1 / 4 * erfc(3 * a) - 1 / 8 * erfc(5 * a);
            testCase.verifyEqual(baseband.theoryBer(16, esn0), expected, "RelTol", 1e-12);
        end

        function rayleighQpskIsItsClosedForm(testCase)
            esn0 = (0:5:30)';
            g = 10.^(esn0 / 10) / 2;
            testCase.verifyEqual(baseband.theoryBer(4, esn0, Channel="rayleigh"), (1 - sqrt(g ./ (1 + g))) / 2, ...
                "RelTol", 1e-12);
        end

        function rayleighSixteenQamAveragesEachTerm(testCase)
            % The white-noise form's erfc(sqrt(c Es/N0)) become
            % 1 - mu(c), mu(c) = sqrt(c Es/N0 / (1 + c Es/N0)).
            esn0 = 10.^((0:5:30)' / 10);
            mu = @(c) sqrt(c * esn0 ./ (1 + c * esn0));
            expected = 3 / 8 * (1 - mu(0.1)) + 1 / 4 * (1 - mu(0.9)) - 1 / 8 * (1 - mu(2.5));
            testCase.verifyEqual(baseband.theoryBer(16, (0:5:30)', Channel="rayleigh"), expected, "RelTol", 1e-12);
        end

        function theRateFallsWithTheSnrAndRisesWithTheOrder(testCase, Channel)
            esn0 = 0:2:30;
            for order = [4 16 64]
                testCase.verifyTrue(all(diff(baseband.theoryBer(order, esn0, Channel=Channel)) < 0), ...
                    sprintf("order %d", order));
                % Without signal half the bits are guessed wrong.
                testCase.verifyEqual(baseband.theoryBer(order, -80, Channel=Channel), 0.5, "AbsTol", 1e-3);
            end
            testCase.verifyLessThan(baseband.theoryBer(4, 10, Channel=Channel), ...
                baseband.theoryBer(16, 10, Channel=Channel));
            testCase.verifyLessThan(baseband.theoryBer(16, 10, Channel=Channel), ...
                baseband.theoryBer(64, 10, Channel=Channel));
            testCase.verifySize(baseband.theoryBer(16, zeros(2, 3), Channel=Channel), [2 3]);
        end

        function fadingCostsAndItsRateFallsTenfoldADecade(testCase)
            for order = [4 16 64]
                testCase.verifyGreaterThan(baseband.theoryBer(order, 0:5:30, Channel="rayleigh"), ...
                    baseband.theoryBer(order, 0:5:30), sprintf("order %d", order));
                testCase.verifyEqual(baseband.theoryBer(order, 50, Channel="rayleigh") ...
                    / baseband.theoryBer(order, 60, Channel="rayleigh"), 10, "RelTol", 1e-3);
            end
            testCase.verifyError(@() baseband.theoryBer(4, 10, Channel="multipath"), "MATLAB:validators:mustBeMember");
        end
    end
end
