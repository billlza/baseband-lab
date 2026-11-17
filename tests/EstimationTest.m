classdef EstimationTest < matlab.unittest.TestCase
%ESTIMATIONTEST The noise and channel estimates and the equalisers.

% SPDX-License-Identifier: GPL-3.0-or-later

    methods (Test)
        function theNoiseIsThePowerOnTheEmptySubcarriers(testCase)
            config = baseband.OfdmConfig();
            clean = binsWith(config, baseband.trainingSymbols(config));
            testCase.verifyEqual(baseband.estimateNoise(clean, config), 0);
            stream = RandStream("twister", "Seed", 30);
            estimates = zeros(400, 1);
            for trial = 1:numel(estimates)
                estimates(trial) = baseband.estimateNoise(baseband.addNoise(clean, 0.2, stream), config);
            end
            testCase.verifyEqual(mean(estimates), 0.2, "RelTol", 0.05);
            testCase.verifyError(@() baseband.estimateNoise(zeros(52, 1), config), "baseband:estimateNoise:bins");
        end

        function aChannelWithinThePrefixIsEstimatedExactly(testCase)
            % Taps 4 to 11 samples into the window, as the receiver's timing
            % puts a channel of 8 taps.
            config = baseband.OfdmConfig();
            [~, second] = baseband.trainingSymbols(config);
            response = frequencyResponse(config, baseband.multipathTaps(8, 2, RandStream("twister", "Seed", 31)), 4);
            received = binsWith(config, response .* second);
            testCase.verifyEqual(baseband.trainingChannel(received, config), response, "AbsTol", 1e-12);
            testCase.verifyEqual(baseband.trainingChannel(received, config, Projection=false), response, ...
                "AbsTol", 1e-12);
            testCase.verifyError(@() baseband.trainingChannel(zeros(52, 1), config), "baseband:trainingChannel:bins");
        end

        function theProjectionKeepsAPrefixsShareOfTheNoise(testCase)
            % The impulse responses within the prefix span 16 of the 52
            % dimensions, so 16/52 of the LS estimate's noise stays.
            config = baseband.OfdmConfig();
            [~, second] = baseband.trainingSymbols(config);
            clean = binsWith(config, second);
            stream = RandStream("twister", "Seed", 32);
            trials = 800;
            projected = zeros(trials, 1);
            raw = zeros(trials, 1);
            for trial = 1:trials
                noisy = baseband.addNoise(clean, 0.1, stream);
                projected(trial) = mean(abs(baseband.trainingChannel(noisy, config) - 1).^2);
                raw(trial) = mean(abs(baseband.trainingChannel(noisy, config, Projection=false) - 1).^2);
            end
            testCase.verifyEqual(mean(raw), 0.1, "RelTol", 0.05);
            testCase.verifyEqual(mean(projected), 0.1 * 16 / 52, "RelTol", 0.05);
        end

        function eachSymbolsPhaseIsTrackedByItsPilots(testCase)
            config = baseband.OfdmConfig();
            [~, second] = baseband.trainingSymbols(config);
            stream = RandStream("twister", "Seed", 33);
            response = frequencyResponse(config, baseband.multipathTaps(8, 2, stream), 2);
            phases = linspace(0, 2.5, config.DataSymbols);
            used = numel(config.UsedSubcarriers);
            values = response .* exp(1j * phases) .* ...
                (randn(stream, used, config.DataSymbols) + 1j * randn(stream, used, config.DataSymbols));
            values(config.PilotRows, :) = response(config.PilotRows) .* exp(1j * phases) ...
                .* baseband.pilotValues(config);
            channel = baseband.estimateChannel(binsWith(config, response .* second), binsWith(config, values), config);
            testCase.verifySize(channel, [numel(config.DataSubcarriers), config.DataSymbols]);
            testCase.verifyEqual(channel, response(config.DataRows) .* exp(1j * phases), "AbsTol", 1e-10);
            testCase.verifyError(@() baseband.estimateChannel(binsWith(config, second), zeros(64, 3), config), ...
                "baseband:estimateChannel:bins");
        end

        function withoutTheProjectionTheLsEstimateIsUsed(testCase)
            config = baseband.OfdmConfig();
            [~, second] = baseband.trainingSymbols(config);
            received = baseband.addNoise(binsWith(config, second), 0.1, RandStream("twister", "Seed", 34));
            ls = baseband.trainingChannel(received, config, Projection=false);
            testCase.verifyEqual(ls, received(config.binsOf(config.UsedSubcarriers)) ./ second);
            % Pilots that match the LS estimate leave its phase as it is.
            values = zeros(numel(config.UsedSubcarriers), config.DataSymbols);
            values(config.PilotRows, :) = ls(config.PilotRows) .* baseband.pilotValues(config);
            channel = baseband.estimateChannel(received, binsWith(config, values), config, Projection=false);
            testCase.verifyEqual(channel, repmat(ls(config.DataRows), 1, config.DataSymbols), "AbsTol", 1e-12);
        end

        function theEqualisersAreTheirFormulas(testCase)
            % y = 2 on h = j and y = 1 + j on h = 2, the noise variance 1.
            received = [2; 1 + 1j];
            channel = [1j; 2];
            [symbols, gain, noise] = baseband.equalize(received, channel, 1, "zf");
            testCase.verifyEqual(symbols, [-2j; 0.5 + 0.5j], "AbsTol", 1e-15);
            testCase.verifyEqual(gain, [1; 1]);
            testCase.verifyEqual(noise, [1; 0.25], "AbsTol", 1e-15);
            [symbols, gain, noise] = baseband.equalize(received, channel, 1);
            testCase.verifyEqual(symbols, [-1j; 0.4 + 0.4j], "AbsTol", 1e-15);
            testCase.verifyEqual(gain, [0.5; 0.8], "AbsTol", 1e-15);
            testCase.verifyEqual(noise, [0.25; 0.16], "AbsTol", 1e-15);
            testCase.verifyError(@() baseband.equalize([1; 2], [1; 2; 3], 0.1), "baseband:equalize:size");
            testCase.verifyError(@() baseband.equalize(1, 1, 0.1, "lms"), "MATLAB:validators:mustBeMember");
        end

        function mmseErrsLessAndBothGiveTheSameLlrs(testCase)
            stream = RandStream("twister", "Seed", 35);
            count = 20000;
            variance = 0.05;
            sent = baseband.qamModulate(randi(stream, [0 1], 4 * count, 1), 16);
            channel = 0.3 * (randn(stream, count, 1) + 1j * randn(stream, count, 1)) / sqrt(2);
            received = baseband.addNoise(channel .* sent, variance, stream);
            [mmse, mmseGain, mmseNoise] = baseband.equalize(received, channel, variance, "mmse");
            [zf, zfGain, zfNoise] = baseband.equalize(received, channel, variance, "zf");
            % Given h, the MMSE error has the mean variance / (|h|^2 + variance).
            testCase.verifyEqual(mean(abs(mmse - sent).^2), mean(variance ./ (abs(channel).^2 + variance)), ...
                "RelTol", 0.05);
            testCase.verifyLessThan(mean(abs(mmse - sent).^2), mean(abs(zf - sent).^2));
            fromMmse = baseband.qamLlr(mmse, mmseGain, mmseNoise, 16);
            fromZf = baseband.qamLlr(zf, zfGain, zfNoise, 16);
            testCase.verifyEqual(fromMmse, fromZf, "AbsTol", 1e-9 * max(abs(fromZf)));
        end
    end
end

function bins = binsWith(config, values)
% All FFT bins of symbols whose used subcarriers carry the columns VALUES.
    bins = zeros(config.FftLength, size(values, 2));
    bins(config.binsOf(config.UsedSubcarriers), :) = values;
end

function response = frequencyResponse(config, taps, delay)
% The used subcarriers' response to TAPS, the first DELAY samples late.
    lags = delay + (0:numel(taps) - 1);
    response = exp(-2j * pi * config.UsedSubcarriers * lags / config.FftLength) * taps;
end
