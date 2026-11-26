function trials = fadingCalibrationTrials(frames, seed)
%FADINGCALIBRATIONTRIALS Record the true taps and coherent 16-QAM errors at 18 dB.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        frames (1,1) double {mustBeInteger, mustBePositive}
        seed (1,1) double {mustBeInteger, mustBeNonnegative}
    end
    config = baseband.OfdmConfig(ModulationOrder=16);
    stream = RandStream("twister", "Seed", seed);
    variance = 10^(-18 / 10);
    taps = complex(zeros(frames, 8));
    errors = zeros(frames, 1);
    for frame = 1:frames
        [samples, payload, truth] = baseband.drawFrame(config, variance, stream, Channel="multipath");
        decoded = coherentReference(samples, config, truth);
        errors(frame) = nnz(decoded ~= payload);
        taps(frame, :) = truth.Taps.';
    end
    trials = table(repmat(seed, frames, 1), (1:frames)', repmat(config.PayloadBits, frames, 1), errors, ...
        'VariableNames', {'StreamSeed', 'Frame', 'PayloadBits', 'BitErrors'});
    for k = 1:size(taps, 2)
        trials.("TapI" + k) = real(taps(:, k));
        trials.("TapQ" + k) = imag(taps(:, k));
    end
end
