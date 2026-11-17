function waveform = transmit(payload, config)
%TRANSMIT One frame's complex baseband samples.
%   WAVEFORM = baseband.transmit(PAYLOAD, CONFIG) appends the CRC-24A of
%   the column of bits PAYLOAD (CONFIG.PayloadBits of them), maps the bits
%   to QAM symbols, fills the data subcarriers of the data symbols with
%   them, symbol after symbol and subcarrier after subcarrier upwards, puts
%   the pilots on the pilot subcarriers, and gives the two training symbols
%   and the data symbols as samples, a column of CONFIG.FrameLength complex
%   values at CONFIG.SampleRate. The mean power of a used subcarrier is
%   one, so the samples' mean power is about the share of the FFT's bins
%   in use.
%
%   See also baseband.receive, baseband.OfdmConfig.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        payload (:,1) double {mustBeMember(payload, [0 1])}
        config (1,1) baseband.OfdmConfig
    end
    if numel(payload) ~= config.PayloadBits
        error("baseband:transmit:payloadLength", ...
            "The payload has %d bits; a frame carries %d.", numel(payload), config.PayloadBits);
    end
    bits = [payload; baseband.crc24a(payload)];
    data = reshape(baseband.qamModulate(bits, config.ModulationOrder), ...
        numel(config.DataSubcarriers), config.DataSymbols);
    symbols = zeros(numel(config.UsedSubcarriers), config.DataSymbols);
    symbols(config.DataRows, :) = data;
    symbols(config.PilotRows, :) = baseband.pilotValues(config);
    [first, second] = baseband.trainingSymbols(config);
    waveform = baseband.ofdmModulate([first, second, symbols], config);
end
