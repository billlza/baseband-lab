classdef SyncTest < matlab.unittest.TestCase
%SYNCTEST Finding a frame, its frequency offset and its first path.

% SPDX-License-Identifier: GPL-3.0-or-later

    methods (Test)
        function theMetricIsOneAcrossTheCyclicPrefix(testCase)
            config = baseband.OfdmConfig();
            [buffer, ~, truth] = impairedFrame(config, RandStream("twister", "Seed", 20));
            [~, metric] = baseband.schmidlCox(buffer, config);
            testCase.verifySize(metric, [numel(buffer) - config.FrameLength + config.CyclicPrefixLength + 1, 1]);
            plateau = truth.Start - config.CyclicPrefixLength:truth.Start;
            testCase.verifyEqual(metric(plateau), ones(numel(plateau), 1), "AbsTol", 1e-12);
            near = truth.Start - 2 * config.CyclicPrefixLength:truth.Start + config.CyclicPrefixLength;
            testCase.verifyLessThan(max(metric(setdiff(1:numel(metric), near))), 0.9);
        end

        function aCleanFrameIsFoundWithItsFractionalOffset(testCase)
            % The start is the middle of the cyclic prefix's plateau.
            config = baseband.OfdmConfig();
            for offset = [-0.9, -0.3, 0, 0.45, 0.99]
                [buffer, ~, truth] = impairedFrame(config, RandStream("twister", "Seed", 21), ...
                    Delay=50, Offset=offset);
                [start, fraction, peak] = baseband.detectFrame(buffer, config, 0.4);
                testCase.verifyEqual(start, truth.Start - config.CyclicPrefixLength / 2);
                testCase.verifyEqual(fraction, offset, "AbsTol", 1e-9);
                testCase.verifyEqual(peak, 1, "AbsTol", 1e-9);
            end
        end

        function theCoarseStartStaysClearOfTheNextSymbolInNoise(testCase)
            % 10 dB through multipath of 8 taps. A start past the first
            % path's would let the next symbol into the windows of
            % baseband.integerOffset; the run of values near the peak, which
            % noise cuts short, put about a fifth of the starts there.
            config = baseband.OfdmConfig(ModulationOrder=4);
            stream = RandStream("twister", "Seed", 27);
            late = false(200, 1);
            for trial = 1:numel(late)
                [buffer, ~, truth] = impairedFrame(config, stream, Delay=randi(stream, [0 60]), ...
                    Offset=8 * rand(stream) - 4, Taps=baseband.multipathTaps(8, 2, stream), Variance=0.1);
                start = baseband.detectFrame(buffer, config, 0.4);
                late(trial) = ~isempty(start) && start > truth.Start;
            end
            testCase.verifyLessThanOrEqual(nnz(late), 10);
        end

        function noiseAloneIsRarelyTakenForAFrame(testCase)
            config = baseband.OfdmConfig();
            stream = RandStream("twister", "Seed", 22);
            found = 0;
            peaks = zeros(200, 1);
            for trial = 1:200
                [start, ~, peaks(trial)] = baseband.detectFrame( ...
                    baseband.addNoise(zeros(1500, 1), 1, stream), config, 0.4);
                found = found + ~isempty(start);
            end
            testCase.verifyLessThanOrEqual(found, 10);
            testCase.verifyLessThan(median(peaks), 0.3);
        end

        function tooFewSamplesOrSilenceIsNoFrame(testCase)
            config = baseband.OfdmConfig();
            [start, fraction, peak] = baseband.detectFrame(zeros(config.FrameLength - 17, 1), config, 0.4);
            testCase.verifyEmpty(start);
            testCase.verifyEmpty(fraction);
            testCase.verifyEqual(peak, 0);
            [start, ~, peak] = baseband.detectFrame(zeros(2000, 1), config, 0.4);
            testCase.verifyEmpty(start);
            testCase.verifyEqual(peak, 0);
        end

        function theWholeOffsetIsFoundThroughMultipath(testCase)
            config = baseband.OfdmConfig();
            stream = RandStream("twister", "Seed", 23);
            for whole = -2:2
                buffer = impairedFrame(config, stream, Delay=30, Offset=2 * whole + 0.3, ...
                    Taps=baseband.multipathTaps(8, 2, stream));
                [coarse, fraction] = baseband.detectFrame(buffer, config, 0.4);
                corrected = baseband.frequencyOffset(buffer, -fraction, config.FftLength);
                bins = baseband.ofdmDemodulate(corrected, coarse, 2, config);
                [shift, score] = baseband.integerOffset(bins(:, 1), bins(:, 2), config, 2);
                testCase.verifyEqual(shift, whole);
                testCase.verifyGreaterThan(score, 0.5);
            end
        end

        function nothingReceivedScoresNothing(testCase)
            config = baseband.OfdmConfig();
            [shift, score] = baseband.integerOffset(zeros(64, 1), zeros(64, 1), config, 1);
            testCase.verifyEqual([shift, score], [-1, 0]);
            testCase.verifyError(@() baseband.integerOffset(zeros(52, 1), zeros(64, 1), config, 1), ...
                "baseband:integerOffset:bins");
        end

        function theWindowStartsAQuarterPrefixBeforeTheFirstPath(testCase)
            config = baseband.OfdmConfig();
            [buffer, ~, truth] = impairedFrame(config, RandStream("twister", "Seed", 24), Delay=45, Offset=1.7);
            corrected = baseband.frequencyOffset(buffer, -1.7, config.FftLength);
            coarse = baseband.detectFrame(buffer, config, 0.4);
            testCase.verifyEqual(baseband.fineTiming(corrected, coarse, config), truth.Start - 4);
        end

        function theWindowStaysFreeOfTheNextSymbolThroughMultipath(testCase)
            % Channels of 8 taps: the window must start within the prefix
            % of the last path and, but for one channel in about 50,000,
            % no later than the first path. In those the sidelobes of the
            % other paths' correlations cancel the first paths' below a
            % fifth of the strongest's power, and the window starts a sample
            % after the first path.
            config = baseband.OfdmConfig();
            stream = RandStream("twister", "Seed", 25);
            trials = 40;
            taps = 8;
            relative = zeros(trials, 1);
            for trial = 1:trials
                channel = baseband.multipathTaps(taps, 2, stream);
                offset = 8 * rand(stream) - 4;
                [buffer, ~, truth] = impairedFrame(config, stream, Delay=randi(stream, [0 60]), ...
                    Offset=offset, Taps=channel);
                coarse = baseband.detectFrame(buffer, config, 0.4);
                start = baseband.fineTiming(baseband.frequencyOffset(buffer, -offset, config.FftLength), ...
                    coarse, config);
                relative(trial) = start - truth.Start;
            end
            testCase.verifyGreaterThanOrEqual(min(relative), taps - 1 - config.CyclicPrefixLength);
            testCase.verifyLessThanOrEqual(nnz(relative > 0), 1);
            testCase.verifyLessThanOrEqual(max(relative), 2);
        end

        function aWindowNeedsRoomForTheSecondSymbol(testCase)
            config = baseband.OfdmConfig();
            testCase.verifyError(@() baseband.fineTiming(zeros(30, 1), 1, config), "baseband:fineTiming:outside");
        end

        function theOffsetIsRefinedToTheNearestTheHalvesAllow(testCase)
            config = baseband.OfdmConfig();
            [buffer, ~, truth] = impairedFrame(config, RandStream("twister", "Seed", 26), Delay=40, Offset=2.7);
            start = truth.Start - 4;
            testCase.verifyEqual(baseband.refineOffset(buffer, start, 2.5, config), 2.7, "AbsTol", 1e-9);
            testCase.verifyEqual(baseband.refineOffset(buffer, start, 3.6, config), 2.7, "AbsTol", 1e-9);
            testCase.verifyEqual(baseband.refineOffset(buffer, start, 0.8, config), 0.7, "AbsTol", 1e-9);
            testCase.verifyError(@() baseband.refineOffset(buffer, numel(buffer) - 10, 0, config), ...
                "baseband:refineOffset:outside");
        end
    end
end
