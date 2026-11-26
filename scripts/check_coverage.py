# SPDX-License-Identifier: GPL-3.0-or-later
"""Check MATLAB Cobertura line coverage against the files in this checkout."""

import argparse
from collections import defaultdict
import os
from pathlib import Path, PureWindowsPath
import re
import sys
import xml.etree.ElementTree as ET


PACKAGE = Path("src/+baseband")


def raise_walk_error(error):
    raise error


def source_inventory(workspace):
    by_name = defaultdict(set)
    lengths = {}
    package = workspace / PACKAGE
    for directory, subdirs, filenames in os.walk(workspace, onerror=raise_walk_error):
        directory = Path(directory)
        if ".git" in subdirs:
            subdirs.remove(".git")
        for name in filenames:
            if not name.endswith(".m"):
                continue
            path = directory / name
            by_name[name].add(path)
            if path.is_relative_to(package):
                if path.resolve(strict=True) != path or not path.is_file():
                    raise ValueError(f"expected a regular checkout source at {path}")
                lengths[path] = len(path.read_bytes().splitlines())
        if directory.is_relative_to(package):
            for name in subdirs:
                if (directory / name).is_symlink():
                    raise ValueError(f"cannot inventory a linked package directory: {directory / name}")
    if not lengths:
        raise ValueError(f"no MATLAB sources found in {package}")
    return by_name, lengths


def report_path(value):
    if not value or not value.strip():
        raise ValueError("empty path in coverage report")
    path = Path(value.replace("\\", "/"))
    if PureWindowsPath(value).drive and not path.is_absolute():
        raise ValueError(f"cannot resolve a foreign drive path in this checkout: {value!r}")
    return path


def resolve_file(filename, roots, workspace, by_name):
    path = report_path(filename)
    if path.suffix != ".m":
        raise ValueError("expected a MATLAB .m filename")
    bare = not path.is_absolute() and len(path.parts) == 1
    if path.is_absolute():
        candidates = [path]
    elif bare:
        # A declared root can directly identify a file even when its name is shared.
        candidates = [root / path for root in roots]
    else:
        bases = roots or {workspace / "src"}
        candidates = [root / path for root in (*bases, workspace)]
    found = set()
    for candidate in candidates:
        if candidate.is_file():
            actual = candidate.resolve(strict=True)
            if candidate.is_relative_to(workspace) or actual.is_relative_to(workspace):
                if actual != Path(os.path.abspath(candidate)) or actual not in by_name[actual.name]:
                    raise ValueError(f"not a canonical checkout source: {candidate}")
            found.add(actual)
    if bare and not found:
        # MATLAB can elide the package directory from a filename. A basename
        # alone is evidence only when it is unique across the entire checkout.
        found = by_name.get(path.name, set())
        if len(found) == 1:
            source = next(iter(found))
            if not source.is_file() or source.resolve(strict=True) != source:
                raise ValueError(f"not a canonical checkout source: {source}")
            if roots and not any(root.is_relative_to(workspace) and source.is_relative_to(root) for root in roots):
                raise ValueError("file is outside the declared checkout source roots")
    if len(found) > 1:
        raise ValueError("ambiguous file: " + ", ".join(str(p) for p in sorted(found)))
    if not found:
        raise ValueError("source file could not be resolved")
    result = next(iter(found))
    if not path.is_absolute() and roots and result.is_relative_to(workspace / PACKAGE):
        if not any(result.is_relative_to(root) for root in roots):
            raise ValueError("file is outside the declared checkout source roots")
    return result


def unsigned_attribute(line, attribute):
    value = line.get(attribute)
    if value is None or re.fullmatch(r"[0-9]+", value) is None:
        raise ValueError(f"invalid line {attribute}={value!r}")
    return int(value)


def check_coverage(report, workspace):
    workspace = workspace.resolve(strict=True)
    by_name, lengths = source_inventory(workspace)
    observations = {}
    errors = []
    try:
        root = ET.parse(report).getroot()
        if root.tag != "coverage":
            raise ValueError("expected a Cobertura coverage document")
        roots = set()
        for element in root.findall("./sources/source"):
            value = (element.text or "").strip()
            if not value:  # A Cobertura source element may contain no path.
                continue
            source = (workspace / report_path(value)).resolve(strict=True)
            if not source.is_dir():
                raise ValueError(f"not a source directory: {source}")
            roots.add(source)
        for cls in root.findall("./packages/package/classes/class"):
            filename = cls.get("filename")
            try:
                path = resolve_file(filename, roots, workspace, by_name)
                if path not in lengths:
                    continue
                hits = observations.setdefault(path, {})
                lines = cls.findall("./lines/line")
                if not lines:
                    raise ValueError("class has no executable lines")
                for line in lines:
                    number = unsigned_attribute(line, "number")
                    if not 1 <= number <= lengths[path]:
                        raise ValueError(f"line {number} outside source range 1..{lengths[path]}")
                    count = unsigned_attribute(line, "hits")
                    hits[number] = hits.get(number, False) or count > 0
            except (OSError, ValueError) as error:
                errors.append(f"{filename!r}: {error}")
    except (OSError, ValueError, ET.ParseError) as error:
        errors.append(str(error))

    covered = total = 0
    print(f"Package line coverage for {len(lengths)} checkout files")
    for path in sorted(lengths):
        name = path.relative_to(workspace).as_posix()
        if path not in observations:
            print(f"   - of    -  {name}  MISSING")
            errors.append(f"no class for {name}")
            continue
        hits = observations[path]
        missed = sorted(number for number, hit in hits.items() if not hit)
        count = len(hits) - len(missed)
        detail = "  missed: " + ", ".join(map(str, missed)) if missed else ""
        print(f"{count:4d} of {len(hits):4d}  {name}{detail}")
        covered += count
        total += len(hits)
    if total:
        print(f"{covered} of {total} distinct executable lines covered ({covered / total:.4%})")
    else:
        errors.append("no executable package lines")
    if 100 * covered < 95 * total:
        errors.append("package line coverage is below 95%")
    for error in errors:
        print(f"ERROR: {error}")
    return not errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--workspace", type=Path, default=Path.cwd())
    args = parser.parse_args()
    try:
        return 0 if check_coverage(args.report, args.workspace) else 1
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
