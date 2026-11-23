import os
import select
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import ci_cancelled_taps as taps  # noqa: E402

TOOL = ROOT / "scripts" / "ci_cancelled_taps.py"
A = "ThorbisUITests/CustomerDocumentBookUITests/testEstimateReview"
B = "ThorbisUITests/JobEstimateHandoffUITests/testLongEstimateTitle"
C = "ThorbisUITests/JobOverviewUITests/testJobOverview"

# The shape of the failure in run 45119132156, shard 4: a tap, the wait for what it should have
# opened, and the failure of that wait.
STEPS = (
    (10.61, 'Tap "Job actions" Button'),
    (13.30, "Waiting 15.0s for Button (First Match) to exist"),
    (16.70, 'Tap "customer-estimate-2218" Button'),
    (17.44, 'Waiting 10.0s for "customer-book-review-sign" Button to exist'),
    (27.60, "Collecting debug information to assist test failure triage"),
)
TAP = 17.148    # where backboardd logged the error, as an offset from the test's start


def starts(index):
    """A test's own start time, as XCTest prints it: one test every 100 s."""
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(1795400000 + index * 100)) + ".002"


def at(index, offset):
    """An offset into test `index`, in seconds since the epoch."""
    return taps.local_seconds(starts(index)) + offset


def case(name, outcome, index=0, took=29.788, steps=STEPS, error="XCTAssertTrue failed", begin=True):
    """Rows as `stamp` writes them for one test case."""
    rows = [(float(index), "started", name)]
    if begin:
        rows.append((float(index), "begin", starts(index)))
    rows += [(float(index), "step", f"{offset} {text}") for offset, text in steps]
    if outcome == "failed" and error is not None:
        rows.append((float(index), "error", f"{name} {error}"))
    if outcome is not None:
        rows.append((float(index), outcome, name if took is None else f"{name} {took}"))
    return rows


def session(*cases, executed=None, failures=None, unexpected=0, sessions=1):
    rows = [(0.0, "session", "started")] * sessions
    ended = failed = 0
    for rows_of_case in cases:
        rows += rows_of_case
        kinds = [kind for _, kind, _ in rows_of_case]
        ended += any(kind in ("passed", "failed", "skipped") for kind in kinds)
        failed += "failed" in kinds
    rows.append((9999.0, "executed", f"{ended if executed is None else executed} "
                                     f"{failed if failures is None else failures} {unexpected}"))
    return rows


class DecideTests(unittest.TestCase):
    def test_a_test_that_failed_on_the_wait_after_a_cancelled_tap_is_run_again(self):
        rows = session(case(A, "passed", 0), case(B, "failed", 1))
        again, reasons = taps.decide(rows, [at(1, TAP)])
        self.assertEqual(again, [B])
        self.assertIn("cancelled the tap at t = 16.70s", reasons[0])

    def test_a_failed_test_without_one_stands(self):
        again, reasons = taps.decide(session(case(B, "failed", 1)), [])
        self.assertEqual(again, [])
        self.assertIn("This failure stands", reasons[0])

    def test_an_error_anywhere_but_at_the_last_tap_does_not_excuse_the_failure(self):
        rows = session(case(A, "passed", 0), case(B, "failed", 1))
        for event in (at(0, TAP),            # inside the test that passed
                      at(1, 10.9),           # at an earlier tap of this test
                      at(1, 5.0),            # while it launched
                      at(1, 25.0),           # during the wait that failed
                      at(1, 31.0)):          # after it had failed
            with self.subTest(event=event):
                self.assertEqual(taps.decide(rows, [event])[0], [])

    def test_the_error_may_fall_a_little_before_the_tap_and_just_after_the_wait_began(self):
        rows = session(case(B, "failed", 1))
        self.assertEqual(taps.decide(rows, [at(1, 16.70 - 0.19)])[0], [B])    # as in shard 1
        self.assertEqual(taps.decide(rows, [at(1, 16.70 - 1.0)])[0], [B])
        self.assertEqual(taps.decide(rows, [at(1, 16.70 - 1.2)])[0], [])
        self.assertEqual(taps.decide(rows, [at(1, 17.44 + 0.5)])[0], [B])
        self.assertEqual(taps.decide(rows, [at(1, 17.44 + 0.7)])[0], [])

    def test_a_failure_that_is_not_the_wait_right_after_a_tap_stands(self):
        swipe = STEPS[:2] + ((16.70, 'Swipe up "form" ScrollView'),) + STEPS[3:]
        typed = STEPS[:3] + ((17.44, "Type 'abc' into TextField"),) + STEPS[4:]
        more = STEPS[:4] + ((19.0, 'Tap "other" Button'), (19.5, "Waiting 2.0s for x to exist")) + STEPS[4:]
        for steps in (swipe, typed, more, STEPS[3:], ()):
            with self.subTest(steps=steps):
                again, reasons = taps.decide(session(case(B, "failed", 1, steps=steps)), [at(1, TAP)])
                self.assertEqual(again, [])
                self.assertIn("This failure stands", reasons[0])

    def test_a_first_failure_before_the_cancelled_tap_stands(self):
        # continueAfterFailure is left on: an assertion fails first, then a later tap is cancelled.
        rows = [(0.0, "session", "started")] + case(B, None, 1, steps=STEPS[:2])
        rows.append((1.0, "error", f"{B} XCTAssertEqual failed: (\"3\") is not equal to (\"4\")"))
        rows += [(1.0, "step", f"{offset} {text}") for offset, text in STEPS[2:]]
        rows += [(1.0, "error", f"{B} XCTAssertTrue failed"), (1.0, "failed", f"{B} 29.788")]
        rows.append((9999.0, "executed", "1 1 0"))
        self.assertEqual(taps.decide(rows, [at(1, TAP)])[0], [])

    def test_an_error_line_of_another_test_is_not_this_ones(self):
        rows = [(0.0, "session", "started")] + case(B, None, 1, steps=STEPS[:2])
        rows.append((1.0, "error", f"{A} XCTAssertTrue failed"))
        rows += [(1.0, "step", f"{offset} {text}") for offset, text in STEPS[2:]]
        rows += [(1.0, "error", f"{B} XCTAssertTrue failed"), (1.0, "failed", f"{B} 29.788")]
        rows.append((9999.0, "executed", "1 1 0"))
        self.assertEqual(taps.decide(rows, [at(1, TAP)])[0], [B])

    def test_a_crash_a_launch_failure_or_an_unexpected_failure_stands(self):
        for error in ("Thorbis crashed in specialized JobOverview.body.getter",
                      "Failed to launch <XCUIApplicationImpl com.thorbis.field>",
                      "Failed to terminate com.thorbis.field:4511",
                      "Application com.thorbis.field is not running",
                      "Lost connection to the test manager service",
                      "Test crashed with signal kill",
                      "failed: caught error: \"NSInternalInconsistencyException\""):
            with self.subTest(error=error):
                again, reasons = taps.decide(session(case(B, "failed", 1, error=error)), [at(1, TAP)])
                self.assertEqual(again, [])
                self.assertIn("is not a wait", reasons[0])
        again, reasons = taps.decide(session(case(B, "failed", 1), unexpected=1), [at(1, TAP)])
        self.assertEqual(again, [])
        self.assertIn("unexpected", reasons[0])

    def test_a_failure_without_xctests_own_record_stands(self):
        for rows in (case(B, "failed", 1, begin=False), case(B, "failed", 1, took=None),
                     case(B, "failed", 1, error=None)):
            with self.subTest(rows=rows):
                self.assertEqual(taps.decide(session(rows), [at(1, TAP)])[0], [])
        twice = case(B, "failed", 1)
        twice.insert(2, (1.0, "begin", starts(1)))
        self.assertEqual(taps.decide(session(twice), [at(1, TAP)])[0], [])

    def test_one_failure_without_a_cancelled_tap_stops_every_rerun(self):
        rows = session(case(A, "failed", 0), case(B, "failed", 1))
        again, reasons = taps.decide(rows, [at(1, TAP)])
        self.assertEqual(again, [])
        self.assertIn("Not every failed test", reasons[-1])

    def test_every_failure_with_one_is_run_again_in_order(self):
        rows = session(case(A, "failed", 0), case(C, "passed", 1), case(B, "failed", 2))
        self.assertEqual(taps.decide(rows, [at(2, TAP), at(0, TAP)])[0], [A, B])

    def test_more_than_the_limit_is_not_a_cancelled_tap_problem(self):
        cases = [case(f"T/K/test{i}", "failed", i) for i in range(4)]
        events = [at(i, TAP) for i in range(4)]
        self.assertEqual(taps.decide(session(*cases), events)[0], [])
        self.assertEqual(len(taps.decide(session(*cases[:3]), events)[0]), 3)
        self.assertEqual(len(taps.decide(session(*cases), events, limit=4)[0]), 4)
        self.assertEqual(taps.decide(session(*cases[:1]), events, limit=0)[0], [])

    def test_a_test_that_never_finished_stops_every_rerun(self):
        rows = session(case(A, "failed", 0), case(B, None, 1), executed=1, failures=1)
        again, reasons = taps.decide(rows, [at(0, TAP)])
        self.assertEqual(again, [])
        self.assertIn("never finished", reasons[0])

    def test_a_test_that_started_while_another_ran_stops_every_rerun(self):
        rows = session(case(A, None, 0) + case(B, "failed", 1), executed=1, failures=1)
        again, reasons = taps.decide(rows, [at(1, TAP)])
        self.assertEqual(again, [])
        self.assertIn(f"{A} started and never finished", reasons[0])

    def test_a_test_that_ended_without_starting_stops_every_rerun(self):
        rows = session([row for row in case(B, "failed", 1) if row[1] != "started"])
        again, reasons = taps.decide(rows, [at(1, TAP)])
        self.assertEqual(again, [])
        self.assertIn("without having started", reasons[0])
        rows = session(case(A, None, 1)[:1] + [row for row in case(B, "failed", 1) if row[1] != "started"])
        self.assertEqual(taps.decide(rows, [at(1, TAP)])[0], [])

    def test_a_test_that_failed_twice_stops_every_rerun(self):
        rows = session(case(B, "failed", 0), case(B, "failed", 1))
        again, reasons = taps.decide(rows, [at(0, TAP), at(1, TAP)])
        self.assertEqual(again, [])
        self.assertIn("more than once", reasons[0])

    def test_a_restarted_runner_stops_every_rerun(self):
        again, reasons = taps.decide(session(case(B, "failed", 1), sessions=2), [at(1, TAP)])
        self.assertEqual(again, [])
        self.assertIn("2 times", reasons[0])
        self.assertEqual(taps.decide(session(case(B, "failed", 1), sessions=0), [at(1, TAP)])[0], [])

    def test_counts_that_disagree_with_xcodebuild_stop_every_rerun(self):
        self.assertEqual(taps.decide(session(case(B, "failed", 1), failures=2), [at(1, TAP)])[0], [])
        self.assertEqual(taps.decide(session(case(B, "failed", 1), executed=2), [at(1, TAP)])[0], [])
        rows = [row for row in session(case(B, "failed", 1)) if row[1] != "executed"]
        self.assertEqual(taps.decide(rows, [at(1, TAP)])[0], [])
        rows = session(case(B, "failed", 1))
        rows[-1] = (9999.0, "executed", "1 1")
        self.assertEqual(taps.decide(rows, [at(1, TAP)])[0], [])

    def test_a_failed_run_with_no_failed_test_is_not_rerun(self):
        again, reasons = taps.decide(session(case(A, "passed", 0)), [at(0, TAP)])
        self.assertEqual(again, [])
        self.assertIn("No test case failed", reasons[0])

    def test_skipped_tests_count_as_finished(self):
        rows = session(case(A, "skipped", 0, steps=()), case(B, "failed", 1))
        self.assertEqual(taps.decide(rows, [at(1, TAP)])[0], [B])

    def test_the_last_summary_is_the_sessions(self):
        rows = session(case(A, "passed", 0), case(B, "failed", 1))
        rows.insert(len(case(A, "passed", 0)) + 1, (41.0, "executed", "1 0 0"))     # a class's own summary
        self.assertEqual(taps.decide(rows, [at(1, TAP)])[0], [B])


class ConfirmTests(unittest.TestCase):
    def test_the_one_test_passing_alone_counts(self):
        self.assertIsNone(taps.confirm(session(case(B, "passed", 0, steps=())), B))

    def test_anything_else_does_not(self):
        for rows in (session(),                                         # nothing ran
                     session(case(B, "skipped", 0, steps=())),          # skipped on the re-run
                     session(case(A, "passed", 0, steps=())),           # another test ran
                     session(case(B, "passed", 0), case(A, "passed", 1)),
                     session(case(B, "failed", 0)),
                     session(case(B, "passed", 0, steps=()), sessions=2),
                     session(case(B, "passed", 0, steps=()), executed=0),
                     session(case(B, "passed", 0, steps=()), unexpected=1),
                     [row for row in session(case(B, "passed", 0)) if row[1] != "executed"]):
            with self.subTest(rows=rows):
                self.assertIsNotNone(taps.confirm(rows, B))
        passed_with_an_error = session(case(B, "passed", 0, steps=()))
        passed_with_an_error.insert(3, (0.0, "error", f"{B} XCTAssertTrue failed"))
        self.assertIsNotNone(taps.confirm(passed_with_an_error, B))


class FileTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.times = os.path.join(self.dir.name, "times.tsv")
        self.log = os.path.join(self.dir.name, "taps.log")

    def stamp(self, text):
        data = text if isinstance(text, bytes) else text.encode()
        copied = subprocess.run([sys.executable, str(TOOL), "stamp", self.times], input=data,
                                capture_output=True, check=True, timeout=30).stdout
        return copied if isinstance(text, bytes) else copied.decode()

    def test_stamp_copies_every_line_and_notes_the_test_facts(self):
        text = (
            "Test Suite 'Selected tests' started at 2026-11-23 05:58:04.722.\n"
            "Test Suite 'ThorbisUITests.xctest' started at 2026-11-23 05:58:04.723.\n"
            "Test Suite 'JobEstimateHandoffUITests' started at 2026-11-23 05:58:04.724.\n"
            "Test Case '-[ThorbisUITests.JobEstimateHandoffUITests testLongEstimateTitle]' started.\n"
            "    t =     0.00s Start Test at 2026-11-23 06:33:21.636\n"
            "    t =     0.08s     Launch com.thorbis.field\n"
            "    t =    34.83s Tap \"job-money-customer-view\" Button\n"
            "    t =    35.17s     Synthesize event\n"
            "    t =    35.54s Waiting 45.0s for \"handoff-select\" Button to exist\n"
            "    t =    80.65s Collecting debug information to assist test failure triage\n"
            "/x/JobEstimateHandoffUITests.swift:234: error: -[ThorbisUITests.JobEstimateHandoffUITests testLongEstimateTitle] : XCTAssertTrue failed\n"
            "Test Case '-[ThorbisUITests.JobEstimateHandoffUITests testLongEstimateTitle]' failed (82.206 seconds).\n"
            "\t Executed 1 test, with 1 failure (0 unexpected) in 82.206 (82.210) seconds\n"
            "Test Case '-[ThorbisUITests.RowSwipeUITests testEdgeSwipe]' started. \xff\n"
            "Test Case '-[ThorbisUITests.RowSwipeUITests testEdgeSwipe]' skipped (0.159 seconds).\n"
            "\t Executed 47 tests, with 1 test skipped and 5 failures (2 unexpected) in 1349.561 (1349.604) seconds\n"
            "\t Executed 77 tests, with 1 failure (0 unexpected) in 2558.273 (2558.416) seconds\n"
        ).encode("latin-1") + b"not text: \xff\xfe and no newline at the end"
        before = time.time()
        self.assertEqual(self.stamp(text), text)
        rows = taps.read_times(self.times)
        self.assertEqual([(kind, value) for _, kind, value in rows], [
            ("session", "started"),
            ("started", B),
            ("begin", "2026-11-23 06:33:21.636"),
            ("step", '34.83 Tap "job-money-customer-view" Button'),
            ("step", '35.54 Waiting 45.0s for "handoff-select" Button to exist'),
            ("step", "80.65 Collecting debug information to assist test failure triage"),
            ("error", f"{B} XCTAssertTrue failed"),
            ("failed", f"{B} 82.206"),
            ("executed", "1 1 0"),
            ("started", "ThorbisUITests/RowSwipeUITests/testEdgeSwipe"),
            ("skipped", "ThorbisUITests/RowSwipeUITests/testEdgeSwipe 0.159"),
            ("executed", "47 5 2"),
            ("executed", "77 1 0"),
        ])
        self.assertTrue(all(before - 1 <= at <= time.time() + 1 for at, _, _ in rows))
        for line in Path(self.times).read_text().splitlines():
            self.assertRegex(line, r"^\d+\.\d{3}\t")

    def test_stamp_keeps_copying_when_it_cannot_write_the_times(self):
        self.times = os.path.join(self.dir.name, "no-such-directory", "times.tsv")
        text = "Test Case '-[A.B testC]' started.\nmore\n"
        self.assertEqual(self.stamp(text), text)

    @unittest.skipUnless(os.path.exists("/dev/full"), "needs /dev/full")
    def test_stamp_keeps_copying_when_writing_the_times_fails(self):
        self.times = "/dev/full"
        text = "Test Case '-[A.B testC]' started.\nmore\n" * 50
        self.assertEqual(self.stamp(text), text)

    def test_stamp_passes_each_line_on_and_times_it_as_it_arrives(self):
        env = {key: value for key, value in os.environ.items() if key != "PYTHONUNBUFFERED"}
        process = subprocess.Popen([sys.executable, str(TOOL), "stamp", self.times], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, env=env)
        self.addCleanup(process.stdout.close)
        self.addCleanup(process.kill)
        process.stdin.write(b"Test Case '-[ThorbisUITests.JobEstimateHandoffUITests testLongEstimateTitle]' started.\n")
        process.stdin.flush()
        ready, _, _ = select.select([process.stdout], [], [], 10)
        self.assertTrue(ready, "stamp held the line back")
        self.assertIn(b"started", process.stdout.readline())
        time.sleep(0.3)
        process.stdin.write(b"Test Case '-[ThorbisUITests.JobEstimateHandoffUITests testLongEstimateTitle]' failed (0.3 seconds).\n")
        process.stdin.close()
        process.stdout.read()
        self.assertEqual(process.wait(timeout=10), 0)
        (began, _, _), (ended, _, _) = taps.read_times(self.times)
        self.assertGreaterEqual(ended - began, 0.25)

    def test_events_are_read_from_the_stream_and_its_header_is_not_one(self):
        Path(self.log).write_text(
            'Filtering the log data using "process == "backboardd" AND eventMessage CONTAINS "unknown digitizer""\n'
            "Timestamp               Ty Process[PID:TID]\n"
            "2026-11-23 06:33:58.000 E  backboardd[5334:3fcd5] [com.apple.BackBoard:TouchEvents] *** unknown digitizer <BKIOHIDService: 0x2>\n"
            "2026-11-23 06:33:56.274 E  backboardd[5334:3fcd5] [com.apple.BackBoard:TouchEvents] *** unknown digitizer <BKIOHIDService: 0x600002c08d00; serviceStatus: <unknown>>\n"
            "2026-11-23 06:33:56.275 E  backboardd[5334:3fcd5] [com.apple.BackBoard:TouchEvents] didn't see a previous touch down or range-in event for pathIndex:2; skipping event\n"
            "2026-11-23 06:40:00.000 E  Thorbis[4511:1] the words unknown digitizer in an app's own line\n"
            "2026-11-23 06:40:01.000 E  Thorbis[4511:1] [app] forwarded from backboardd: unknown digitizer\n"
            "2026-11-23 06:40:02.000 E  backboardd[5334:1] [com.apple.BackBoard:TouchEvents] unknown service\n"
        )
        expected = taps.local_seconds("2026-11-23 06:33:56.274")
        events = taps.read_events(self.log)
        self.assertEqual(len(events), 2)
        self.assertAlmostEqual(events[0], expected, places=3)
        self.assertAlmostEqual(events[1] - events[0], 1.726, places=3)

    def test_the_tests_clock_and_the_logs_clock_are_read_in_the_same_local_time(self):
        code = ("import sys, time; sys.path.insert(0, sys.argv[1]); import ci_cancelled_taps as t; "
                "s = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(1795400000)) + '.250'; "
                "print(t.local_seconds(s))")
        for zone in ("UTC", "America/Los_Angeles", "Asia/Kolkata"):
            with self.subTest(zone=zone):
                result = subprocess.run([sys.executable, "-c", code, str(ROOT / "scripts")], capture_output=True,
                                        text=True, env=dict(os.environ, TZ=zone), timeout=30, check=True)
                self.assertAlmostEqual(float(result.stdout), 1795400000.25, places=3)

    def run_tool(self, *args):
        return subprocess.run([sys.executable, str(TOOL), *args], capture_output=True, text=True,
                              stdin=subprocess.DEVNULL, timeout=30)

    def decide(self, *extra):
        return self.run_tool("decide", self.times, self.log, *extra)

    def write_run(self, offset):
        rows = session(case(A, "failed", 0), case(B, "failed", 1))
        Path(self.times).write_text("".join(f"{at_:.3f}\t{kind}\t{value}\n" for at_, kind, value in rows))
        events = (at(0, TAP), at(1, offset))
        Path(self.log).write_text("".join(
            time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(int(event))) + f".{round(event % 1 * 1000):03d}"
            " E  backboardd[5334:3fcd5] [com.apple.BackBoard:TouchEvents] *** unknown digitizer <x>\n"
            for event in events))

    def test_the_command_prints_the_tests_to_run_again(self):
        self.write_run(TAP)
        result = self.decide()
        self.assertEqual((result.returncode, result.stdout), (0, f"{A}\n{B}\n"))
        self.assertIn(taps.clock(at(1, TAP)), result.stderr)

    def test_the_command_prints_nothing_when_the_failure_stands(self):
        self.write_run(25.0)
        result = self.decide()
        self.assertEqual((result.returncode, result.stdout), (1, ""))
        self.assertIn("This failure stands", result.stderr)

    def test_the_limit_can_be_set(self):
        self.write_run(TAP)
        self.assertEqual((self.decide("--limit", "1").returncode, self.decide("--limit", "1").stdout), (1, ""))
        self.assertEqual(self.decide("--limit", "2").returncode, 0)
        for extra in (("--other", "1"), ("--limit",), ("--limit", "x")):
            with self.subTest(extra=extra):
                self.assertEqual(self.decide(*extra).returncode, 2)

    def test_a_missing_or_damaged_file_stops_every_rerun(self):
        self.write_run(TAP)
        good = Path(self.times).read_text().splitlines(keepends=True)
        after = next(i for i, line in enumerate(good) if f"\tstarted\t{B}" in line) + 1
        for junk in ("junk\n", "1.0\tstarted\n", "1.0\tstarted\tA\textra\n", "x\tstarted\tA\n",
                     "1.0\tbegin\tnot a time\n", "1.0\tstep\tx Tap\n"):
            with self.subTest(junk=junk):
                Path(self.times).write_text("".join(good[:after] + [junk] + good[after:]))
                result = self.decide()
                self.assertEqual((result.returncode, result.stdout), (1, ""))
                self.assertNotIn("Traceback", result.stderr)
        Path(self.times).write_text("".join(good))
        os.remove(self.log)
        result = self.decide()
        self.assertEqual((result.returncode, result.stdout), (1, ""))
        self.assertIn("could not be read", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_confirm_exits_0_only_for_the_one_test_passing(self):
        rows = session(case(B, "passed", 0, steps=()))
        Path(self.times).write_text("".join(f"{at_:.3f}\t{kind}\t{value}\n" for at_, kind, value in rows))
        self.assertEqual(self.run_tool("confirm", self.times, B).returncode, 0)
        result = self.run_tool("confirm", self.times, A)
        self.assertEqual(result.returncode, 1)
        self.assertIn("alone", result.stderr)
        Path(self.times).write_text("")
        self.assertEqual(self.run_tool("confirm", self.times, B).returncode, 1)
        os.remove(self.times)
        self.assertEqual(self.run_tool("confirm", self.times, B).returncode, 1)

    def test_a_wrong_command_line_is_refused(self):
        for args in ([], ["decide", self.times], ["decide", self.times, self.log, "--limit", "x"], ["stamp"],
                     ["confirm", self.times], ["other", "a", "b"]):
            with self.subTest(args=args):
                self.assertEqual(self.run_tool(*args).returncode, 2)


if __name__ == "__main__":
    unittest.main()
