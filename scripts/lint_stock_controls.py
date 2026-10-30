#!/usr/bin/env python3
"""Reject stock controls beyond explicitly counted existing source lines."""

from collections import Counter, defaultdict
from pathlib import Path
import re
import sys

PATTERN = re.compile(r"(?<![.a-zA-Z])Menu \{| Picker\(|\.confirmationDialog\(|\.buttonStyle\(\.bordered|\.borderedProminent")
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Thorbis/Sources"
BASELINE = ROOT / "scripts/.stock-controls-allowlist"


def main() -> int:
    if not SOURCE.is_dir():
        print("error: Swift source directory is missing", file=sys.stderr)
        return 1
    allowed: dict[tuple[str, str], int] = {}
    try:
        for raw in BASELINE.read_text(encoding="utf-8").splitlines():
            if not raw.strip() or raw.lstrip().startswith("#"):
                continue
            path, count, line = raw.split("\t", 2)
            key = (path, line)
            if key in allowed or not count.isdecimal() or int(count) < 1 or line != line.strip():
                raise ValueError("invalid or duplicate baseline entry")
            allowed[key] = int(count)
    except (OSError, ValueError) as error:
        print(f"error: cannot read stock-control baseline: {error}", file=sys.stderr)
        return 1

    found: Counter[tuple[str, str]] = Counter()
    locations: dict[tuple[str, str], list[str]] = defaultdict(list)
    for path in sorted(SOURCE.rglob("*.swift")):
        if "DesignSystem" in path.relative_to(SOURCE).parts:
            continue
        relative = path.relative_to(ROOT).as_posix()
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            matches = len(PATTERN.findall(line))
            if matches:
                key = (relative, line.strip())
                found[key] += matches
                locations[key].append(f"{relative}:{number}: {line.strip()}")

    violations = [key for key, count in found.items() if count > allowed.get(key, 0)]
    if violations:
        print("error: new stock SwiftUI controls found outside the design system.")
        for key in violations:
            print(f"  {found[key]} found; {allowed.get(key, 0)} recorded")
            for location in locations[key]:
                print("  " + location)
        return 1
    print(f"ok: no new stock controls; {sum(found.values())} existing occurrences recorded.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
