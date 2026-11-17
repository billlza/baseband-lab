function curves = linkCurves(frames)
%LINKCURVES The link's bit error rates beside the theory, as a table.
%   CURVES = linkCurves() runs baseband.simulateLink, 200 frames a point,
%   for QPSK, 16QAM and 64QAM in white noise and for QPSK and 16QAM through
%   Rayleigh multipath of 8 taps, and puts each point's theoretical rate
%   (baseband.theoryBer) beside it. CURVES = linkCurves(FRAMES) sends
%   FRAMES frames a point. From the repository's root:
%
%     addpath("src", "examples"); disp(linkCurves())
%
%   The rates are repeatable: each curve runs with simulateLink's seed.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        frames (1,1) double {mustBeInteger, mustBePositive} = 200
    end
    % Channel, order and the SNRs in dB around a rate of 1e-2.
    points = {
        "awgn", 4, (4:2:10)'
        "awgn", 16, (10:2:16)'
        "awgn", 64, (16:2:22)'
        "multipath", 4, (10:5:25)'
        "multipath", 16, (15:5:30)'
        };
    rows = cell(size(points, 1), 1);
    for index = 1:size(points, 1)
        [channel, order, snr] = points{index, :};
        results = baseband.simulateLink(baseband.OfdmConfig(ModulationOrder=order), snr, frames, ...
            Channel=channel);
        fading = "awgn";
        if channel == "multipath"
            fading = "rayleigh";
        end
        rows{index} = [table(repmat(channel, numel(snr), 1), repmat(order, numel(snr), 1), ...
            'VariableNames', {'Channel', 'Order'}), results(:, {'SnrDb', 'Missed', 'Ber', 'Bler'}), ...
            table(baseband.theoryBer(order, snr, Channel=fading), 'VariableNames', {'TheoryBer'})];
    end
    curves = vertcat(rows{:});
end
