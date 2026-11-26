function [payload, crcPassed] = coherentReference(samples, config, truth)
%COHERENTREFERENCE Decode the received waveform with known timing, CFO and taps.
%   The transmitted payload is deliberately absent from this interface.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        samples (:,1) double {mustBeFinite}
        config (1,1) baseband.OfdmConfig
        truth (1,1) struct
    end
    if numel(truth.Taps) - 1 > config.CyclicPrefixLength
        error("baseband:reference:channel", "The channel exceeds the cyclic prefix.");
    end
    corrected = baseband.frequencyOffset(samples, -truth.Offset, config.FftLength);
    fftBins = baseband.ofdmDemodulate(corrected, truth.Start, config.DataSymbols + 2, config);
    dataBins = config.binsOf(config.DataSubcarriers);
    frequencyResponse = fft(truth.Taps(:), config.FftLength, 1);
    channel = repmat(frequencyResponse(dataBins), 1, config.DataSymbols);
    [symbols, gain, noise] = baseband.equalize(fftBins(dataBins, 3:end), channel, ...
        truth.NoiseVariance, "zf");
    bits = double(baseband.qamLlr(symbols(:), gain(:), noise(:), config.ModulationOrder) < 0);
    payload = bits(1:config.PayloadBits);
    crcPassed = ~any(baseband.crc24a(bits));
end
