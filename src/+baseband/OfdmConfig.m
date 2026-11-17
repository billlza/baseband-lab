classdef OfdmConfig
%OFDMCONFIG The numerology and frame layout of the OFDM link.
%   CONFIG = baseband.OfdmConfig() is the default link: a 64-point FFT, a
%   16-sample cyclic prefix, subcarriers -26 to 26 without the DC one, six
%   pilots, 16QAM, 12 data symbols a frame and 2 MHz sampling.
%
%   CONFIG = baseband.OfdmConfig(Name=Value) sets any of the properties
%   below; the others keep their defaults. The properties are set only
%   here, and the constructor refuses a combination the link cannot carry.
%
%   A frame is two training symbols and DataSymbols data symbols, each
%   preceded by its cyclic prefix:
%     1. the first training symbol, a known BPSK sequence on the even
%        subcarriers only, so that its two halves are equal in time
%        (Schmidl and Cox): the receiver finds the frame and the
%        fractional frequency offset from it;
%     2. the second training symbol, a known BPSK sequence on every used
%        subcarrier: the integer frequency offset, the first path and the
%        channel;
%     3. the data symbols: QAM on the data subcarriers and known BPSK on
%        the pilots, which track each symbol's common phase.
%
%   Properties:
%     FftLength           FFT points, even (64)
%     CyclicPrefixLength  cyclic prefix samples, 1 to FftLength-1 (16)
%     UsedPerSide         K: subcarriers -K to -1 and 1 to K carry the
%                         signal, 2 <= K <= FftLength/2-1 (26)
%     PilotSpacing        S: the pilots are the subcarriers of magnitude
%                         K, K-S, K-2S, ..., 1 <= S <= K (12)
%     ModulationOrder     4, 16 or 64 (16)
%     DataSymbols         data symbols a frame (12)
%     SampleRate          samples a second, in Hz (2e6)
%
%   Derived, read only: UsedSubcarriers, PilotSubcarriers and
%   DataSubcarriers (columns of signed subcarrier indices, ascending),
%   PilotRows and DataRows (their rows in UsedSubcarriers), BitsPerSymbol,
%   FrameBits (the data subcarriers' bits a frame), PayloadBits (FrameBits
%   less the CRC), SymbolLength and FrameLength (samples, the frame's
%   first cyclic prefix included), SubcarrierSpacing (Hz).
%
%   See also baseband.transmit, baseband.receive, baseband.simulateLink.

% SPDX-License-Identifier: GPL-3.0-or-later

    properties (SetAccess = immutable)
        FftLength (1,1) double
        CyclicPrefixLength (1,1) double
        UsedPerSide (1,1) double
        PilotSpacing (1,1) double
        ModulationOrder (1,1) double
        DataSymbols (1,1) double
        SampleRate (1,1) double
    end

    properties (Constant)
        % The parity bits of CRC-24A that end every frame's bits.
        CrcBits = 24
    end

    properties (Dependent)
        UsedSubcarriers
        PilotSubcarriers
        DataSubcarriers
        PilotRows
        DataRows
        BitsPerSymbol
        FrameBits
        PayloadBits
        SymbolLength
        FrameLength
        SubcarrierSpacing
    end

    methods
        function obj = OfdmConfig(options)
            arguments
                options.FftLength (1,1) double {mustBeInteger, mustBePositive} = 64
                options.CyclicPrefixLength (1,1) double {mustBeInteger, mustBePositive} = 16
                options.UsedPerSide (1,1) double {mustBeInteger, mustBePositive} = 26
                options.PilotSpacing (1,1) double {mustBeInteger, mustBePositive} = 12
                options.ModulationOrder (1,1) double {mustBeMember(options.ModulationOrder, [4 16 64])} = 16
                options.DataSymbols (1,1) double {mustBeInteger, mustBePositive} = 12
                options.SampleRate (1,1) double {mustBePositive, mustBeFinite} = 2e6
            end
            if mod(options.FftLength, 2) ~= 0
                error("baseband:OfdmConfig:fftLength", ...
                    "FftLength must be even, for the first training symbol's halves; it is %d.", ...
                    options.FftLength);
            end
            if options.CyclicPrefixLength >= options.FftLength
                error("baseband:OfdmConfig:cyclicPrefix", ...
                    "CyclicPrefixLength (%d) must be shorter than FftLength (%d).", ...
                    options.CyclicPrefixLength, options.FftLength);
            end
            if options.UsedPerSide < 2 || options.UsedPerSide > options.FftLength / 2 - 1
                error("baseband:OfdmConfig:usedPerSide", ...
                    "UsedPerSide must be 2 to %d, leaving a guard subcarrier; it is %d.", ...
                    options.FftLength / 2 - 1, options.UsedPerSide);
            end
            if options.PilotSpacing > options.UsedPerSide
                error("baseband:OfdmConfig:pilotSpacing", ...
                    "PilotSpacing (%d) must not exceed UsedPerSide (%d).", ...
                    options.PilotSpacing, options.UsedPerSide);
            end
            obj.FftLength = options.FftLength;
            obj.CyclicPrefixLength = options.CyclicPrefixLength;
            obj.UsedPerSide = options.UsedPerSide;
            obj.PilotSpacing = options.PilotSpacing;
            obj.ModulationOrder = options.ModulationOrder;
            obj.DataSymbols = options.DataSymbols;
            obj.SampleRate = options.SampleRate;
            if obj.PayloadBits < 1
                error("baseband:OfdmConfig:payload", ...
                    "A frame carries %d data bits, too few for the %d-bit CRC and a payload.", ...
                    obj.FrameBits, obj.CrcBits);
            end
        end

        function k = get.UsedSubcarriers(obj)
            k = [-obj.UsedPerSide:-1, 1:obj.UsedPerSide]';
        end

        function k = get.PilotSubcarriers(obj)
            magnitudes = obj.UsedPerSide:-obj.PilotSpacing:1;
            k = sort([-magnitudes, magnitudes])';
        end

        function k = get.DataSubcarriers(obj)
            k = setdiff(obj.UsedSubcarriers, obj.PilotSubcarriers);
        end

        function rows = get.PilotRows(obj)
            [~, rows] = ismember(obj.PilotSubcarriers, obj.UsedSubcarriers);
        end

        function rows = get.DataRows(obj)
            [~, rows] = ismember(obj.DataSubcarriers, obj.UsedSubcarriers);
        end

        function bits = get.BitsPerSymbol(obj)
            bits = log2(obj.ModulationOrder);
        end

        function bits = get.FrameBits(obj)
            bits = obj.DataSymbols * numel(obj.DataSubcarriers) * obj.BitsPerSymbol;
        end

        function bits = get.PayloadBits(obj)
            bits = obj.FrameBits - obj.CrcBits;
        end

        function samples = get.SymbolLength(obj)
            samples = obj.FftLength + obj.CyclicPrefixLength;
        end

        function samples = get.FrameLength(obj)
            samples = (obj.DataSymbols + 2) * obj.SymbolLength;
        end

        function hertz = get.SubcarrierSpacing(obj)
            hertz = obj.SampleRate / obj.FftLength;
        end

        function bins = binsOf(obj, k)
            %BINSOF The FFT bins of subcarriers.
            %   BINS = CONFIG.binsOf(K) gives the 1-based FFT bins of the
            %   signed subcarrier indices K, wrapping negative ones to the
            %   top of the FFT, so that X(BINS) are their values.
            arguments
                obj (1,1) baseband.OfdmConfig
                k double {mustBeInteger}
            end
            bins = mod(k, obj.FftLength) + 1;
        end
    end
end
