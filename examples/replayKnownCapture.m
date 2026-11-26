function summary = replayKnownCapture(filename, options)
%REPLAYKNOWNCAPTURE Score one stored known frame in signed 12-bit I/Q counts.
%   See docs/capture-replay.md for the capture fields and the two data sources.
%   ScoreSamples restricts decoding to a predeclared prefix of a native block.
%   Acquisition validity, ADC range and clipping still cover the whole block.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        filename (1,1) string
        options.ScoreSamples (1,1) double {mustBePositive, mustBeInteger, mustBeFinite}
    end
    archive = load(filename, "capture");
    fields = ["Source", "IQ", "SampleRateHz", "CenterFrequencyHz", "RxGainDb", ...
        "DataValid", "Overflow", "Config", "Payload"];
    if ~isfield(archive, "capture") || ~isstruct(archive.capture) || ...
            ~isscalar(archive.capture) || ~all(isfield(archive.capture, fields))
        error("baseband:capture:metadata", "Missing capture data or acquisition metadata.");
    end
    c = archive.capture;
    origin = string(c.Source);
    if ~isscalar(origin) || ~ismember(origin, ["synthetic-control", "sdr-capture"])
        error("baseband:capture:source", "The capture must declare its source.");
    end
    validateattributes(c.SampleRateHz, {'double'}, {'real', 'scalar', 'finite', 'positive'});
    validateattributes(c.CenterFrequencyHz, {'double'}, {'real', 'scalar', 'finite', 'positive'});
    validateattributes(c.RxGainDb, {'double'}, {'real', 'scalar', 'finite'});
    validateattributes(c.DataValid, {'logical'}, {'scalar'});
    validateattributes(c.Overflow, {'logical'}, {'scalar'});
    validateattributes(c.IQ, {'int16'}, {'real', '2d', 'ncols', 2, 'nonempty'});
    if ~c.DataValid || c.Overflow
        error("baseband:capture:continuity", "The capture has invalid or lost samples.");
    end
    if any(c.IQ < -2048 | c.IQ > 2047, "all")
        error("baseband:capture:range", "Expected signed 12-bit ADC codes.");
    end
    atRail = nnz(c.IQ == -2048 | c.IQ == 2047);
    if atRail > 0
        error("baseband:capture:rail", "%d components reached an ADC rail.", atRail);
    end
    args = namedargs2cell(c.Config);
    config = baseband.OfdmConfig(args{:});
    validateattributes(c.Payload, {'logical', 'double'}, {'column', 'numel', config.PayloadBits});
    if any(~ismember(c.Payload, [0, 1]))
        error("baseband:capture:payload", "The known reference must contain payload bits.");
    end
    nativeCount = size(c.IQ, 1);
    count = nativeCount;
    if isfield(options, "ScoreSamples")
        count = options.ScoreSamples;
        if count > nativeCount
            error("baseband:capture:shortBlock", "The native block does not contain the scoring window.");
        end
    end
    samples = complex(double(c.IQ(1:count, 1)), double(c.IQ(1:count, 2)));
    result = baseband.receive(samples - mean(samples), c.SampleRateHz, config);
    summary = struct("Source", origin, "SampleCount", numel(samples), "NativeSampleCount", nativeCount, ...
        "SampleRateHz", c.SampleRateHz, "CenterFrequencyHz", c.CenterFrequencyHz, ...
        "RxGainDb", c.RxGainDb, "RailComponents", atRail, "Detected", result.Detected, ...
        "Bits", 0, "BitErrors", NaN, "Ber", NaN, "CrcPassed", result.CrcPassed, ...
        "CfoHz", result.CfoHz, "FftStart", result.Start);
    if result.Detected
        summary.Bits = config.PayloadBits;
        summary.BitErrors = nnz(result.Payload ~= c.Payload);
        summary.Ber = summary.BitErrors / summary.Bits;
    end
end
