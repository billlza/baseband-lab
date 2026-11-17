function refined = refineOffset(samples, start, offset, config)
%REFINEOFFSET The frequency offset again, at the refined window.
%   REFINED = baseband.refineOffset(SAMPLES, START, OFFSET, CONFIG) takes
%   the Schmidl-Cox correlation of the first training symbol's halves at
%   START (baseband.fineTiming's, inside the cyclic prefix and so free of
%   the next symbol) in the uncorrected SAMPLES, whose angle gives the
%   offset modulo 2 subcarrier spacings, and of the offsets it allows
%   returns the one nearest OFFSET, the estimate made at the coarse start:
%   a coarse start late enough to reach into the next symbol biases the
%   fractional part, never by a whole spacing.
%
%   See also baseband.receive, baseband.schmidlCox.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        samples (:,1) double
        start (1,1) double {mustBeInteger, mustBePositive}
        offset (1,1) double {mustBeReal, mustBeFinite}
        config (1,1) baseband.OfdmConfig
    end
    half = config.FftLength / 2;
    if start + config.FftLength - 1 > numel(samples)
        error("baseband:refineOffset:outside", ...
            "The training symbol from sample %d does not fit in %d samples.", start, numel(samples));
    end
    early = samples(start + (0:half - 1));
    late = samples(start + half + (0:half - 1));
    fraction = angle(early' * late) / pi;
    refined = fraction + 2 * round((offset - fraction) / 2);
end
