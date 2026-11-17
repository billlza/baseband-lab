function shifted = frequencyOffset(samples, offset, fftLength)
%FREQUENCYOFFSET Samples shifted in frequency by subcarrier spacings.
%   SHIFTED = baseband.frequencyOffset(SAMPLES, OFFSET, FFTLENGTH)
%   multiplies the n-th of the column SAMPLES (n from 0) by
%   exp(2j*pi*OFFSET*n/FFTLENGTH): a carrier frequency offset of OFFSET
%   subcarrier spacings, the spacing being the sample rate over FFTLENGTH.
%   The channel applies one, and the receiver removes its estimate with
%   the opposite OFFSET.
%
%   See also baseband.receive, baseband.simulateLink.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        samples (:,1) double
        offset (1,1) double {mustBeReal, mustBeFinite}
        fftLength (1,1) double {mustBeInteger, mustBePositive}
    end
    n = (0:numel(samples) - 1)';
    shifted = samples .* exp(2j * pi * offset * n / fftLength);
end
