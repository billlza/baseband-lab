function result = scoreBenchBlock(trialFolder)
%SCOREBENCHBLOCK Score the fixed prefix of a saved block using replayKnownCapture.
%   Keep the native block including every surplus, invalid or clipped sample.
%   One period of candidate FFT starts corresponds to one scoring opportunity.

% SPDX-License-Identifier: GPL-3.0-or-later
    arguments
        trialFolder (1,1) string
    end
    file = fullfile(trialFolder, "native.mat");
    record = load(file, "scoreSamples");
    result = replayKnownCapture(file, ScoreSamples=record.scoreSamples);
end
