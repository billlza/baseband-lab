function runReceiverStudy(outputDir)
%RUNRECEIVERSTUDY Run the conditions fixed in docs/receiver-study.md.
%   Save per-frame measurements and theory for independent aggregation.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        outputDir (1,1) string
    end
    if ~isfolder(outputDir)
        mkdir(outputDir);
    end
    cases = {"awgn", 4, [-6 6 12]; "multipath", 4, [-6 6 12]; ...
             "awgn", 16, [6 12 18]; "multipath", 16, [6 12 18]; ...
             "awgn", 64, [16 20 24]};
    seeds = [2601, 2602];
    frames = 200;
    cells = cell(2 * size(cases, 1) * 3, 1);
    condition = 0;
    for group = 1:size(cases, 1)
        [channel, order, points] = cases{group, :};
        config = baseband.OfdmConfig(ModulationOrder=order);
        theoryChannel = "awgn";
        if channel == "multipath"
            theoryChannel = "rayleigh";
        end
        for snr = points
            condition = condition + 1;
            for batch = 1:numel(seeds)
                t = receiverTrials(config, snr, channel, frames, 100 * seeds(batch) + condition);
                n = height(t);
                t.Batch = repmat(seeds(batch), n, 1);
                t.Channel = repmat(channel, n, 1);
                t.Order = repmat(order, n, 1);
                t.EsN0dB = repmat(snr, n, 1);
                t.TheoryBER = repmat(baseband.theoryBer(order, snr, Channel=theoryChannel), n, 1);
                cells{(condition - 1) * numel(seeds) + batch} = t;
            end
        end
    end
    trials = vertcat(cells{:});
    writetable(trials, fullfile(outputDir, "frames.csv"));
    metadata = struct("release", string(version("-release")), "matlab", string(version), ...
        "framesPerConditionAndSeed", frames, "seeds", seeds, ...
        "conditions", condition, "receiverRows", height(trials));
    writelines(jsonencode(metadata), fullfile(outputDir, "environment.json"));
end
