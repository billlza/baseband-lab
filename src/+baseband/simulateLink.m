function results = simulateLink(config, snrDb, frames, options)
%SIMULATELINK Bit and block error rates of the link by Monte Carlo.
%   RESULTS = baseband.simulateLink(CONFIG, SNRDB, FRAMES) sends FRAMES
%   frames of random payload at each symbol energy to noise density ratio
%   in SNRDB (dB, of a used subcarrier) through the channel and the
%   receiver, and counts the errors. Each frame starts a random number of
%   samples (0 to MaxDelay) into a buffer that ends FftLength samples after
%   it, gets a random frequency offset, uniform within +-CfoRange
%   subcarrier spacings, and noise over the whole buffer.
%
%   Name-value options:
%     Channel     "awgn" (default), or "multipath": a new
%                 baseband.multipathTaps channel each frame
%     Taps        the multipath channel's taps (8)
%     Decay       their power decay, in samples (2)
%     CfoRange    the offsets drawn, and looked for (4)
%     MaxDelay    the largest delay before a frame, in samples (64)
%     Equalizer   "mmse" (default) or "zf"
%     Projection  as baseband.receive's (true)
%     Seed        the seed of the random stream, which makes a run
%                 repeatable (1)
%
%   RESULTS is a table, one row an SNR: SnrDb, Frames, Missed (frames not
%   found), BitErrors and Bits (over the frames found), Ber (their ratio,
%   NaN when no frame was found), BlockErrors (frames missed or failing
%   the CRC) and Bler (BlockErrors / Frames).
%
%   See also baseband.theoryBer, baseband.transmit, baseband.receive.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        config (1,1) baseband.OfdmConfig
        snrDb (:,1) double {mustBeReal, mustBeFinite}
        frames (1,1) double {mustBeInteger, mustBePositive}
        options.Channel (1,1) string {mustBeMember(options.Channel, ["awgn", "multipath"])} = "awgn"
        options.Taps (1,1) double {mustBeInteger, mustBePositive} = 8
        options.Decay (1,1) double {mustBePositive, mustBeFinite} = 2
        options.CfoRange (1,1) double {mustBeNonnegative, mustBeFinite} = 4
        options.MaxDelay (1,1) double {mustBeInteger, mustBeNonnegative} = 64
        options.Equalizer (1,1) string {mustBeMember(options.Equalizer, ["zf", "mmse"])} = "mmse"
        options.Projection (1,1) logical = true
        options.Seed (1,1) double {mustBeInteger, mustBeNonnegative} = 1
    end
    stream = RandStream("twister", "Seed", options.Seed);
    count = numel(snrDb);
    missed = zeros(count, 1);
    bitErrors = zeros(count, 1);
    bits = zeros(count, 1);
    blockErrors = zeros(count, 1);
    for point = 1:count
        variance = 10^(-snrDb(point) / 10);
        for frame = 1:frames
            [buffer, payload] = baseband.drawFrame(config, variance, stream, ...
                Channel=options.Channel, Taps=options.Taps, Decay=options.Decay, ...
                CfoRange=options.CfoRange, MaxDelay=options.MaxDelay);
            result = baseband.receive(buffer, config.SampleRate, config, CfoRange=options.CfoRange, ...
                Equalizer=options.Equalizer, Projection=options.Projection);
            if ~result.Detected
                missed(point) = missed(point) + 1;
                blockErrors(point) = blockErrors(point) + 1;
                continue
            end
            bitErrors(point) = bitErrors(point) + nnz(result.Payload ~= payload);
            bits(point) = bits(point) + config.PayloadBits;
            blockErrors(point) = blockErrors(point) + ~result.CrcPassed;
        end
    end
    results = table(snrDb, repmat(frames, count, 1), missed, bitErrors, bits, bitErrors ./ bits, ...
        blockErrors, blockErrors / frames, 'VariableNames', ...
        {'SnrDb', 'Frames', 'Missed', 'BitErrors', 'Bits', 'Ber', 'BlockErrors', 'Bler'});
end
