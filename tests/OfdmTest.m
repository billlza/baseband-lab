classdef OfdmTest < matlab.unittest.TestCase
%OFDMTEST OFDM symbols, the training symbols, the pilots and the frame.

% SPDX-License-Identifier: GPL-3.0-or-later

    methods (Test)
        function demodulationUndoesModulation(testCase)
            config = baseband.OfdmConfig();
            stream = RandStream("twister", "Seed", 8);
            grid = randn(stream, 52, 5) + 1j * randn(stream, 52, 5);
            waveform = baseband.ofdmModulate(grid, config);
            testCase.verifySize(waveform, [5 * 80, 1]);
            bins = baseband.ofdmDemodulate(waveform, 17, 5, config);
            testCase.verifySize(bins, [64, 5]);
            testCase.verifyEqual(bins(config.binsOf(config.UsedSubcarriers), :), grid, "AbsTol", 1e-12);
            unused = setdiff(1:64, config.binsOf(config.UsedSubcarriers));
            testCase.verifyLessThan(max(abs(bins(unused, :)), [], "all"), 1e-12);
        end

        function aSymbolKeepsItsEnergyAndItsPrefixIsItsTail(testCase)
            config = baseband.OfdmConfig();
            stream = RandStream("twister", "Seed", 9);
            grid = randn(stream, 52, 1) + 1j * randn(stream, 52, 1);
            waveform = baseband.ofdmModulate(grid, config);
            testCase.verifyEqual(sum(abs(waveform(17:80)).^2), sum(abs(grid).^2), "RelTol", 1e-12);
            testCase.verifyEqual(waveform(1:16), waveform(65:80));
        end

        function windowsAndGridsMustFit(testCase)
            config = baseband.OfdmConfig();
            testCase.verifyError(@() baseband.ofdmDemodulate(zeros(200, 1), 100, 2, config), ...
                "baseband:ofdmDemodulate:outside");
            testCase.verifyError(@() baseband.ofdmModulate(zeros(50, 1), config), "baseband:ofdmModulate:rows");
        end

        function theFirstTrainingSymbolHasEqualHalves(testCase)
            config = baseband.OfdmConfig();
            [first, second] = baseband.trainingSymbols(config);
            k = config.UsedSubcarriers;
            testCase.verifyEqual(first(mod(k, 2) ~= 0), zeros(26, 1));
            testCase.verifyEqual(abs(first(mod(k, 2) == 0)), sqrt(2) * ones(26, 1), "AbsTol", 1e-15);
            testCase.verifyEqual(abs(second), ones(52, 1));
            samples = baseband.ofdmModulate(first, config);
            testCase.verifyEqual(samples(17:48), samples(49:80), "AbsTol", 1e-12);
            % The two symbols differ: the second's halves do not repeat.
            other = baseband.ofdmModulate(second, config);
            testCase.verifyGreaterThan(max(abs(other(17:48) - other(49:80))), 0.1);
        end

        function thePilotsAreBpskAndChangeFromSymbolToSymbol(testCase)
            config = baseband.OfdmConfig();
            pilots = baseband.pilotValues(config);
            testCase.verifySize(pilots, [6, 12]);
            testCase.verifyEqual(abs(pilots), ones(6, 12));
            testCase.verifyGreaterThan(nnz(diff(pilots, 1, 2)), 0);
        end

        function aFrameCarriesItsBitsAndTheKnownSymbols(testCase)
            config = baseband.OfdmConfig(ModulationOrder=64);
            stream = RandStream("twister", "Seed", 10);
            payload = randi(stream, [0 1], config.PayloadBits, 1);
            waveform = baseband.transmit(payload, config);
            testCase.verifySize(waveform, [config.FrameLength, 1]);
            bins = baseband.ofdmDemodulate(waveform, 17, config.DataSymbols + 2, config);
            [first, second] = baseband.trainingSymbols(config);
            used = config.binsOf(config.UsedSubcarriers);
            testCase.verifyEqual(bins(used, 1), complex(first), "AbsTol", 1e-12);
            testCase.verifyEqual(bins(used, 2), complex(second), "AbsTol", 1e-12);
            sent = baseband.qamModulate([payload; baseband.crc24a(payload)], 64);
            data = bins(config.binsOf(config.DataSubcarriers), 3:end);
            testCase.verifyEqual(data(:), sent, "AbsTol", 1e-12);
            testCase.verifyEqual(bins(config.binsOf(config.PilotSubcarriers), 3:end), ...
                complex(baseband.pilotValues(config)), "AbsTol", 1e-12);
            testCase.verifyError(@() baseband.transmit(payload(2:end), config), "baseband:transmit:payloadLength");
        end
    end
end
