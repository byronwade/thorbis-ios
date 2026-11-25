#!/usr/bin/env python3
"""Compare the simulator's live log stream with the simulator's stored log (BYR-1896, CI only).

Evidence, not a test. scripts/ci-run-ui-tests.sh decides whether a failed test runs once more from
the lines one live `log stream` wrote (scripts/ci_cancelled_taps.py). Two routes of that rule can
accept when lines are missing, so a stream that loses lines can widen the rule without a sign. This
tool reads, after the tests and their evidence are saved, the same filter over the simulator's
stored log (`log show`) and says whether the store holds every line the stream wrote, and which lines
only the store has.

    ci_log_compare.py bounds <window.txt>       two lines: the stream's start - 30 s and stop + 30 s,
                                                as `log show --start/--end` take them (local time)
    ci_log_compare.py predicate                 the stream's own filter, read from ci-run-ui-tests.sh
    ci_log_compare.py compare <experiment dir> [<cpu-load.txt>] [<test-times.tsv>]

`compare` reads stream.log, store.log, window.txt and log-show.txt in the experiment directory,
writes store-clean.log (the store's entries inside the window, header and statistics lines left
out) and compare.txt, and prints the same text. Its last line is always
`log compare: store holds every stream entry: yes|no|not known (<why>)`. It always exits 0, except
that `bounds` and `predicate` exit 1 when they cannot answer.

Both files are read as local time without a zone, as both log tools print them; the window comes
from the host's clock (seconds since the epoch) and is turned into local time on this host. The
simulator is assumed to use the host's zone; a stream entry outside its own window says it does not,
and the answer is then "not known".
"""
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
RUN_UI_TESTS = os.path.join(HERE, "ci-run-ui-tests.sh")
PREDICATE = re.compile(r"\blog stream --style compact --level default\s*\\?\s*\n?\s*--predicate '([^']*)'")
ENTRY = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)(\.\d+)?\S*\s+(\S+)\s+(.+?)\[(\d+):([0-9a-fA-F]+)\]\s+(.*)$")
STAMPED = re.compile(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d")
DROPPED = (re.compile(r"^Filtering the log data"), re.compile(r"^Timestamp\s"), re.compile(r"^Skipping info and debug"),
           re.compile(r"^-+\s*$"), re.compile(r"^\s*(Log|Activity)\s+-\s+"))
MATCH_WITHIN = 1.0
MARGIN = 30
KINDS = (("unknown digitizer", "unknown digitizer"), ("KCMD: match", "KCMD: match "), ("KCMD: no match", "KCMD: no match "),
         ("cache miss", "cache miss for Keyboard event"), ("sequence starting", "sequence starting with Keyboard event"),
         ("registrations", "new key command registrations for pid:"), ("Connection added", "Connection added: "))
SHOWN = 5


def local_seconds(stamp, fraction):
    return time.mktime(time.strptime(stamp, "%Y-%m-%d %H:%M:%S")) + (float(fraction) if fraction else 0.0)


def kind_of(message):
    for name, text in KINDS:
        if text in message:
            return name
    return "other"


class Entry:
    def __init__(self, t, stamp, pid, tid, message, raw):
        self.t, self.stamp, self.pid, self.tid, self.message, self.raw = t, stamp, pid, tid, message, raw

    def key(self):
        return (self.pid, self.tid, " ".join(self.message.split()))


def read_entries(path):
    """(entries, dropped header and statistics lines, lines before any entry that are neither)."""
    entries, dropped, stray = [], 0, 0
    current = None
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.rstrip("\r\n")
            if any(pattern.match(line) for pattern in DROPPED):
                dropped += 1
                current = None
                continue
            match = ENTRY.match(line)
            if match:
                try:
                    t = local_seconds(match.group(1), match.group(2))
                except (ValueError, OverflowError):
                    stray += 1
                    current = None
                    continue
                current = Entry(t, match.group(1) + (match.group(2) or ""), match.group(5), match.group(6).lower(),
                                match.group(7), [line])
                entries.append(current)
            elif current is not None and not STAMPED.match(line):
                current.message += "\n" + line
                current.raw.append(line)
            else:
                stray += 1
                current = None
    return entries, dropped, stray


def read_window(path):
    began = ended = None
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            word, _, value = line.strip().partition(" ")
            if word in ("began", "ended") and value.isdigit():
                if word == "began":
                    began = int(value)
                else:
                    ended = int(value)
    return began, ended


def bounds(path):
    began, ended = read_window(path)
    if began is None or ended is None or ended < began:
        print(f"log compare: {path} has no began and ended line", file=sys.stderr)
        return 1
    for t in (began - MARGIN, ended + MARGIN):
        print(time.strftime("%Y-%m-%d %H:%M:%S%z", time.localtime(t)))
    return 0


def predicate(path=RUN_UI_TESTS):
    try:
        with open(path, encoding="utf-8") as handle:
            found = PREDICATE.findall(handle.read())
    except OSError as error:
        print(f"log compare: could not read {path} ({type(error).__name__})", file=sys.stderr)
        return None
    return found[0] if len(found) == 1 else None


def match(stream, store):
    """Pair each stream entry with an unused store entry of the same pid, tid and message within
    MATCH_WITHIN seconds, the closest first. Returns the unmatched of each, in time order."""
    free = {}
    for index, entry in enumerate(store):
        free.setdefault(entry.key(), []).append(index)
    used = set()
    lost = []
    for entry in sorted(stream, key=lambda e: e.t):
        candidates = [i for i in free.get(entry.key(), ()) if i not in used and abs(store[i].t - entry.t) <= MATCH_WITHIN]
        if candidates:
            used.add(min(candidates, key=lambda i: abs(store[i].t - entry.t)))
        else:
            lost.append(entry)
    return lost, [entry for i, entry in enumerate(store) if i not in used], used


def write_log(path, entries, header):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(header)
        for entry in entries:
            handle.write("\n".join(entry.raw) + "\n")


def diagnosticd_changes(record_path):
    """Times (epoch) at which a diagnosticd pid first or last showed in the CPU load record."""
    if not record_path or not os.path.exists(record_path):
        return []
    sys.path.insert(0, HERE)
    try:
        import ci_cpu_load
    except Exception:       # evidence only
        return []
    rec = ci_cpu_load.read_record(record_path)
    seen, changes = {}, []
    valid = rec.valid()
    for sample in valid:
        for pid, (_, name) in sample.procs.items():
            if name == "diagnosticd":
                if pid not in seen and sample is not valid[0]:
                    changes.append((sample.t, f"diagnosticd {pid} first seen"))
                seen[pid] = sample.t
    for pid, last in seen.items():
        if valid and last < valid[-1].t:
            changes.append((last, f"diagnosticd {pid} last seen"))
    return sorted(changes)


def test_windows(path):
    """(start, end) of each test in a test-times.tsv, host clock, or [] when there is none."""
    windows = []
    if not path or not os.path.exists(path):
        return windows
    started = None
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 3:
                continue
            try:
                at = float(parts[0])
            except ValueError:
                continue
            if parts[1] == "started":
                started = at
            elif parts[1] in ("passed", "failed", "skipped") and started is not None:
                windows.append((started, at))
                started = None
    return windows


def compare(directory, record_path=None, times_path=None):
    out = []
    say = out.append

    def finish(answer, why):
        say(f"log compare: store holds every stream entry: {answer} ({why})")
        text = "\n".join(out) + "\n"
        try:
            with open(os.path.join(directory, "compare.txt"), "w", encoding="utf-8") as handle:
                handle.write(text)
        except OSError as error:
            text += f"log compare: could not write compare.txt ({type(error).__name__})\n"
        sys.stdout.write(text)
        return 0

    paths = {name: os.path.join(directory, name) for name in ("stream.log", "store.log", "window.txt", "log-show.txt")}
    for name in ("stream.log", "window.txt", "log-show.txt"):
        if not os.path.exists(paths[name]):
            return finish("not known", f"no {name}")
    began, ended = read_window(paths["window.txt"])
    if began is None or ended is None:
        return finish("not known", "window.txt has no began and ended line")
    with open(paths["log-show.txt"], encoding="utf-8", errors="replace") as handle:
        shown = handle.read().split()
    exit_code = shown[1] if len(shown) >= 2 and shown[0] == "exit" else "?"
    seconds = shown[3] if len(shown) >= 4 and shown[2] == "seconds" else "?"
    say(f"log show: exit {exit_code} after {seconds} s")
    if exit_code == "142":
        return finish("not known", f"log show did not finish in its alarm, {seconds} s")
    if exit_code != "0":
        return finish("no", f"log show exited {exit_code}, so the store could not be read in full")
    if not os.path.exists(paths["store.log"]) or os.path.getsize(paths["store.log"]) == 0:
        return finish("not known", "the store gave nothing")
    stream_all, stream_dropped, stream_stray = read_entries(paths["stream.log"])
    store_all, store_dropped, store_stray = read_entries(paths["store.log"])
    say(f"stream.log: {len(stream_all)} entries, {stream_dropped} header lines, {stream_stray} other lines")
    say(f"store.log: {len(store_all)} entries, {store_dropped} header and statistics lines, {store_stray} other lines")
    inside = lambda entry: began <= entry.t <= ended + 1      # noqa: E731
    outside_stream = [entry for entry in stream_all if not inside(entry)]
    stream = [entry for entry in stream_all if inside(entry)]
    store = [entry for entry in store_all if inside(entry)]
    say(f"window: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(began))} to "
        f"{time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(ended))} local; store entries outside it, not "
        f"compared: {len(store_all) - len(store)}")
    header = "Timestamp               Ty Process[PID:TID]\n"
    try:
        write_log(os.path.join(directory, "store-clean.log"), store, header)
    except OSError as error:
        say(f"log compare: could not write store-clean.log ({type(error).__name__})")
    if outside_stream:
        return finish("not known", f"{len(outside_stream)} stream entries lie outside the stream's own window, "
                                   "so the simulator's clock zone may differ from the host's")
    if not stream:
        return finish("not known", "the stream has no entries")
    lost, only_store, used = match(stream, store)
    both = len(stream) - len(lost)
    for name in [kind for kind, _ in KINDS] + ["other"]:
        s = sum(1 for e in stream if kind_of(e.message) == name)
        t = sum(1 for e in store if kind_of(e.message) == name)
        a = sum(1 for e in lost if kind_of(e.message) == name)
        b = sum(1 for e in only_store if kind_of(e.message) == name)
        if s or t:
            say(f"kind {name}: stream {s}, store {t}, both {s - a}, only in stream {a}, only in store {b}")
    say(f"total: stream {len(stream)}, store {len(store)}, both {both}, only in stream {len(lost)}, "
        f"only in store {len(only_store)}")
    first_stream = min(entry.t for entry in stream)
    first_store = min((entry.t for entry in store), default=None)
    say(f"first stream entry {min(stream, key=lambda e: e.t).stamp}; first store entry "
        f"{min(store, key=lambda e: e.t).stamp if store else '-'}")
    for entry in lost[:SHOWN]:
        say(f"  only in stream: {entry.stamp} pid {entry.pid} {entry.message.splitlines()[0][:160]}")
    early = [entry for entry in only_store if entry.t < first_stream]
    later = [entry for entry in only_store if entry.t >= first_stream]
    windows = test_windows(times_path)
    in_test = [entry for entry in later if any(lo <= entry.t <= hi for lo, hi in windows)]
    say(f"only in store: {len(early)} before the stream's first entry (the stream may not have attached yet), "
        f"{len(later)} after it" + (f", of which {len(in_test)} inside a test" if windows else ""))
    changes = diagnosticd_changes(record_path)
    for entry in later[:SHOWN]:
        near = min(changes, key=lambda change: abs(change[0] - entry.t)) if changes else None
        where = f"; {entry.t - near[0]:+.1f} s from {near[1]}" if near else ""
        say(f"  only in store: {entry.stamp} pid {entry.pid} {entry.message.splitlines()[0][:160]}{where}")
    agree = agreement(stream, [store[i] for i in sorted(used)], directory)
    say(f"ci_cancelled_taps reads the stream and the matched store entries the same way: {agree}")
    if not both:
        return finish("not known", "no stream entry was found in the store, so the two may not be the same log")
    if later:
        say(f"log compare: the live stream lost {len(later)} entries (see above)")
    if lost:
        return finish("no", f"{len(lost)} stream entries are not in the store")
    if first_store is None or first_store > first_stream + MATCH_WITHIN:
        return finish("no", "the store starts later than the stream")
    if agree != "yes":
        return finish("no", "ci_cancelled_taps reads the two differently")
    return finish("yes", f"{both} of {len(stream)} stream entries found in the store")


def agreement(stream, matched, directory):
    """Whether read_events and read_keys give the same messages, at times within MATCH_WITHIN."""
    sys.path.insert(0, HERE)
    try:
        import ci_cancelled_taps as taps
    except Exception as error:      # evidence only
        return f"not known (ci_cancelled_taps could not be loaded: {type(error).__name__})"
    a, b = os.path.join(directory, "compare-stream-entries.log"), os.path.join(directory, "compare-store-entries.log")
    header = "Timestamp               Ty Process[PID:TID]\n"
    try:
        write_log(a, stream, header)
        write_log(b, matched, header)
        events = taps.read_events(a), taps.read_events(b)
        keys = taps.read_keys(a), taps.read_keys(b)
    except (OSError, ValueError) as error:
        return f"not known ({type(error).__name__})"
    if len(events[0]) != len(events[1]) or any(abs(x - y) > MATCH_WITHIN for x, y in zip(*events)):
        return f"no (events {len(events[0])} and {len(events[1])})"
    if sorted(text for _, text in keys[0]) != sorted(text for _, text in keys[1]):
        return f"no (key lines {len(keys[0])} and {len(keys[1])})"
    return "yes"


def main(argv):
    try:
        if argv[:1] == ["bounds"] and len(argv) == 2:
            return bounds(argv[1])
        if argv == ["predicate"]:
            found = predicate()
            if found is None:
                print("log compare: the stream's filter was not found once in ci-run-ui-tests.sh", file=sys.stderr)
                return 1
            print(found)
            return 0
        if argv[:1] == ["compare"] and 2 <= len(argv) <= 4:
            return compare(argv[1], *(argv[2:] + [None, None])[:2])
    except Exception as error:      # evidence only: never a stack trace
        print(f"log compare: store holds every stream entry: not known (the compare failed: {type(error).__name__})")
        return 0 if argv[:1] == ["compare"] else 1
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
