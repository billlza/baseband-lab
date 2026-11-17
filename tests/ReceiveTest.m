classdef ReceiveTest < matlab.unittest.TestCase
%RECEIVETEST The receiver, from complex baseband samples to the payload.

% SPDX-License-Identifier: GPL-3.0-or-later

    properties (TestParameter)
        Order = {4, 16, 64}
    end

    methods (Test)
        function aCleanFrameThroughMultipathDecodesExactly(testCase, Order)
            config = baseband.OfdmConfig(ModulationOrder=Order);
            stream = RandStream("twister", "Seed", 40 + Order);
            for trial = 1:10
                label = sprintf("trial %d", trial);
                taps = baseband.multipathTaps(8, 2, stream);
                offset = 8 * rand(stream) - 4;
                [buffer, payload, truth] = impairedFrame(config, stream, Delay=randi(stream, [0 60]), ...
                    Offset=offset, Taps=taps);
                result = baseband.receive(buffer, config.SampleRate, config);
                testCase.verifyTrue(result.Detected, label);
                testCase.verifyEqual(result.Payload, payload, label);
                testCase.verifyTrue(result.CrcPassed, label);
                testCase.verifyLessThan(abs(result.Cfo - offset), 1e-6, label);
                testCase.verifyEqual(result.CfoHz, result.Cfo * config.SubcarrierSpacing, label);
                testCase.verifyGreaterThanOrEqual(result.Start, ...
                    truth.Start - config.CyclicPrefixLength + numel(taps) - 1, label);
                testCase.verifyLessThanOrEqual(result.Start, truth.Start, label);
                testCase.verifyGreaterThan(result.Peak, 0.9, label);
            end
        end

        function theEqualisersDecideAlike(testCase)
            config = baseband.OfdmConfig();
            [buffer, payload] = impairedFrame(config, RandStream("twister", "Seed", 41), Offset=-1.3, ...
                Taps=[0.9; 0.3j], Variance=1e-3);
            mmse = baseband.receive(buffer, config.SampleRate, config);
            zf = baseband.receive(buffer, config.SampleRate, config, Equalizer="zf");
            testCase.verifyEqual(mmse.Payload, payload);
            testCase.verifyEqual(zf.Payload, payload);
            testCase.verifyTrue(mmse.CrcPassed && zf.CrcPassed);
            testCase.verifyEqual(zf.Llr, mmse.Llr, "AbsTol", 1e-9 * max(abs(mmse.Llr)));
            testCase.verifySize(mmse.Llr, [config.FrameBits, 1]);
            shape = [numel(config.DataSubcarriers), config.DataSymbols];
            testCase.verifySize(mmse.Symbols, shape);
            testCase.verifySize(mmse.Channel, shape);
            % MMSE scales every symbol by its gain, below one.
            testCase.verifyLessThan(abs(mmse.Symbols), abs(zf.Symbols));
            testCase.verifyGreaterThan(mmse.NoiseVariance, 1e-4);
            testCase.verifyLessThan(mmse.NoiseVariance, 1e-2);
        end

        function integerSamplesOfAnSdrDecode(testCase)
            config = baseband.OfdmConfig(ModulationOrder=4);
            [buffer, payload] = impairedFrame(config, RandStream("twister", "Seed", 42), Offset=-2.2);
            samples = int16(2000 * buffer);
            testCase.assertClass(samples, "int16");
            testCase.assertFalse(isreal(samples));
            result = baseband.receive(samples, config.SampleRate, config);
            testCase.verifyEqual(result.Payload, payload);
            testCase.verifyTrue(result.CrcPassed);
            testCase.verifyLessThan(abs(result.Cfo + 2.2), 1e-3);
            % A row of samples is read as a column.
            fromRow = baseband.receive(samples.', config.SampleRate, config);
            testCase.verifyEqual(fromRow.Payload, payload);
        end

        function silenceAndShortBuffersHoldNoFrame(testCase)
            config = baseband.OfdmConfig();
            found = baseband.receive(impairedFrame(config, RandStream("twister", "Seed", 43)), ...
                config.SampleRate, config);
            testCase.assertTrue(found.Detected);
            for samples = {zeros(3000, 1), ones(100, 1)}
                result = baseband.receive(samples{1}, config.SampleRate, config);
                testCase.verifyFalse(result.Detected);
                testCase.verifyEmpty(result.Payload);
                testCase.verifyEmpty(result.Llr);
                testCase.verifyFalse(result.CrcPassed);
                testCase.verifyTrue(isnan(result.Start) && isnan(result.Cfo) && isnan(result.CfoHz) ...
                    && isnan(result.NoiseVariance));
                testCase.verifyEqual(result.Peak, 0);
                testCase.verifyEqual(fieldnames(result), fieldnames(found));
            end
        end

        function aDamagedSymbolFailsTheCrcAlone(testCase)
            config = baseband.OfdmConfig();
            stream = RandStream("twister", "Seed", 44);
            delay = 30;
            [buffer, payload] = impairedFrame(config, stream, Delay=delay);
            [other, otherPayload] = impairedFrame(config, stream, Delay=delay);
            % The third data symbol, after the two training symbols, from the other frame.
            third = delay + 4 * config.SymbolLength + (1:config.SymbolLength);
            buffer(third) = other(third);
            result = baseband.receive(buffer, config.SampleRate, config);
            testCase.verifyTrue(result.Detected);
            testCase.verifyFalse(result.CrcPassed);
            perSymbol = numel(config.DataSubcarriers) * config.BitsPerSymbol;
            carried = 2 * perSymbol + (1:perSymbol);
            kept = setdiff(1:config.PayloadBits, carried);
            testCase.verifyEqual(result.Payload(carried), otherPayload(carried));
            testCase.verifyEqual(result.Payload(kept), payload(kept));
        end

        function aFrameCutAtEitherEndIsNotDecoded(testCase)
            % The window starts 4 samples into the first prefix and ends 4
            % samples before the last symbol's end.
            config = baseband.OfdmConfig();
            stream = RandStream("twister", "Seed", 45);
            [buffer, payload] = impairedFrame(config, stream, Delay=0);
            result = baseband.receive(buffer(13:end), config.SampleRate, config);
            testCase.verifyTrue(result.Detected);
            testCase.verifyEqual(result.Payload, payload);
            testCase.verifyEqual(result.Start, 1);
            result = baseband.receive(buffer(14:end), config.SampleRate, config);
            testCase.verifyFalse(result.Detected);
            testCase.verifyEqual(result.Peak, 1, "AbsTol", 1e-9);

            [buffer, payload] = impairedFrame(config, stream, Tail=0);
            result = baseband.receive(buffer(1:end - 4), config.SampleRate, config);
            testCase.verifyTrue(result.Detected);
            testCase.verifyEqual(result.Payload, payload);
            result = baseband.receive(buffer(1:end - 5), config.SampleRate, config);
            testCase.verifyFalse(result.Detected);
            testCase.verifyEqual(result.Peak, 1, "AbsTol", 1e-9);
        end

        function noisyMultipathFramesAreFoundAndTimed(testCase)
            % 10 dB through Rayleigh multipath of 8 taps.
            config = baseband.OfdmConfig(ModulationOrder=4);
            stream = RandStream("twister", "Seed", 46);
            trials = 200;
            inside = false(trials, 1);
            errors = NaN(trials, 1);
            for trial = 1:trials
                taps = baseband.multipathTaps(8, 2, stream);
                offset = 8 * rand(stream) - 4;
                [buffer, ~, truth] = impairedFrame(config, stream, Delay=randi(stream, [0 60]), ...
                    Offset=offset, Taps=taps, Variance=0.1);
                result = baseband.receive(buffer, config.SampleRate, config);
                if result.Detected
                    inside(trial) = result.Start >= truth.Start - config.CyclicPrefixLength + numel(taps) - 1 ...
                        && result.Start <= truth.Start;
                    errors(trial) = result.Cfo - offset;
                end
            end
            found = ~isnan(errors);
            testCase.verifyGreaterThanOrEqual(nnz(found), 194);
            testCase.verifyGreaterThanOrEqual(nnz(inside), nnz(found) - 3);
            testCase.verifyLessThan(sqrt(mean(errors(found).^2)), 0.05);
            testCase.verifyLessThan(max(abs(errors(found))), 0.3);
        end

        function theRateAndTheSearchMustFit(testCase)
            config = baseband.OfdmConfig();
            testCase.verifyError(@() baseband.receive(zeros(2000, 1), 1e6, config), "baseband:receive:sampleRate");
            testCase.verifyError(@() baseband.receive(zeros(2000, 1), config.SampleRate, config, CfoRange=17), ...
                "baseband:receive:cfoRange");
            result = baseband.receive(zeros(2000, 1), config.SampleRate * (1 + 1e-12), config, CfoRange=16);
            testCase.verifyFalse(result.Detected);
        end
    end
end
