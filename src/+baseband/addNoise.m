function noisy = addNoise(samples, variance, stream)
%ADDNOISE Circular complex white Gaussian noise added to samples.
%   NOISY = baseband.addNoise(SAMPLES, VARIANCE, STREAM) adds to each of
%   SAMPLES an independent complex Gaussian value of variance VARIANCE
%   (VARIANCE/2 in each of the real and imaginary parts), drawn from the
%   RandStream STREAM. With the unitary scaling of baseband.ofdmModulate,
%   VARIANCE is also the noise on each subcarrier, so the symbol energy to
%   noise density ratio of a used subcarrier is 1/VARIANCE.
%
%   See also baseband.simulateLink.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        samples double
        variance (1,1) double {mustBeReal, mustBeNonnegative, mustBeFinite}
        stream (1,1) RandStream
    end
    noise = randn(stream, size(samples)) + 1j * randn(stream, size(samples));
    noisy = samples + sqrt(variance / 2) * noise;
end
