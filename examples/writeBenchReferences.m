function writeBenchReferences(folder)
%WRITEBENCHREFERENCES Export four distinct 16-QAM transmit periods and known bits.
%   Each .cf32 file holds one unpadded period, interleaved float32 I/Q, little
%   endian. Each .bin contains the independent MSB-first transmit payload.

% SPDX-License-Identifier: GPL-3.0-or-later
    arguments
        folder (1,1) string
    end
    [ok, message, id] = mkdir(folder);
    if ~ok || ~isempty(id)
        error("baseband:bench:newFolder", "A new output directory is required: %s", message);
    end
    config = baseband.OfdmConfig;
    for frameId = 1:4
        bytes = benchBytes(frameId, config.PayloadBits / 8);
        bits = false(8, numel(bytes));
        for b = 1:8
            bits(b, :) = bitget(bytes, 9 - b).';
        end
        payload = double(bits(:));
        tx = baseband.transmit(payload, config);
        tx = single(tx * (0.5 / max(abs(tx))));
        base = fullfile(folder, compose("frame-%02d", frameId));
        writeBinary(base + ".bin", bytes, "uint8");
        writeBinary(base + ".cf32", [real(tx).'; imag(tx).'], "single");
        reference = struct("Kind", "generated-tx", "FrameId", frameId, "Payload", payload, ...
            "Config", struct("ModulationOrder", 16, "SampleRate", config.SampleRate), ...
            "TxWaveform", tx, "PeriodSamples", numel(tx), ...
            "ScoreSamples", numel(tx) + config.FrameLength - config.CyclicPrefixLength - 1);
        save(base + ".mat", "reference", "-v7");
    end
end

function bytes = benchBytes(frameId, count)
    bytes = zeros(count, 1, "uint8");
    bytes(1:8) = [uint8('MRIQ'), 1, 0, 0, uint8(frameId)].';
    state = bitxor(uint32(hex2dec('A51C73D9')), uint32(frameId));
    for i = 9:count
        state = bitxor(state, bitshift(state, 13));
        state = bitxor(state, bitshift(state, -17));
        state = bitxor(state, bitshift(state, 5));
        bytes(i) = uint8(bitand(state, uint32(255)));
    end
end

function writeBinary(path, data, precision)
    [handle, message] = fopen(path, 'wb', 'ieee-le');
    if handle < 0
        error("baseband:bench:write", "Cannot open %s: %s", path, message);
    end
    cleanup = onCleanup(@() fclose(handle));
    if fwrite(handle, data, precision) ~= numel(data)
        error("baseband:bench:write", "Incomplete write to %s.", path);
    end
end
