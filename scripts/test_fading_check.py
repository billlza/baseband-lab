# SPDX-License-Identifier: GPL-3.0-or-later
import unittest

import numpy as np
from score_fading_check import CARRIER_WEIGHTS, DATA, conditional_ber, rayleigh_ber


class FadingReferenceTest(unittest.TestCase):
    def test_quadrature_integration_matches_known_flat_16qam_points(self):
        self.assertAlmostEqual(float(conditional_ber(0)), .5)
        self.assertAlmostEqual(float(conditional_ber(1)), .000143180830556995, places=14)
        self.assertAlmostEqual(rayleigh_ber(), .0283725393947398, places=14)
        self.assertAlmostEqual(float(conditional_ber(4)), 0, places=14)

    def test_payload_weight_excludes_crc_carriers_only_in_last_symbol(self):
        self.assertEqual(len(DATA),46)
        np.testing.assert_array_equal(CARRIER_WEIGHTS[:40], np.full(40,12))
        np.testing.assert_array_equal(CARRIER_WEIGHTS[40:], np.full(6,11))
        self.assertEqual(4*CARRIER_WEIGHTS.sum(),2184)
