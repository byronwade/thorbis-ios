#!/usr/bin/env python3
"""Tell a UI test that failed on its own from one whose tap the simulator cancelled.

XCTest sends each tap through a virtual touchscreen it attaches for that one gesture. On a busy
runner the simulator's input server (backboardd) now and then registers that touchscreen twice.
It then drops the events that follow the touch down, the lift among them, and cancels the touch
when the touchscreen goes away. It says so in the simulator's log:

    backboardd[...] [com.apple.BackBoard:TouchEvents] *** unknown digitizer <BKIOHIDService ...>

The app sees a finger that went down and was cancelled, and rightly does nothing. The test then
fails waiting for what the tap should have opened (BYR-1835; first shown in CI run 45119132156,
where it happened once in each of two shards and nowhere in a test that passed).

Two commands, both used by scripts/ci-run-ui-tests.sh:

  ci_cancelled_taps.py stamp <times.tsv>
      Copy standard input to standard output unchanged. For every line in which xcodebuild says
      a test case started, passed, failed or was skipped, a test session started, or a session
      was summed up ("Executed N tests, with F failures"), append the time and the fact to
      <times.tsv>. Nothing it cannot write stops the copying.

  ci_cancelled_taps.py decide <times.tsv> <simulator-log> [--limit N]
      Print the failed tests that may be run once more, one "Target/Class/test" per line, and
      exit 0. That is only when the run is fully accounted for and EVERY failed test has an
      "unknown digitizer" error from backboardd inside the time it ran. Otherwise print nothing,
      say why on standard error, and exit 1. A failure with no such error is a failure.
"""
from __future__ import annotations

import re
import sys
import time

CASE = re.compile(r"Test Case '-\[(\w+)\.(\w+) (\w+)\]' (started|passed|failed|skipped)\b")
SESSION = re.compile(r"Test Suite 'Selected tests' started\b")
EXECUTED = re.compile(r"Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures? \((\d+) unexpected\)")
# A log line from `log stream --style compact`: local time, then the process. The stream's own
# header quotes the filter and names both words, but it does not start with a time.
EVENT = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)(\.\d+)?\S*\s.*\bbackboardd\[\d+.*unknown digitizer")
DEFAULT_LIMIT = 3


def stamp(times_path: str) -> int:
    """Copy stdin to stdout; note each test fact with the time it was read."""
    try:
        times = open(times_path, "a", encoding="utf-8")
    except OSError:
        times = None

    def note(kind: str, value: str) -> None:
        nonlocal times
        if times is None:
            return
        try:
            times.write(f"{time.time():.3f}\t{kind}\t{value}\n")
            times.flush()
        except OSError:
            times = None

    out = sys.stdout.buffer
    for raw in sys.stdin.buffer:
        try:
            out.write(raw)
            out.flush()
        except BrokenPipeError:
            return 0
        line = raw.decode("utf-8", errors="replace")
        match = CASE.search(line)
        if match:
            module, klass, name, what = match.groups()
            note(what, f"{module}/{klass}/{name}")
        elif SESSION.search(line):
            note("session", "started")
        else:
            match = EXECUTED.search(line)
            if match:
                note("executed", f"{match.group(1)} {match.group(3)}")
    return 0


def read_times(path: str):
    """The facts `stamp` wrote, as (time, kind, value), oldest first."""
    rows = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 3:
                raise ValueError(f"not a line this tool wrote: {line!r}")
            rows.append((float(parts[0]), parts[1], parts[2]))
    return rows


def read_events(path: str):
    """When backboardd logged the error, as seconds since the epoch, oldest first."""
    events = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = EVENT.match(line)
            if not match:
                continue
            whole = time.mktime(time.strptime(match.group(1), "%Y-%m-%d %H:%M:%S"))
            events.append(whole + float(match.group(2) or 0))
    return sorted(events)


def clock(seconds: float) -> str:
    return time.strftime("%H:%M:%S", time.localtime(seconds))


def decide(rows, events, limit: int = DEFAULT_LIMIT):
    """Return (tests to run once more, the reasons to print).

    The list is empty unless every failed test may be run again.
    """
    sessions = sum(1 for _, kind, _ in rows if kind == "session")
    if sessions != 1:
        return [], [f"The test session started {sessions} times, not once (no start seen, or the "
                    "runner was restarted after a crash). Nothing is run again."]

    running = None          # (name, started at)
    ended = 0
    failed = []             # (name, started at, ended at)
    for at, kind, value in rows:
        if kind == "started":
            if running is not None:
                return [], [f"{running[0]} started and never finished. Nothing is run again."]
            running = (value, at)
        elif kind in ("passed", "failed", "skipped"):
            if running is None or running[0] != value:
                return [], [f"{value} {kind} without having started. Nothing is run again."]
            ended += 1
            if kind == "failed":
                failed.append((value, running[1], at))
            running = None
    if running is not None:
        return [], [f"{running[0]} started and never finished. Nothing is run again."]

    summaries = [value for _, kind, value in rows if kind == "executed"]
    if not summaries:
        return [], ["xcodebuild never summed the session up. Nothing is run again."]
    executed, failures = (int(part) for part in summaries[-1].split())
    if executed != ended or failures != len(failed):
        return [], [f"xcodebuild counted {executed} tests and {failures} failures; the log shows "
                    f"{ended} and {len(failed)}. Nothing is run again."]
    if not failed:
        return [], ["No test case failed, so the failure is not a test's. Nothing is run again."]
    names = [name for name, _, _ in failed]
    if len(set(names)) != len(names):
        return [], ["A test failed more than once in one session. Nothing is run again."]

    reasons = []
    without = 0
    for name, began, finished in failed:
        inside = [event for event in events if began <= event <= finished]
        if inside:
            reasons.append(f"{name}: the simulator cancelled a tap XCTest had synthesized at "
                           f"{clock(inside[0])} (backboardd logged \"unknown digitizer\").")
        else:
            without += 1
            reasons.append(f"{name}: no cancelled tap in the simulator's log while it ran "
                           f"({clock(began)} to {clock(finished)}). This failure stands.")
    if without:
        reasons.append("Not every failed test had a cancelled tap. Nothing is run again.")
        return [], reasons
    if len(failed) > limit:
        reasons.append(f"{len(failed)} tests had a cancelled tap, more than the {limit} this "
                       "would run again. Nothing is run again.")
        return [], reasons
    return names, reasons


def main(argv) -> int:
    if len(argv) == 3 and argv[1] == "stamp":
        return stamp(argv[2])
    if len(argv) in (4, 6) and argv[1] == "decide":
        limit = DEFAULT_LIMIT
        if len(argv) == 6:
            if argv[4] != "--limit" or not argv[5].isdigit():
                print(__doc__, file=sys.stderr)
                return 2
            limit = int(argv[5])
        try:
            rows = read_times(argv[2])
            events = read_events(argv[3])
        except (OSError, ValueError) as problem:
            print(f"The run's times or the simulator's log could not be read ({problem}). "
                  "Nothing is run again.", file=sys.stderr)
            return 1
        again, reasons = decide(rows, events, limit)
        for reason in reasons:
            print(reason, file=sys.stderr)
        if not again:
            return 1
        print("\n".join(again))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
