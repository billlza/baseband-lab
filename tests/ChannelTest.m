classdef ChannelTest < matlab.unittest.TestCase
%CHANNELTEST The channel's noise, frequency offset and multipath.

% SPDX-License-Identifier: GPL-3.0-or-later

    methods (Test)
        function noiseHasTheVarianceAskedForHalfInEachPart(testCase)
            stream = RandStream("twister", "Seed", 11);
            noise = baseband.addNoise(zeros(200000, 1), 0.3, stream);
            testCase.verifyEqual(mean(abs(noise).^2), 0.3, "RelTol", 0.02);
            testCase.verifyEqual(var(real(noise)), 0.15, "RelTol", 0.02);
            testCase.verifyEqual(var(imag(noise)), 0.15, "RelTol", 0.02);
            testCase.verifyLessThan(abs(mean(real(noise) .* imag(noise))), 0.005);
            testCase.verifyEqual(baseband.addNoise([1; 2j], 0, stream), [1; 2j]);
        end

        function theSameSeedGivesTheSameNoise(testCase)
            a = baseband.addNoise(zeros(10, 2), 1, RandStream("twister", "Seed", 12));
            b = baseband.addNoise(zeros(10, 2), 1, RandStream("twister", "Seed", 12));
            testCase.verifyEqual(a, b);
            testCase.verifySize(a, [10, 2]);
        end

        function anOffsetMovesAToneByWholeSubcarriers(testCase)
            tone = exp(2j * pi * 5 * (0:63)' / 64);
            shifted = baseband.frequencyOffset(tone, 3, 64);
            [~, bin] = max(abs(fft(shifted)));
            testCase.verifyEqual(bin, 9);
            testCase.verifyEqual(baseband.frequencyOffset(shifted, -3, 64), tone, "AbsTol", 1e-12);
            testCase.verifyEqual(baseband.frequencyOffset(tone, 0, 64), tone);
        end

        function multipathHasUnitMeanPowerAndDecayingTaps(testCase)
            stream = RandStream("twister", "Seed", 13);
            draws = 4000;
            power = zeros(8, draws);
            for draw = 1:draws
                power(:, draw) = abs(baseband.multipathTaps(8, 2, stream)).^2;
            end
            % The total power of a draw has a standard deviation of about
            % 0.5, so its mean over 4000 one of 0.008.
            testCase.verifyEqual(mean(sum(power, 1)), 1, "RelTol", 0.04);
            profile = exp(-(0:7)' / 2);
            testCase.verifyEqual(mean(power, 2), profile / sum(profile), "RelTol", 0.1);
            testCase.verifySize(baseband.multipathTaps(3, 1, stream), [3, 1]);
        end
    end
end
