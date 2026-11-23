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

That the error happened while a test ran is not enough. It must be the reason the test failed,
as far as XCTest's own record of the test shows it:

  - the error falls within a second of a "Tap" step, on XCTest's own clock (the test's
    "Start Test at" time plus the step's offset), before the next step began;
  - the next step is a "Waiting ..." step, and it is the one that failed: no other step comes
    between it and the test's first failure;
  - that first failure does not speak of a crash, a launch, a termination, a lost connection,
    an exception or anything unexpected, and xcodebuild counted no unexpected failure.

Three commands, all used by scripts/ci-run-ui-tests.sh:

  ci_cancelled_taps.py stamp <times.tsv>
      Copy standard input to standard output unchanged. For every line in which xcodebuild says
      a test case started, passed, failed or was skipped, a test began on XCTest's clock, a test
      took a step, a test failed an assertion, a test session started, or a session was summed
      up ("Executed N tests, with F failures"), append the time and the fact to <times.tsv>.
      Nothing it cannot write stops the copying.

  ci_cancelled_taps.py decide <times.tsv> <simulator-log> [--limit N]
      Print the failed tests that may be run once more, one "Target/Class/test" per line, and
      exit 0. That is only when the run is fully accounted for and EVERY failed test failed on
      the wait right after a tap the simulator cancelled, as above. Otherwise print nothing, say
      why on standard error, and exit 1. A failure without that evidence is a failure.

  ci_cancelled_taps.py confirm <times.tsv> <Target/Class/test>
      Exit 0 only when <times.tsv> shows one session in which exactly that one test ran and
      passed, with no failure and no skip. Otherwise say why on standard error and exit 1.
"""
from __future__ import annotations

import re
import sys
import time

CASE = re.compile(r"Test Case '-\[(\w+)\.(\w+) (\w+)\]' (started|passed|failed|skipped)\b"
                  r"(?: \((\d+(?:\.\d+)?) seconds\))?")
SESSION = re.compile(r"Test Suite 'Selected tests' started\b")
EXECUTED = re.compile(r"Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures? \((\d+) unexpected\)")
# XCTest's activity log. A step of the test itself follows "t = N.NNs " directly; the parts of a
# step are indented further and are not noted.
BEGIN = re.compile(r"\bt =\s+\d+(?:\.\d+)?s Start Test at (\d{4}-\d\d-\d\d \d\d:\d\d:\d\d(?:\.\d+)?)")
STEP = re.compile(r"^\s*t =\s+(\d+(?:\.\d+)?)s (\S[^\t\r\n]*)")
ERROR = re.compile(r": error: -\[(\w+)\.(\w+) (\w+)\] : ([^\t\r\n]*)")
# A log line from `log stream --style compact`: local time, then the process. The stream's own
# header quotes the filter and names both words, but it does not start with a time.
EVENT = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)(\.\d+)?\S*\s.*\bbackboardd\[\d+.*unknown digitizer")
DEFAULT_LIMIT = 3
# How far before a Tap step's own time the error may fall. In run 45119132156 it fell 0.19 s
# before one tap and 0.45 s after another.
BEFORE_TAP = 1.0
# How far after the next step began it may still fall.
AFTER_NEXT = 0.5
# A first failure that says any of these is the app's or the runner's, never a lost tap.
NOT_A_LOST_TAP = ("crash", "launch", "terminate", "lost connection", "not running", "exception",
                  "unexpected", "signal")


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
            module, klass, name, what, took = match.groups()
            note(what, f"{module}/{klass}/{name}" + (f" {took}" if took and what != "started" else ""))
            continue
        match = BEGIN.search(line)
        if match:
            note("begin", match.group(1))
            continue
        match = STEP.search(line)
        if match:
            note("step", f"{match.group(1)} {match.group(2)[:120]}")
            continue
        match = ERROR.search(line)
        if match:
            module, klass, name, message = match.groups()
            note("error", f"{module}/{klass}/{name} {message[:300]}")
            continue
        if SESSION.search(line):
            note("session", "started")
            continue
        match = EXECUTED.search(line)
        if match:
            note("executed", f"{match.group(1)} {match.group(3)} {match.group(4)}")
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


def local_seconds(text: str) -> float:
    """"2026-11-23 06:20:25.002" in this machine's local time, as seconds since the epoch."""
    whole, _, fraction = text.partition(".")
    return time.mktime(time.strptime(whole, "%Y-%m-%d %H:%M:%S")) + (float("0." + fraction) if fraction else 0.0)


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
    return time.strftime("%H:%M:%S", time.localtime(seconds)) + f".{int(round(seconds % 1 * 1000)) % 1000:03d}"


class Refused(Exception):
    """The run cannot be accounted for; nothing is run again."""


def read_run(rows):
    """Every test of the one session: [{name, outcome, began, took, steps, first_error}]."""
    sessions = sum(1 for _, kind, _ in rows if kind == "session")
    if sessions != 1:
        raise Refused(f"The test session started {sessions} times, not once (no start seen, or the "
                      "runner was restarted after a crash).")
    tests = []
    running = None
    for _, kind, value in rows:
        if kind == "started":
            if running is not None:
                raise Refused(f"{running['name']} started and never finished.")
            running = {"name": value, "outcome": None, "began": [], "took": None, "steps": [],
                       "first_error": None, "steps_before_error": None}
        elif kind in ("passed", "failed", "skipped"):
            name, _, took = value.partition(" ")
            if running is None or running["name"] != name:
                raise Refused(f"{name} {kind} without having started.")
            running["outcome"] = kind
            running["took"] = float(took) if took else None
            tests.append(running)
            running = None
        elif running is None:
            continue
        elif kind == "begin":
            running["began"].append(value)
        elif kind == "step":
            offset, _, text = value.partition(" ")
            running["steps"].append((float(offset), text))
        elif kind == "error":
            name, _, message = value.partition(" ")
            if name == running["name"] and running["first_error"] is None:
                running["first_error"] = message
                running["steps_before_error"] = list(running["steps"])
    if running is not None:
        raise Refused(f"{running['name']} started and never finished.")

    summaries = [value for _, kind, value in rows if kind == "executed"]
    if not summaries:
        raise Refused("xcodebuild never summed the session up.")
    parts = summaries[-1].split()
    if len(parts) != 3:
        raise Refused(f"xcodebuild's summary could not be read ({summaries[-1]!r}).")
    executed, failures, unexpected = (int(part) for part in parts)
    failed = [test for test in tests if test["outcome"] == "failed"]
    if executed != len(tests) or failures != len(failed):
        raise Refused(f"xcodebuild counted {executed} tests and {failures} failures; the log shows "
                      f"{len(tests)} and {len(failed)}.")
    if unexpected:
        raise Refused(f"xcodebuild counted {unexpected} unexpected failures (a crash or a thrown "
                      "error, not a failed wait).")
    return tests


def lost_tap(test, events):
    """When the simulator cancelled the tap this test failed on, or a reason it did not."""
    name = test["name"]
    if len(test["began"]) != 1 or test["took"] is None:
        return None, f"{name}: XCTest's own start time or duration is missing. This failure stands."
    began = local_seconds(test["began"][0])
    finished = began + test["took"]
    message = test["first_error"]
    if message is None:
        return None, f"{name}: no failure message from XCTest was seen. This failure stands."
    if any(word in message.lower() for word in NOT_A_LOST_TAP):
        return None, f"{name}: its first failure is not a wait ({message[:160]}). This failure stands."
    steps = [step for step in test["steps_before_error"]
             if not step[1].startswith("Collecting debug information")]
    if len(steps) < 2:
        return None, f"{name}: fewer than two steps came before its first failure. This failure stands."
    (tapped_at, tap), (waited_at, wait) = steps[-2], steps[-1]
    if not (tap.startswith("Tap ") or tap.startswith("Double tap ")) or not wait.startswith("Waiting "):
        return None, (f"{name}: it did not fail on the wait right after a tap (its last two steps: "
                      f"{tap[:80]!r}, {wait[:80]!r}). This failure stands.")
    low = max(began, began + tapped_at - BEFORE_TAP)
    high = min(finished, began + waited_at + AFTER_NEXT)
    inside = [event for event in events if low <= event <= high]
    if not inside:
        return None, (f"{name}: no cancelled tap in the simulator's log at its last tap ({clock(low)} "
                      f"to {clock(high)}). This failure stands.")
    return inside[0], (f"{name}: the simulator cancelled the tap at t = {tapped_at:.2f}s ({tap[:80]}) at "
                       f"{clock(inside[0])} (backboardd logged \"unknown digitizer\"), and the test "
                       f"failed on the wait that came next.")


def decide(rows, events, limit: int = DEFAULT_LIMIT):
    """Return (tests to run once more, the reasons to print).

    The list is empty unless every failed test may be run again.
    """
    try:
        tests = read_run(rows)
    except Refused as problem:
        return [], [f"{problem} Nothing is run again."]
    failed = [test for test in tests if test["outcome"] == "failed"]
    if not failed:
        return [], ["No test case failed, so the failure is not a test's. Nothing is run again."]
    names = [test["name"] for test in failed]
    if len(set(names)) != len(names):
        return [], ["A test failed more than once in one session. Nothing is run again."]

    reasons = []
    without = 0
    for test in failed:
        at, reason = lost_tap(test, events)
        reasons.append(reason)
        if at is None:
            without += 1
    if without:
        reasons.append("Not every failed test failed on a tap the simulator cancelled. Nothing is run again.")
        return [], reasons
    if len(failed) > limit:
        reasons.append(f"{len(failed)} tests had a cancelled tap, more than the {limit} this "
                       "would run again. Nothing is run again.")
        return [], reasons
    return names, reasons


def confirm(rows, name: str):
    """Return a reason the re-run of `name` does not count as passed, or None when it does."""
    try:
        tests = read_run(rows)
    except Refused as problem:
        return str(problem)
    outcomes = [(test["name"], test["outcome"]) for test in tests]
    if outcomes != [(name, "passed")]:
        return f"The re-run was to run {name} alone and see it pass; it ran {outcomes or 'nothing'}."
    if tests[0]["first_error"] is not None:
        return f"{name} passed but reported a failure ({tests[0]['first_error'][:160]})."
    return None


def main(argv) -> int:
    if len(argv) == 3 and argv[1] == "stamp":
        return stamp(argv[2])
    if len(argv) == 4 and argv[1] == "confirm":
        try:
            rows = read_times(argv[2])
        except (OSError, ValueError) as problem:
            print(f"The re-run's times could not be read ({problem}).", file=sys.stderr)
            return 1
        problem = confirm(rows, argv[3])
        if problem:
            print(problem, file=sys.stderr)
            return 1
        return 0
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
        try:
            again, reasons = decide(rows, events, limit)
        except (ValueError, OverflowError) as problem:
            print(f"The run's times could not be read ({problem}). Nothing is run again.", file=sys.stderr)
            return 1
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
