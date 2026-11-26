function rows = replayPublicWindows(folder, outputFile)
%REPLAYPUBLICWINDOWS Exercise the original frame receiver and shared DSP on public I/Q.
%   The scheduled candidate is the source STF hint. RX samples remain floating
%   point. The source-phy adapter uses its own training, pilots, labels and
%   CRC-32. It selects an orientation using only the known ten header bytes.
%   See lkk688/ofdm-preamble-intelligence and RF-Stream-PHY (CoaxSweep).
% SPDX-License-Identifier: GPL-3.0-or-later
    arguments
        folder (1,1) string
        outputFile (1,1) string
    end
    index = jsondecode(fileread(fullfile(folder, "index.json")));
    parts = cell(numel(index), 1);
    for k = 1:numel(index)
        entry = index(k);
        raw = readBinary(fullfile(folder, entry.file), "single=>double");
        samples = complex(raw(1:2:end), raw(2:2:end));
        truth = readBinary(fullfile(folder, entry.reference), "uint8=>uint8");
        config = baseband.OfdmConfig(ModulationOrder=entry.order, SampleRate=entry.sampleRateHz);
        native = baseband.receive(samples - mean(samples), entry.sampleRateHz, config);
        row = adapter(samples, entry, truth, config);
        row.File = string(entry.source);
        row.Modulation = string(entry.modulation);
        row.NativeDetected = native.Detected;
        row.NativeCrc24Passed = native.CrcPassed;
        parts{k} = row;
    end
    rows = vertcat(parts{:});
    writelines(jsonencode(rows), outputFile);
end

function row = adapter(x, entry, truth, config)
    row = struct("Identified", false, "Bits", 0, "BitErrors", NaN, "Ber", NaN, ...
        "Crc32Passed", NaN, "Crc32ReceivedHex", "", "Crc32ComputedHex", "");
    pilots = [-21; -7; 7; 21];
    used = [-26:-1, 1:26].';
    data = setdiff(used, pilots);
    bins = @(k) mod(k, 64) + 1;
    first = entry.stf;
    stfLength = 16 + 64 * entry.stfRepeats;
    stf = x(first:first+stfLength-1);
    w = angle(stf(1:end-32)' * stf(33:end)) / 32;
    corrected = x .* exp(-1j * w * (0:numel(x)-1).');
    signs = (-1).^(0:numel(used)-1).';
    known = zeros(64, 1);
    known(bins(used)) = signs;
    symbol = ifft(ifftshift(known)) * sqrt(64);
    template = [symbol(end-15:end); symbol];
    starts = first + stfLength + (-16:16);
    windows = corrected((0:79).' + starts);
    energy = sum(abs(windows).^2, 1);
    score = abs(template' * windows) ./ sqrt(max(energy * (template' * template), eps));
    [peak, best] = max(score);
    if peak == 0
        return
    end
    ltf = starts(best);
    phase = [1; 1; 1; -1] * (-1).^(0:entry.symbols-1);
    labels = sourceLabels(entry.order);
    match = uint8([65; 73; 83; 49; 0; 0; 1; 0; mod(numel(truth),256); floor(numel(truth)/256)]);
    frameBits = 8*(numel(truth)+14);
    pairs = 0;
    for conjugated = [false, true]
        oriented = corrected;
        if conjugated
            oriented = conj(oriented);
        end
        f = fftshift(baseband.ofdmDemodulate(oriented, ltf+16, entry.ltfs+entry.symbols, config), 1);
        training = f(bins(used), 1:entry.ltfs);
        meanTraining = mean(training, 2);
        gain = meanTraining ./ signs;
        if any(abs(gain) < 1e-12)
            continue
        end
        noisePower = mean(abs(training - meanTraining).^2, "all");
        h = repmat(gain, 1, entry.symbols);
        [equalized, softGain, noise] = baseband.equalize(f(bins(used), entry.ltfs+1:end), h, noisePower, "zf");
        isPilot = ismember(used, pilots);
        commonPhase = angle(sum(equalized(isPilot, :) .* conj(phase), 1));
        [~, dataRows] = ismember(data, used);
        symbols = equalized(dataRows, :) .* exp(-1j * commonPhase);
        sg = softGain(dataRows, :);
        nv = noise(dataRows, :);
        width = log2(entry.order);
        powers = 2.^(width-1:-1:0);
        for quarterTurn = 0:3
            decision = baseband.qamLlr(symbols(:)*(1j^quarterTurn), sg(:), nv(:), entry.order) < 0;
            address = 1 + powers * reshape(double(decision), width, []);
            source = reshape(labels(address, :).', [], 1);
            if ~isequal(dewhite(source(1:80)), match)
                continue
            end
            decoded = dewhite(source(1:frameBits));
            bytes = decoded(11:end-4);
            mismatch = bitxor(bytes, truth);
            errors = 0;
            for bit = 1:8
                errors = errors + sum(bitget(mismatch, bit));
            end
            checksum = ieeeCrc32(decoded(1:end-4));
            got = uint32(0);
            for bit = 0:3
                got = bitor(got, bitshift(uint32(decoded(end-3+bit)), 8*bit));
            end
            pairs = pairs + 1;
            row.Identified = true;
            row.Bits = numel(truth)*8;
            row.BitErrors = errors;
            row.Ber = errors/row.Bits;
            row.Crc32Passed = double(checksum == got);
            row.Crc32ReceivedHex = string(lower(dec2hex(got, 8)));
            row.Crc32ComputedHex = string(lower(dec2hex(checksum, 8)));
        end
    end
    if pairs > 1
        error("baseband:public:ambiguity", "Multiple distinct header hypotheses matched.");
    end
end

function labels = sourceLabels(order)
    width = log2(order);
    bits = double(dec2bin(0:order-1, width) - '0');
    own = baseband.qamModulate(reshape(bits.', [], 1), order);
    if order == 4
        other = [1+1j, -1+1j, -1-1j, 1-1j] / sqrt(2);
    else
        axisValues = [-3, -1, 3, 1];
        other = (repelem(axisValues, 4) + 1j * repmat(axisValues, 1, 4)) / sqrt(10);
    end
    [distance, loc] = min(abs(own - other), [], 2);
    if any(distance > 1e-12) || numel(unique(loc)) ~= order
        error("baseband:public:labels", "The two decision constellations do not match.");
    end
    labels = bits(loc, :);
end

function bytes = dewhite(bits)
    state = uint8(127);
    out = zeros(size(bits), 'uint8');
    for k = 1:numel(bits)
        b = bitget(state, 7);
        out(k) = bitxor(uint8(bits(k)), b);
        state = bitand(bitor(bitshift(state, 1), bitxor(b, bitget(state, 4))), uint8(127));
    end
    bytes = uint8((2.^(7:-1:0) * reshape(double(out), 8, [])).');
end

function value = ieeeCrc32(bytes)
    value = intmax('uint32');
    poly = uint32(hex2dec('EDB88320'));
    for k = 1:numel(bytes)
        value = bitxor(value, uint32(bytes(k)));
        for b = 1:8
            low = bitget(value, 1);
            value = bitshift(value, -1);
            if low
                value = bitxor(value, poly);
            end
        end
    end
    value = bitcmp(value);
end

function result = readBinary(path, precision)
    [file, message] = fopen(path, 'rb', 'ieee-le');
    if file < 0
        error("baseband:public:read", "Cannot open %s: %s", path, message);
    end
    close = onCleanup(@() fclose(file));
    result = fread(file, Inf, precision);
end
