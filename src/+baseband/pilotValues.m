function values = pilotValues(config)
%PILOTVALUES The known pilot values of a frame's data symbols.
%   VALUES = baseband.pilotValues(CONFIG) gives the BPSK values (+1 or -1)
%   of the pilots, one row a pilot subcarrier in the order of
%   CONFIG.PilotSubcarriers and one column a data symbol: the PN sequence
%   from the seed 333, column after column.
%
%   See also baseband.transmit, baseband.estimateChannel.

% SPDX-License-Identifier: GPL-3.0-or-later

    arguments
        config (1,1) baseband.OfdmConfig
    end
    count = numel(config.PilotSubcarriers);
    bits = baseband.pnSequence(count * config.DataSymbols, 333);
    values = 1 - 2 * reshape(bits, count, config.DataSymbols);
end
