#!/usr/bin/env python3
"""Split the UI test classes into balanced shards for CI.

The UI suite is too long for one runner, so `.github/workflows/ios.yml` runs it as a matrix.
Each matrix job asks this script which classes are its share:

    scripts/ui_test_shards.py --shards 8 --index 1      # -only-testing:ThorbisUITests/<Class> ...
    scripts/ui_test_shards.py --shards 8 --list          # every shard, with test counts
    scripts/ui_test_shards.py --shards 8 --check         # exit 1 unless every class is in one shard

A class weighs as many tests as it declares, and classes go to the lightest shard, heaviest
first. The split depends only on the source files, so every job computes the same answer.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UI_TESTS = ROOT / "ThorbisUITests"
TARGET = "ThorbisUITests"

CLASS = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b", re.M)
TEST = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*func\s+(test\w*)\s*\(", re.M)


def test_classes(directory: Path = UI_TESTS) -> dict[str, int]:
    """Each XCTestCase class in the directory with the number of tests it declares."""
    classes: dict[str, int] = {}
    for path in sorted(directory.glob("*.swift")):
        text = path.read_text(encoding="utf-8")
        starts = [(match.start(), match.group(1)) for match in CLASS.finditer(text)]
        for position, (start, name) in enumerate(starts):
            end = starts[position + 1][0] if position + 1 < len(starts) else len(text)
            count = len(TEST.findall(text[start:end]))
            if name in classes:
                raise SystemExit(f"UI test class {name} is declared twice")
            if count:
                classes[name] = count
    return classes


def shards(classes: dict[str, int], count: int) -> list[list[str]]:
    """Balanced shards: heaviest class first, onto whichever shard holds the fewest tests."""
    result: list[list[str]] = [[] for _ in range(count)]
    weights = [0] * count
    for name, weight in sorted(classes.items(), key=lambda item: (-item[1], item[0])):
        lightest = min(range(count), key=lambda shard: (weights[shard], shard))
        result[lightest].append(name)
        weights[lightest] += weight
    return [sorted(shard) for shard in result]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--shards", type=int, required=True, help="how many shards the matrix has")
    parser.add_argument("--index", type=int, help="which shard to print, counting from 1")
    parser.add_argument("--list", action="store_true", help="print every shard with its test count")
    parser.add_argument("--check", action="store_true", help="verify the split covers every class once")
    args = parser.parse_args(argv)

    if args.shards < 1:
        parser.error("--shards must be at least 1")
    classes = test_classes()
    if not classes:
        print(f"No XCTestCase classes with tests found in {UI_TESTS}", file=sys.stderr)
        return 1
    split = shards(classes, args.shards)

    if args.check:
        seen = [name for shard in split for name in shard]
        missing = sorted(set(classes) - set(seen))
        repeated = sorted({name for name in seen if seen.count(name) > 1})
        empty = [number for number, shard in enumerate(split, start=1) if not shard]
        if missing or repeated or empty:
            print(f"missing: {missing} repeated: {repeated} empty shards: {empty}", file=sys.stderr)
            return 1
        print(f"{len(classes)} classes, {sum(classes.values())} tests, {args.shards} shards")
        return 0

    if args.list:
        for number, shard in enumerate(split, start=1):
            print(f"shard {number}: {sum(classes[name] for name in shard)} tests")
            for name in shard:
                print(f"  {name} ({classes[name]})")
        return 0

    if args.index is None or not 1 <= args.index <= args.shards:
        parser.error("--index must be between 1 and --shards")
    print(" ".join(f"-only-testing:{TARGET}/{name}" for name in split[args.index - 1]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
