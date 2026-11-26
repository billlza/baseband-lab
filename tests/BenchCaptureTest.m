classdef BenchCaptureTest < matlab.unittest.TestCase
%BENCHCAPTURETEST Check reference identities, ADC replay and predeclared windows.

% SPDX-License-Identifier: GPL-3.0-or-later
    methods (TestMethodSetup)
        function addExamples(testCase)
            root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "examples")));
        end
    end
    methods (Test)
        function exportedReferencesAndCorruptionControls(testCase)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            refs = fullfile(tmp.Folder, "refs");
            output = fullfile(tmp.Folder, "controls");
            writeBenchReferences(refs);
            testCase.verifyError(@() writeBenchReferences(refs), "baseband:bench:newFolder");
            observations = benchDigitalControls(refs, output);
            testCase.verifyEqual([observations(1:4).BitErrors], zeros(1, 4));
            testCase.verifyEqual([observations(1:4).Bits], repmat(2184, 1, 4));
            testCase.verifyTrue(all([observations(1:4).CrcPassed]));
            testCase.verifyEqual(observations(5).BitErrors, 1);
            testCase.verifyFalse(observations(5).CrcPassed);
            testCase.verifyGreaterThan(observations(6).BitErrors, 0);
            testCase.verifyTrue(observations(6).CrcPassed);
            testCase.verifyFalse(observations(7).Detected);
            testCase.verifyEqual(observations(7).Bits, 0);
            testCase.verifyTrue(isnan(observations(7).BitErrors));
            folder = fullfile(output, "clean-01");
            filename = fullfile(folder, "native.mat");
            good = scoreBenchBlock(folder);
            testCase.verifyEqual([good.SampleCount, good.NativeSampleCount], [2223, 2304]);
            item = load(filename);
            capture = item.capture;
            scoreSamples = item.scoreSamples;
            capture.IQ(end, 1) = 2047;
            save(filename, "capture", "scoreSamples");
            testCase.verifyError(@() scoreBenchBlock(folder), "baseband:capture:rail");
            capture.IQ = capture.IQ(1:100, :);
            save(filename, "capture", "scoreSamples");
            testCase.verifyError(@() scoreBenchBlock(folder), "baseband:capture:shortBlock");
        end
    end
end
