function result = recordPlutoBenchTrial(referenceFile, folder, settings)
%RECORDPLUTOBENCHTRIAL Acquire one bounded trial on an externally attenuated coax link.
%   Requires a connected Pluto with its TX and RX ports connected by the
%   documented passive path. Releases TX before saving or scoring. Call
%   explicitly from the local research host after checking the path budget.
%   See docs/iq-bench.md for settings, units and acceptance.

% SPDX-License-Identifier: GPL-3.0-or-later
    arguments
        referenceFile (1,1) string
        folder (1,1) string
        settings.RadioID (1,1) string
        settings.CenterFrequencyHz (1,1) double {mustBeFinite, mustBePositive}
        settings.TxGainDb (1,1) double {mustBeFinite, mustBeNonpositive}
        settings.RxGainDb (1,1) double {mustBeFinite}
        settings.PathLossDb (1,1) double {mustBeFinite, mustBePositive}
        settings.PathDescription (1,1) string {mustBeNonzeroLengthText}
    end
    stored = load(referenceFile, "reference");
    ref = stored.reference;
    if ref.Kind ~= "generated-tx"
        error("baseband:bench:reference", "Select the separately archived TX reference.");
    end
    [ok, message, id] = mkdir(folder);
    if ~ok || ~isempty(id)
        error("baseband:bench:newFolder", "A new trial directory is required: %s", message);
    end
    trial = struct("FrameId", ref.FrameId, "Settings", settings, ...
        "UtcStart", string(datetime("now", "TimeZone", "UTC")), "Matlab", string(version), ...
        "Status", "started");
    save(fullfile(folder, "intent.mat"), "trial", "ref");
    tx = sdrtx("Pluto", "RadioID", settings.RadioID, "CenterFrequency", settings.CenterFrequencyHz, ...
        "BasebandSampleRate", ref.Config.SampleRate, "Gain", settings.TxGainDb);
    txCleanup = onCleanup(@() release(tx));
    rx = sdrrx("Pluto", "RadioID", settings.RadioID, "CenterFrequency", settings.CenterFrequencyHz, ...
        "BasebandSampleRate", ref.Config.SampleRate, "GainSource", "Manual", "Gain", settings.RxGainDb, ...
        "SamplesPerFrame", 256 * ceil(ref.ScoreSamples / 256), "OutputDataType", "int16");
    rxCleanup = onCleanup(@() release(rx));
    txInfo = info(tx);
    rxInfo = info(rx);
    if ~isfield(txInfo, "BasebandSampleRate") || ~isfield(rxInfo, "BasebandSampleRate") || ...
            ~isfield(rxInfo, "CenterFrequency") || ~isfield(txInfo, "CenterFrequency") || ...
            ~all(isfinite([txInfo.BasebandSampleRate, rxInfo.BasebandSampleRate, ...
                           txInfo.CenterFrequency, rxInfo.CenterFrequency])) || ...
            min([txInfo.BasebandSampleRate, rxInfo.BasebandSampleRate, ...
                 txInfo.CenterFrequency, rxInfo.CenterFrequency]) <= 0 || ...
            abs(txInfo.BasebandSampleRate - rxInfo.BasebandSampleRate) > 1e-9 * txInfo.BasebandSampleRate
        error("baseband:bench:readback", "Readback does not confirm matched RF and reference sample rates.");
    end
    airConfig = ref.Config;
    airConfig.SampleRate = txInfo.BasebandSampleRate;
    args = namedargs2cell(airConfig);
    config = baseband.OfdmConfig(args{:});
    if abs(txInfo.CenterFrequency - rxInfo.CenterFrequency) > 4 * config.SubcarrierSpacing
        error("baseband:bench:frequency", "The reported RF offset exceeds the receiver's acquisition range.");
    end
    transmitRepeat(tx, ref.TxWaveform);
    [raw, valid, overflow] = rx();
    release(tx);
    release(rx);
    scoreSamples = ref.ScoreSamples;
    capture = struct("Source", "sdr-capture", "IQ", [real(raw), imag(raw)], ...
        "SampleRateHz", rxInfo.BasebandSampleRate, "CenterFrequencyHz", rxInfo.CenterFrequency, ...
        "RxGainDb", settings.RxGainDb, "DataValid", valid, "Overflow", overflow, ...
        "Config", airConfig, "Payload", ref.Payload);
    trial.UtcEnd = string(datetime("now", "TimeZone", "UTC"));
    trial.Status = "acquired";
    save(fullfile(folder, "native.mat"), "capture", "scoreSamples", "trial", "rxInfo", "txInfo", "-v7");
    result = scoreBenchBlock(folder);
    save(fullfile(folder, "result.mat"), "result");
end
