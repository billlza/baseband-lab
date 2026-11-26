# SPDX-License-Identifier: GPL-3.0-or-later
"""Regression checks for comparisons of the fixed public recording set."""
import unittest

from public_iq_ci import baseline, check


class PublicWindowComparisonTest(unittest.TestCase):
    def setUp(self):
        self.ref = baseline()
        self.index = []
        self.rows = []
        for mod, run in self.ref["runs"].items():
            for w in run["windows"]:
                p = w["python"]
                self.index.append(dict(modulation=mod, source=w["file"], sourceSha256=w["sha256"],
                                       candidateSha256=w["candidate_sha256"]))
                self.rows.append(dict(Modulation=mod, File=w["file"], Identified=True, Bits=p["bits"],
                                      BitErrors=p["bit_errors"], Ber=p["ber"], Crc32Passed=int(p["crc32_pass"]),
                                      Crc32ReceivedHex=p["crc32_received_hex"], Crc32ComputedHex=p["crc32_computed_hex"],
                                      NativeDetected=True, NativeCrc24Passed=False))

    def compare(self):
        return check(self.ref, self.index, self.rows, {"release":"fixture"})

    def test_frame_identity_does_not_depend_on_row_order(self):
        self.rows.reverse()
        receipt = self.compare()
        self.assertTrue(receipt["passed"])
        self.assertEqual(receipt["matches"], 16)

    def test_same_total_and_crc_failure_counts_cannot_hide_shifted_frame_scores(self):
        a, b = [r for r in self.rows if r["Modulation"] == "qam16" and not r["Crc32Passed"]][:2]
        for field in ("BitErrors", "Ber"):
            a[field], b[field] = b[field], a[field]
        result = self.compare()
        self.assertFalse(result["passed"])
        self.assertEqual(result["matches"], 14)

    def test_crc_word_change_fails_even_if_crc_outcome_does_not_change(self):
        r = next(r for r in self.rows if not r["Crc32Passed"])
        r["Crc32ComputedHex"] = f'{int(r["Crc32ComputedHex"], 16) ^ 1:08x}'
        self.assertEqual(self.compare()["matches"], 15)

    def test_duplicate_and_missing_windows_are_rejected(self):
        self.rows.append(self.rows[0])
        with self.assertRaisesRegex(ValueError, "duplicate"):
            self.compare()
        self.rows = self.rows[:-2]
        with self.assertRaisesRegex(ValueError, "missing"):
            self.compare()

    def test_replacing_the_checked_candidate_is_rejected(self):
        value = int(self.index[0]["candidateSha256"], 16) ^ 1
        self.index[0]["candidateSha256"] = f"{value:064x}"
        with self.assertRaisesRegex(ValueError, "unverified"):
            self.compare()


if __name__ == "__main__":
    unittest.main()
