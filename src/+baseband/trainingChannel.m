function channel = trainingChannel(second, config, options)
%TRAININGCHANNEL The channel on every used subcarrier, from a training symbol.
%   CHANNEL = baseband.trainingChannel(SECOND, CONFIG) takes the FFT bins
%   of the received second training symbol, corrected for the frequency
%   offset, divides the used subcarriers' values by the known symbol, the
%   least-squares (LS) estimate, and projects that onto the frequency
%   responses of impulse responses of CyclicPrefixLength taps: the LS fit
%   of such an impulse response. A channel that, with the timing, fits
%   within the cyclic prefix is unchanged by the projection, while the
%   noise keeps CyclicPrefixLength / numel(UsedSubcarriers) of its power.
%   CHANNEL is a column on CONFIG.UsedSubcarriers.
%
%   baseband.trainingChannel(SECOND, CONFIG, Projection=false) gives the
%   LS estimate itself.
%
%   See also baseband.estimateChannel, baseband.receive.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        second (:,1) double
        config (1,1) baseband.OfdmConfig
        options.Projection (1,1) logical = true
    end
    if numel(second) ~= config.FftLength
        error("baseband:trainingChannel:bins", "SECOND must hold all %d FFT bins.", config.FftLength);
    end
    [~, known] = baseband.trainingSymbols(config);
    k = config.UsedSubcarriers;
    channel = second(config.binsOf(k)) ./ known;
    if options.Projection
        basis = exp(-2j * pi * k * (0:config.CyclicPrefixLength - 1) / config.FftLength);
        channel = basis * (basis \ channel);
    end
end
