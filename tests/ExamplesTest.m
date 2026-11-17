classdef ExamplesTest < matlab.unittest.TestCase
%EXAMPLESTEST The examples run and give what they describe.

% SPDX-License-Identifier: GPL-3.0-or-later

    methods (Test)
        function theLinkCurvesHaveARowAPoint(testCase)
            root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "examples")));
            curves = linkCurves(2);
            testCase.verifyEqual(curves.Properties.VariableNames, ...
                {'Channel', 'Order', 'SnrDb', 'Missed', 'Ber', 'Bler', 'TheoryBer'});
            testCase.verifyEqual(height(curves), 20);
            testCase.verifyEqual(curves.Channel([1, end]), ["awgn"; "multipath"]);
            testCase.verifyEqual(curves.TheoryBer(1), baseband.theoryBer(4, 4), "RelTol", 1e-12);
            testCase.verifyEqual(curves.TheoryBer(end), baseband.theoryBer(16, 30, Channel="rayleigh"), ...
                "RelTol", 1e-12);
        end

        function theReadmesExampleDecodesItsFrame(testCase)
            % The lines of the example in README.md.
            config = baseband.OfdmConfig(ModulationOrder=16);
            stream = RandStream("twister", "Seed", 1);
            payload = randi(stream, [0 1], config.PayloadBits, 1);
            samples = [zeros(100, 1); baseband.transmit(payload, config); zeros(64, 1)];
            samples = baseband.frequencyOffset(samples, 1.3, config.FftLength);
            samples = baseband.addNoise(samples, 10^(-25 / 10), stream);
            result = baseband.receive(samples, config.SampleRate, config);
            testCase.verifyTrue(isequal(result.Payload, payload));
        end
    end
end
