import os
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


def session(*cases, executed=None, failures=None, sessions=1):
    """Rows as `stamp` writes them. Each case is (name, outcome, began, finished)."""
    rows = [(0.0, "session", "started")] * sessions
    for name, outcome, began, finished in cases:
        rows.append((began, "started", name))
        if outcome is not None:
            rows.append((finished, outcome, name))
    counted = sum(1 for case in cases if case[1] is not None)
    failed = sum(1 for case in cases if case[1] == "failed")
    rows.append((9999.0, "executed", f"{counted if executed is None else executed} {failed if failures is None else failures}"))
    return rows


class DecideTests(unittest.TestCase):
    def test_a_failed_test_with_a_cancelled_tap_inside_it_is_run_again(self):
        rows = session((A, "passed", 10, 40), (B, "failed", 50, 130))
        again, reasons = taps.decide(rows, [86.2])
        self.assertEqual(again, [B])
        self.assertIn("cancelled a tap", reasons[0])

    def test_a_failed_test_without_one_stands(self):
        rows = session((A, "passed", 10, 40), (B, "failed", 50, 130))
        again, reasons = taps.decide(rows, [])
        self.assertEqual(again, [])
        self.assertIn("This failure stands", reasons[0])

    def test_a_cancelled_tap_in_another_test_does_not_excuse_this_one(self):
        rows = session((A, "passed", 10, 40), (B, "failed", 50, 130))
        self.assertEqual(taps.decide(rows, [25.0])[0], [])       # inside the test that passed
        self.assertEqual(taps.decide(rows, [49.9])[0], [])       # between the two
        self.assertEqual(taps.decide(rows, [130.1])[0], [])      # after it had failed

    def test_one_failure_without_a_cancelled_tap_stops_every_rerun(self):
        rows = session((A, "failed", 10, 40), (B, "failed", 50, 130))
        again, reasons = taps.decide(rows, [86.2])
        self.assertEqual(again, [])
        self.assertIn("Not every failed test", reasons[-1])

    def test_every_failure_with_one_is_run_again_in_order(self):
        rows = session((A, "failed", 10, 40), (C, "passed", 41, 49), (B, "failed", 50, 130))
        self.assertEqual(taps.decide(rows, [86.2, 12.0])[0], [A, B])

    def test_more_than_the_limit_is_not_a_cancelled_tap_problem(self):
        cases = [(f"T/K/test{i}", "failed", i * 10, i * 10 + 9) for i in range(4)]
        events = [i * 10 + 5 for i in range(4)]
        self.assertEqual(taps.decide(session(*cases), events)[0], [])
        self.assertEqual(len(taps.decide(session(*cases[:3]), events)[0]), 3)
        self.assertEqual(len(taps.decide(session(*cases), events, limit=4)[0]), 4)

    def test_a_test_that_never_finished_stops_every_rerun(self):
        rows = session((A, "failed", 10, 40), (B, None, 50, 0), executed=1, failures=1)
        again, reasons = taps.decide(rows, [20.0])
        self.assertEqual(again, [])
        self.assertIn("never finished", reasons[0])

    def test_a_restarted_runner_stops_every_rerun(self):
        rows = session((A, "failed", 10, 40), sessions=2)
        again, reasons = taps.decide(rows, [20.0])
        self.assertEqual(again, [])
        self.assertIn("2 times", reasons[0])
        self.assertEqual(taps.decide(session((A, "failed", 10, 40), sessions=0), [20.0])[0], [])

    def test_counts_that_disagree_with_xcodebuild_stop_every_rerun(self):
        self.assertEqual(taps.decide(session((A, "failed", 10, 40), failures=2), [20.0])[0], [])
        self.assertEqual(taps.decide(session((A, "failed", 10, 40), executed=2), [20.0])[0], [])
        rows = [row for row in session((A, "failed", 10, 40)) if row[1] != "executed"]
        self.assertEqual(taps.decide(rows, [20.0])[0], [])

    def test_a_failed_run_with_no_failed_test_is_not_rerun(self):
        again, reasons = taps.decide(session((A, "passed", 10, 40)), [20.0])
        self.assertEqual(again, [])
        self.assertIn("No test case failed", reasons[0])

    def test_skipped_tests_count_as_finished(self):
        rows = session((A, "skipped", 10, 11), (B, "failed", 50, 130))
        self.assertEqual(taps.decide(rows, [86.2])[0], [B])

    def test_the_last_summary_is_the_sessions(self):
        rows = session((A, "passed", 10, 40), (B, "failed", 50, 130))
        rows.insert(3, (41.0, "executed", "1 0"))     # the first class's own summary
        self.assertEqual(taps.decide(rows, [86.2])[0], [B])


class FileTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.times = os.path.join(self.dir.name, "times.tsv")
        self.log = os.path.join(self.dir.name, "taps.log")

    def stamp(self, text):
        data = text if isinstance(text, bytes) else text.encode()
        copied = subprocess.run([sys.executable, str(TOOL), "stamp", self.times], input=data,
                                capture_output=True, check=True).stdout
        return copied if isinstance(text, bytes) else copied.decode()

    def test_stamp_copies_every_line_and_notes_the_test_facts(self):
        text = (
            "Test Suite 'Selected tests' started at 2026-11-23 05:58:04.722.\n"
            "Test Case '-[ThorbisUITests.JobEstimateHandoffUITests testLongEstimateTitle]' started.\n"
            "    t =    80.65s Collecting debug information to assist test failure triage\n"
            "/x/JobEstimateHandoffUITests.swift:234: error: -[ThorbisUITests.JobEstimateHandoffUITests testLongEstimateTitle] : XCTAssertTrue failed\n"
            "Test Case '-[ThorbisUITests.JobEstimateHandoffUITests testLongEstimateTitle]' failed (82.206 seconds).\n"
            "Test Case '-[ThorbisUITests.RowSwipeUITests testEdgeSwipe]' started.\n"
            "Test Case '-[ThorbisUITests.RowSwipeUITests testEdgeSwipe]' skipped (0.159 seconds).\n"
            "\t Executed 47 tests, with 1 test skipped and 5 failures (0 unexpected) in 1349.561 (1349.604) seconds\n"
            "\t Executed 77 tests, with 1 failure (0 unexpected) in 2558.273 (2558.416) seconds\n"
        ).encode() + b"not text: \xff\xfe and no newline at the end"
        before = time.time()
        self.assertEqual(self.stamp(text), text)
        rows = taps.read_times(self.times)
        self.assertEqual([(kind, value) for _, kind, value in rows], [
            ("session", "started"),
            ("started", B),
            ("failed", B),
            ("started", "ThorbisUITests/RowSwipeUITests/testEdgeSwipe"),
            ("skipped", "ThorbisUITests/RowSwipeUITests/testEdgeSwipe"),
            ("executed", "47 5"),
            ("executed", "77 1"),
        ])
        self.assertTrue(all(before - 1 <= at <= time.time() + 1 for at, _, _ in rows))

    def test_stamp_keeps_copying_when_it_cannot_write_the_times(self):
        self.times = os.path.join(self.dir.name, "no-such-directory", "times.tsv")
        text = "Test Case '-[A.B testC]' started.\nmore\n"
        self.assertEqual(self.stamp(text), text)

    def test_events_are_read_from_the_stream_and_its_header_is_not_one(self):
        Path(self.log).write_text(
            'Filtering the log data using "process == "backboardd" AND composedMessage CONTAINS "unknown digitizer""\n'
            "Timestamp               Ty Process[PID:TID]\n"
            "2026-11-23 06:33:56.274 E  backboardd[5334:3fcd5] [com.apple.BackBoard:TouchEvents] *** unknown digitizer <BKIOHIDService: 0x600002c08d00; serviceStatus: <unknown>>\n"
            "2026-11-23 06:33:56.275 E  backboardd[5334:3fcd5] [com.apple.BackBoard:TouchEvents] didn't see a previous touch down or range-in event for pathIndex:2; skipping event\n"
            "2026-11-23 06:40:00.000 E  Thorbis[4511:1] the words unknown digitizer in an app's own line\n"
        )
        expected = time.mktime(time.strptime("2026-11-23 06:33:56", "%Y-%m-%d %H:%M:%S")) + 0.274
        events = taps.read_events(self.log)
        self.assertEqual(len(events), 1)
        self.assertAlmostEqual(events[0], expected, places=3)

    def decide(self):
        return subprocess.run([sys.executable, str(TOOL), "decide", self.times, self.log], capture_output=True, text=True)

    def write_run(self, event_line):
        began = time.mktime(time.strptime("2026-11-23 06:33:20", "%Y-%m-%d %H:%M:%S"))
        Path(self.times).write_text(
            f"{began - 100:.3f}\tsession\tstarted\n"
            f"{began:.3f}\tstarted\t{B}\n"
            f"{began + 82:.3f}\tfailed\t{B}\n"
            f"{began + 83:.3f}\texecuted\t1 1\n"
        )
        Path(self.log).write_text(event_line)

    def test_the_command_prints_the_tests_to_run_again(self):
        self.write_run("2026-11-23 06:33:56.274 E  backboardd[5334:3fcd5] [com.apple.BackBoard:TouchEvents] *** unknown digitizer <x>\n")
        result = self.decide()
        self.assertEqual((result.returncode, result.stdout), (0, B + "\n"))
        self.assertIn("06:33:56", result.stderr)

    def test_the_command_prints_nothing_when_the_failure_stands(self):
        self.write_run("2026-11-23 06:36:00.000 E  backboardd[5334:3fcd5] [com.apple.BackBoard:TouchEvents] *** unknown digitizer <x>\n")
        result = self.decide()
        self.assertEqual((result.returncode, result.stdout), (1, ""))
        self.assertIn("This failure stands", result.stderr)

    def test_a_missing_or_damaged_file_stops_every_rerun(self):
        self.write_run("")
        os.remove(self.log)
        self.assertEqual(self.decide().returncode, 1)
        self.write_run("")
        Path(self.times).write_text("not a line this tool wrote\n")
        result = self.decide()
        self.assertEqual((result.returncode, result.stdout), (1, ""))

    def test_a_wrong_command_line_is_refused(self):
        for args in ([], ["decide", self.times], ["decide", self.times, self.log, "--limit", "x"], ["stamp"], ["other", "a", "b"]):
            with self.subTest(args=args):
                result = subprocess.run([sys.executable, str(TOOL), *args], capture_output=True, text=True, stdin=subprocess.DEVNULL)
                self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
