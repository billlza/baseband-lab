# SPDX-License-Identifier: GPL-3.0-or-later
"""Regression tests for the coverage gate using temporary MATLAB sources."""

from contextlib import redirect_stdout
import io
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
import xml.etree.ElementTree as ET

from check_coverage import check_coverage


class CoverageTest(unittest.TestCase):
    def setUp(self):
        temp = TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.workspace = Path(temp.name).resolve() / "checkout"
        self.package = self.workspace / "src/+baseband"
        self.package.mkdir(parents=True)
        self.report = self.workspace / "coverage.xml"
        self.source("src/+baseband/receive.m", 20)

    def source(self, name, lines=1):
        path = self.workspace / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("value = 1;\n" * lines, encoding="utf-8")
        return path

    def write_report(self, entries, roots=()):
        coverage = ET.Element("coverage")
        sources = ET.SubElement(coverage, "sources")
        for root in roots:
            ET.SubElement(sources, "source").text = str(root)
        package = ET.SubElement(ET.SubElement(coverage, "packages"), "package")
        classes = ET.SubElement(package, "classes")
        for name, line_values in entries:
            cls = ET.SubElement(classes, "class", filename=str(name))
            lines = ET.SubElement(cls, "lines")
            for number, hits in line_values:
                fields = {"number": number, "hits": hits}
                ET.SubElement(lines, "line", {k: str(v) for k, v in fields.items() if v is not None})
        ET.ElementTree(coverage).write(self.report)

    def check(self, expected_success, *messages):
        output = io.StringIO()
        with redirect_stdout(output):
            success = check_coverage(self.report, self.workspace)
        self.assertEqual(success, expected_success, output.getvalue())
        for message in messages:
            self.assertIn(message, output.getvalue())

    def test_basename_source_relative_workspace_relative_and_absolute(self):
        inner = self.source("src/+baseband/+sub/fine.m")
        self.source("src/+baseband/crc.m")
        self.source("src/+baseband/train.m")
        self.source("src/+baseband/pilots.m")
        self.source("examples/plot.m")
        self.write_report([
            ("receive.m", [(1, 1)]),
            (inner, [(1, 1)]),
            ("+baseband/crc.m", [(1, 1)]),
            ("src/+baseband/train.m", [(1, 1)]),
            (r"+baseband\pilots.m", [(1, 1)]),
            ("examples/plot.m", [(1, 0)]),
        ], [self.workspace / "src"])
        self.check(True, "5 of 5 distinct executable lines", "src/+baseband/+sub/fine.m")

    def test_real_nonpackage_files_contribute_no_lines(self):
        outside = self.source("../other/src/+baseband/receive.m")
        self.source("tests/receive.m")
        self.source("examples/plot.m")
        self.write_report([("examples/plot.m", [(1, 1)]), ("tests/receive.m", [(1, 1)]),
                           (outside.resolve(), [(1, 1)]), ("plot.m", [(1, 1)])])
        self.check(False, "src/+baseband/receive.m  MISSING", "no executable package lines")

    def test_bare_name_requires_unique_checkout_match_or_a_direct_declared_root(self):
        self.write_report([("receive.m", [(1, 1)])], [""])
        self.check(True, "1 of 1 distinct executable lines")
        self.source("tests/receive.m")
        for roots in [[], [""], ["src"]]:
            with self.subTest(roots=roots):
                self.write_report([("receive.m", [(1, 1)])], roots)
                self.check(False, "ambiguous file", "tests/receive.m", "src/+baseband/receive.m  MISSING")
        self.write_report([("receive.m", [(1, 1)])], [self.package])
        self.check(True, "1 of 1 distinct executable lines")
        self.write_report([("receive.m", [(1, 1)])], ["tests"])
        self.check(False, "src/+baseband/receive.m  MISSING")
        self.write_report([("receive.m", [(1, 1)])], ["src/+baseband", "tests"])
        self.check(False, "ambiguous file")

    def test_unknown_or_conflicting_paths_cannot_rebind_by_basename(self):
        self.source("tests/known.m")
        cases = [
            ("receive.m", ["tests"], "outside the declared"),
            ("+baseband/receive.m", ["tests"], "could not be resolved"),
            ("src/+baseband/receive.m", ["tests"], "outside the declared"),
            ("missing/+baseband/receive.m", [], "could not be resolved"),
            (self.workspace.parent / "absent/src/+baseband/receive.m", [], "could not be resolved"),
            (r"C:\foreign\src\+baseband\receive.m", [], "foreign drive"),
            ("receive.m", ["absent"], "absent"),
            ("", [], "empty path"),
        ]
        for name, roots, reason in cases:
            with self.subTest(name=name, roots=roots):
                self.write_report([(name, [(1, 1)])], roots)
                self.check(False, reason, "src/+baseband/receive.m  MISSING")

    def test_unknown_class_fails_even_if_all_expected_sources_are_covered(self):
        self.write_report([("receive.m", [(1, 1)]), ("stale.m", [(1, 1)])])
        self.check(False, "'stale.m'", "could not be resolved")

    def test_missing_expected_files_and_empty_class(self):
        self.source("src/+baseband/+sub/missing.m")
        self.write_report([("receive.m", [])])
        self.check(False, "src/+baseband/+sub/missing.m  MISSING", "class has no executable lines",
                   "no executable package lines")

    def test_rejects_invalid_line_numbers_and_hit_counts(self):
        for number, hits in [(0, 1), (21, 1), (-1, 1), ("1.0", 1), (None, 1),
                             (1, None), (1, -1), (1, "0.5"), (1, "1e1"), (1, "nan")]:
            with self.subTest(number=number, hits=hits):
                self.write_report([("receive.m", [(2, 1), (number, hits)])])
                self.check(False, "ERROR: 'receive.m'")

    def test_duplicate_classes_merge_each_line_and_exactly_95_percent_passes(self):
        self.write_report([
            ("receive.m", [(i, 1) for i in range(1, 19)] + [(19, 0), (20, 0)]),
            ("+baseband/receive.m", [(19, 2), (19, 0), (18, 0), (20, 0)]),
        ])
        self.check(True, "19 of 20 distinct executable lines", "missed: 20")

    def test_duplicate_hits_cannot_raise_a_below_threshold_result(self):
        self.write_report([("receive.m", [(i, 1) for i in range(1, 19)] + [(19, 0)]),
                           ("+baseband/receive.m", [(1, 42)] * 20)])
        self.check(False, "18 of 19 distinct executable lines", "below 95%")

    def test_empty_or_unreadable_report_still_lists_expected_sources(self):
        self.check(False, "coverage.xml", "src/+baseband/receive.m  MISSING")
        self.report.write_text("<coverage>", encoding="utf-8")
        self.check(False, "no element found", "src/+baseband/receive.m  MISSING")
        self.write_report([])
        self.check(False, "src/+baseband/receive.m  MISSING", "no executable package lines")

    def test_symlink_in_an_unrelated_directory_cannot_supply_the_package_class(self):
        alias = self.workspace / "examples/alias.m"
        alias.parent.mkdir()
        alias.symlink_to(self.package / "receive.m")
        self.write_report([("examples/alias.m", [(1, 1)])])
        self.check(False, "not a canonical checkout source", "src/+baseband/receive.m  MISSING")


if __name__ == "__main__":
    unittest.main()
