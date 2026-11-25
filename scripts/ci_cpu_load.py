#!/usr/bin/env python3
"""The CPU time and load record of a UI test shard, and the table read from it (BYR-1841).

Evidence, not a test. On CI the app's main thread sometimes stops answering for many seconds the
first time Customer view opens on Estimates. A stack sample cannot tell "the app was working all
that time" from "the app was waiting for a CPU on a busy 3-core runner". This record adds what a
stack cannot: once a second, how much CPU time all the app's threads together have used so far, and
the host's load (see "How to read it" for what that can and cannot show).

    ci_cpu_load.py record <cpu-load.txt> [--interval 1.0] [--max-seconds 6000] [--ps-timeout 5]
    ci_cpu_load.py read <cpu-load.txt> [<times.tsv> ...] [--out <cpu-load-table.txt>]

`record` runs in the background for as long as scripts/ci-run-ui-tests.sh runs. The file it writes
is tab-separated, one line per fact, each but `p` lines starting with the UTC time:
    start     format version, interval, the exact ps command, the recorder's pid
    ncpu      os.cpu_count(), then the raw output of `sysctl -n hw.ncpu hw.physicalcpu hw.logicalcpu`
    loadraw   the raw output of `sysctl -n vm.loadavg` (at the start and at the stop)
    sample    sequence number; the 1, 5 and 15 minute load averages; how long ps took; how many
              lines it printed and how many of those did not parse; `busy`, the CPU seconds every
              process together used since the previous sample (a lower bound). `ps failed` when ps
              did not answer: the load is still there, the process times are not.
    p         one raw line of `ps -Ao pid=,time=,ucomm=` for a process of interest (the app, the UI
              test runner, xcodebuild and the simulator services that compete for CPU), belonging
              to the sample above it: pid, accumulated CPU time (user + system), short name
    ident     (format 2) one raw line of `ps -o pid=,ppid=,user=,ucomm= -p <pid> ...` for a
              diagnosticd, apsd, logd or launchd_sim pid first seen under that name: its parent
              tells whether it runs on the host (parent 1) or in the simulator (parent launchd_sim)
    identcall (format 2) one per such call: how many pids it asked for, rows, ms, exit or timeout
    top       every 60 samples, the names that used the most CPU in them, with seconds: 8 names in
              format 1, 20 in format 2, which also leaves the recorder's own pid out
    note      something that went wrong (ps timed out or failed)
    stop      samples, missed ticks, the CPU the recorder and its children (ps, sysctl) used,
              wall time, and why it stopped
`ucomm` is the kernel's short process name (at most 16 characters). Neither command line nor
environment is ever read or written: ps is not asked for `command`, `args`, `comm` or `-E`, and it
runs with an environment of PATH and LC_ALL only.

Format 2 (BYR-1896) differs from format 1 only in the names kept in `p` lines, the `ident` lines
and the longer `top` lines; `read` reads both.

`read` takes the record and the step times `ci_cancelled_taps.py stamp` wrote (test-times.tsv and
any rerun-N-times.tsv) and prints, for every test step of 10 s or more, and separately for every
first screen read after a tap on "job-money-customer-view", how much CPU the app's process used
during it, as a share of the step's length. It always exits 0. Right after its "Record:" line it prints a budget
block (BYR-1896): the record's busy CPU split into named groups, for the whole record and for its first
nine top lines, each group from `p` lines where the record has them and from the 8 busiest names of each
`top` line, with a side (host or simulator) for each diagnosticd and apsd pid from the `ident` lines,
the shard's treatment from treatment.txt beside the record, and one `BUDGET 2 key=value ...` line.

How to read it. The app's CPU time is that of all its threads together, so the share can be over
100%, and 70% of one CPU can be two threads at 35% each. A share of 70% or more ("working") says
that the app's threads together used at least 0.7 s of CPU per second of the step; it does not say
which threads ran, nor that the main thread was one of them. A share of 30% or less ("waiting")
says that they used at most 0.3 s of CPU per second of the step, so for most of the step no thread
of the app was running: each was waiting for a CPU or blocked (on a reply from the test runner or
backboardd, a lock, I/O or a sleep). The "host busy" and "load 1m" columns say whether the runner's
CPUs were busy then, and only a low share with a high "host busy" points to a CPU shortage.
A step in which the app's process did not exist for part of the time (launched or ended inside it)
is named and not judged.

How the number is made. The CPU time is interpolated linearly between the samples on either side of
the step's start and of its end; the range beside it runs from the growth between the samples inside
the step to the growth between the samples just outside it. Samples are about 1 s apart, which is why
steps under 10 s are listed but not judged.
"""
import bisect
import calendar
import os
import re
import signal
import subprocess
import sys
import time

# A first cut, to be revised once a run has been read: the share of one CPU the app used over a step.
WORKING_SHARE = 0.70   # at least this: the app's threads together used 0.7 s of CPU per second of the step
WAITING_SHARE = 0.30   # at most this: for most of the step no thread of the app was running
LONG_STEP = 10.0       # seconds; shorter steps are within the 1 s sampling error and are not judged
ABSENT_LIMIT = 2.5     # sample intervals without an app process inside a step before it is not judged
PARTIAL = "not judged: app not running all step"

PS = ["ps", "-Ao", "pid=,time=,ucomm="]
APP = "Thorbis"
RUNNER_PREFIX = "ThorbisUITests"
# Format 1 kept these names. Format 2 (BYR-1896) adds the system services the first eight records
# named in their top lines, so their CPU is exact too. Each is the kernel's short name (at most 16
# characters): "BackgroundShortc" stands for every name that starts so, and trustd, spindump,
# mobileassetd and storagekitd run both on the host and in the simulator under one name.
FORMAT1_NAMES = ("Thorbis", "xcodebuild", "backboardd", "SpringBoard", "testmanagerd", "diagnosticd", "logd", "log")
OF_INTEREST = set(FORMAT1_NAMES) | {
    "apsd", "mds", "mds_stores", "mdworker_shared", "searchd", "corespotlightd", "SimRenderServer", "SimMetalHost",
    "spindump", "launchd_sim", "trustd", "diskimagesiod", "storagekitd", "mobileassetd", "ThorbisWidgets",
    "PosterBoard", "amsengagementd", "BackgroundShortc"}
INTEREST_PREFIXES = (RUNNER_PREFIX, "provjobd")
# Which side a daemon runs on, host or simulator, is told by its parent: one ps call per new
# (pid, name) of these four names only, so the number of calls does not follow a treatment.
IDENT_NAMES = ("diagnosticd", "apsd", "logd", "launchd_sim")
IDENT_PS = ["ps", "-o", "pid=,ppid=,user=,ucomm="]
IDENT_TIMEOUT = 2.0
IDENT_TRIES = 3
IDENT_MAX = 50
TOP_NAMES = 20
DOOR_TAP = 'Tap "job-money-customer-view" Button'
FORMAT = "ci_cpu_load 2"
MAX_NOTES = 50

CPU_MINUTES = re.compile(r"^(\d+):([0-5]\d)(?:\.(\d{1,2}))?$")                  # macOS: M:SS.cc
CPU_HOURS = re.compile(r"^(?:(\d+)-)?(\d+):([0-5]\d):([0-5]\d)(?:\.(\d+))?$")   # [D-]H:MM:SS[.ff]
PS_LINE = re.compile(r"^\s*(\d+)\s+(\S+)\s+(.*?)\s*$")
IDENT_LINE = re.compile(r"^\s*(\d+)\s+(\d+)\s+(\S+)\s+(.*?)\s*$")
ISO = re.compile(r"^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)\.(\d{3})Z$")
RERUN_FILE = re.compile(r"^(rerun-\d+)-times\.tsv$")


def parse_cpu_time(text):
    """Seconds of CPU from ps's `time` column, or None. macOS prints `123:45.67` (minutes past 60);
    other ps builds print `01:02:03`, `1:02:03.50` or `2-03:04:05`."""
    text = text.strip()
    match = CPU_MINUTES.match(text)
    if match:
        minutes, seconds, hundredths = match.groups()
        return int(minutes) * 60 + int(seconds) + (int(hundredths.ljust(2, "0")) / 100 if hundredths else 0.0)
    match = CPU_HOURS.match(text)
    if match:
        days, hours, minutes, seconds, fraction = match.groups()
        return ((int(days or 0) * 24 + int(hours)) * 60 + int(minutes)) * 60 + int(seconds) + \
            (float("0." + fraction) if fraction else 0.0)
    return None


def parse_ps_line(line):
    """(pid, cpu seconds, name) from one line of `ps -Ao pid=,time=,ucomm=`, or None."""
    match = PS_LINE.match(line)
    if not match:
        return None
    seconds = parse_cpu_time(match.group(2))
    name = match.group(3)
    if seconds is None or not name:
        return None
    if name.startswith("(") and name.endswith(")"):
        name = name[1:-1]
    return int(match.group(1)), seconds, name


def of_interest(name):
    return name in OF_INTEREST or name.startswith(INTEREST_PREFIXES)


def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%03dZ" % int(t % 1 * 1000)


def clean(text):
    """One line, no tabs or control characters."""
    return "".join(ch if ch >= " " and ch != "\x7f" else "?" for ch in text.strip().replace("\n", " | "))


# ----------------------------------------------------------------------------------------------
# record

class _Stop(Exception):
    pass


def record(path, interval=1.0, max_seconds=6000.0, ps_timeout=5.0):
    """Write the record until a signal, the parent's end or max_seconds. Always returns 0."""
    def on_signal(signum, frame):
        raise _Stop("signal")

    for which in (signal.SIGTERM, signal.SIGINT):
        try:
            signal.signal(which, on_signal)
        except (OSError, ValueError):
            pass
    try:
        os.nice(10)
    except (OSError, AttributeError):
        pass
    try:
        out = open(path, "w", encoding="utf-8")
    except OSError:
        return 0
    env = {"PATH": os.environ.get("PATH") or "/bin:/usr/sbin:/usr/bin", "LC_ALL": "C"}
    state = {"notes": 0}

    def write(kind, *fields, at=None):
        try:
            out.write("\t".join((iso(time.time() if at is None else at), kind) + fields) + "\n")
            out.flush()
        except (OSError, ValueError):
            raise _Stop("cannot write")

    def note(text):
        state["notes"] += 1
        if state["notes"] <= MAX_NOTES:
            write("note", clean(text)[:200])
        elif state["notes"] == MAX_NOTES + 1:
            write("note", f"more than {MAX_NOTES} notes; the rest are not written")

    def run(args, timeout):
        return subprocess.run(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              env=env, timeout=timeout)

    def raw_sysctl(args, timeout):
        try:
            result = run(["sysctl"] + args, timeout)
        except subprocess.TimeoutExpired:
            return f"sysctl did not finish in {timeout:g} s"
        except OSError as error:
            return f"sysctl could not start ({type(error).__name__})"
        if result.returncode != 0:
            return f"sysctl failed {result.returncode}"
        return clean(result.stdout.decode("utf-8", "replace"))[:200]

    def ident(wanted):
        """Ask ps for the parent and user of each new (pid, name) of IDENT_NAMES. A pair counts as
        asked once a call that finished has answered; a call that timed out or failed is tried
        again with the next sample, at most IDENT_TRIES times per pair."""
        args = list(IDENT_PS)
        for pid, _ in wanted:
            args += ["-p", str(pid)]
        pids = {pid for pid, _ in wanted}
        started = time.monotonic()
        rows = 0
        try:
            result = run(args, IDENT_TIMEOUT)
        except subprocess.TimeoutExpired:
            outcome = "timeout"
            note(f"ident ps did not finish in {IDENT_TIMEOUT:g} s; {len(wanted)} pids not identified this time")
        except OSError as error:
            outcome = "could not start"
            note(f"ident ps could not start ({type(error).__name__})")
        else:
            outcome = f"exit {result.returncode}"
            for line in result.stdout.decode("utf-8", "replace").splitlines():
                match = IDENT_LINE.match(line)
                if match and int(match.group(1)) in pids:
                    rows += 1
                    write("ident", clean(line.rstrip()))
            if result.returncode != 0 and rows == 0:
                note(f"ident ps exited {result.returncode}: " + clean(result.stderr.decode("utf-8", "replace"))[:120])
            else:
                for key in wanted:      # a pid ps did not list has ended; asking again tells nothing new
                    state["identified"].add(key)
        for key in wanted:
            if key not in state["identified"]:
                state["tries"][key] = state["tries"].get(key, 0) + 1
        write("identcall", f"pids {len(wanted)}", f"rows {rows}", f"ms {(time.monotonic() - started) * 1000:.0f}",
              outcome)

    state["identified"] = set()
    state["tries"] = {}
    own_pid = os.getpid()
    began = time.monotonic()
    parent = os.getppid()
    why = "error"
    samples = missed = tick = 0
    previous = None
    top = {}
    try:
        write("start", FORMAT, f"interval {interval:g}", " ".join(PS), f"pid {os.getpid()}")
        ncpu = raw_sysctl(["-n", "hw.ncpu", "hw.physicalcpu", "hw.logicalcpu"], ps_timeout)
        write("ncpu", str(os.cpu_count() or 0), ncpu if ncpu.startswith("sysctl") else "sysctl " + ncpu)
        write("loadraw", raw_sysctl(["-n", "vm.loadavg"], ps_timeout))
        while True:
            if time.monotonic() - began >= max_seconds:
                why = "time limit"
                break
            if os.getppid() != parent:
                why = "parent gone"
                break
            samples += 1
            wall_before, mono_before = time.time(), time.monotonic()
            lines = None
            try:
                result = run(PS, ps_timeout)
            except subprocess.TimeoutExpired:
                note(f"ps did not finish in {ps_timeout:g} s; sample {samples} has no process times")
            except OSError as error:
                note(f"ps could not start ({type(error).__name__})")
            else:
                if result.returncode != 0:
                    note(f"ps exited {result.returncode}: " + clean(result.stderr.decode("utf-8", "replace"))[:120])
                lines = result.stdout.decode("utf-8", "replace").splitlines()
            took = (time.monotonic() - mono_before) * 1000
            at = (wall_before + time.time()) / 2
            try:
                load = "load %.2f %.2f %.2f" % os.getloadavg()
            except OSError:
                load = "load - - -"
            parsed, unread, kept = {}, 0, []
            for line in lines or ():
                fact = parse_ps_line(line)
                if fact is None:
                    unread += 1
                    continue
                parsed[fact[0]] = fact
                if of_interest(fact[2]):
                    kept.append("p\t" + clean(line.rstrip()))
            if not parsed:
                write("sample", str(samples), load, "ps failed", f"lines {len(lines or ())}", f"unread {unread}",
                      "busy -", at=at)
            else:
                busy = 0.0
                if previous is not None:
                    for pid, (_, seconds, name) in parsed.items():
                        before = previous.get(pid)
                        grew = seconds - before if before is not None and seconds >= before else seconds
                        busy += grew
                        if pid != own_pid:
                            top[name] = top.get(name, 0.0) + grew
                previous = {pid: seconds for pid, (_, seconds, _) in parsed.items()}
                write("sample", str(samples), load, f"ps {took:.0f} ms", f"lines {len(lines)}", f"unread {unread}",
                      f"busy {busy:.2f}", at=at)
                try:
                    out.write("".join(line + "\n" for line in kept))
                    out.flush()
                except (OSError, ValueError):
                    raise _Stop("cannot write")
                wanted = sorted({(pid, name) for pid, (_, _, name) in parsed.items()
                                 if name in IDENT_NAMES and (pid, name) not in state["identified"]
                                 and state["tries"].get((pid, name), 0) < IDENT_TRIES})[:IDENT_MAX]
                if wanted:
                    ident(wanted)
            if samples % 60 == 0 and top:
                busiest = sorted(top.items(), key=lambda item: -item[1])[:TOP_NAMES]
                write("top", *(f"{clean(name)} {seconds:.2f}" for name, seconds in busiest))
                top = {}
            # A schedule kept from the start: a tick that comes while the last one still runs is skipped.
            due = int((time.monotonic() - began) / interval) + 1
            missed += max(0, due - tick - 1)
            tick = due
            time.sleep(max(0.0, min(began + tick * interval, began + max_seconds) - time.monotonic()))
    except _Stop as stop:
        why = str(stop)
    except Exception as error:      # never a stack trace, never a failure
        why = f"error {type(error).__name__}"
    for which in (signal.SIGTERM, signal.SIGINT):
        try:
            signal.signal(which, signal.SIG_IGN)
        except (OSError, ValueError):
            pass
    try:
        if why != "cannot write":
            write("loadraw", raw_sysctl(["-n", "vm.loadavg"], 1.0))
            own = cost(0)
            children = cost(1)
            write("stop", f"samples {samples}", f"missed {missed}", f"recorder cpu {own:.2f}", f"ps cpu {children:.2f}",
                  f"wall {time.monotonic() - began:.1f}", f"why {why}")
    except Exception:
        pass
    try:
        out.close()
    except Exception:
        pass
    return 0


def cost(children):
    try:
        import resource
        usage = resource.getrusage(resource.RUSAGE_CHILDREN if children else resource.RUSAGE_SELF)
        return usage.ru_utime + usage.ru_stime
    except Exception:
        return 0.0


# ----------------------------------------------------------------------------------------------
# read

class Sample:
    def __init__(self, t, load1, valid, unread, busy):
        self.t, self.load1, self.valid, self.unread, self.busy = t, load1, valid, unread, busy
        self.procs = {}         # pid -> (cpu seconds, name)


class Record:
    def __init__(self):
        self.samples = []
        self.interval = 1.0
        self.ncpu = None
        self.unread = 0
        self.stop = {}
        self.format = None          # "1", "2" or None when the start line does not say
        self.recorder_pid = None
        self.tops = []              # (time, [(name, cpu seconds)]) in the order written
        self.idents = []            # (time, pid, ppid, user, name)
        self.ident_calls = []       # (time, pids, rows, ms, outcome)

    def valid(self):
        return [sample for sample in self.samples if sample.valid]


def iso_seconds(text):
    match = ISO.match(text)
    if not match:
        return None
    parts = [int(part) for part in match.groups()]
    try:
        return calendar.timegm((parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], 0, 0, 0)) + parts[6] / 1000
    except (ValueError, OverflowError):
        return None


def _number(text):
    try:
        value = float(text)
    except (TypeError, ValueError):
        return None
    return value if value == value and abs(value) != float("inf") else None


def field(fields, word):
    """The rest of the field that starts with `word `, e.g. field(["missed 3"], "missed") is "3"."""
    for item in fields:
        if item.startswith(word + " "):
            return item[len(word) + 1:]
    return None


def read_record(path):
    rec = Record()
    current = None
    try:
        handle = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return rec
    with handle:
        for line in handle:
            line = line.rstrip("\n")
            if line.startswith("p\t"):
                fact = parse_ps_line(line[2:])
                if current is None or fact is None:
                    rec.unread += 1
                    continue
                current.procs[fact[0]] = (fact[1], fact[2])
                continue
            fields = line.split("\t")
            at = iso_seconds(fields[0]) if len(fields) >= 2 else None
            if at is None:
                rec.unread += 1
                current = None
                continue
            kind, rest = fields[1], fields[2:]
            try:
                if kind == "sample":
                    loads = field(rest, "load").split()
                    valid = field(rest, "ps") not in (None, "failed")
                    busy = field(rest, "busy")
                    current = Sample(at, float(loads[0]), valid, int(field(rest, "unread") or 0),
                                     float(busy) if valid and busy not in (None, "-") else None)
                    current.ps_ms = _number((field(rest, "ps") or "").split(" ")[0]) if valid else None
                    rec.samples.append(current)
                elif kind == "start":
                    current = None
                    if rest and rest[0].startswith("ci_cpu_load "):
                        rec.format = rest[0].split(" ", 1)[1]
                    pid = field(rest, "pid")
                    rec.recorder_pid = int(pid) if pid and pid.isdigit() else None
                    interval = field(rest, "interval")
                    if interval:
                        rec.interval = float(interval)
                elif kind == "ncpu":
                    current = None
                    rec.ncpu = int(rest[0]) or None
                elif kind == "stop":
                    current = None
                    for item in rest:
                        word, _, value = item.rpartition(" ")
                        rec.stop[word] = value
                elif kind == "top":
                    current = None
                    items = []
                    for item in rest:       # a top line never counts as unread, as in format 1
                        name, _, seconds = item.rpartition(" ")
                        value = _number(seconds)
                        if name and value is not None:
                            items.append((name, value))
                    rec.tops.append((at, items))
                elif kind == "ident":
                    current = None
                    match = IDENT_LINE.match(rest[0]) if len(rest) == 1 else None
                    if not match:
                        raise ValueError("ident")
                    rec.idents.append((at, int(match.group(1)), int(match.group(2)), match.group(3), match.group(4)))
                elif kind == "identcall":
                    current = None
                    rec.ident_calls.append((at, field(rest, "pids"), field(rest, "rows"), field(rest, "ms"),
                                            rest[-1] if rest else "?"))
                elif kind in ("loadraw", "note"):
                    current = None
                else:
                    raise ValueError(kind)
            except (ValueError, IndexError, AttributeError, TypeError):
                rec.unread += 1
                current = None
    rec.samples.sort(key=lambda sample: sample.t)
    return rec


class Step:
    def __init__(self, test, run, t, text, start, length, after_door):
        self.test, self.run, self.t, self.text = test, run, t, text
        self.start, self.length, self.after_door = start, length, after_door


def run_label(path):
    name = os.path.basename(path)
    if name == "test-times.tsv":
        return "first"
    match = RERUN_FILE.match(name)
    return match.group(1) if match else name


def read_steps(paths):
    """Every stamped step with its start (host clock) and length (XCTest's clock)."""
    steps = []
    for path in paths:
        label = run_label(path)
        try:
            handle = open(path, encoding="utf-8", errors="replace")
        except OSError:
            continue
        rows = []
        with handle:
            for line in handle:
                parts = line.rstrip("\n").split("\t")
                if len(parts) != 3:
                    continue
                try:
                    rows.append((float(parts[0]), parts[1], parts[2]))
                except ValueError:
                    continue
        test, stamped, offsets, ended = None, [], [], None

        def finish():
            if test is None or not stamped:
                return
            anchor = min(offsets)
            for index, (t, text) in enumerate(stamped):
                if index + 1 < len(stamped):
                    end = anchor + stamped[index + 1][0]
                elif ended is not None:
                    end = ended
                else:
                    continue
                after = index > 0 and stamped[index - 1][1].startswith(DOOR_TAP)
                steps.append(Step(test, label, t, text, anchor + t, end - (anchor + t), after))

        for at, kind, value in rows:
            if kind == "started":
                finish()
                test, stamped, offsets, ended = value, [], [], None
            elif test is None:
                continue
            elif kind == "begin":
                offsets.append(at)
            elif kind == "step":
                head, _, text = value.partition(" ")
                try:
                    t = float(head)
                except ValueError:
                    continue
                stamped.append((t, text))
                offsets.append(at - t)
            elif kind in ("passed", "failed", "skipped") and value.split(" ", 1)[0] == test:
                ended = at
                finish()
                test, stamped, offsets, ended = None, [], [], None
        finish()
    return steps


class Row:
    def __init__(self, step):
        self.step = step
        self.app_pids = []
        self.app_cpu = self.app_low = self.app_high = self.app_share = None
        self.runner_cpu = self.runner_share = None
        self.load = self.host_busy = None
        self.busiest = None
        self.verdict = "-"
        self.note = ""
        self.absent = None      # seconds of the step with no app process listed (None: not measured)


def _prepare(rec):
    """The valid samples, their times, and each pid's (times, cpu) points, computed once per record.
    A pid that appears after the first valid sample starts from zero at the sample before it."""
    if getattr(rec, "_prepared", None) is None:
        valid = rec.valid()
        series = {}
        for index, sample in enumerate(valid):
            for pid, (seconds, name) in sample.procs.items():
                entry = series.get(pid)
                if entry is None:
                    entry = series[pid] = ([], [], name, [])
                    if index > 0:
                        entry[0].append(valid[index - 1].t)
                        entry[1].append(0.0)
                entry[0].append(sample.t)
                entry[1].append(seconds)
                entry[3].append(index)
        rec._prepared = (valid, [sample.t for sample in valid], series)
    return rec._prepared


def _at(times, values, t):
    if t <= times[0]:
        return values[0]
    if t >= times[-1]:
        return values[-1]
    i = bisect.bisect_right(times, t)
    t0, t1, c0, c1 = times[i - 1], times[i], values[i - 1], values[i]
    return c0 if t1 == t0 else c0 + (c1 - c0) * (t - t0) / (t1 - t0)


def measure(rec, step):
    row = Row(step)
    start, end = step.start, step.start + step.length
    everything = rec.samples
    if getattr(rec, "_all_times", None) is None:
        rec._all_times = [sample.t for sample in everything]
    inside = everything[bisect.bisect_left(rec._all_times, start):bisect.bisect_right(rec._all_times, end)]
    if inside:
        row.load = sum(sample.load1 for sample in inside) / len(inside)
    elif everything:
        row.load = min(everything, key=lambda sample: abs(sample.t - start)).load1
    valid, times, series = _prepare(rec)
    first = bisect.bisect_right(times, start) - 1          # last valid sample at or before the start
    last = bisect.bisect_left(times, end)                  # first valid sample at or after the end
    if first < 0 or last >= len(times):
        row.verdict = "not measured: outside the record"
        return row
    lo_start = bisect.bisect_left(times, start)            # first at or after the start
    hi_end = bisect.bisect_right(times, end) - 1           # last at or before the end
    gaps = [b - a for a, b in zip(times[first:last], times[first + 1:last + 1])]
    notes = []
    if gaps and max(gaps) > 1.5 * rec.interval:
        notes.append(f"gap {max(gaps):.1f} s")

    by_name = {}
    for pid, (ptimes, values, name, present) in series.items():
        # Only a pid listed in a sample from the one before the start to the one after the end.
        j = bisect.bisect_left(present, first)
        if j >= len(present) or present[j] > last:
            continue
        used = _at(ptimes, values, end) - _at(ptimes, values, start)
        low = max(0.0, _at(ptimes, values, times[hi_end]) - _at(ptimes, values, times[lo_start])) \
            if hi_end >= lo_start else 0.0
        high = _at(ptimes, values, times[last]) - _at(ptimes, values, times[first])
        by_name.setdefault(name, []).append((pid, max(0.0, used), low, max(0.0, high)))

    def total(entries):
        return (sum(entry[1] for entry in entries), sum(entry[2] for entry in entries), sum(entry[3] for entry in entries))

    app = by_name.get(APP, [])
    runner = [entry for name, entries in by_name.items() if name.startswith(RUNNER_PREFIX) for entry in entries]
    if runner:
        row.runner_cpu = total(runner)[0]
        row.runner_share = row.runner_cpu / step.length if step.length > 0 else None
    others = {name: total(entries)[0] for name, entries in by_name.items()
              if name != APP and not name.startswith(RUNNER_PREFIX)}
    if others:
        name = max(others, key=others.get)
        row.busiest = (name, others[name])
    if rec.ncpu and hi_end > lo_start:
        span = times[hi_end] - times[lo_start]
        busy = [valid[index].busy for index in range(lo_start + 1, hi_end + 1)]
        if span > 0 and None not in busy:
            row.host_busy = sum(busy) / span / rec.ncpu
    if not app:
        row.absent = step.length
        row.verdict = "not measured: no app process"
        row.note = "; ".join(notes)
        return row
    app.sort(key=lambda entry: -entry[1])
    row.app_pids = [entry[0] for entry in app]
    if len(app) > 1:
        notes.insert(0, "pid changed")
    row.app_cpu, row.app_low, row.app_high = total(app)
    row.app_share = row.app_cpu / step.length if step.length > 0 else None
    # The time inside the step between two samples of which one lists no app process: the app was
    # launched, ended or between two launches then. A pid handed over between two samples is not.
    listed = [any(name == APP for _, name in valid[index].procs.values()) for index in range(first, last + 1)]
    absent, at_start, at_end = 0.0, False, False
    for k in range(last - first):
        if listed[k] and listed[k + 1]:
            continue
        a, b = max(times[first + k], start), min(times[first + k + 1], end)
        if b > a:
            absent += b - a
            at_start = at_start or k == 0
            at_end = at_end or k == last - first - 1
    row.absent = absent
    partial = absent > ABSENT_LIMIT * rec.interval
    if partial:
        where = [words for flag, words in ((at_start, "app started inside it"), (at_end, "app ended inside it")) if flag]
        text = f"no app process for {absent:.1f} s of the step" + (" (" + ", ".join(where) + ")" if where else "")
        ran = step.length - absent
        if ran > 0:
            text += f"; {row.app_cpu / ran * 100:.0f}% of a CPU while it ran"
        notes.append(text)
    row.note = "; ".join(notes)
    if step.length < LONG_STEP or row.app_share is None:
        row.verdict = "-"
    elif partial:
        row.verdict = PARTIAL
    elif row.app_share >= WORKING_SHARE:
        row.verdict = "working"
    elif row.app_share <= WAITING_SHARE:
        row.verdict = "waiting"
    else:
        row.verdict = "in between"
    return row


def _clock(t):
    return time.strftime("%H:%M:%S", time.gmtime(t)) + ".%03d" % int(round(t % 1 * 1000) % 1000)


def _cells(row):
    def seconds(value):
        return "-" if value is None else f"{value:.2f}s"

    def share(value):
        return "-" if value is None else f"{value * 100:.0f}%"

    pids = ",".join(str(pid) for pid in row.app_pids) or "-"
    if len(row.app_pids) > 1:
        pids += " pid changed"
    app_cpu = "-" if row.app_cpu is None else f"{row.app_cpu:.2f}s ({row.app_low:.2f}-{row.app_high:.2f})"
    gap = "; ".join(part for part in row.note.split("; ") if part and part != "pid changed") or "-"
    return [_clock(row.step.start), f"{row.step.length:.2f}s", pids, app_cpu, share(row.app_share),
            seconds(row.runner_cpu), share(row.runner_share), "-" if row.load is None else f"{row.load:.1f}",
            share(row.host_busy), "-" if row.busiest is None else f"{row.busiest[0]} {row.busiest[1]:.1f}s",
            row.verdict, gap, f"t={row.step.t:.2f} {row.step.text}"]


HEAD = ["start UTC", "length", "app pid", "app CPU (range)", "app", "runner CPU", "runner", "load 1m", "host busy",
        "busiest other", "verdict", "note", "step"]


def _section(title, rows):
    lines = [title]
    if not rows:
        return lines + ["  none"]
    groups = []
    for row in rows:
        key = (row.step.test, row.step.run)
        if not groups or groups[-1][0] != key:
            groups.append((key, []))
        groups[-1][1].append(_cells(row))
    widths = [max(len(HEAD[i]), *(len(cells[i]) for _, group in groups for cells in group)) for i in range(len(HEAD) - 1)]

    def join(cells):
        return "  " + "  ".join(cell.ljust(widths[i]) for i, cell in enumerate(cells[:-1])) + "  " + cells[-1]

    for (test, run), group in groups:
        lines.append(f"{test.split('/', 1)[-1]} ({run})")
        lines.append(join(HEAD))
        lines.extend(join(cells) for cells in group)
    return lines


def _counts(rows, judged_only):
    def count(test):
        return sum(1 for row in rows if test(row.verdict))
    working = count(lambda v: v == "working")
    waiting = count(lambda v: v == "waiting")
    between = count(lambda v: v == "in between")
    unmeasured = count(lambda v: v.startswith("not measured"))
    partial = count(lambda v: v == PARTIAL)
    text = f"working {working}, waiting {waiting}, in between {between}"
    if not judged_only:
        text += f", not judged (under {LONG_STEP:g} s) {count(lambda v: v == '-')}"
    text += f", not measured {unmeasured}"
    if partial:
        text += f", not judged (app not running all step) {partial}"
    return text + "."


# ----------------------------------------------------------------------------------------------
# budget (BYR-1896): the record's busy CPU split into named groups, for the runner load experiment

BUDGET_GROUPS = (
    ("app", (APP,)), ("runner", None), ("xcodebuild", ("xcodebuild",)), ("diagnosticd", ("diagnosticd",)),
    ("apsd", ("apsd",)), ("spotlight", ("mds", "mds_stores", "mdworker_shared")),
    ("simsearch", ("searchd", "corespotlightd")), ("springboard", ("SpringBoard", "backboardd")),
    ("render", ("SimRenderServer", "SimMetalHost")), ("spindump", ("spindump",)),
    ("logs", ("logd", "log", "testmanagerd")), ("launchd_sim", ("launchd_sim",)))
SIDED = ("diagnosticd", "apsd")
SIDES = ("host", "sim", "unknown")
TREATMENT = re.compile(r"^LOAD EXPERIMENT (\S+) (\S+) (\S+?):? (.*)$")
OPEN_STEP = "Open com.thorbis.field"
# The recorder's own children: their CPU is in the stop line's "ps cpu", so a top line naming them
# must not take it off `rest` a second time.
RECORDER_CHILDREN = ("ps", "sysctl")


def _group_of(name):
    if name.startswith(RUNNER_PREFIX):
        return "runner"
    for group, members in BUDGET_GROUPS:
        if members and name in members:
            return group
    return "other"


def _percentile(values, q):
    """Nearest rank; q in 0..100."""
    ordered = sorted(values)
    if not ordered:
        return None
    return ordered[max(0, min(len(ordered) - 1, int(-(-q * len(ordered) // 100)) - 1))]


def _account(valid):
    """CPU growth per p line, as (time, name, pid, seconds). The same pid under the same name with a
    value not lower counts its growth; a pid first seen after the first valid sample, or seen again
    under another name or lower, is a new process and its whole value counts. Also the births per name."""
    last, events, born = {}, [], {}
    for index, sample in enumerate(valid):
        for pid, (seconds, name) in sample.procs.items():
            old = last.get(pid)
            last[pid] = (seconds, name)
            if index == 0:
                continue
            if old is not None and old[1] == name and seconds >= old[0]:
                grew = seconds - old[0]
            else:
                born[name] = born.get(name, 0) + 1
                grew = seconds
            events.append((sample.t, name, pid, grew))
    return events, born, {name for _, (_, name) in valid[0].procs.items()} if valid else set()


def _sides(rec, valid):
    """(pid, name) -> [(time, side, ppid, user)] from the ident rows; launchd_sim pids from both."""
    sim_parents = {pid for _, pid, _, _, name in rec.idents if name == "launchd_sim"}
    for sample in valid:
        sim_parents.update(pid for pid, (_, name) in sample.procs.items() if name == "launchd_sim")
    table = {}
    for at, pid, ppid, user, name in rec.idents:
        side = "sim" if ppid in sim_parents else "host" if ppid == 1 else "unknown"
        table.setdefault((pid, name), []).append((at, side, ppid, user))
    return table


def _side_at(table, pid, name, t):
    rows = table.get((pid, name))
    if not rows:
        return ("unknown", None, None)
    before = [row for row in rows if row[0] <= t]
    row = before[-1] if before else rows[0]
    return row[1:]


def read_treatment(path):
    """(shard, plan word, applied, lines) from the experiment's treatment.txt, or Nones."""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = [clean(line)[:200] for line in handle if line.strip()]
    except OSError:
        return None, None, None, []
    shard = plan = applied = None
    started = False
    for line in lines:
        match = TREATMENT.match(line)
        if not match:
            continue
        shard = shard or match.group(1)
        phase, word, rest = match.group(2), match.group(3), match.group(4)
        if phase == "plan":
            plan = word if word != "unknown" else "unknown"
            if word == "none":
                applied = "-"
            continue
        plan = plan if plan not in (None, "none") else word
        if rest.startswith("started"):
            started = True
        elif rest.startswith("applied ") and phase == "sim":
            verdict = rest[len("applied "):].split(" (", 1)[0].strip()
            applied = {"yes": "yes", "no": "no"}.get(verdict, "not_known")
            started = False
    if plan not in (None, "none", "unknown") and (applied is None or started):
        applied = "not_known"
    return shard, plan, applied, lines


def budget(rec, record_path, long_rows, times_paths=None):
    """The budget block's lines. Never raises: a fault is one line saying so. With no step times
    (times_paths empty) the Open figures are not measured, which is not the same as none."""
    try:
        return _budget(rec, record_path, long_rows, times_paths)
    except Exception as error:      # evidence only: the table above and below must still come out
        return [f"budget: could not be read ({type(error).__name__})"]


def _budget(rec, record_path, long_rows, times_paths=None):
    shard, plan, applied, treatment = read_treatment(os.path.join(os.path.dirname(record_path) or ".", "treatment.txt"))
    lines = ["Budget (BYR-1896). Share = CPU s / (window s x CPUs). p = from p lines: exact for a process that lives "
             "between samples, a lower bound for one that ends or is born and gone between them. top8 = lower bound "
             "from the 8 busiest names of each top line. diag is the total of diag_host, diag_sim and diag_unknown; "
             "apsd (p) and apsd_top8 are two kinds of figure. Names are 16-character short names.",
             f"budget format {rec.format or '?'} shard {shard or '-'}"]
    lines += [f"budget treatment {line}" for line in treatment[:10]] or ["budget treatment none written"]
    samples, valid, n = rec.samples, rec.valid(), rec.ncpu
    if not samples or len(valid) < 2 or not n:
        lines.append("budget record: too few samples or no CPU count, so no budget")
        return lines
    t0, tend = samples[0].t, samples[-1].t
    span = tend - t0
    wall = _number(rec.stop.get("wall"))
    missed = _number(rec.stop.get("missed"))
    ps = [sample.ps_ms for sample in valid if getattr(sample, "ps_ms", None) is not None]
    missed_pct = None if wall in (None, 0) or missed is None else missed / wall * 100
    lines.append("budget record wall %s s samples %d missed %s (%s%%) ps median %s ms p90 %s ms" % (
        "-" if wall is None else f"{wall:.1f}", len(samples), "-" if missed is None else f"{missed:.0f}",
        "-" if missed_pct is None else f"{missed_pct:.1f}",
        "-" if not ps else f"{_percentile(ps, 50):.0f}", "-" if not ps else f"{_percentile(ps, 90):.0f}"))
    events, born, first_names = _account(valid)
    pnames = {event[1] for event in events} | first_names
    table = _sides(rec, valid)
    recorder_cpu = (_number(rec.stop.get("recorder cpu")) or 0.0) + (_number(rec.stop.get("ps cpu")) or 0.0)
    has_stop = "recorder cpu" in rec.stop
    windows = [("whole", tend + 1)]
    # The first nine top lines, or the whole record when it has fewer.
    windows.append(("early", rec.tops[8][0] if len(rec.tops) >= 9 else tend + 1))
    # Format 2 names every OF_INTEREST process in its p lines, so a group none of whose names was ever
    # seen there is a measured 0; format 1 did not look for most of them ("-", not measured).
    measured_all = rec.format == "2"
    ident_names = {name for _, _, _, _, name in rec.idents}
    figures = {}
    for label, hi in windows:
        secs = min(hi, tend) - t0
        pairs = [(b.busy, b.t - a.t) for a, b in zip(valid, valid[1:]) if t0 <= b.t < hi and b.t > a.t and b.busy is not None]
        busy = sum(value for value, _ in pairs)
        per = [value / dt / n for value, dt in pairs]
        if secs <= 0 or not pairs:
            lines.append(f"budget window {label} - s: no samples")
            continue
        share = lambda seconds: seconds / secs / n * 100     # noqa: E731
        lines.append("budget window %s %.0f s busy mean %.1f%% p90 %.1f%%" % (
            label, secs, busy / sum(dt for _, dt in pairs) / n * 100, _percentile(per, 90) * 100))
        p_cpu, sided = {}, {}
        for t, name, pid, grew in events:
            if t >= hi:
                continue
            p_cpu[name] = p_cpu.get(name, 0.0) + grew
            if name in SIDED:
                side = _side_at(table, pid, name, t)[0]
                sided[(name, side)] = sided.get((name, side), 0.0) + grew
        top8, top_all = {}, {}
        for t, items in rec.tops:
            if t > hi:
                continue
            kept = [item for item in items if not (has_stop and item[0] in RECORDER_CHILDREN)]
            for rank, (name, seconds) in enumerate(kept):
                top_all[name] = top_all.get(name, 0.0) + seconds
                if rank < 8:
                    top8[name] = top8.get(name, 0.0) + seconds
        recorder = recorder_cpu * secs / span if span > 0 else 0.0
        group_p, group_top8 = {}, {}
        for name, seconds in p_cpu.items():
            group_p[_group_of(name)] = group_p.get(_group_of(name), 0.0) + seconds
        for name, seconds in top8.items():
            group_top8[_group_of(name)] = group_top8.get(_group_of(name), 0.0) + seconds
        groups_with_p = {_group_of(name) for name in pnames}

        def row(name, p_value, top_value):
            def cell(value):
                return "- -" if value is None else f"{value:.1f} s {share(value):.1f}%"
            lines.append(f"budget group {label} {name} p {cell(p_value)} top8 {cell(top_value)}")
            figures[(label, name)] = (None if p_value is None else share(p_value), None if top_value is None else share(top_value))

        for group, _ in BUDGET_GROUPS + (("other", None),):
            seen = group in groups_with_p or (measured_all and group != "other")
            row(group, group_p.get(group, 0.0) if seen else None, group_top8.get(group, 0.0))
            if group in SIDED:
                for side in SIDES:
                    if group in pnames:
                        # No ident row for the name at all (format 1, or every ident call failed):
                        # its side was never measured, so host and sim are "-" and all of it is unknown.
                        known = side == "unknown" or group in ident_names
                        value = sided.get((group, side), 0.0) if known else None
                    else:
                        value = 0.0 if measured_all else None
                    row(f"{group}.{side}", value, None)
        row("recorder", recorder if has_stop else None, None)
        rest = busy - sum(p_cpu.values()) - sum(v for name, v in top_all.items() if name not in pnames) - recorder
        old = {name for name in pnames if name in FORMAT1_NAMES or name.startswith(RUNNER_PREFIX)}
        rest1 = busy - sum(p_cpu.get(name, 0.0) for name in old) - sum(v for name, v in top8.items() if name not in old) - recorder
        row("rest", rest, None)
        row("rest1", rest1, None)
    for (pid, name) in sorted({(pid, name) for sample in valid for pid, (_, name) in sample.procs.items()
                               if name in ("diagnosticd", "apsd", "logd")}, key=lambda key: (key[1], key[0])):
        side, ppid, user = _side_at(table, pid, name, tend)
        cpu = sum(grew for _, nm, pd, grew in events if pd == pid and nm == name)
        lines.append(f"budget ident {pid} {name} {side} ppid {'-' if ppid is None else ppid} user {user or '-'} cpu {cpu:.1f} s")
    if born:
        lines.append("budget born " + ", ".join(f"{name} {count}" for name, count in sorted(born.items(), key=lambda x: (-x[1], x[0]))[:20]))
    for at, pids, rows, ms, outcome in rec.ident_calls[:10]:
        lines.append(f"budget identcall {_clock(at)[:8]} pids {pids or '-'} rows {rows or '-'} ms {ms or '-'} {outcome}")
    if len(rec.ident_calls) > 10:
        lines.append(f"budget identcall {len(rec.ident_calls) - 10} more")
    opens = [r for r in long_rows if r.step.text.startswith(OPEN_STEP)]
    longest = max((r.step.length for r in opens), default=None)
    has_steps = bool(times_paths) or times_paths is None
    if has_steps:
        lines.append("budget opens count %d longest %s s sum %.1f s no_app %.1f s" % (
            len(opens), "-" if longest is None else f"{longest:.1f}", sum(r.step.length for r in opens),
            sum(r.absent or 0.0 for r in opens)))
    else:
        lines.append("budget opens: no step times, so the Open steps are not measured here")

    def key(label, name, which):
        value = figures.get((label, name), (None, None))[0 if which == "p" else 1]
        return "-" if value is None else f"{value:.1f}"

    whole = [l for l in lines if l.startswith("budget window whole ")]
    apsd_unknown = figures.get(("whole", "apsd.unknown"), (None, None))[0]
    # Any apsd CPU whose side is not known could be the simulator's, so apsd_sim is then not a figure.
    apsd_sim = "-" if apsd_unknown is None or apsd_unknown > 0 else key("whole", "apsd.sim", "p")
    mean = p90 = "-"
    if whole:
        parts = whole[0].split()
        mean, p90 = parts[-3].rstrip("%"), parts[-1].rstrip("%")
    lines.append(" ".join([
        "BUDGET 2", f"format={rec.format or '?'}", f"shard={shard or '-'}", f"plan={plan or '-'}", f"applied={applied or '-'}",
        f"busy_mean={mean}", f"busy_p90={p90}", "missed_pct=" + ("-" if missed_pct is None else f"{missed_pct:.1f}"),
        f"app={key('whole', 'app', 'p')}", f"diag={key('whole', 'diagnosticd', 'p')}",
        f"diag_host={key('whole', 'diagnosticd.host', 'p')}", f"diag_sim={key('whole', 'diagnosticd.sim', 'p')}",
        f"diag_unknown={key('whole', 'diagnosticd.unknown', 'p')}", f"apsd={key('whole', 'apsd', 'p')}",
        f"apsd_host={key('whole', 'apsd.host', 'p')}", f"apsd_sim={apsd_sim}",
        f"apsd_unknown={key('whole', 'apsd.unknown', 'p')}", f"apsd_top8={key('whole', 'apsd', 'top8')}",
        f"spotlight={key('whole', 'spotlight', 'p')}", f"spotlight_early={key('early', 'spotlight', 'p')}",
        f"spotlight_top8={key('whole', 'spotlight', 'top8')}", f"spotlight_top8_early={key('early', 'spotlight', 'top8')}",
        f"render_top8={key('whole', 'render', 'top8')}", f"rest1={key('whole', 'rest1', 'p')}",
        "open10_n=" + (str(len(opens)) if has_steps else "-"),
        "open10_max=" + ("-" if longest is None or not has_steps else f"{longest:.1f}")]))
    return lines


def report(record_path, times_paths):
    rec = read_record(record_path)
    steps = read_steps(times_paths)
    rows = [measure(rec, step) for step in steps if step.length >= LONG_STEP or step.after_door]
    long_rows = [row for row in rows if row.step.length >= LONG_STEP]
    door_rows = [row for row in rows if row.step.after_door]
    lines = ["CPU load during long steps (scripts/ci_cpu_load.py, BYR-1841)"]
    if rec.samples:
        valid = rec.valid()
        text = (f"Record: {rec.ncpu or '?'} CPUs, {len(rec.samples)} samples ({len(valid)} with process times) "
                f"from {_clock(rec.samples[0].t)[:8]} to {_clock(rec.samples[-1].t)[:8]} UTC, "
                f"{rec.stop.get('missed', '?')} missed, {rec.unread} unread lines")
        try:
            used = float(rec.stop["recorder cpu"]) + float(rec.stop["ps cpu"])
            wall = float(rec.stop["wall"])
            text += f"; recorder and ps used {used:.1f} s of CPU in {wall:.0f} s ({used / wall * 100:.1f}% of one CPU)"
        except (KeyError, ValueError, ZeroDivisionError):
            text += "; no stop line, so the recorder's own cost is not known"
        lines.append(text + ".")
    else:
        lines.append(f"Record: no samples in {record_path}.")
    lines.extend(budget(rec, record_path, long_rows, times_paths))
    names = ", ".join(os.path.basename(path) for path in times_paths) or "no step times"
    lines.append(f"Read: {names}. App CPU share: the CPU time of all the app's threads together over the step's "
                 f"length, so 100% is one CPU busy for the whole step and it can be over 100%.")
    lines.append(f"Working ({WORKING_SHARE * 100:.0f}% or more): the app's threads together used at least "
                 f"{WORKING_SHARE:.1f} s of CPU per second of the step; this does not say which threads ran, nor "
                 f"that the main thread was one of them. Waiting ({WAITING_SHARE * 100:.0f}% or less): they used at "
                 f"most {WAITING_SHARE:.1f} s of CPU per second of the step, so for most of the step no thread of "
                 f"the app was running, each waiting for a CPU or blocked; only a low share with a high "
                 f'"host busy" points to a CPU shortage.')
    lines.append("App CPU is interpolated linearly to the step's start and end; the range runs from the samples "
                 "inside the step to the samples just outside it.")
    lines.append("")
    lines.extend(_section(f"Steps of {LONG_STEP:g} s or more", long_rows))
    lines.append("")
    lines.extend(_section('First screen read after a tap on "job-money-customer-view"', door_rows))
    lines.append("")
    lines.append(f"Steps of {LONG_STEP:g} s or more ({len(long_rows)}): {_counts(long_rows, True)}")
    lines.append(f"First reads after the door tap ({len(door_rows)}): {_counts(door_rows, False)}")
    return "\n".join(lines) + "\n"


def _read(args):
    out = None
    if "--out" in args:
        index = args.index("--out")
        out = args[index + 1] if index + 1 < len(args) else None
        args = args[:index] + args[index + 2:]
    if not args:
        print("cpu load: usage: ci_cpu_load.py read <cpu-load.txt> [<times.tsv> ...] [--out <table.txt>]")
        return 0
    text = report(args[0], args[1:])
    if out:
        try:
            with open(out, "w", encoding="utf-8") as handle:
                handle.write(text)
        except OSError as error:
            text += f"cpu load: could not write {out} ({type(error).__name__})\n"
    sys.stdout.write(text)
    sys.stdout.flush()
    return 0


def _option(args, name, default):
    if name in args:
        index = args.index(name)
        try:
            value = float(args[index + 1])
        except (IndexError, ValueError):
            value = default
        return value, args[:index] + args[index + 2:]
    return default, args


def main(argv):
    try:
        if argv[:1] == ["record"]:
            args = argv[1:]
            interval, args = _option(args, "--interval", 1.0)
            max_seconds, args = _option(args, "--max-seconds", 6000.0)
            ps_timeout, args = _option(args, "--ps-timeout", 5.0)
            return record(args[0], max(interval, 0.05), max_seconds, ps_timeout) if args else 0
        if argv[:1] == ["read"]:
            def on_alarm(signum, frame):
                raise TimeoutError("took over 60 s")
            previous = None
            if hasattr(signal, "SIGALRM"):
                try:
                    previous = signal.signal(signal.SIGALRM, on_alarm)
                    signal.alarm(60)
                except (OSError, ValueError):
                    previous = None
            try:
                return _read(argv[1:])
            finally:
                if previous is not None:
                    signal.alarm(0)
                    signal.signal(signal.SIGALRM, previous)
        print("cpu load: usage: ci_cpu_load.py record <file> | read <file> [<times.tsv> ...] [--out <file>]")
        return 0
    except Exception as error:      # evidence only: never fail the job
        try:
            print(f"cpu load: could not read the record ({type(error).__name__})")
        except Exception:
            pass
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
