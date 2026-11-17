classdef QamTest < matlab.unittest.TestCase
%QAMTEST The QAM mapping of TS 38.211 and its max-log demapping.

% SPDX-License-Identifier: GPL-3.0-or-later

    properties (TestParameter)
        Order = {4, 16, 64}
    end

    methods (Test)
        function theConstellationHasUnitPowerAndGrayNeighbours(testCase, Order)
            width = log2(Order);
            labels = dec2bin(0:Order - 1, width) == '1';
            points = baseband.qamModulate(double(reshape(labels.', [], 1)), Order);
            testCase.verifyEqual(mean(abs(points).^2), 1, "AbsTol", 1e-12);
            distance = abs(points - points.');
            nearest = min(distance(distance > 1e-9));
            testCase.verifyEqual(nearest, 2 / sqrt(2 * (Order - 1) / 3), "AbsTol", 1e-12);
            [a, b] = find(abs(distance - nearest) < 1e-9);
            testCase.verifyEqual(sum(labels(a, :) ~= labels(b, :), 2), ones(numel(a), 1));
            testCase.verifyEqual(numel(unique(round(points * 1e9))), Order);
        end

        function thePointsAreTheStandardsOnes(testCase)
            testCase.verifyEqual(baseband.qamModulate([0; 0; 0; 1; 1; 0; 1; 1], 4), ...
                [1 + 1j; 1 - 1j; -1 + 1j; -1 - 1j] / sqrt(2), "AbsTol", 1e-12);
            testCase.verifyEqual(baseband.qamModulate( ...
                [0; 0; 0; 0; 0; 0; 0; 1; 0; 0; 1; 0; 0; 0; 1; 1; 1; 1; 1; 1], 16), ...
                [1 + 1j; 1 + 3j; 3 + 1j; 3 + 3j; -3 - 3j] / sqrt(10), "AbsTol", 1e-12);
            testCase.verifyEqual(baseband.qamModulate( ...
                [0; 0; 0; 0; 0; 0; 1; 1; 1; 1; 1; 1; 0; 0; 0; 0; 1; 0], 64), ...
                [3 + 3j; -7 - 7j; 1 + 3j] / sqrt(42), "AbsTol", 1e-12);
            testCase.verifySize(baseband.qamModulate(zeros(0, 1), 16), [0, 1]);
        end

        function qpskLlrsAreTheirClosedForm(testCase)
            stream = RandStream("twister", "Seed", 5);
            y = randn(stream, 20, 1) + 1j * randn(stream, 20, 1);
            gain = 0.2 + rand(stream, 20, 1);
            noise = 0.1 + rand(stream, 20, 1);
            llr = reshape(baseband.qamLlr(y, gain, noise, 4), 2, []);
            testCase.verifyEqual(llr(1, :).', 2 * sqrt(2) * gain .* real(y) ./ noise, "AbsTol", 1e-10);
            testCase.verifyEqual(llr(2, :).', 2 * sqrt(2) * gain .* imag(y) ./ noise, "AbsTol", 1e-10);
        end

        function noiselessSymbolsDecideTheirOwnBits(testCase, Order)
            stream = RandStream("twister", "Seed", 6);
            bits = randi(stream, [0 1], 600 * log2(Order), 1);
            llr = baseband.qamLlr(0.7 * baseband.qamModulate(bits, Order), 0.7, 0.01, Order);
            testCase.verifyEqual(double(llr < 0), bits);
            testCase.verifyEqual(sign(baseband.qamLlr(baseband.qamModulate(bits, Order), 1, 0, Order)), ...
                1 - 2 * bits);
        end

        function hardDecisionsInWhiteNoiseMeetTheTheory(testCase, Order)
            % The modem alone, at an SNR where the theory gives about 1e-2.
            snr = 3 * log2(Order) + 1;
            stream = RandStream("twister", "Seed", 7);
            bits = randi(stream, [0 1], 100000 * log2(Order), 1);
            received = baseband.addNoise(baseband.qamModulate(bits, Order), 10^(-snr / 10), stream);
            llr = baseband.qamLlr(received, 1, 10^(-snr / 10), Order);
            ber = mean(double(llr < 0) ~= bits);
            testCase.verifyEqual(ber, baseband.theoryBer(Order, snr), "RelTol", 0.1);
        end

        function inputsMustFitTogether(testCase)
            testCase.verifyError(@() baseband.qamModulate([0; 1; 1], 4), "baseband:qamModulate:bitCount");
            testCase.verifyError(@() baseband.qamLlr([1; 1j], [1; 1; 1], 0.1, 4), "baseband:qamLlr:size");
            testCase.verifyError(@() baseband.qamLlr([1; 1j], 1, [0.1; 0.1; 0.1], 4), "baseband:qamLlr:size");
            testCase.verifySize(baseband.qamLlr(zeros(0, 1), 1, 1, 16), [0, 1]);
        end
    end
end
