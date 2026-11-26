function rows = receiverTrials(config, snrDb, channel, frames, seed)
%RECEIVERTRIALS Score five receivers on the same independently drawn frames.
%   A non-detection has no bit-error observation. Both block endpoints count it.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        config (1,1) baseband.OfdmConfig
        snrDb (1,1) double {mustBeReal, mustBeFinite}
        channel (1,1) string {mustBeMember(channel, ["awgn", "multipath"])}
        frames (1,1) double {mustBeInteger, mustBePositive}
        seed (1,1) double {mustBeInteger, mustBeNonnegative}
    end
    names = ["coherent"; "projected-mmse"; "projected-zf"; "ls-mmse"; "ls-zf"];
    equalizers = ["mmse", "zf", "mmse", "zf"];
    projection = [true, true, false, false];
    count = numel(names);
    stream = RandStream("twister", "Seed", seed);
    variance = 10^(-snrDb / 10);
    values = nan(frames * count, 6);
    for frame = 1:frames
        [samples, payload, truth] = baseband.drawFrame(config, variance, stream, Channel=channel);
        [ideal, passed] = coherentReference(samples, config, truth);
        first = (frame - 1) * count + 1;
        errors = nnz(ideal ~= payload);
        values(first, :) = [1, config.PayloadBits, errors, ~passed, errors > 0, NaN];
        prevBits = [];
        for arm = 1:numel(equalizers)
            result = baseband.receive(samples, config.SampleRate, config, ...
                Equalizer=equalizers(arm), Projection=projection(arm));
            stats = [0, 0, NaN, 1, 1, NaN];
            if result.Detected
                errors = nnz(result.Payload ~= payload);
                stats(1:5) = [1, config.PayloadBits, errors, ~result.CrcPassed, errors > 0];
                if equalizers(arm) == "zf" && ~isempty(prevBits)
                    stats(6) = nnz(result.Payload ~= prevBits);
                end
            end
            prevBits = result.Payload;
            values(first + arm, :) = stats;
        end
    end
    rows = array2table(values, 'VariableNames', ...
        {'Detected', 'Bits', 'BitErrors', 'CrcBlockError', 'PayloadBlockError', 'BitDisagreements'});
    rows.Frame = repelem((1:frames)', count);
    rows.Receiver = repmat(names, frames, 1);
    rows.StreamSeed = repmat(seed, height(rows), 1);
end
