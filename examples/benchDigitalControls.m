function rows = benchDigitalControls(referenceFolder, evidenceFolder)
%BENCHDIGITALCONTROLS Exercise the complete replay path without any radio.
%   Each block spans one period of possible FFT starts. Conditions include a
%   clean stream, a known payload bit flipped with its original CRC and a
%   different, fully valid frame scored against the declared TX reference.

% SPDX-License-Identifier: GPL-3.0-or-later
    arguments
        referenceFolder (1,1) string
        evidenceFolder (1,1) string
    end
    [ok, message, id] = mkdir(evidenceFolder);
    if ~ok || ~isempty(id)
        error("baseband:bench:newFolder", "A new evidence directory is required: %s", message);
    end
    phases = [43, 271, 535, 805];
    labels = ["clean-01", "clean-02", "clean-03", "clean-04", "one-bit-original-crc", "wrong-reference", "no-signal"];
    rows = repmat(struct("Case", "", "Detected", false, "Bits", 0, "BitErrors", NaN, "CrcPassed", false), numel(labels), 1);
    for k = 1:numel(labels)
        frameId = min(k, 4);
        entry = load(fullfile(referenceFolder, compose("frame-%02d.mat", frameId)), "reference");
        ref = entry.reference;
        tx = double(ref.TxWaveform);
        if labels(k) == "one-bit-original-crc"
            config = baseband.OfdmConfig;
            grid = baseband.ofdmDemodulate(tx, config.CyclicPrefixLength + 1, config.DataSymbols + 2, config);
            idx = config.binsOf(config.DataSubcarriers(1));
            grid(idx, 3) = complex(-real(grid(idx, 3)), imag(grid(idx, 3)));
            tx = baseband.ofdmModulate(grid(config.binsOf(config.UsedSubcarriers), :), config);
        elseif labels(k) == "wrong-reference"
            other = load(fullfile(referenceFolder, "frame-01.mat"), "reference");
            tx = double(other.reference.TxWaveform);
        elseif labels(k) == "no-signal"
            tx(:) = 0;
        end
        sizeRaw = 256 * ceil(ref.ScoreSamples / 256);
        take = 1 + mod(phases(frameId) + (0:sizeRaw-1), ref.PeriodSamples);
        raw = int16(2047 * [real(tx(take)), imag(tx(take))]);
        capture = struct("Source", "synthetic-control", "IQ", raw, "SampleRateHz", ref.Config.SampleRate, ...
            "CenterFrequencyHz", 1e9, "RxGainDb", 0, "DataValid", true, "Overflow", false, ...
            "Config", ref.Config, "Payload", ref.Payload);
        folder = fullfile(evidenceFolder, labels(k));
        mkdir(folder);
        scoreSamples = ref.ScoreSamples;
        save(fullfile(folder, "native.mat"), "capture", "scoreSamples");
        result = scoreBenchBlock(folder);
        rows(k) = struct("Case", labels(k), "Detected", result.Detected, "Bits", result.Bits, ...
            "BitErrors", result.BitErrors, "CrcPassed", result.CrcPassed);
    end
    writelines(jsonencode(rows), fullfile(evidenceFolder, "control-results.json"));
end
