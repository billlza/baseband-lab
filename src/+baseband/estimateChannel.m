function channel = estimateChannel(second, data, config, options)
%ESTIMATECHANNEL The channel on each data symbol's data subcarriers.
%   CHANNEL = baseband.estimateChannel(SECOND, DATA, CONFIG) takes the FFT
%   bins of the received second training symbol (a column) and of the data
%   symbols (one column each), all corrected for the frequency offset. It
%   estimates the channel from the training symbol
%   (baseband.trainingChannel) and turns it, for each data symbol, by the
%   angle of that symbol's pilots against it, the phase a residual
%   frequency offset has added since the training symbol. CHANNEL has one
%   row a data subcarrier, in the order of CONFIG.DataSubcarriers, and one
%   column a data symbol.
%
%   baseband.estimateChannel(..., Projection=false) uses the training
%   symbol's LS estimate without the projection.
%
%   See also baseband.trainingChannel, baseband.equalize, baseband.receive.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        second (:,1) double
        data (:,:) double
        config (1,1) baseband.OfdmConfig
        options.Projection (1,1) logical = true
    end
    if size(data, 1) ~= config.FftLength || size(data, 2) ~= config.DataSymbols
        error("baseband:estimateChannel:bins", ...
            "DATA must hold all %d FFT bins of each of the %d data symbols.", ...
            config.FftLength, config.DataSymbols);
    end
    reference = baseband.trainingChannel(second, config, Projection=options.Projection);
    pilots = data(config.binsOf(config.PilotSubcarriers), :);
    expected = reference(config.PilotRows) .* baseband.pilotValues(config);
    phase = angle(sum(pilots .* conj(expected), 1));
    channel = reference(config.DataRows) .* exp(1j * phase);
end
