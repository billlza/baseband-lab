# SPDX-License-Identifier: GPL-3.0-or-later
import math
import unittest

import numpy as np
from summarize_study import ratio_interval, summarize, wilson, zero_upper


class FrameInferenceTest(unittest.TestCase):
    def test_zero_or_missing_bits_remain_distinguishable(self):
        w = np.ones((4, 4))
        x = np.zeros(4)
        self.assertEqual(ratio_interval(x, x, w)[:2], (None, None))
        rate, bounds, _ = ratio_interval(x, np.full(4, 100.), w)
        self.assertEqual(rate, 0)
        self.assertAlmostEqual(bounds[1], 1-.025**.25)
        self.assertGreater(wilson(0, 4)[1], 0)
        self.assertEqual(wilson(4, 4)[1], 1)

    def test_pair_uses_joint_detections_and_all_frames_for_block_errors(self):
        # On frame 2 the coherent receiver has two errors and all others miss.
        # On frame 3 only projected MMSE has payload errors.
        cells = np.zeros((3, 5, 6))
        cells[:, :, 0] = 1
        cells[:, :, 1] = 100
        cells[:, :, 5] = np.nan
        cells[:, (2, 4), 5] = 0
        cells[1, 0, 2:5] = [2, 1, 1]
        cells[1, 1:, :] = [0, 0, np.nan, 1, 1, np.nan]
        cells[2, 1, 2:5] = [3, 1, 1]
        info = summarize(cells, np.ones((4, 3)))
        practical = info['arms']['projected-mmse']
        self.assertEqual(practical['bits'], 200)
        self.assertAlmostEqual(practical['ber'], 3/200)
        self.assertEqual(practical['crc_block_errors'], 2)
        self.assertEqual(practical['missed'], 1)
        contrast = info['pairs']['projected-mmse minus coherent']
        self.assertEqual(contrast['common_frames'], 2)
        self.assertAlmostEqual(contrast['delta_ber'], 3/200)
        self.assertAlmostEqual(contrast['delta_bler'], 1/3)
        self.assertAlmostEqual(zero_upper(200), 1-math.exp(math.log(.025)/200))


if __name__ == '__main__':
    unittest.main()
