function taps = multipathTaps(count, decay, stream)
%MULTIPATHTAPS A random Rayleigh multipath channel of sample-spaced taps.
%   TAPS = baseband.multipathTaps(COUNT, DECAY, STREAM) draws COUNT complex
%   Gaussian taps, one a sample, from the RandStream STREAM, with mean
%   powers proportional to exp(-l/DECAY) for the l-th tap (l from 0) and
%   adding up to one, so that the channel's mean power gain is one and the
%   gain of each subcarrier is Rayleigh. conv(WAVEFORM, TAPS) applies it.
%   A channel longer than the cyclic prefix less the receiver's margin
%   brings inter-symbol interference.
%
%   See also baseband.simulateLink.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        count (1,1) double {mustBeInteger, mustBePositive}
        decay (1,1) double {mustBePositive, mustBeFinite}
        stream (1,1) RandStream
    end
    powers = exp(-(0:count - 1)' / decay);
    powers = powers / sum(powers);
    taps = sqrt(powers / 2) .* (randn(stream, count, 1) + 1j * randn(stream, count, 1));
end
