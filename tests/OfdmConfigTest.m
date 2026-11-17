classdef OfdmConfigTest < matlab.unittest.TestCase
%OFDMCONFIGTEST The link's numerology, its derived layout and its limits.

% SPDX-License-Identifier: GPL-3.0-or-later

    methods (Test)
        function theDefaultLinkHasTheDocumentedLayout(testCase)
            config = baseband.OfdmConfig();
            testCase.verifyEqual([config.FftLength, config.CyclicPrefixLength, config.UsedPerSide, ...
                config.PilotSpacing, config.ModulationOrder, config.DataSymbols, config.SampleRate], ...
                [64, 16, 26, 12, 16, 12, 2e6]);
            testCase.verifyEqual(config.UsedSubcarriers, [-26:-1, 1:26]');
            testCase.verifyEqual(config.PilotSubcarriers, [-26; -14; -2; 2; 14; 26]);
            testCase.verifyEqual(config.DataSubcarriers, setdiff([-26:-1, 1:26]', [-26; -14; -2; 2; 14; 26]));
            testCase.verifyEqual(config.BitsPerSymbol, 4);
            testCase.verifyEqual(config.FrameBits, 12 * 46 * 4);
            testCase.verifyEqual(config.PayloadBits, 12 * 46 * 4 - 24);
            testCase.verifyEqual(config.SymbolLength, 80);
            testCase.verifyEqual(config.FrameLength, 14 * 80);
            testCase.verifyEqual(config.SubcarrierSpacing, 31250);
        end

        function theRowsPickTheSubcarriersFromTheUsedOnes(testCase)
            config = baseband.OfdmConfig(UsedPerSide=20, PilotSpacing=5);
            used = config.UsedSubcarriers;
            testCase.verifyEqual(used(config.PilotRows), config.PilotSubcarriers);
            testCase.verifyEqual(used(config.DataRows), config.DataSubcarriers);
            testCase.verifyEqual(sort([config.PilotRows; config.DataRows]), (1:numel(used))');
            % The outermost subcarriers are pilots, then every fifth inwards.
            testCase.verifyEqual(config.PilotSubcarriers, [-20; -15; -10; -5; 5; 10; 15; 20]);
        end

        function aSubcarrierSitsInItsFftBin(testCase)
            config = baseband.OfdmConfig();
            testCase.verifyEqual(config.binsOf([-26; -1; 1; 26]), [39; 64; 2; 27]);
        end

        function everyPropertyCanBeSet(testCase)
            config = baseband.OfdmConfig(FftLength=128, CyclicPrefixLength=32, UsedPerSide=50, ...
                PilotSpacing=10, ModulationOrder=64, DataSymbols=3, SampleRate=3.84e6);
            testCase.verifyEqual([config.FftLength, config.CyclicPrefixLength, config.UsedPerSide, ...
                config.PilotSpacing, config.ModulationOrder, config.DataSymbols, config.SampleRate], ...
                [128, 32, 50, 10, 64, 3, 3.84e6]);
            testCase.verifyEqual(numel(config.PilotSubcarriers), 10);
            testCase.verifyEqual(config.FrameBits, 3 * 90 * 6);
            testCase.verifyEqual(config.FrameLength, 5 * 160);
            testCase.verifyEqual(config.SubcarrierSpacing, 30000);
        end

        function aLinkThatCannotWorkIsRefused(testCase)
            testCase.verifyError(@() baseband.OfdmConfig(FftLength=63), "baseband:OfdmConfig:fftLength");
            testCase.verifyError(@() baseband.OfdmConfig(CyclicPrefixLength=64), ...
                "baseband:OfdmConfig:cyclicPrefix");
            testCase.verifyError(@() baseband.OfdmConfig(UsedPerSide=32), "baseband:OfdmConfig:usedPerSide");
            testCase.verifyError(@() baseband.OfdmConfig(UsedPerSide=1, PilotSpacing=1), ...
                "baseband:OfdmConfig:usedPerSide");
            testCase.verifyError(@() baseband.OfdmConfig(PilotSpacing=27), "baseband:OfdmConfig:pilotSpacing");
            % Every subcarrier a pilot leaves nothing for data.
            testCase.verifyError(@() baseband.OfdmConfig(PilotSpacing=1), "baseband:OfdmConfig:payload");
            testCase.verifyError(@() baseband.OfdmConfig(ModulationOrder=8), "MATLAB:validators:mustBeMember");
        end

        function theLimitsThemselvesAreAccepted(testCase)
            longest = baseband.OfdmConfig(CyclicPrefixLength=63);
            testCase.verifyEqual(longest.SymbolLength, 127);
            widest = baseband.OfdmConfig(UsedPerSide=31);
            testCase.verifyEqual(widest.PilotSubcarriers, [-31; -19; -7; 7; 19; 31]);
            narrowest = baseband.OfdmConfig(UsedPerSide=2, PilotSpacing=2);
            testCase.verifyEqual(narrowest.DataSubcarriers, [-1; 1]);
            testCase.verifyEqual(narrowest.PayloadBits, 12 * 2 * 4 - 24);
            sparsest = baseband.OfdmConfig(PilotSpacing=26);
            testCase.verifyEqual(sparsest.PilotSubcarriers, [-26; 26]);
        end
    end
end
