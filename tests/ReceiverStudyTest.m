classdef ReceiverStudyTest < matlab.unittest.TestCase
%RECEIVERSTUDYTEST Paired observations, a coherent control, and archived I/Q.

% SPDX-License-Identifier: GPL-3.0-or-later

    methods (TestMethodSetup)
        function examplesOnPath(testCase)
            root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "examples")));
        end
    end

    methods (Test)
        function referenceUsesPhysicalTruthAndNoPayload(testCase)
            config = baseband.OfdmConfig(ModulationOrder=16);
            [samples, payload, truth] = baseband.drawFrame(config, 0, RandStream("twister", "Seed", 73), ...
                Channel="multipath");
            testCase.verifyGreaterThan(truth.Start, config.CyclicPrefixLength + 1);
            testCase.verifyNotEqual(truth.Offset, 0);
            testCase.verifyNumElements(truth.Taps, 8);
            [decoded, crc] = coherentReference(samples, config, truth);
            testCase.verifyEqual(decoded, payload);
            testCase.verifyTrue(crc);
            truth.Taps = -truth.Taps;
            testCase.verifyNotEqual(coherentReference(samples, config, truth), payload);
            truth.Taps = ones(config.CyclicPrefixLength + 2, 1);
            testCase.verifyError(@() coherentReference(samples, config, truth), "baseband:reference:channel");
        end

        function practicalDefaultReproducesTheExistingSimulator(testCase)
            config = baseband.OfdmConfig(ModulationOrder=4);
            snr = 6;
            seed = 260101;
            t = receiverTrials(config, snr, "multipath", 12, seed);
            old = baseband.simulateLink(config, snr, 12, Channel="multipath", Seed=seed);
            arm = t(t.Receiver == "projected-mmse", :);
            testCase.verifyEqual(height(t), 60);
            testCase.verifyEqual(sum(arm.Bits), old.Bits);
            testCase.verifyEqual(sum(arm.BitErrors, "omitnan"), old.BitErrors);
            testCase.verifyEqual(sum(arm.CrcBlockError), old.BlockErrors);
            testCase.verifyEqual(nnz(~arm.Detected), old.Missed);
            pairs = t(endsWith(t.Receiver, "-zf") & t.Detected == 1, :);
            testCase.verifyNotEmpty(pairs);
            testCase.verifyEqual(pairs.BitDisagreements, zeros(height(pairs), 1));
        end

        function syntheticAdcReplayPreservesCountsAndDistinguishesMisses(testCase)
            config = baseband.OfdmConfig(ModulationOrder=4);
            [samples, payload] = baseband.drawFrame(config, 0, RandStream("twister", "Seed", 39));
            counts = int16(1200 * [real(samples), imag(samples)] / max(abs(samples)));
            capture = struct("Source", "synthetic-control", "IQ", counts, "SampleRateHz", config.SampleRate, ...
                "CenterFrequencyHz", 915e6, "RxGainDb", 0, "DataValid", true, "Overflow", false, ...
                "Config", struct("ModulationOrder", 4, "SampleRate", config.SampleRate), "Payload", payload);
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            file = fullfile(folder.Folder, "frame.mat");
            save(file, "capture");
            good = replayKnownCapture(file);
            testCase.verifyTrue(good.Detected && good.CrcPassed);
            testCase.verifyEqual(good.Source, "synthetic-control");
            testCase.verifyEqual([good.BitErrors, good.Bits], [0, config.PayloadBits]);
            capture.SampleRateHz = config.SampleRate / 2;
            save(file, "capture");
            testCase.verifyError(@() replayKnownCapture(file), "baseband:receive:sampleRate");
            capture.SampleRateHz = config.SampleRate;
            capture.IQ = zeros(48, 2, "int16");
            save(file, "capture");
            missed = replayKnownCapture(file);
            testCase.verifyFalse(missed.Detected);
            testCase.verifyEqual(missed.Bits, 0);
            testCase.verifyTrue(isnan(missed.Ber));
            capture.Overflow = true;
            save(file, "capture");
            testCase.verifyError(@() replayKnownCapture(file), "baseband:capture:continuity");
            capture.Overflow = false;
            capture.IQ(1, 1) = -2048;
            save(file, "capture");
            testCase.verifyError(@() replayKnownCapture(file), "baseband:capture:rail");
        end
    end
end
