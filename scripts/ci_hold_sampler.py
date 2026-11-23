#!/usr/bin/env python3
"""Take a stack sample of the app while its main thread has been held for several seconds.

Evidence for BYR-1841, not a test. The first time Customer view opens on the Estimates page in
a launch, the app's main thread is held: over 507 first openings in eight CI runs the median
was about 3 s, 15 were over 11 s, 3 over 20 s, and one over 30 s failed a UI test, because 30 s
is XCTest's own limit for one query. What the main thread does meanwhile is not known.

The first sampler (ced67b7e, removed in 7b994231) was set off by a backboardd line logged near
the START of every hold. The sample tool takes 1.3 to 16 s to start on a loaded runner, so eight
of its nine samples were of an app that was idle again. This one is set off by the hold itself
having lasted several seconds, so a sample starts only inside a hold that is already long.

How a hold is seen. While XCTest drives the app, a helper thread inside the app logs a pair of
lines for every request XCTest makes of the app's main thread:

    Thorbis[53314:143488] [Default] XCTPerformOnMainRunLoop[not MT]: about to CFRunLoopPerform
        when the request is queued (logged off the main thread), and
    Thorbis[53314:142933] [Default] XCTPerformOnMainRunLoop[MT]: inside CFRunLoopPerform
        when the main thread starts serving it.

A request of one pid that has been queued for N seconds with no "inside" line since is a hold of
N seconds, seen from outside the main thread. Whether these lines reach the simulator's unified
log, and at which level, has not been observed (the copies on disk came from the app's stdout
and stderr). So the level steps up only when needed (step_up_now, below): the stream starts at
"default", the level the runner script's own filter uses. If ESCALATE_SECONDS pass after a
stream starts and not one request line has been read from it, that stream is stopped and a new
one starts at the next level, "info", then "debug", where it stays. A debug stream makes every
process in the simulator emit its debug messages while it is attached, so it is asked for only
when the quieter levels delivered nothing. Once one request line has been read, the level never
changes again. If none ever arrives, it ends at "debug" for the rest of the first run and takes
no sample. Both the stderr shape above and `log stream --style compact`'s shape are read: the pid
and the two markers are looked for anywhere in a line. A marker is "XCTPerformOnMainRunLoop" with
"about to CFRunLoopPerform" or with "inside CFRunLoopPerform", not the bracketed tag, so a tag the
unified log redacts to <private> still counts (in the app's logs each phrase comes only with its
own tag). Every other line the stream delivers is counted, and the first few are kept in
summary.txt, so a run whose lines arrive in a shape not read here says so. Time is measured by
when a line ARRIVES, on a monotonic clock, not by the stamps in the lines.

The rule (Holds, below): when a hold has lasted HOLD_SECONDS take a first sample of that pid; if
the SAME hold is still going at SECOND_SECONDS take one more, which shows whether the thread is
moving; never more than two per hold and never more than LIMIT per run. A served line for that
pid ends its hold. A queued line for another pid (a new launch) drops the older pid's hold.
Lines that piled up while a sample ran are all read before the next decision, and they arrive
only then, so they never make an old hold look newer or a new one look older.

    ci_hold_sampler.py watch <simulator-id> <output-dir> [--limit N]

Follows the simulator's log through `xcrun simctl spawn <id> log stream --level <level>` (a child
in its own process group) and runs `sudo -n sample <pid> 3 20 -file <file>`, or `sample` itself
if that fails, each bounded: after 60 s it is asked to stop, then killed, and a tool that still
holds its output (sample, as root under sudo) is left running and no longer waited for. Each
sample is <output-dir>/hold-NN-HHMMSS-pid<pid>.txt; beside it
hold-NN-HHMMSS-pid<pid>.trigger.txt says how long the hold had lasted, which sample of the hold
it is, what the tool took and said, and whether the hold was still going when it returned. On
SIGTERM or SIGINT it stops the stream, lets a running sample finish (bounded), writes
<output-dir>/summary.txt and prints the same one line to standard error; both say which level was
in use at the end and each step up, and summary.txt lists every stream started, in order. It
never writes to standard output, never reads standard input, never signals anything but its own
children, and exits 0 in every case. scripts/ci-run-ui-tests.sh starts it only when
THORBIS_HOLD_SAMPLES names a directory.

It does not change how a test passes or fails, or which test is run once more. It does add some
load while it runs: a filtered log stream for the shard's first run, and, during a hold that
has already lasted 5 s, a 3 s stack sample. It does not watch a test that is being run once more
by itself. Remove it once BYR-1841 has its stack.
"""
from __future__ import annotations

import os
import re
import select
import signal
import subprocess
import sys
import time

HOLD_SECONDS = 5.0
SECOND_SECONDS = 15.0
LIMIT = 8
# 3 s at one stack every 20 ms. No -mayDie: it reads every image's symbols before the first
# stack, which on a loaded runner can outlast the hold.
SAMPLE_SECONDS = 3
SAMPLE_INTERVAL_MS = 20
TOOL_TIMEOUT = 60.0
# Past its bound, how long a tool has after SIGTERM, and then after SIGKILL, before it is left.
TOOL_GRACE = 3.0
# Once a stop is asked for, how much longer a running sample may take before it is stopped. With
# the two graces and the stream's close (2 s + 2 s) it stays inside the runner script's 30 s.
STOP_GRACE = 15.0
PREDICATE = 'process == "Thorbis" AND eventMessage CONTAINS "CFRunLoopPerform"'
# The stream's levels, quietest first. It starts at the first, the level of the runner script's
# own filter, and steps up one at a time (step_up_now). At the last it stays.
LEVELS = ("default", "info", "debug")
# How long a stream may deliver no request line before the next level is tried. On real runs
# the first app launch comes 60 to 97 s after the step starts, so by 300 s the level delivers
# nothing.
ESCALATE_SECONDS = 300.0

QUEUED = "queued"
SERVED = "served"

APP = re.compile(r"\bThorbis\[([0-9]+):")
QUEUED_MARKS = ("XCTPerformOnMainRunLoop", "about to CFRunLoopPerform")
SERVED_MARKS = ("XCTPerformOnMainRunLoop", "inside CFRunLoopPerform")
HEADER = "Filtering the log data"
# The column line `log stream --style compact` prints after the header.
COLUMNS = "Timestamp "
# How many lines the stream delivered that were not understood are kept, and how much of each.
KEEP_OTHERS = 20
KEEP_WIDTH = 300
# A line longer than this without a newline is dropped, so a broken stream cannot fill memory.
LONGEST_LINE = 1 << 20


def parse_line(text: str):
    """Return (pid, QUEUED or SERVED) for one of the app's two lines, else None.

    The stream's header quotes the predicate, and so names the marker words, but it is never an
    event; nor is any line without "Thorbis[<pid>:".
    """
    if HEADER in text:
        return None
    found = APP.search(text)
    if not found:
        return None
    if all(mark in text for mark in QUEUED_MARKS):
        return int(found.group(1)), QUEUED
    if all(mark in text for mark in SERVED_MARKS):
        return int(found.group(1)), SERVED
    return None


class Lines:
    """Split bytes as they are read into whole lines; keep a partial last line for next time."""

    def __init__(self):
        self.rest = b""

    def feed(self, data: bytes):
        self.rest += data
        *whole, self.rest = self.rest.split(b"\n")
        if len(self.rest) > LONGEST_LINE:
            self.rest = b""
        return [line.rstrip(b"\r").decode("utf-8", errors="replace") for line in whole]

    def end(self):
        rest, self.rest = self.rest, b""
        return [rest.decode("utf-8", errors="replace")] if rest else []


class Sample:
    """One sample the watcher should take now."""

    def __init__(self, pid: int, lasted: float, which: int, hold: int):
        self.pid = pid
        self.lasted = lasted    # how long the hold had lasted when it was asked for
        self.which = which      # 1: first of this hold, 2: second
        self.hold = hold        # which hold of the run, counting from 1

    def __repr__(self):
        return f"Sample(pid={self.pid}, lasted={self.lasted:.2f}, which={self.which}, hold={self.hold})"


class Holds:
    """The pure rule. Fed parsed events with their arrival time; asked what to do at a time."""

    def __init__(self, hold: float = HOLD_SECONDS, second: float = SECOND_SECONDS, limit: int = LIMIT):
        self.hold_after = hold
        self.second_after = second
        self.limit = limit
        self.pid = None         # the pid whose request is waiting, if any
        self.began = None       # when that request arrived
        self.number = 0         # holds started in this run (requests that began one)
        self.taken = 0          # samples asked for in this hold
        self.passed = False     # whether this hold has passed hold_after
        self.queued = 0
        self.served = 0
        self.long_holds = 0     # holds that lasted hold_after or more
        self.samples = 0        # samples asked for in this run
        self.over_limit = 0     # samples not asked for because the run's limit was reached

    def feed(self, at: float, pid: int, kind: str):
        if kind == QUEUED:
            self.queued += 1
            if self.pid is not None and self.pid != pid:
                self.pid = None     # a new launch: the old pid's hold is over without a word
            if self.pid is None:
                self.pid = pid
                self.began = at
                self.number += 1
                self.taken = 0
                self.passed = False
            # Another request of a held pid is the same hold: it began when the first did.
        elif kind == SERVED:
            self.served += 1
            if pid == self.pid:
                self.pid = None
                self.began = None

    def holding(self, pid: int, hold: int) -> bool:
        """Whether that hold is still going."""
        return self.pid == pid and self.number == hold

    def lasted(self, now: float) -> float:
        return now - self.began if self.pid is not None else 0.0

    def wait(self, now: float, longest: float) -> float:
        """How long the watcher may wait for the next line before it must ask `due` again."""
        if self.pid is None or self.taken >= 2:
            return longest
        at = self.began + (self.hold_after if self.taken == 0 else self.second_after)
        return max(0.0, min(longest, at - now))

    def due(self, now: float):
        """The sample to take now, or None."""
        if self.pid is None:
            return None
        lasted = now - self.began
        if lasted < self.hold_after:
            return None
        if not self.passed:
            self.passed = True
            self.long_holds += 1
        if self.taken == 0:
            which = 1
        elif self.taken == 1 and lasted >= self.second_after:
            which = 2
        else:
            return None
        self.taken += 1     # counted even past the limit, so a hold is never asked about twice
        if self.samples >= self.limit:
            self.over_limit += 1
            return None
        self.samples += 1
        return Sample(self.pid, lasted, which, self.number)


def step_up_now(since_start: float, events_since_start: int, level: str, after: float = ESCALATE_SECONDS) -> bool:
    """Whether to stop the stream at `level` and start one at the next.

    Yes only when `after` s have passed since that stream started, not one request line (queued
    or served) has been read since, and a louder level is left. Lines not understood do not count.
    """
    return level != LEVELS[-1] and events_since_start == 0 and since_start >= after


def stream_command(simulator_id: str, level: str = LEVELS[0]):
    return ["xcrun", "simctl", "spawn", simulator_id, "log", "stream", "--style", "compact",
            "--level", level, "--predicate", PREDICATE]


def sample_commands(pid: int, path: str):
    tool = ["sample", str(pid), str(SAMPLE_SECONDS), str(SAMPLE_INTERVAL_MS), "-file", path]
    return [["sudo", "-n"] + tool, tool]


def say(text: str):
    try:
        print(text, file=sys.stderr, flush=True)
    except (OSError, ValueError):
        pass


class Watcher:
    def __init__(self, simulator_id, out, limit=LIMIT, hold=HOLD_SECONDS, second=SECOND_SECONDS,
                 clock=time.monotonic, tool_timeout=TOOL_TIMEOUT, tool_grace=TOOL_GRACE,
                 escalate=ESCALATE_SECONDS):
        self.simulator_id = simulator_id
        self.out = out
        self.holds = Holds(hold, second, limit)
        self.clock = clock
        self.lines = Lines()
        self.child = None
        self.reaped = False
        self.stop_at = None
        self.escalate = escalate
        self.level = 0          # the index in LEVELS of the stream asked for last
        self.streams = []       # every stream started, in order: its level, command and header
        self.steps = []         # each step up, in plain words
        self.stream_began = None
        self.events_at_start = 0
        self.taken = 0
        self.failed = 0
        self.problem = None
        self.stream_status = None
        self.tool_timeout = tool_timeout
        self.tool_grace = tool_grace
        self.lines_seen = 0     # lines the stream delivered, apart from its header and columns
        self.others = 0         # of those, the ones that were not one of the app's two lines
        self.examples = []      # the first KEEP_OTHERS of them

    # -- signals ------------------------------------------------------------------------------
    def ask_stop(self, *_):
        if self.stop_at is None:
            self.stop_at = self.clock()
        self.stop_stream(signal.SIGTERM)

    def stop_stream(self, sig):
        if self.child is not None and not self.reaped:
            try:
                os.killpg(self.child.pid, sig)
            except (ProcessLookupError, PermissionError, OSError):
                pass

    # -- the stream ---------------------------------------------------------------------------
    @property
    def header(self):
        """The header of the stream started last, if it wrote one."""
        return self.streams[-1]["header"] if self.streams else None

    def events(self) -> int:
        """Request lines read so far in this run, over every stream."""
        return self.holds.queued + self.holds.served

    def handle(self, line: str):
        if self.streams and self.header is None and HEADER in line:
            self.streams[-1]["header"] = line.strip()[:KEEP_WIDTH]
        event = parse_line(line)
        if event:
            self.holds.feed(self.clock(), *event)
        if not line.strip() or HEADER in line or line.startswith(COLUMNS):
            return
        self.lines_seen += 1
        if not event:
            self.others += 1
            if len(self.examples) < KEEP_OTHERS:
                self.examples.append(line.strip()[:KEEP_WIDTH])

    def read(self, wait: float) -> bool:
        """Read what the stream has, waiting at most `wait` s for the first bytes. False at its end."""
        fd = self.child.stdout.fileno()
        for _ in range(256):    # a stream that never pauses still lets the rule be asked
            try:
                ready, _, _ = select.select([fd], [], [], wait)
            except InterruptedError:
                ready = []
            if not ready:
                return True
            try:
                data = os.read(fd, 65536)
            except BlockingIOError:
                return True
            except OSError:
                data = b""
            if not data:
                for line in self.lines.end():
                    self.handle(line)
                return False
            for line in self.lines.feed(data):
                self.handle(line)
            wait = 0    # then take everything else already there, without waiting
        return True

    def start_stream(self) -> bool:
        """Start the stream at the current level. False if it could not be started."""
        level = LEVELS[self.level]
        command = stream_command(self.simulator_id, level)
        try:
            # Each later stream's messages go after the earlier ones'.
            errors = open(os.path.join(self.out, "stream-stderr.txt"), "ab" if self.streams else "wb")
        except OSError:
            errors = subprocess.DEVNULL
        try:
            self.child = subprocess.Popen(command, stdin=subprocess.DEVNULL,
                                          stdout=subprocess.PIPE, stderr=errors, start_new_session=True)
        except OSError as problem:
            self.problem = f"the log stream did not start at level {level} ({problem})"
            return False
        finally:
            if errors is not subprocess.DEVNULL:
                errors.close()
        self.reaped = False
        self.lines = Lines()
        self.streams.append({"level": level, "command": command, "header": None})
        self.stream_began = self.clock()
        self.events_at_start = self.events()
        if self.stop_at is not None:
            self.stop_stream(signal.SIGTERM)
        return True

    def step_up_due(self, now: float) -> bool:
        return step_up_now(now - self.stream_began, self.events() - self.events_at_start,
                           LEVELS[self.level], self.escalate)

    def until_step_up(self, now: float, longest: float) -> float:
        """How long the watcher may wait for the next line before it must ask step_up_due again."""
        if LEVELS[self.level] == LEVELS[-1] or self.events() > self.events_at_start:
            return longest
        return max(0.0, min(longest, self.stream_began + self.escalate - now))

    def step_up(self) -> bool:
        """Stop this stream as close() does and start one at the next level. False if none runs."""
        quiet = LEVELS[self.level]
        self.close()
        self.stream_status = None   # stopped here, not ended by itself
        self.level += 1
        self.steps.append(f"level {quiet} delivered no request line in {self.escalate:g} s; "
                          f"stepped up to {LEVELS[self.level]}")
        if self.stop_at is not None:
            return False
        return self.start_stream()

    def run(self) -> None:
        try:
            os.makedirs(self.out, exist_ok=True)
        except OSError as problem:
            self.problem = f"the output directory could not be made ({problem})"
            return
        if not self.start_stream():
            return
        alive = True
        while alive and self.stop_at is None:
            # Never more than a second, so a stop is seen soon; less when a sample or a step up
            # falls due sooner.
            now = self.clock()
            alive = self.read(min(self.holds.wait(now, 1.0), self.until_step_up(now, 1.0)))
            if self.stop_at is not None:
                break
            if alive and self.step_up_due(self.clock()):
                if not self.step_up():
                    break
                continue
            due = self.holds.due(self.clock())
            if due:
                self.take(due)
                # Take what piled up meanwhile before anything is decided again.
                alive = self.read(0) and alive

    def close(self):
        if self.child is None or self.reaped:
            return
        self.stop_stream(signal.SIGTERM)
        try:
            self.child.stdout.close()
        except OSError:
            pass
        try:
            self.stream_status = self.child.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.stop_stream(signal.SIGKILL)
            try:
                self.stream_status = self.child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
        self.reaped = True

    # -- a sample ------------------------------------------------------------------------------
    def tool(self, command):
        """Run one sample command, bounded. Return (status or a word, seconds, its messages)."""
        began = self.clock()
        try:
            process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, start_new_session=True)
        except OSError as problem:
            return f"did not start ({problem})", self.clock() - began, ""
        output = b""
        status = None
        while True:
            limit = began + self.tool_timeout
            if self.stop_at is not None:
                limit = min(limit, self.stop_at + STOP_GRACE)
            try:
                out, _ = process.communicate(timeout=max(0.05, min(0.5, limit - self.clock())))
                output += out or b""
                status = process.returncode
                break
            except subprocess.TimeoutExpired:
                if self.clock() < limit:
                    continue
            # Past its bound: ask it to stop (sudo hands the signal on), then make it.
            process.terminate()
            left = ""
            try:
                out, _ = process.communicate(timeout=self.tool_grace)
            except subprocess.TimeoutExpired:
                process.kill()
                try:
                    out, _ = process.communicate(timeout=self.tool_grace)
                except subprocess.TimeoutExpired as late:
                    # Something it started (sample, as root under sudo) outlived the kill and still
                    # holds the pipe: keep what it said, stop waiting for it, and leave it.
                    out = late.output
                    left = " (the tool was left running)"
                    try:
                        process.stdout.close()
                    except OSError:
                        pass
                    try:
                        process.wait(timeout=1)
                    except subprocess.TimeoutExpired:
                        pass
            output += out or b""
            status = "stopped after %.0f s%s" % (self.clock() - began, left)
            break
        return status, self.clock() - began, output.decode("utf-8", errors="replace")

    def take(self, due: Sample):
        self.taken += 1
        stamp = time.strftime("%H%M%S", time.gmtime())
        base = os.path.join(self.out, f"hold-{self.taken:02d}-{stamp}-pid{due.pid}")
        path = base + ".txt"
        began_wall = time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime())
        report = [
            f"pid: {due.pid}",
            f"hold: {due.hold} of this run",
            f"sample: {'first' if due.which == 1 else 'second'} of this hold",
            f"the hold had lasted: {due.lasted:.2f} s when sampling began",
            f"sampling began: {began_wall}",
        ]
        ok = False
        for command in sample_commands(due.pid, path):
            status, took, messages = self.tool(command)
            report += [f"command: {' '.join(command)}", f"the tool took: {took:.2f} s", f"exit status: {status}",
                       "its messages:", messages.rstrip() or "(none)"]
            if status == 0:
                ok = True
                break
            # A tool that had to be stopped, or a stop asked for, starts no other. A refusal
            # (sudo needs a password) or a missing program goes on to `sample` itself.
            if self.stop_at is not None or (isinstance(status, str) and status.startswith("stopped")):
                break
        if not ok:
            self.failed += 1
        self.read(0)            # what the app logged while the tool ran
        now = self.clock()
        if self.holds.holding(due.pid, due.hold):
            report.append(f"the hold was still going when the tool returned: yes, {self.holds.lasted(now):.2f} s in")
        else:
            report.append("the hold was still going when the tool returned: no")
        try:
            with open(base + ".trigger.txt", "w", encoding="utf-8") as handle:
                handle.write("\n".join(report) + "\n")
        except OSError:
            pass

    # -- the end ------------------------------------------------------------------------------
    def summary(self) -> str:
        h = self.holds
        if self.problem and self.streams:
            started = f"stopped: {self.problem}"    # an earlier stream ran; the next did not start
        elif self.problem:
            started = f"not running: {self.problem}"
        elif self.header:
            started = "the log stream started"
        else:
            started = "the log stream wrote no header"
        if self.stream_status is not None and self.stop_at is None:
            started += f" and ended by itself (status {self.stream_status})"
        level = ""
        if self.streams:
            level = (f" Level in use at the end: {self.streams[-1]['level']}"
                     + "".join(f"; {step}" for step in self.steps) + ".")
        return (f"Hold sampler (BYR-1841): {started}; {h.queued} requests to the main thread seen, "
                f"{h.served} served; {self.lines_seen} stream lines, {self.others} not understood; "
                f"{h.long_holds} holds lasted {h.hold_after:g} s or more; "
                f"{self.taken} samples taken, {self.failed} failed"
                + (f", {h.over_limit} not taken past the limit of {h.limit}" if h.over_limit else "") + "."
                + level)

    def finish(self):
        line = self.summary()
        try:
            with open(os.path.join(self.out, "summary.txt"), "w", encoding="utf-8") as handle:
                handle.write(line + "\n")
                for stream in self.streams:     # every stream started, in order
                    if stream["header"]:
                        handle.write(f"stream header: {stream['header']}\n")
                    handle.write(f"stream: {' '.join(stream['command'])}\n")
                for example in self.examples:
                    handle.write(f"line not understood: {example}\n")
        except OSError:
            pass
        say(line)


def watch(argv) -> int:
    """The `watch` command. Always returns 0."""
    args = list(argv)
    options = {"--limit": str(LIMIT), "--hold-seconds": str(HOLD_SECONDS), "--second-seconds": str(SECOND_SECONDS),
               "--tool-timeout": str(TOOL_TIMEOUT), "--tool-grace": str(TOOL_GRACE),
               "--escalate-seconds": str(ESCALATE_SECONDS)}
    plain = []
    while args:
        word = args.pop(0)
        if word in options and args:
            options[word] = args.pop(0)
        else:
            plain.append(word)
    try:
        simulator_id, out = plain
        limit = int(options["--limit"])
        # Test-only: the tests shorten the thresholds so they run in a second or two.
        hold = float(options["--hold-seconds"])
        second = float(options["--second-seconds"])
        tool_timeout = float(options["--tool-timeout"])
        tool_grace = float(options["--tool-grace"])
        escalate = float(options["--escalate-seconds"])
    except ValueError:
        say("usage: ci_hold_sampler.py watch <simulator-id> <output-dir> [--limit N]")
        say("Hold sampler (BYR-1841): not running: the command line was not understood.")
        return 0
    watcher = Watcher(simulator_id, out, limit, hold, second, tool_timeout=tool_timeout, tool_grace=tool_grace,
                      escalate=escalate)
    signal.signal(signal.SIGTERM, watcher.ask_stop)
    signal.signal(signal.SIGINT, watcher.ask_stop)
    try:
        watcher.run()
    except BaseException as problem:  # noqa: BLE001 - evidence only; it must never fail the step
        watcher.problem = watcher.problem or f"stopped by {type(problem).__name__}: {problem}"
    try:
        watcher.close()
    except BaseException:  # noqa: BLE001
        pass
    try:
        watcher.finish()
    except BaseException:  # noqa: BLE001
        pass
    return 0


def main(argv) -> int:
    if len(argv) >= 2 and argv[1] == "watch":
        return watch(argv[2:])
    say(__doc__)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except BaseException:  # noqa: BLE001
        sys.exit(0)
