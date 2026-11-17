classdef SimulateLinkTest < matlab.unittest.TestCase
%SIMULATELINKTEST The link's error rates by Monte Carlo, against the theory.

% SPDX-License-Identifier: GPL-3.0-or-later

    properties (TestParameter)
        % The modulation order and the SNR in dB, where the theory gives about 1e-2.
        Point = struct("qpsk", [4, 8], "qam16", [16, 14], "qam64", [64, 20])
    end

    methods (Test)
        function whiteNoiseCostsUnderTwoAndAHalfDecibels(testCase, Point)
            % The estimates' noise costs the receiver about 1.4 dB.
            order = Point(1);
            snr = Point(2);
            config = baseband.OfdmConfig(ModulationOrder=order);
            results = baseband.simulateLink(config, snr, 60, Seed=order);
            testCase.verifyEqual(results.Missed, 0);
            testCase.verifyEqual(results.Bits, 60 * config.PayloadBits);
            testCase.verifyGreaterThan(results.Ber, baseband.theoryBer(order, snr));
            testCase.verifyLessThan(results.Ber, baseband.theoryBer(order, snr - 2.5));
        end

        function aHighSnrIsErrorFree(testCase)
            config = baseband.OfdmConfig(ModulationOrder=64);
            results = baseband.simulateLink(config, [30; 35], 20, Seed=3);
            testCase.verifyEqual(results.Properties.VariableNames, ...
                {'SnrDb', 'Frames', 'Missed', 'BitErrors', 'Bits', 'Ber', 'BlockErrors', 'Bler'});
            testCase.verifyEqual(results.SnrDb, [30; 35]);
            testCase.verifyEqual(results.Frames, [20; 20]);
            testCase.verifyEqual(results.Missed, [0; 0]);
            testCase.verifyEqual(results.Bits, [20; 20] * config.PayloadBits);
            testCase.verifyEqual(results.BitErrors, [0; 0]);
            testCase.verifyEqual(results.Ber, [0; 0]);
            testCase.verifyEqual(results.BlockErrors, [0; 0]);
            testCase.verifyEqual(results.Bler, [0; 0]);
        end

        function rayleighFadingCostsUnderThreeDecibels(testCase)
            % Each subcarrier of the multipath channel is Rayleigh faded. A
            % run's fades are few, so its rate scatters; the lower bound only
            % rules out a link better than the theory 2 dB higher.
            config = baseband.OfdmConfig(ModulationOrder=4);
            snr = [10; 20];
            results = baseband.simulateLink(config, snr, 200, Channel="multipath", Seed=7);
            testCase.verifyLessThanOrEqual(results.Missed, [8; 8]);
            testCase.verifyGreaterThan(results.Ber, baseband.theoryBer(4, snr + 2, Channel="rayleigh"));
            testCase.verifyLessThan(results.Ber, baseband.theoryBer(4, snr - 3, Channel="rayleigh"));
        end

        function theProjectionLowersTheErrorRate(testCase)
            % The same frames and noise, with and without the projection.
            config = baseband.OfdmConfig(ModulationOrder=4);
            projected = baseband.simulateLink(config, 8, 30, Seed=21);
            raw = baseband.simulateLink(config, 8, 30, Seed=21, Projection=false);
            testCase.verifyEqual(raw.Missed, projected.Missed);
            testCase.verifyGreaterThan(raw.Ber, 1.5 * projected.Ber);
        end

        function aSmallSearchFindsSmallOffsets(testCase)
            % Offsets within 0.5 spacings, and the receiver's search as narrow.
            config = baseband.OfdmConfig(ModulationOrder=4);
            results = baseband.simulateLink(config, 8, 30, CfoRange=0.5, MaxDelay=0, Seed=22);
            testCase.verifyEqual(results.Missed, 0);
            testCase.verifyLessThan(results.Ber, baseband.theoryBer(4, 8 - 2.5));
        end

        function aSeedRepeatsItsRun(testCase)
            % Three error counts: another seed gives the same three only by
            % a chance of about one in a million.
            config = baseband.OfdmConfig(ModulationOrder=4);
            snr = [4; 6; 8];
            first = baseband.simulateLink(config, snr, 5, Seed=11);
            testCase.verifyEqual(baseband.simulateLink(config, snr, 5, Seed=11), first);
            other = baseband.simulateLink(config, snr, 5, Seed=12);
            testCase.verifyNotEqual(other.BitErrors, first.BitErrors);
        end

        function framesBuriedInNoiseAreMissed(testCase)
            % Noise alone reaches the detection threshold about once in a
            % thousand buffers, and what is decoded from it fails the CRC.
            config = baseband.OfdmConfig(ModulationOrder=4);
            frames = 3;
            results = baseband.simulateLink(config, -30, frames, Seed=5);
            testCase.verifyGreaterThanOrEqual(results.Missed, frames - 1);
            testCase.verifyEqual(results.Bits, (frames - results.Missed) * config.PayloadBits);
            testCase.verifyEqual(isnan(results.Ber), results.Missed == frames);
            testCase.verifyEqual(results.BlockErrors, frames);
            testCase.verifyEqual(results.Bler, 1);
        end
    end
end
