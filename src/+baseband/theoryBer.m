function ber = theoryBer(order, esn0Db, options)
%THEORYBER The bit error rate of Gray-mapped square QAM.
%   BER = baseband.theoryBer(ORDER, ESN0DB) is the exact bit error rate of
%   ORDER-QAM (4, 16 or 64), Gray-mapped as baseband.qamModulate maps it,
%   with coherent detection in additive white Gaussian noise, at the
%   symbol energy to noise density ratios ESN0DB (dB), by the closed form
%   of Cho and Yoon (IEEE Trans. Commun., 2002): a weighted sum of terms
%   erfc(sqrt(c Es/N0)). For QPSK it is erfc(sqrt(Es/N0/2))/2. BER has
%   the size of ESN0DB.
%
%   BER = baseband.theoryBer(ORDER, ESN0DB, Channel="rayleigh") is the rate
%   on a Rayleigh-faded subcarrier of mean Es/N0 ESN0DB, the receiver
%   knowing the channel: each term averaged over the fading, which makes
%   it 1 - sqrt(c Es/N0 / (1 + c Es/N0)). For QPSK it is
%   (1 - sqrt(g/(1+g)))/2, g = Es/N0/2. Channel="awgn" is the default.
%
%   See also baseband.simulateLink, baseband.qamModulate.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        order (1,1) double {mustBeMember(order, [4 16 64])}
        esn0Db double {mustBeReal}
        options.Channel (1,1) string {mustBeMember(options.Channel, ["awgn", "rayleigh"])} = "awgn"
    end
    root = sqrt(order);
    perDimension = log2(root);
    esn0 = 10.^(esn0Db / 10);
    ber = zeros(size(esn0Db));
    for bit = 1:perDimension
        for level = 0:(1 - 2^(-bit)) * root - 1
            step = level * 2^(bit - 1) / root;
            weight = (-1)^floor(step) * (2^(bit - 1) - floor(step + 1 / 2));
            ratio = (2 * level + 1)^2 * 3 * esn0 / (2 * (order - 1));
            if options.Channel == "awgn"
                term = erfc(sqrt(ratio));
            else
                term = 1 - sqrt(ratio ./ (1 + ratio));
            end
            ber = ber + weight * term / root;
        end
    end
    ber = ber / perDimension;
end
