#!/usr/bin/env python3
"""Split the UI test classes into balanced shards for CI.

The UI suite is too long for one runner, so `.github/workflows/ios.yml` runs it as a matrix.
Each matrix job asks this script which classes are its share:

    scripts/ui_test_shards.py --shards 8 --index 1      # -only-testing:ThorbisUITests/<Class> ...
    scripts/ui_test_shards.py --shards 8 --list          # every shard, with test counts
    scripts/ui_test_shards.py --shards 8 --check         # exit 1 unless every class is in one shard

A class weighs as many tests as it runs: its own, those in its extensions (in any file), and
those it inherits from a base class declared here. Classes go to the lightest shard, heaviest
first. The split depends only on the source files, so every job computes the same answer.

Only the classes named here run in CI, so the planner refuses to guess. It stops with an error
when a `func test...` is not inside a test class it can name, when a class with tests (or a
class named ...Tests) inherits from a class it cannot see, when an extension of a type that is
not a test class declares tests, and when a test class is nested in another type.
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UI_TESTS = ROOT / "ThorbisUITests"
TARGET = "ThorbisUITests"
BASE = "XCTestCase"

# A class or extension header. Comments and strings are blanked first (`_mask`), so the header
# and the braces read here are code.
DECLARATION = re.compile(
    r"(?:^|(?<=[\s;{}]))(?:@[\w.]+(?:\([^)]*\))?\s+)*"
    r"(?:(?:public|open|internal|fileprivate|private|final|nonisolated|indirect)\s+)*"
    r"\b(class|extension)\s+([A-Za-z_][\w.]*)"
)
TEST = re.compile(r"\bfunc\s+(test\w*)\s*[<(]")
NOT_A_TYPE = {"func", "var", "let", "subscript", "override", "final", "private", "fileprivate",
              "public", "open", "internal", "static", "nonisolated", "init", "deinit"}


@dataclass
class _Type:
    name: str
    file: str
    line: int
    superclass: str | None
    tests: list[str] = field(default_factory=list)


def _mask(text: str) -> str:
    """The source with comments and string literals blanked (newlines kept, so offsets and line
    numbers still match). Handles nested block comments, raw strings (#"..."#), multi-line strings
    and interpolation, which may hold strings of its own."""
    out = list(text)
    length = len(text)

    def blank(start: int, end: int) -> None:
        for index in range(start, min(end, length)):
            if out[index] != "\n":
                out[index] = " "

    def string_start(index: int) -> tuple[int, int, bool] | None:
        """(hashes, index after the opening quotes, multi-line) when a string literal starts here."""
        hashes = 0
        while index + hashes < length and text[index + hashes] == "#":
            hashes += 1
        quote = index + hashes
        if quote >= length or text[quote] != '"':
            return None
        if text.startswith('"""', quote):
            return hashes, quote + 3, True
        return hashes, quote + 1, False

    def skip_string(index: int) -> int:
        hashes, position, multiline = string_start(index)  # type: ignore[misc]
        closer = ('"""' if multiline else '"') + "#" * hashes
        escape = "\\" + "#" * hashes
        while position < length:
            if text.startswith(closer, position):
                return position + len(closer)
            if text.startswith(escape, position):
                after = position + len(escape)
                if after < length and text[after] == "(":
                    position = skip_code(after + 1, ")")
                    continue
                position = after + 1
                continue
            if text[position] == "\n" and not multiline:
                return position  # An unterminated literal ends at the line, as the compiler reports.
            position += 1
        return length

    def skip_code(index: int, stop: str | None) -> int:
        depth = 0
        while index < length:
            char = text[index]
            if text.startswith("//", index):
                end = text.find("\n", index)
                end = length if end < 0 else end
                blank(index, end)
                index = end
                continue
            if text.startswith("/*", index):
                start, level = index, 0
                while index < length:
                    if text.startswith("/*", index):
                        level += 1
                        index += 2
                    elif text.startswith("*/", index):
                        level -= 1
                        index += 2
                        if level == 0:
                            break
                    else:
                        index += 1
                blank(start, index)
                continue
            if char in '#"' and string_start(index) is not None:
                end = skip_string(index)
                blank(index, end)
                index = end
                continue
            if stop is not None:
                if char == "(":
                    depth += 1
                elif char == ")":
                    if depth == 0:
                        return index + 1
                    depth -= 1
            index += 1
        return length

    skip_code(0, None)
    return "".join(out)


def _matching_brace(masked: str, opening: int) -> int:
    depth = 0
    for index in range(opening, len(masked)):
        if masked[index] == "{":
            depth += 1
        elif masked[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    return len(masked)


def _superclass(clause: str) -> str | None:
    """The first name in an inheritance clause (`: XCTestCase, Sendable where ...`), if any."""
    clause = re.split(r"\bwhere\b", clause)[0].strip()
    if not clause.startswith(":"):
        return None
    first = clause[1:].split(",")[0]
    first = re.sub(r"@[\w.]+(?:\([^)]*\))?", "", first).strip()
    match = re.match(r"[A-Za-z_][\w.]*", first)
    return match.group(0).split(".")[-1] if match else None


def _scan(directory: Path) -> tuple[dict[str, _Type], dict[str, list[tuple[str, int, list[str]]]],
                                     list[str], list[tuple[str, int, str]]]:
    """Classes and extensions at file scope, problems found while reading, and every test function
    that is not a direct member of a class or extension body (file, line, name)."""
    classes: dict[str, _Type] = {}
    extensions: dict[str, list[tuple[str, int, list[str]]]] = {}
    problems: list[str] = []
    stray: list[tuple[str, int, str]] = []

    for path in sorted(directory.rglob("*.swift")):
        relative = path.relative_to(directory).as_posix()
        masked = _mask(path.read_text(encoding="utf-8"))
        depth_at = [0] * (len(masked) + 1)
        depth = 0
        for index, char in enumerate(masked):
            depth_at[index] = depth
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
        depth_at[len(masked)] = depth

        def line_of(offset: int) -> int:
            return masked.count("\n", 0, offset) + 1

        tests_here: dict[int, str] = {}
        for match in TEST.finditer(masked):
            prefix_start = max(masked.rfind(mark, 0, match.start()) for mark in "\n{};") + 1
            if re.search(r"\b(static|class)\b", masked[prefix_start:match.start()]):
                continue  # A type method is never a test.
            tests_here[match.start()] = match.group(1)

        members: set[int] = set()
        for match in DECLARATION.finditer(masked):
            kind, name = match.group(1), match.group(2)
            if name in NOT_A_TYPE:
                continue
            opening = masked.find("{", match.end())
            if opening < 0:
                continue
            between = masked[match.end():opening]
            if ";" in between or "}" in between:
                continue  # Not a type body.
            header = re.sub(r"^\s*<[^>{]*>", "", between)
            closing = _matching_brace(masked, opening)
            level = depth_at[match.start()]
            own = [offset for offset in tests_here if opening < offset < closing and depth_at[offset] == level + 1]
            line = line_of(match.start())
            superclass = _superclass(header)
            if level > 0:
                if kind == "class" and (superclass == BASE or superclass in classes):
                    problems.append(f"{relative}:{line}: test class {name} is nested in another type; "
                                    f"declare it at file scope so -only-testing can name it")
                continue
            members.update(own)
            names = [tests_here[offset] for offset in own]
            if kind == "extension":
                extensions.setdefault(name.split(".")[-1], []).append((relative, line, names))
            elif name in classes:
                problems.append(f"UI test class {name} is declared twice "
                                f"({classes[name].file}:{classes[name].line} and {relative}:{line})")
            else:
                classes[name] = _Type(name, relative, line, superclass, names)
        stray.extend((relative, line_of(offset), test) for offset, test in sorted(tests_here.items())
                     if offset not in members)
    return classes, extensions, problems, stray


def _chain(name: str, classes: dict[str, _Type]) -> tuple[list[str], str | None]:
    """The class and its ancestors declared here, and how the chain ends: BASE, None (no
    superclass), or the name of a superclass the planner cannot see."""
    chain: list[str] = []
    current: str | None = name
    while current is not None and current in classes and current not in chain:
        chain.append(current)
        current = classes[current].superclass
    if current is not None and current in chain:
        return chain, f"{current} (a cycle)"
    return chain, current


def test_classes(directory: Path = UI_TESTS) -> dict[str, int]:
    """Each XCTestCase class in the directory with the number of tests it runs. Exits with an
    error (SystemExit) naming every test the split could not account for."""
    classes, extensions, problems, stray = _scan(directory)

    def declared(name: str) -> list[str]:
        return classes[name].tests + [test for _, _, tests in extensions.get(name, []) for test in tests]

    result: dict[str, int] = {}
    for name, declaration in classes.items():
        chain, end = _chain(name, classes)
        tests = [test for member in chain for test in declared(member)]
        where = f"{declaration.file}:{declaration.line}"
        if end == BASE:
            if tests:
                result[name] = len(tests)
        elif end is None:
            if declared(name):
                problems.append(f"{where}: {name} declares tests but is not an {BASE}, so they never run")
        elif tests or name.endswith("Tests"):
            problems.append(f"{where}: {name} inherits from {end}, which is not declared in {TARGET}; "
                            f"the planner cannot tell which tests it runs")
    for name, blocks in extensions.items():
        if name in classes:
            continue
        for relative, line, tests in blocks:
            if tests:
                problems.append(f"{relative}:{line}: extension {name} declares {', '.join(tests)}, "
                                f"but {name} is not a UI test class declared in {TARGET}")
    for relative, line, test in stray:
        problems.append(f"{relative}:{line}: func {test} is not a direct member of a UI test class "
                        f"or its extension, so no shard would run it")
    if problems:
        raise SystemExit("The UI test shards cannot account for every test:\n  " + "\n  ".join(problems))
    return result


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
