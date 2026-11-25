#!/usr/bin/env python3
"""Tell a UI test that failed on its own from one whose tap or key chord the simulator lost.

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
    between it and the test's first failure. A wait made with XCTWaiter on a predicate does not
    count. XCTest writes no "Waiting ..." step for it, only a "Checking `Expect predicate `...`"
    step each time it checks, about once a second, and nothing that marks where the wait begins
    or ends. In run 45558161330, shard 3, the checks of one wait came 0.92 to 1.07 s apart, and a
    wait's first check came about a second after it began. So a wait that passed, followed by a
    wait on the same predicate that failed, can write the same steps as one wait that failed, and
    that record cannot show that the test failed on the wait right after its tap. Such a failure
    stands;
  - that first failure does not speak of a crash, a launch, a termination, a lost connection,
    an exception or anything unexpected, and xcodebuild counted no unexpected failure.

The same input server loses a hardware-keyboard chord in a second way (BYR-1843; CI runs
45133610900 and 45148171838, the iPad ⌘K test). XCTest attaches a virtual keyboard for each
typeKey call and removes it about 0.2 s later. backboardd hands a ⌘ chord to the app as a key
command only once the app has told it which key commands it has:

    backboardd[...] [com.apple.BackBoard:EventDelivery] new key command registrations for pid:15145
        environment: keyboardFocus; ... keyCommands: { ... cmd: (... k ...), ... }

Until then the chord takes one of two routes, and neither reaches the app as the chord. If
SpringBoard's own keyboardFocus table holds no command for it (⌘K, ⇧⌘N), backboardd finds none
and hands the app the bare letter:

    backboardd[...] [com.apple.BackBoard:EventDeliveryMatching] cache miss for Keyboard event
    backboardd[...] [com.apple.BackBoard:EventDelivery] sequence starting with Keyboard event:
        <sq: ...; (<keyboardFocus; display: builtin; pid: 15145; token: ...>)>

If SpringBoard's table holds it (⌘F, ⌃⌘S), backboardd refuses it in SpringBoard's system overlay,
matches it in SpringBoard's keyboardFocus table, SpringBoard takes it, and the app is sent nothing
(CI run 45573322329, SpringBoard pid 1378):

    backboardd[...] [com.apple.BackBoard:EventDeliveryMatching] KCMD: no match in pid:1378 systemKeyCommandOverlay
    backboardd[...] [com.apple.BackBoard:EventDeliveryMatching] KCMD: match in pid:1378 keyboardFocus

On the iPad the app usually registers 0.2 to 0.7 s after the first keyboard comes, but now and
then not until a later one, and a test that pressed its chord twice before that fails. A
failure counts as that, and as nothing else, only when ALL of these hold:

  - the same rules about the first failure as for a tap, and its last two steps are a
    "Type '<key>' key with modifiers '<m>' (0x..)" step and then a "Waiting <N>s ..." step;
  - that wait ran out: between it and the first failure XCTest wrote its "Collecting debug
    information" notice, no sooner than the wait began, and for the second route below at
    least N seconds after it began. For the second route the same holds for the wait after
    EVERY chord of the test: the next step after each chord is a "Waiting <N>s" step, and the
    notice follows it, before the step after it, at least N seconds after it began. Without
    that the failure stands, whatever it was: a wait that passed, a wait step whose N cannot
    be read, or a wait that ran out without the notice. (In run 45573322329 the notices came
    4.23 and 4.37 s after the last 4.0 s waits, and after each first wait too; each of the ten
    notices in that job's log came at least N seconds after a "Waiting <N>s" step, and none
    followed a wait that passed. The bare-key route checks neither the N seconds nor the
    earlier chords' waits, because the tests of ci-run-ui-tests.sh write its lost chords with
    one notice, straight after the last wait.)
  - backboardd logged exactly one connection from a process named Thorbis while the test ran,
    before its first chord, which names the app's pid;
  - for EVERY chord of the test, between a second before its step and half a second after the
    next step began on XCTest's clock, backboardd sent the key to no pid but the app's, and
    EITHER every chord logged a cache miss and then the key sent to the app's pid as a bare
    "Keyboard event", OR every chord took the second route: no key sent at all, and "KCMD: match
    in pid:<P> keyboardFocus" right after "KCMD: no match in pid:<P> systemKeyCommandOverlay" at
    the same instant, for one pid P that registered a systemKeyCommandOverlay table (in run 45573322329 only
    SpringBoard, pid 1378, did; in the iPad shard 1 log of head b1f4a10 a second process, pid
    3252, registered one too, which is why the next bullet requires exactly one), never
    connected as Thorbis, and whose last keyboardFocus
    registration before the match lists the key under exactly the modifiers pressed. Each
    chord's match comes after the previous chord's. A test whose chords took both routes, a
    cache miss alone, or a match in any other process or table counts as neither;
  - for the second route also: P is the only process whose systemKeyCommandOverlay
    registration appears anywhere in the log, whether or not the rest of that line can be read
    (a second one, or SpringBoard back under a new pid, stands); from a second before the
    first chord to the end of the test, backboardd sent no key on to anyone; while the test
    ran, it never logged "KCMD: no match in pid:<P> keyboardFocus"; and the app's first
    registration came at most REGISTERED_WITHIN (1.0 s) after the last match (0.33 and 0.47 s
    in run 45573322329);
  - backboardd matched or refused no key command for the app's pid during the test ("KCMD: ...
    in pid:<app>" never appears), so no chord reached the app as a command;
  - the app registered no key commands before its last chord was sent, and its first
    registration after it, during the test, lists the key under exactly the modifiers pressed:
    the app does declare the chord, and the chord came before it had said so.

What the log cannot show, and what the rule assumes. First, that a late first registration is the
simulator's doing (it follows XCTest's keyboard), not the app being slow to set up its commands;
the log cannot tell the two apart. Second, for the second route only, that the app was the one
that should have had the keyboard when SpringBoard took the chord. Nothing in the log proves it,
and a SpringBoard alert over the app would most likely log the same lines. The rule accepts that,
on these grounds: the app registering the pressed chord within a second of the last press shows
it became the keyboard's target then, which it would not under an alert that stayed; a test that
is run again must pass on its own, and a second failure fails the step. What the log cannot show
is why the simulator had not yet made the app the keyboard's target.

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
      the wait right after a tap the simulator cancelled, or right after a key chord it did not
      deliver in either of the two ways above. Otherwise print nothing, say why on standard error, and exit 1. A
      failure without that evidence is a failure. The simulator log holds both kinds of line.

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
# How soon after a chord the system's own table took the app's first registration must follow. Observed:
# 0.33 s and 0.47 s in run 45573322329; after a bare key 0.2 to 0.7 s.
REGISTERED_WITHIN = 1.0
# A first failure that says any of these is the app's or the runner's, never a lost tap.
NOT_A_LOST_TAP = ("crash", "launch", "terminate", "lost connection", "not running", "exception",
                  "unexpected", "signal")
# Lines XCTest writes among a test's steps that are its own notices, not steps the test took. The
# second is what it says after waiting 60 s for the app's animations to finish, which can happen
# inside a tap: the tap is still the step, and the wait after it is still the next one.
NOT_A_STEP = ("Collecting debug information", "App animations complete notification not received")
# Any line of that log that names backboardd, with the message after the subsystem. A message
# can span lines; in compact style only its first line carries a time.
STAMPED = re.compile(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d")
KEY_LINE = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)(\.\d+)?\S*\s+\S+\s+backboardd\[\d+:[0-9a-fA-F]+\]\s+"
                      r"(?:\[[^\]\s]*\]\s+)?(\S.*)$")
# What backboardd says about a key, as logged in runs 45133610900 and 45148171838.
CONNECTED = re.compile(r"^Connection added: IOHIDEventSystemConnection\b.*?\bpid:(\d+) process:Thorbis\s")
MATCHING = re.compile(r"^KCMD: .*?\bin pid:(\d+)\b")
# A chord matched in a process's own keyboardFocus table, as logged in run 45573322329 for SpringBoard.
TAKEN = re.compile(r"^KCMD: match in pid:(\d+) keyboardFocus$")
MISSED = re.compile(r"^cache miss for Keyboard event\b")
ROUTED = re.compile(r"^sequence starting with Keyboard event: ")
ROUTED_TO = re.compile(r"\bpid: (\d+);")
REGISTERED = re.compile(r"^new key command registrations for pid:(\d+) environment: (\w+); [^\n]*keyCommands: \{\n(.*)\n\}\s*$",
                        re.S)
REGISTERED_GROUP = re.compile(r"^\s*([a-z|]+): \((.*)\),?\s*$")
REGISTERED_KEY = re.compile(r'\(\w+:\w+\)|"[^"]*"|[^\s,()"]+')
# XCTest's own step for typeKey(_:modifierFlags:), and its modifier bits as backboardd names them.
CHORD = re.compile(r"^Type '(.)' key with modifiers '[^']*' \(0x([0-9a-fA-F]+)\)$")
MODIFIERS = {0x02: "shft", 0x04: "ctrl", 0x08: "opt", 0x10: "cmd"}
# Any registration of the system's own overlay table, whether or not REGISTERED can read the rest of it.
OVERLAY_ANY = re.compile(r"^new key command registrations for pid:(\d+) environment: systemKeyCommandOverlay\b")
# How long XCTest's own "Waiting 4.0s for ..." step may wait.
WAIT_TIME = re.compile(r"^Waiting (\d+(?:\.\d+)?)s ")


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


def read_keys(path: str):
    """What backboardd said about keys and the app, as (seconds since the epoch, message), oldest
    first. A message's later lines are joined to its first with newlines."""
    records = []
    current = None
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.rstrip("\r\n")
            if STAMPED.match(line):
                match = KEY_LINE.match(line)
                current = None
                if match and "unknown digitizer" not in match.group(3):
                    whole = time.mktime(time.strptime(match.group(1), "%Y-%m-%d %H:%M:%S"))
                    current = [whole + float(match.group(2) or 0), match.group(3)]
                    records.append(current)
            elif current is not None:
                current[1] += "\n" + line
    # By time alone: lines logged in the same millisecond keep the order backboardd logged them in.
    return sorted(((at, text) for at, text in records), key=lambda record: record[0])


def key_commands(text: str):
    """A registration's pid, environment and {modifier set: keys}, or None if it is not one."""
    match = REGISTERED.match(text)
    if not match:
        return None
    groups = {}
    for line in match.group(3).split("\n"):
        group = REGISTERED_GROUP.match(line)
        if not group:
            return None
        keys = set(REGISTERED_KEY.findall(group.group(2)))
        groups[frozenset(group.group(1).split("|"))] = keys
    return int(match.group(1)), match.group(2), groups


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
                       "first_error": None, "steps_before_error": None, "errors": 0}
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
            if name == running["name"]:
                running["errors"] += 1
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
    # xcodebuild counts failure records, not failed tests: a test that fails a wait and then a
    # later step counts twice. Compare it with the error lines recorded under the tests.
    recorded = sum(test["errors"] for test in tests)
    if executed != len(tests) or failures != recorded:
        raise Refused(f"xcodebuild counted {executed} tests and {failures} failures; the log shows "
                      f"{len(tests)} and {recorded}.")
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
             if not step[1].startswith(NOT_A_STEP)]
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


def chord_steps(test):
    """The test's steps before its first failure, and whether it failed on the wait after a chord."""
    steps = [step for step in test["steps_before_error"] or ()
             if not step[1].startswith(NOT_A_STEP)]
    shaped = len(steps) >= 2 and CHORD.match(steps[-2][1]) is not None and steps[-1][1].startswith("Waiting ")
    return steps, shaped


def lost_chord(test, keys):
    """When the simulator sent the chord this test failed on to the app as a bare key, or let the system's
    own key commands take it, or a reason it did neither."""
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
    steps, shaped = chord_steps(test)
    if not shaped:
        return None, f"{name}: it did not fail on the wait right after a key chord. This failure stands."
    last_at, last_chord = steps[-2]
    key, mask = CHORD.match(last_chord).groups()
    bits = int(mask, 16)
    pressed = frozenset(word for bit, word in MODIFIERS.items() if bits & bit)
    if "cmd" not in pressed or bits & ~sum(MODIFIERS):
        return None, f"{name}: its last chord ({last_chord[:80]}) is not a ⌘ key command. This failure stands."

    apps = [(at, int(CONNECTED.match(text).group(1))) for at, text in keys
            if began <= at <= finished and CONNECTED.match(text)]
    if len(apps) != 1:
        return None, (f"{name}: backboardd logged {len(apps)} connections from the app while it ran, not one, "
                      "so the app's pid is not known. This failure stands.")
    connected, app = apps[0]
    chords = [(index, at, text) for index, (at, text) in enumerate(steps[:-1]) if CHORD.match(text)]
    if connected >= began + chords[0][1]:
        return None, f"{name}: the app connected to backboardd only after its first chord. This failure stands."
    launches = {int(CONNECTED.match(text).group(1)) for _, text in keys if CONNECTED.match(text)}

    def tables(pid, environment, when):
        """`pid`'s registrations for `environment` logged at or before `when`, parsed."""
        return [key_commands(text) for at, text in keys if at <= when and REGISTERED.match(text)
                and REGISTERED.match(text).groups()[:2] == (str(pid), environment)]

    def holds(pid, when):
        """Whether `pid`'s last keyboardFocus registration before `when` lists the pressed chord."""
        found = tables(pid, "keyboardFocus", when)
        listed = found[-1][2].get(pressed, set()) if found and found[-1] is not None else set()
        return key in listed or f'"{key}"' in listed

    def system(pid, position, inside):
        """Whether the match at `inside[position]` is in the system's own table: `pid` registered the
        system key command overlay, and backboardd refused the chord in that overlay, in that very pid,
        in the record just before the match and at the same instant."""
        if not position or not tables(pid, "systemKeyCommandOverlay", inside[position][0]):
            return False
        when, line = inside[position - 1]
        return when == inside[position][0] and line == f"KCMD: no match in pid:{pid} systemKeyCommandOverlay"

    sent = taker = None
    forms = set()
    for index, at, text in chords:
        if CHORD.match(text).groups() != (key, mask):
            return None, (f"{name}: it pressed more than one chord ({text[:60]!r} and {last_chord[:60]!r}). "
                          "This failure stands.")
        low = max(began, began + at - BEFORE_TAP)
        high = min(finished, began + steps[index + 1][0] + AFTER_NEXT)
        inside = [(when, line) for when, line in keys if low <= when <= high]
        missed = [when for when, line in inside if MISSED.match(line)]
        routed = [(when, ROUTED_TO.findall(line)) for when, line in inside if ROUTED.match(line)]
        if any(pids != [str(app)] for _, pids in routed):
            return None, (f"{name}: at t = {at:.2f}s backboardd sent a key to another process than the app "
                          f"(pid {app}). This failure stands.")
        bare = [when for when, _ in routed if missed and missed[0] <= when]
        # The second form: matched in the system's own keyboardFocus table, one that holds this chord, with
        # nothing sent to the app. Each chord needs its own match, later than the last chord's, in the same pid.
        taken = [(when, int(TAKEN.match(line).group(1))) for position, (when, line) in enumerate(inside)
                 if TAKEN.match(line) and int(TAKEN.match(line).group(1)) not in launches | {app}
                 and (sent is None or when > sent) and (taker is None or int(TAKEN.match(line).group(1)) == taker)
                 and holds(int(TAKEN.match(line).group(1)), when)
                 and system(int(TAKEN.match(line).group(1)), position, inside)]
        if bare:
            sent = bare[-1]
            forms.add("bare")
        elif taken and not routed:
            sent, taker = taken[-1]
            forms.add("taken")
        else:
            return None, (f"{name}: no chord the simulator failed to deliver at t = {at:.2f}s ({clock(low)} to "
                          f"{clock(high)}): backboardd did not log a cache miss and a bare key to the app. "
                          "This failure stands.")
        if len(forms) > 1:
            return None, (f"{name}: at t = {at:.2f}s its chords had taken both routes, a bare key to the app and "
                          "a match in the system's own table, which no lost chord shows. This failure stands.")
    matched = [when for when, line in keys if began <= when <= finished + AFTER_NEXT
               and MATCHING.match(line) and int(MATCHING.match(line).group(1)) == app]
    if matched:
        return None, (f"{name}: backboardd matched a key command against the app (pid {app}) at "
                      f"{clock(matched[0])}, so a chord reached it. This failure stands.")
    registrations = [(when, key_commands(line)) for when, line in keys
                     if REGISTERED.match(line) and int(REGISTERED.match(line).group(1)) == app]
    early = [when for when, _ in registrations if when <= sent]
    if early:
        return None, (f"{name}: the app (pid {app}) had registered its key commands at {clock(early[0])}, "
                      "before its last chord. This failure stands.")
    later = [(when, parsed) for when, parsed in registrations if sent < when <= finished]
    if not later or later[0][1] is None:
        return None, (f"{name}: the app (pid {app}) registered no key commands that could be read after its "
                      "last chord, so nothing shows it declares that chord. This failure stands.")
    registered_at, (_, environment, groups) = later[0]
    listed = groups.get(pressed, set())
    if environment != "keyboardFocus" or (key not in listed and f'"{key}"' not in listed):
        return None, (f"{name}: the key commands the app (pid {app}) registered at {clock(registered_at)} do not "
                      f"include {last_chord[5:40]!r}. This failure stands.")
    # XCTest's notices after each step, up to the next step: notices[i] follows steps[i].
    notices = []
    for when, text in test["steps_before_error"]:
        if not text.startswith(NOT_A_STEP):
            notices.append([])
        elif notices:
            notices[-1].append((when, text))

    def ran_out(position, timed):
        """Whether steps[position] is a "Waiting <N>s" step after which, before the next step, XCTest wrote its
        "Collecting debug information" notice no sooner than the wait began, and if `timed`, at least N s after it."""
        waited_at, wait = steps[position]
        timeout = WAIT_TIME.match(wait)
        least = float(timeout.group(1)) if timeout and timed else 0.0
        return timeout is not None and any(text.startswith(NOT_A_STEP[0]) and round(when - waited_at, 2) >= least
                                           for when, text in notices[position])

    # The wait after the last chord ran out, in the second form no sooner than the wait's own time after it began.
    if not ran_out(len(steps) - 1, forms == {"taken"}):
        return None, (f"{name}: XCTest's record does not show that its last wait ({steps[-1][1][:60]!r}) ran out, so "
                      "the test may have failed on something else. This failure stands.")
    if forms == {"taken"}:
        # So did the wait after every earlier chord: a wait that passed shows that its chord did its job.
        for index, at, _ in chords:
            if not ran_out(index + 1, True):
                return None, (f"{name}: XCTest's record does not show that the wait after its chord at t = {at:.2f}s "
                              "ran out, so that chord may have reached the app. This failure stands.")
        systems = sorted({int(OVERLAY_ANY.match(line).group(1)) for _, line in keys if OVERLAY_ANY.match(line)})
        if systems != [taker]:
            return None, (f"{name}: more than one process registered the system's own key commands (pids "
                          f"{', '.join(map(str, systems))}), so pid {taker} is not known to be SpringBoard. "
                          "This failure stands.")
        first = began + chords[0][1] - BEFORE_TAP
        refused = [when for when, line in keys if began <= when <= finished
                   and line == f"KCMD: no match in pid:{taker} keyboardFocus"]
        if refused:
            return None, (f"{name}: backboardd also found no command for a key in the table of pid {taker} at "
                          f"{clock(refused[0])}, while the test ran. This failure stands.")
        handed = [when for when, line in keys if first <= when <= finished and ROUTED.match(line)]
        if handed:
            return None, (f"{name}: backboardd sent a key on at {clock(handed[0])}, after the test's first chord, "
                          "so not every key of the test was taken. This failure stands.")
        if registered_at - sent > REGISTERED_WITHIN:
            return None, (f"{name}: the app (pid {app}) registered its key commands at {clock(registered_at)}, "
                          f"more than {REGISTERED_WITHIN:.1f} s after its last chord was taken at {clock(sent)}. "
                          "This failure stands.")
        return sent, (f"{name}: the simulator did not deliver the key chord it failed on: at t = {last_at:.2f}s "
                      f"({last_chord[:60]}) backboardd matched it in the system's own key commands (pid {taker}), "
                      f"not the app's (pid {app}), at {clock(sent)}, and sent the app nothing, as it did for every "
                      "chord of the test, before the app had registered any key commands; the app registered "
                      f"that chord at {clock(registered_at)}, and the test failed on the wait that came next.")
    return sent, (f"{name}: the simulator did not deliver the key chord it failed on: at t = {last_at:.2f}s "
                  f"({last_chord[:60]}) backboardd sent the app (pid {app}) the bare key at {clock(sent)}, as it "
                  f"did for every chord of the test, before the app had registered any key commands; the app "
                  f"registered that chord at {clock(registered_at)}, and the test failed on the wait that "
                  "came next.")


def decide(rows, events, limit: int = DEFAULT_LIMIT, keys=()):
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
        if at is None and chord_steps(test)[1]:
            at, reason = lost_chord(test, keys)
        reasons.append(reason)
        if at is None:
            without += 1
    if without:
        reasons.append("Not every failed test failed on a tap the simulator cancelled or a key chord it did "
                       "not deliver. Nothing is run again.")
        return [], reasons
    if len(failed) > limit:
        reasons.append(f"{len(failed)} tests had a cancelled tap or a lost key chord, more than the {limit} this "
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
            keys = read_keys(argv[3])
        except (OSError, ValueError) as problem:
            print(f"The run's times or the simulator's log could not be read ({problem}). "
                  "Nothing is run again.", file=sys.stderr)
            return 1
        try:
            again, reasons = decide(rows, events, limit, keys)
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
