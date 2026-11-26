function runCoherentFadingCheck(filename)
%RUNCOHERENTFADINGCHECK Recreate the flagged cell and measure fresh 16-QAM frames.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        filename (1,1) string
    end
    seeds = [260112, 260212, 921607, 921608];
    sizes = [200, 200, 2000, 2000];
    batches = cell(numel(seeds), 1);
    for k = 1:numel(seeds)
        batches{k} = fadingCalibrationTrials(sizes(k), seeds(k));
    end
    writetable(vertcat(batches{:}), filename);
end
