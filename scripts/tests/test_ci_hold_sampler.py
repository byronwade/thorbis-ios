"""Tests for scripts/ci_hold_sampler.py: the hold rule, the line parser and the watcher.

The rule and the parser are pure and are tested with a made-up clock. The watcher is run as a
program with stand-ins for xcrun, sudo and sample first on PATH: the xcrun stand-in plays a
scripted log stream (which may depend on the --level it is given), and the thresholds are
shortened with the watcher's test-only options so each run takes about a second.
"""
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import ci_hold_sampler as hs  # noqa: E402

TOOL = ROOT / "scripts" / "ci_hold_sampler.py"

# Real lines from the app's own output (run on 2f17fb46, app pid 53314): the stderr mirror shape.
QUEUED_LINE = ("2026-11-23 16:03:51.474153+0000 Thorbis[53314:143488] [Default] "
               "XCTPerformOnMainRunLoop[not MT]: about to CFRunLoopPerform")
WAITING_LINE = ("2026-11-23 16:03:51.474273+0000 Thorbis[53314:143488] [Default] "
                "XCTPerformOnMainRunLoop[not MT]: waiting with 30.00s responsiveness timeout")
SERVED_LINE = ("2026-11-23 16:03:38.631365+0000 Thorbis[53314:142933] [Default] "
               "XCTPerformOnMainRunLoop[MT]: inside CFRunLoopPerform")
RESPONDED_LINE = ("2026-11-23 16:03:38.631616+0000 Thorbis[53314:142933] [Default] "
                  "XCTPerformOnMainRunLoop[MT]: MT responded in time (won the race to the busy flag)")
GAVE_UP_LINE = ("2026-11-23 16:04:21.483988+0000 Thorbis[53314:143488] [Default] "
                "XCTPerformOnMainRunLoop[not MT]: MT did not respond in time (lost the race to the busy flag)")
# The compact shape `log stream --style compact` prints, as it does for backboardd on the same
# simulator: local time to the millisecond, the type, process[pid:hex tid], [subsystem:category].
COMPACT_QUEUED = ("2026-11-23 15:43:41.877 Df Thorbis[7051:2304f] [com.apple.dt.xctest:Default] "
                  "XCTPerformOnMainRunLoop[not MT]: about to CFRunLoopPerform")
COMPACT_SERVED = ("2026-11-23 15:43:42.112 Df Thorbis[7051:22f1a] [com.apple.dt.xctest:Default] "
                  "XCTPerformOnMainRunLoop[MT]: inside CFRunLoopPerform")
# The header the tool prints first. It quotes the predicate (rewritten to composedMessage, as the
# runners' log tool does), so it names the markers' words.
HEADERS = (
    'Filtering the log data using "process == "Thorbis" AND composedMessage CONTAINS "CFRunLoopPerform""',
    'Filtering the log data using "process == "Thorbis" AND eventMessage CONTAINS "CFRunLoopPerform""',
    'Filtering the log data using "process == "Thorbis[1:" AND eventMessage CONTAINS '
    '"XCTPerformOnMainRunLoop[not MT]: about to CFRunLoopPerform""',
)


def holds(**kw):
    return hs.Holds(**kw)


class ParseTests(unittest.TestCase):
    def test_both_shapes_of_each_line_parse(self):
        self.assertEqual(hs.parse_line(QUEUED_LINE), (53314, hs.QUEUED))
        self.assertEqual(hs.parse_line(SERVED_LINE), (53314, hs.SERVED))
        self.assertEqual(hs.parse_line(COMPACT_QUEUED), (7051, hs.QUEUED))
        self.assertEqual(hs.parse_line(COMPACT_SERVED), (7051, hs.SERVED))

    def test_a_tag_redacted_by_the_unified_log_still_parses(self):
        for kind, phrase in ((hs.QUEUED, "about to"), (hs.SERVED, "inside")):
            line = (f"2026-11-23 15:43:41.877 Df Thorbis[7051:2304f] [com.apple.dt.xctest:Default] "
                    f"XCTPerformOnMainRunLoop[<private>]: {phrase} CFRunLoopPerform")
            with self.subTest(line=line):
                self.assertEqual(hs.parse_line(line), (7051, kind))

    def test_a_pid_is_ascii_digits_only(self):
        self.assertIsNone(hs.parse_line("Thorbis[\u0664\u0662:1] XCTPerformOnMainRunLoop[MT]: inside CFRunLoopPerform"))

    def test_the_header_is_never_an_event(self):
        for header in HEADERS:
            with self.subTest(header=header):
                self.assertIsNone(hs.parse_line(header))

    def test_other_lines_are_ignored(self):
        for line in (WAITING_LINE, RESPONDED_LINE, GAVE_UP_LINE, "Timestamp               Ty Process[PID:TID]", "",
                     "2026-11-23 15:43:41.877 Df backboardd[1563:672c] [com.apple.BackBoard:EventDelivery] "
                     "XCTPerformOnMainRunLoop[not MT]: about to CFRunLoopPerform",
                     "2026-11-23 15:43:41.877 Df ThorbisUITests-Runner[88:1] XCTPerformOnMainRunLoop[MT]: "
                     "inside CFRunLoopPerform",
                     "    cmd: (f, k, n),",
                     "2026-11-23 15:43:41.877 Df Thorbis[7051:2304f] <private>: about to CFRunLoopPerform"):
            with self.subTest(line=line):
                self.assertIsNone(hs.parse_line(line))

    def test_lines_split_across_reads_are_joined_and_bad_bytes_tolerated(self):
        lines = hs.Lines()
        data = (QUEUED_LINE + "\n" + SERVED_LINE + "\r\n").encode()
        got = []
        for cut in range(0, len(data), 7):
            got += lines.feed(data[cut:cut + 7])
        self.assertEqual(got, [QUEUED_LINE, SERVED_LINE])
        self.assertEqual(lines.feed(b"\xff\xfe Thorbis[9:1] XCTPerformOnMainRunLoop[MT]: inside "), [])
        self.assertEqual(lines.feed(b"CFRunLoopPerform\n"), ["�� Thorbis[9:1] XCTPerformOnMainRunLoop[MT]: "
                                                              "inside CFRunLoopPerform"])
        self.assertEqual(hs.parse_line(lines.feed(b"x\n")[0]), None)
        self.assertEqual(lines.feed(b"partial"), [])
        self.assertEqual(lines.end(), ["partial"])
        self.assertEqual(lines.end(), [])


class RuleTests(unittest.TestCase):
    def test_no_hold_under_the_threshold(self):
        rule = holds()
        rule.feed(0.0, 7, hs.QUEUED)
        self.assertIsNone(rule.due(4.99))
        rule.feed(4.99, 7, hs.SERVED)
        self.assertIsNone(rule.due(100.0))
        self.assertEqual((rule.queued, rule.served, rule.long_holds, rule.samples), (1, 1, 0, 0))

    def test_one_sample_at_five_seconds(self):
        rule = holds()
        rule.feed(10.0, 7, hs.QUEUED)
        self.assertIsNone(rule.due(14.9))
        sample = rule.due(15.0)
        self.assertEqual((sample.pid, sample.which, sample.hold), (7, 1, 1))
        self.assertAlmostEqual(sample.lasted, 5.0)
        self.assertIsNone(rule.due(15.1))
        self.assertIsNone(rule.due(24.9))
        self.assertEqual(rule.long_holds, 1)

    def test_a_second_at_fifteen_and_never_a_third(self):
        rule = holds()
        rule.feed(0.0, 7, hs.QUEUED)
        self.assertEqual(rule.due(5.0).which, 1)
        self.assertIsNone(rule.due(14.0))
        second = rule.due(15.2)
        self.assertEqual((second.which, second.hold), (2, 1))
        rule.feed(20.0, 7, hs.QUEUED)    # more requests of the same held app are the same hold
        for now in (15.3, 30.0, 60.0, 600.0):
            self.assertIsNone(rule.due(now))
        self.assertEqual((rule.samples, rule.long_holds, rule.number), (2, 1, 1))

    def test_a_late_check_takes_the_first_and_only_then_the_second(self):
        rule = holds()
        rule.feed(0.0, 7, hs.QUEUED)
        self.assertEqual(rule.due(16.0).which, 1)    # asked late: one sample, the first
        self.assertEqual(rule.due(19.0).which, 2)    # the next ask, once the first has run
        self.assertIsNone(rule.due(30.0))

    def test_the_wait_until_the_next_decision(self):
        rule = holds()
        self.assertEqual(rule.wait(0.0, 1.0), 1.0)
        rule.feed(10.0, 7, hs.QUEUED)
        self.assertAlmostEqual(rule.wait(14.6, 1.0), 0.4)
        self.assertEqual(rule.wait(11.0, 1.0), 1.0)
        rule.due(15.0)
        self.assertAlmostEqual(rule.wait(24.5, 1.0), 0.5)
        self.assertEqual(rule.wait(26.0, 1.0), 0.0)
        rule.due(26.0)
        self.assertEqual(rule.wait(27.0, 1.0), 1.0)

    def test_the_step_up_decision(self):
        after = hs.ESCALATE_SECONDS
        self.assertEqual(hs.LEVELS, ("default", "info", "debug"))
        self.assertEqual(after, 300.0)
        # Nothing read at a level with a louder one left: step up once the time has passed.
        for level in ("default", "info"):
            with self.subTest(level=level):
                self.assertFalse(hs.step_up_now(0.0, 0, level))
                self.assertFalse(hs.step_up_now(299.99, 0, level))
                self.assertTrue(hs.step_up_now(300.0, 0, level))
                self.assertTrue(hs.step_up_now(5000.0, 0, level))
                # One request line read since the stream started: never, however long after.
                self.assertFalse(hs.step_up_now(300.0, 1, level))
                self.assertFalse(hs.step_up_now(5000.0, 40, level))
        # At the loudest level it stays, whatever arrives.
        for since, events in ((0.0, 0), (300.0, 0), (5000.0, 0), (5000.0, 3)):
            self.assertFalse(hs.step_up_now(since, events, "debug"))
        self.assertTrue(hs.step_up_now(0.5, 0, "default", after=0.5))
        self.assertFalse(hs.step_up_now(0.49, 0, "default", after=0.5))

    def test_a_served_line_ends_the_hold_and_a_later_hold_is_sampled_again(self):
        rule = holds()
        rule.feed(0.0, 7, hs.QUEUED)
        self.assertEqual(rule.due(5.0).which, 1)
        rule.feed(6.0, 7, hs.SERVED)
        self.assertIsNone(rule.due(15.0))
        self.assertFalse(rule.holding(7, 1))
        rule.feed(20.0, 7, hs.QUEUED)
        self.assertIsNone(rule.due(24.0))
        sample = rule.due(25.0)
        self.assertEqual((sample.which, sample.hold), (1, 2))
        self.assertTrue(rule.holding(7, 2))

    def test_a_served_line_of_another_pid_does_not_end_the_hold(self):
        rule = holds()
        rule.feed(0.0, 7, hs.QUEUED)
        rule.feed(1.0, 8, hs.SERVED)
        self.assertEqual(rule.due(5.0).pid, 7)

    def test_the_limit(self):
        rule = holds(limit=3)
        taken = []
        for start in range(0, 100, 20):
            rule.feed(float(start), 7, hs.QUEUED)
            for now in (start + 5.0, start + 15.0):
                sample = rule.due(now)
                if sample:
                    taken.append((sample.hold, sample.which))
            rule.feed(start + 16.0, 7, hs.SERVED)
        self.assertEqual(taken, [(1, 1), (1, 2), (2, 1)])
        self.assertEqual(rule.samples, 3)
        self.assertEqual(rule.long_holds, 5)    # holds are still counted past the limit
        self.assertEqual(rule.over_limit, 7)

    def test_a_new_pid_drops_the_old_hold(self):
        rule = holds()
        rule.feed(0.0, 7, hs.QUEUED)
        self.assertEqual(rule.due(5.0).pid, 7)
        rule.feed(8.0, 9, hs.QUEUED)            # a new launch
        self.assertFalse(rule.holding(7, 1))
        self.assertIsNone(rule.due(12.9))       # no second sample of the old pid, nor yet of the new
        sample = rule.due(13.0)
        self.assertEqual((sample.pid, sample.which, sample.hold), (9, 1, 2))
        rule.feed(14.0, 7, hs.SERVED)           # the old pid's line does not end the new hold
        self.assertTrue(rule.holding(9, 2))

    def test_lines_that_piled_up_during_a_sample_arrive_when_read(self):
        # A sample of hold 1 ran from 5 s to 12 s. Meanwhile the app served it and queued a new
        # request, and both lines are read at 12 s: the new hold is 0 s old then, not 7.
        rule = holds()
        rule.feed(0.0, 7, hs.QUEUED)
        self.assertEqual(rule.due(5.0).which, 1)
        rule.feed(12.0, 7, hs.SERVED)
        rule.feed(12.0, 7, hs.QUEUED)
        self.assertIsNone(rule.due(12.0))
        self.assertIsNone(rule.due(16.9))
        self.assertEqual(rule.due(17.0).hold, 2)
        # Only requests piled up, none served: still the first hold, and its second sample.
        rule = holds()
        rule.feed(0.0, 7, hs.QUEUED)
        self.assertEqual(rule.due(5.0).which, 1)
        rule.feed(12.0, 7, hs.QUEUED)
        rule.feed(12.0, 7, hs.QUEUED)
        self.assertIsNone(rule.due(12.0))
        second = rule.due(15.0)
        self.assertEqual((second.hold, second.which), (1, 2))


# -- the watcher, run as a program -------------------------------------------------------------

XCRUN = textwrap.dedent("""\
    import json, os, sys, time
    STUB = os.environ["STUB_DIR"]
    with open(os.path.join(STUB, "calls.jsonl"), "a") as calls:
        calls.write(json.dumps(["xcrun"] + sys.argv[1:]) + "\\n")
    with open(os.path.join(STUB, "stream.json")) as handle:
        script = json.load(handle)
    level = sys.argv[sys.argv.index("--level") + 1] if "--level" in sys.argv else None
    with open(os.path.join(STUB, "streams.jsonl"), "a") as streams:
        streams.write(json.dumps({"pid": os.getpid(), "level": level}) + "\\n")
    if script.get("refuse"):
        print("log: Invalid predicate", file=sys.stderr, flush=True)
        sys.exit(64)
    begun = time.monotonic()
    lines = script["by_level"].get(level, []) if script.get("by_level") else script["lines"]
    for at, text in lines:
        while time.monotonic() - begun < at:
            time.sleep(0.01)
        if text is None:
            sys.exit(0)
        sys.stdout.buffer.write(text.encode() if isinstance(text, str) else bytes(text))
        sys.stdout.flush()
    time.sleep(script.get("then", 15))
    """)

SAMPLE = textwrap.dedent("""\
    import json, os, stat, sys, time
    STUB = os.environ["STUB_DIR"]
    mode = os.fstat(0)
    null = os.stat(os.devnull)
    record = {"argv": sys.argv[1:], "stdin_is_devnull": os.path.samestat(mode, null), "via": os.environ.get("VIA", "")}
    with open(os.path.join(STUB, "calls.jsonl"), "a") as calls:
        calls.write(json.dumps(["sample", record]) + "\\n")
    if os.environ.get("SAMPLE_STUCK"):
        import signal
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        print("sample: stuck", flush=True)
        time.sleep(100)
    time.sleep(float(os.environ.get("SAMPLE_TAKES", "0")))
    if os.environ.get("SAMPLE_FAILS"):
        print("sample: cannot examine process", flush=True)
        sys.exit(1)
    path = sys.argv[sys.argv.index("-file") + 1]
    with open(path, "w") as handle:
        handle.write("Call graph:\\n    150 Thread_1   DispatchQueue_1: com.apple.main-thread\\n")
    print("Sampling process for 3 seconds with 20 milliseconds of run time between samples", flush=True)
    """)

SUDO = textwrap.dedent("""\
    import json, os, sys
    STUB = os.environ["STUB_DIR"]
    with open(os.path.join(STUB, "calls.jsonl"), "a") as calls:
        calls.write(json.dumps(["sudo"] + sys.argv[1:]) + "\\n")
    if os.environ.get("SUDO_REFUSES"):
        print("sudo: a password is required", file=sys.stderr, flush=True)
        sys.exit(1)
    args = sys.argv[1:]
    if args and args[0] == "-n":
        args = args[1:]
    os.environ["VIA"] = "sudo"
    if not os.environ.get("SUDO_FORKS"):
        os.execvp(args[0], args)
    # As the real sudo does: run the command as a child and hand SIGTERM on to it.
    import signal, subprocess
    child = subprocess.Popen(args)
    signal.signal(signal.SIGTERM, lambda *_: child.send_signal(signal.SIGTERM))
    sys.exit(child.wait())
    """)


class DocstringTests(unittest.TestCase):
    """The module's docstring is what a reader of the CI log goes by, so it must say what happens."""

    def test_it_says_where_the_level_ends_when_no_request_line_arrives(self):
        # With no request line the watcher ends on a debug stream (see the watcher test
        # test_nothing_at_any_level_ends_at_debug_with_three_streams); it is not "harmless".
        doc = " ".join(hs.__doc__.split())
        self.assertNotIn("harmless", doc)
        self.assertIn('If none ever arrives, it ends at "debug" for the rest of the first run', doc)

    def test_its_lines_are_wrapped(self):
        long = [line for line in hs.__doc__.splitlines() if len(line) > 100]
        self.assertEqual(long, [])


def queued(pid=4242):
    return (f"2026-11-23 15:43:41.877 Df Thorbis[{pid}:2304f] [com.apple.dt.xctest:Default] "
            "XCTPerformOnMainRunLoop[not MT]: about to CFRunLoopPerform\n")


def served(pid=4242):
    return (f"2026-11-23 15:43:42.877 Df Thorbis[{pid}:22f1a] [com.apple.dt.xctest:Default] "
            "XCTPerformOnMainRunLoop[MT]: inside CFRunLoopPerform\n")


HEADER = HEADERS[0] + "\n"
# Shortened thresholds for the program's runs: the 5 s and 15 s of CI become 0.3 s and 0.8 s.
FAST = ["--hold-seconds", "0.3", "--second-seconds", "0.8"]


class WatcherTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        self.addCleanup(self.kill_stand_ins)
        self.bin = self.dir / "bin"
        self.bin.mkdir()
        for name, body in (("xcrun", XCRUN), ("sample", SAMPLE), ("sudo", SUDO)):
            path = self.bin / name
            path.write_text(f"#!{sys.executable}\n" + body)
            path.chmod(0o755)
        self.stub = self.dir / "stub"
        self.stub.mkdir()
        self.out = self.dir / "hold-samples"
        self.process = None

    def kill_stand_ins(self):
        if self.process and self.process.poll() is None:
            self.process.kill()
            self.process.wait()
        found = subprocess.run(["pgrep", "-f", str(self.bin)], capture_output=True, text=True).stdout.split() \
            if shutil.which("pgrep") else []
        for pid in found:
            try:
                os.kill(int(pid), signal.SIGKILL)
            except (ProcessLookupError, ValueError):
                pass

    def start(self, lines, *, then=15, refuse=False, extra=(), env=None, path=None, out=None, by_level=None):
        (self.stub / "stream.json").write_text(json.dumps({"lines": lines, "then": then, "refuse": refuse,
                                                           "by_level": by_level}))
        environment = dict(os.environ, STUB_DIR=str(self.stub),
                           PATH=path if path is not None else f"{self.bin}{os.pathsep}{os.environ['PATH']}")
        for name in ("SUDO_REFUSES", "SUDO_FORKS", "SAMPLE_FAILS", "SAMPLE_TAKES", "SAMPLE_STUCK"):
            environment.pop(name, None)
        environment.update(env or {})
        self.stdout = open(self.dir / "stdout.txt", "w+")
        self.stderr = open(self.dir / "stderr.txt", "w+")
        self.addCleanup(self.stdout.close)
        self.addCleanup(self.stderr.close)
        self.process = subprocess.Popen([sys.executable, str(TOOL), "watch", "SIM-1", str(out or self.out), *FAST, *extra],
                                        env=environment, stdin=subprocess.PIPE, stdout=self.stdout, stderr=self.stderr)
        # A pipe it could read, not /dev/null: the stand-ins check their own stdin is /dev/null.
        self.addCleanup(self.process.stdin.close)
        return self.process

    def stop(self, limit=5.0):
        began = time.monotonic()
        self.process.send_signal(signal.SIGTERM)
        code = self.process.wait(timeout=limit + 5)
        self.assertLess(time.monotonic() - began, limit, "the watcher did not stop in time")
        return code

    def wait_until(self, check, limit=5.0):
        end = time.monotonic() + limit
        while time.monotonic() < end:
            if check():
                return True
            time.sleep(0.02)
        return False

    def calls(self, kind=None):
        path = self.stub / "calls.jsonl"
        rows = [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
        return [row for row in rows if kind is None or row[0] == kind]

    def output(self):
        self.stdout.seek(0)
        self.stderr.seek(0)
        return self.stdout.read(), self.stderr.read()

    def summary(self):
        return (self.out / "summary.txt").read_text()

    def streams(self):
        """The streams the xcrun stand-in played, in order: [{"pid": ..., "level": ...}]."""
        path = self.stub / "streams.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def stream_levels(self):
        return [call[call.index("--level") + 1] for call in self.calls("xcrun")]

    def triggers(self):
        return sorted(self.out.glob("hold-*.trigger.txt"))

    def test_the_stream_is_started_with_the_expected_arguments(self):
        self.start([[0, HEADER]])
        self.assertTrue(self.wait_until(lambda: self.calls("xcrun")))
        self.assertEqual(self.stop(), 0)
        self.assertEqual(self.calls("xcrun"), [[
            "xcrun", "simctl", "spawn", "SIM-1", "log", "stream", "--style", "compact", "--level", "default",
            "--predicate", 'process == "Thorbis" AND eventMessage CONTAINS "CFRunLoopPerform"']])
        out, err = self.output()
        self.assertEqual(out, "")
        self.assertIn("Hold sampler (BYR-1841): the log stream started; 0 requests to the main thread seen, 0 served; "
                      "0 stream lines, 0 not understood; 0 holds lasted 0.3 s or more; 0 samples taken, 0 failed.", err)
        self.assertIn("0 samples taken", self.summary())
        self.assertEqual(self.calls("sample"), [])

    def test_a_long_hold_is_sampled_twice_with_the_pid_and_never_reads_stdin(self):
        # A request queued, then nothing for 1.2 s (a 5 s gap at CI's 5 s/15 s, here 0.3/0.8),
        # then served; then a short hold that is never sampled.
        self.start([[0, HEADER], [0.05, queued()], [1.2, served()], [1.3, queued()], [1.35, served()]])
        self.assertTrue(self.wait_until(lambda: len(self.calls("sample")) >= 2))
        time.sleep(0.6)
        self.assertEqual(self.stop(), 0)
        samples = self.calls("sample")
        self.assertEqual(len(samples), 2)
        for kind, record in samples:
            self.assertEqual(record["argv"][:3], ["4242", "3", "20"])
            self.assertEqual(record["argv"][3], "-file")
            self.assertRegex(Path(record["argv"][4]).name, r"^hold-0[12]-\d{6}-pid4242\.txt$")
            self.assertTrue(record["stdin_is_devnull"])
            self.assertEqual(record["via"], "sudo")
        self.assertEqual([call[1:3] for call in self.calls("sudo")], [["-n", "sample"]] * 2)
        first, second = [path.read_text() for path in self.triggers()]
        self.assertIn("pid: 4242", first)
        self.assertIn("sample: first of this hold", first)
        self.assertIn("sample: second of this hold", second)
        self.assertIn("exit status: 0", first)
        self.assertIn("command: sudo -n sample 4242 3 20 -file ", first)
        self.assertIn("the hold was still going when the tool returned: yes", first)
        self.assertRegex(first, r"the hold had lasted: 0\.[3-9]\d s when sampling began")
        for path in self.triggers():
            self.assertTrue(Path(str(path).replace(".trigger.txt", ".txt")).read_text().startswith("Call graph:"))
        self.assertIn("2 requests to the main thread seen, 2 served; 4 stream lines, 0 not understood; 1 holds lasted 0.3 s or more; "
                      "2 samples taken, 0 failed.", self.summary())
        self.assertEqual(self.output()[0], "")

    def test_a_refused_sudo_falls_back_to_sample_itself(self):
        self.start([[0, HEADER], [0.05, queued()]], env={"SUDO_REFUSES": "1"})
        self.assertTrue(self.wait_until(lambda: len(self.calls("sample")) >= 1))
        self.assertTrue(self.wait_until(lambda: self.triggers()))
        self.assertEqual(self.stop(), 0)
        record = self.calls("sample")[0][1]
        self.assertEqual(record["via"], "")
        self.assertTrue(record["stdin_is_devnull"])
        trigger = self.triggers()[0].read_text()
        self.assertIn("sudo: a password is required", trigger)
        self.assertIn("command: sample 4242 3 20 -file ", trigger)
        self.assertIn("1 samples taken, 0 failed", self.summary())

    def test_a_failing_sample_tool_is_recorded_and_the_watcher_still_exits_0(self):
        self.start([[0, HEADER], [0.05, queued()]], env={"SAMPLE_FAILS": "1"})
        self.assertTrue(self.wait_until(lambda: len(self.triggers()) >= 2))
        self.assertEqual(self.stop(), 0)
        trigger = self.triggers()[0].read_text()
        self.assertIn("exit status: 1", trigger)
        self.assertIn("sample: cannot examine process", trigger)
        self.assertEqual(trigger.count("command: "), 2)     # sudo's run, then sample's own
        self.assertIn("2 samples taken, 2 failed.", self.summary())

    def test_sigterm_during_a_sample_lets_it_finish_and_exits_0_with_a_summary(self):
        self.start([[0, HEADER], [0.05, queued()]], env={"SAMPLE_TAKES": "1"})
        self.assertTrue(self.wait_until(lambda: len(self.calls("sample")) >= 1))
        self.assertEqual(self.stop(limit=4), 0)
        self.assertEqual(len(self.triggers()), 1)
        self.assertIn("exit status: 0", self.triggers()[0].read_text())
        self.assertIn("1 samples taken, 0 failed.", self.summary())
        self.assertIn("Hold sampler (BYR-1841):", self.output()[1])

    def test_sigint_also_stops_it(self):
        self.start([[0, HEADER]])
        self.assertTrue(self.wait_until(lambda: self.calls("xcrun")))
        time.sleep(0.1)
        self.process.send_signal(signal.SIGINT)
        self.assertEqual(self.process.wait(timeout=5), 0)
        self.assertTrue((self.out / "summary.txt").exists())

    def test_the_limit_holds_across_holds(self):
        lines = [[0, HEADER]]
        for n in range(4):
            lines += [[0.05 + n * 0.5, queued()], [0.45 + n * 0.5, served()]]
        self.start(lines, extra=["--limit", "2"])
        self.assertTrue(self.wait_until(lambda: len(self.calls("sample")) >= 2))
        time.sleep(1.8)
        self.assertEqual(self.stop(), 0)
        self.assertEqual(len(self.calls("sample")), 2)
        self.assertIn("2 samples taken, 0 failed, 2 not taken past the limit of 2.", self.summary())

    def test_a_refused_stream_still_ends_with_a_summary_and_exit_0(self):
        self.start([], refuse=True)
        self.assertEqual(self.process.wait(timeout=5), 0)
        summary = self.summary()
        self.assertIn("the log stream wrote no header and ended by itself (status 64)", summary)
        self.assertIn("Invalid predicate", (self.out / "stream-stderr.txt").read_text())

    def test_no_xcrun_no_writable_directory_and_a_bad_command_line_all_exit_0(self):
        empty = self.dir / "empty-bin"
        empty.mkdir()
        self.start([], path=str(empty))
        self.assertEqual(self.process.wait(timeout=5), 0)
        self.assertIn("not running: the log stream did not start", self.summary())
        blocker = self.dir / "a-file"
        blocker.write_text("")
        self.start([[0, HEADER]], out=blocker / "inside")
        self.assertEqual(self.process.wait(timeout=5), 0)
        self.assertIn("not running: the output directory could not be made", self.output()[1])
        result = subprocess.run([sys.executable, str(TOOL), "watch", "only-one"], capture_output=True, text=True,
                                timeout=10, stdin=subprocess.DEVNULL)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_lines_the_stream_delivers_but_the_parser_rejects_are_counted_and_kept(self):
        odd = "2026-11-23 15:43:41.877 Df Thorbis[4242:2304f] [com.apple.dt.xctest:Default] <private>: about to CFRunLoopPerform"
        self.start([[0, HEADER], [0.01, "Timestamp               Ty Process[PID:TID]\n"], [0.02, odd + "\n"],
                    [0.03, queued()], [0.04, served()]])
        self.assertTrue(self.wait_until(lambda: self.calls("xcrun")))
        time.sleep(0.3)
        self.assertEqual(self.stop(), 0)
        summary = self.summary()
        self.assertIn("1 requests to the main thread seen, 1 served; 3 stream lines, 1 not understood;", summary)
        self.assertIn("line not understood: " + odd, summary)
        self.assertIn("3 stream lines, 1 not understood;", self.output()[1])

    def test_a_sample_tool_that_outlives_its_kill_is_left_and_the_watcher_stays_bounded(self):
        # sudo runs sample as a child (as root on CI, out of the watcher's reach); this sample
        # ignores SIGTERM, so killing sudo leaves it holding the output pipe.
        began = time.monotonic()
        self.start([[0, HEADER], [0.05, queued()]], env={"SUDO_FORKS": "1", "SAMPLE_STUCK": "1"},
                   extra=["--tool-timeout", "0.4", "--tool-grace", "0.3", "--limit", "1"])
        self.assertTrue(self.wait_until(lambda: self.triggers(), limit=5))
        self.assertLess(time.monotonic() - began, 4.0, "the stuck tool was waited for past its bound")
        self.assertEqual(self.stop(), 0)
        trigger = self.triggers()[0].read_text()
        self.assertRegex(trigger, r"exit status: stopped after \d+ s \(the tool was left running\)")
        self.assertIn("sample: stuck", trigger)
        self.assertEqual(trigger.count("command: "), 1)     # a stopped tool starts no other
        self.assertIn("1 samples taken, 1 failed", self.summary())

    def test_lines_split_across_writes_and_bad_bytes_from_the_stream_are_read(self):
        line = queued().encode()
        self.start([[0, HEADER], [0.05, list(b"\xff\xfe junk\n")], [0.06, list(line[:30])], [0.1, list(line[30:])]])
        self.assertTrue(self.wait_until(lambda: len(self.calls("sample")) >= 1))
        self.assertEqual(self.stop(), 0)
        self.assertEqual(self.calls("sample")[0][1]["argv"][0], "4242")


    # -- the level steps up only when needed ------------------------------------------------------

    def test_lines_at_default_keep_the_one_default_stream_long_after_the_threshold(self):
        self.start([[0, HEADER], [0.05, queued()], [0.1, served()]], extra=["--escalate-seconds", "0.3"])
        self.assertTrue(self.wait_until(lambda: self.calls("xcrun")))
        time.sleep(1.5)                     # five times the threshold
        self.assertEqual(self.stop(), 0)
        self.assertEqual(self.stream_levels(), ["default"])
        self.assertEqual(len(self.streams()), 1)
        summary = self.summary()
        self.assertIn("1 requests to the main thread seen, 1 served;", summary)
        self.assertIn(" Level in use at the end: default.", summary)
        self.assertNotIn("stepped up", summary)
        self.assertEqual(summary.count("stream: xcrun"), 1)
        self.assertIn("stream: xcrun simctl spawn SIM-1 log stream --style compact --level default --predicate ", summary)

    def test_nothing_at_default_steps_up_to_info_where_a_hold_is_sampled(self):
        self.start([], by_level={"default": [[0, HEADER]],
                                 "info": [[0, HEADER], [0.05, queued()]]},
                   extra=["--escalate-seconds", "0.5"])
        self.assertTrue(self.wait_until(lambda: len(self.calls("sample")) >= 1, limit=6))
        self.assertTrue(self.wait_until(lambda: self.triggers()))
        time.sleep(1.0)                     # past the threshold again: info has delivered, so it stays
        self.assertEqual(self.stop(), 0)
        self.assertEqual(self.stream_levels(), ["default", "info"])
        first, second = self.streams()
        self.assertEqual((first["level"], second["level"]), ("default", "info"))
        with self.assertRaises(ProcessLookupError):     # the default stream was stopped and reaped
            os.kill(first["pid"], 0)
        self.assertEqual(self.calls("sample")[0][1]["argv"][0], "4242")
        self.assertIn("pid: 4242", self.triggers()[0].read_text())
        summary = self.summary()
        self.assertIn(" Level in use at the end: info; level default delivered no request line in 0.5 s; "
                      "stepped up to info.", summary)
        self.assertIn("1 requests to the main thread seen, 0 served;", summary)
        self.assertIn("Level in use at the end: info", self.output()[1])
        commands = [line for line in summary.splitlines() if line.startswith("stream: ")]
        self.assertEqual(len(commands), 2)
        self.assertIn("--level default", commands[0])
        self.assertIn("--level info", commands[1])
        self.assertEqual(summary.count("stream header: "), 2)

    def test_nothing_at_any_level_ends_at_debug_with_three_streams(self):
        self.start([[0, HEADER], [0.01, "Timestamp               Ty Process[PID:TID]\n"],
                    [0.02, "2026-11-23 15:43:41.877 Df Thorbis[4242:2304f] <private>: something else\n"]],
                   extra=["--escalate-seconds", "0.4"])
        self.assertTrue(self.wait_until(lambda: len(self.calls("xcrun")) >= 3, limit=6))
        time.sleep(1.2)                     # three times the threshold at debug: no fourth stream
        self.assertEqual(self.stop(), 0)
        self.assertEqual(self.stream_levels(), ["default", "info", "debug"])
        for stream in self.streams()[:2]:
            with self.assertRaises(ProcessLookupError):
                os.kill(stream["pid"], 0)
        summary = self.summary()
        self.assertIn(" Level in use at the end: debug; level default delivered no request line in 0.4 s; "
                      "stepped up to info; level info delivered no request line in 0.4 s; stepped up to debug.",
                      summary)
        # Lines that were not understood are counted, over every stream, and do not stop a step up.
        self.assertIn("0 requests to the main thread seen, 0 served; 3 stream lines, 3 not understood;", summary)
        self.assertNotIn("ended by itself", summary)
        self.assertEqual([line.split("--level ")[1].split()[0] for line in summary.splitlines()
                          if line.startswith("stream: ")], ["default", "info", "debug"])

    def test_sigterm_while_waiting_for_a_step_up_exits_promptly_with_0(self):
        self.start([[0, HEADER]], extra=["--escalate-seconds", "30"])
        self.assertTrue(self.wait_until(lambda: self.calls("xcrun")))
        time.sleep(0.3)
        self.assertEqual(self.stop(limit=3), 0)
        self.assertEqual(self.stream_levels(), ["default"])
        self.assertIn(" Level in use at the end: default.", self.summary())


if __name__ == "__main__":
    unittest.main()
