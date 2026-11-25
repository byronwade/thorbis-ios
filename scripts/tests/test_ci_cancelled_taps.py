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
        failed += kinds.count("error")
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
        rows.append((9999.0, "executed", "1 2 0"))
        again, reasons = taps.decide(rows, [at(1, TAP)])
        self.assertEqual(again, [])
        self.assertIn("This failure stands", reasons[0])

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

    def test_xcodebuild_counts_failures_not_failed_tests(self):
        # Run 45325427169, iPad shard 2: one test failed its wait and then a later tap, so
        # xcodebuild counted two failures for one failed test.
        rows = case(B, "failed", 1)
        rows.insert(-1, (1.0, "error", f"{B} Failed to not hittable: Button, identifier: 'header-filter'"))
        self.assertEqual(taps.decide(session(rows), [at(1, TAP)])[0], [B])
        for failures in (1, 3):     # a failure message the log lost, or one it never had
            with self.subTest(failures=failures):
                again, reasons = taps.decide(session(rows, failures=failures), [at(1, TAP)])
                self.assertEqual(again, [])
                self.assertIn("xcodebuild counted", reasons[0])

    def test_xctests_notice_that_the_app_never_went_idle_is_not_a_step(self):
        # Run 45325427169, shard 5: inside one tap XCTest waited 60 s twice for the app's animations
        # to finish and wrote a notice each time. It sent the tap between the two notices, backboardd
        # logged the cancelled tap there, and the wait that failed came next.
        notice = "App animations complete notification not received, will attempt to continue."
        steps = (
            (36.87, 'Tap "close-line" Button'),
            (96.90, notice),
            (157.85, notice),
            (157.88, 'Waiting 5.0s for "invoice-line-price-310D7268" TextField to not exist'),
            (163.39, "Collecting debug information to assist test failure triage"),
        )
        rows = session(case(B, "failed", 1, took=171.678, steps=steps))
        again, reasons = taps.decide(rows, [at(1, 97.554)])
        self.assertEqual(again, [B])
        self.assertIn("the simulator cancelled the tap at t = 36.87s", reasons[0])
        # The notices change nothing else: with no cancelled tap from the tap to the wait, it stands.
        for events in ([at(1, 30.0)], [at(1, 160.0)]):
            with self.subTest(events=events):
                again, reasons = taps.decide(rows, events)
                self.assertEqual(again, [])
                self.assertIn("no cancelled tap in the simulator's log at its last tap", reasons[0])
        # And a notice is not a wait: a tap followed only by notices is not "the wait right after a tap".
        rows = session(case(B, "failed", 1, took=171.678, steps=steps[:3]))
        again, reasons = taps.decide(rows, [at(1, 97.554)])
        self.assertEqual(again, [])
        self.assertIn("This failure stands", reasons[0])

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


# Run 45532660760, phone shard 5: the simulator cancelled the "Job actions" tap (backboardd logged
# "unknown digitizer" 10.531 s into the test), so the More sheet never opened. The test's helper
# tapped the sheet's Customer view row straight after, with no wait, and failed on that tap.
MORE_STEPS = (
    (0.04, "Set Up"),
    (0.04, "Open com.thorbis.field"),
    (7.34, 'Waiting 15.0s for "Job actions" Button to exist'),
    (9.15, 'Tap "Job actions" Button'),
)
MORE_TAP = 10.531
D = "ThorbisUITests/CustomerDocumentBookRecoveryUITests/testZeroIssuedRevisionWithARealLineRemainsReviewable"


class MoreSheetRowTests(unittest.TestCase):
    def test_a_row_tapped_straight_after_the_lost_more_tap_stands(self):
        steps = MORE_STEPS + ((10.81, "Tap Button (First Match)"),
                              (14.27, "Requesting snapshot of accessibility hierarchy for app with pid 13763"))
        error = ("Failed to tap Button (First Match): No matches found for first query match sequence: "
                 "`Descendants matching type Button` -> `Elements matching predicate 'label BEGINSWITH "
                 "\"Customer view\"'`, given input App element pid: 13763")
        rows = session(case(D, "failed", 1, took=15.056, steps=steps, error=error))
        again, reasons = taps.decide(rows, [at(1, MORE_TAP)])
        self.assertEqual(again, [])
        self.assertIn("it did not fail on the wait right after a tap", reasons[0])

    def test_the_wait_for_the_row_after_the_lost_more_tap_is_run_again(self):
        # The same failure once the helper waits for the row before tapping it.
        steps = MORE_STEPS + ((10.81, "Waiting 10.0s for Button (First Match) to exist"),
                              (20.89, "Collecting debug information to assist test failure triage"))
        error = "XCTAssertTrue failed - More shows Customer view once Job actions is tapped"
        rows = session(case(D, "failed", 1, took=21.7, steps=steps, error=error))
        again, reasons = taps.decide(rows, [at(1, MORE_TAP)])
        self.assertEqual(again, [D])
        self.assertIn('cancelled the tap at t = 9.15s (Tap "Job actions" Button)', reasons[0])
        # Without the cancelled tap in that window it still stands.
        for event in (at(1, 9.15 - 1.2), at(1, 10.81 + 0.7)):
            with self.subTest(event=event):
                self.assertEqual(taps.decide(rows, [event])[0], [])


# Run 45558161330 (head 8894c9b7), phone shard 3: the simulator cancelled the "saved-work-done" tap
# (backboardd logged "unknown digitizer" 33.677 s into the test, its only such line in the shard),
# and the test failed in waitForSchedule(), an XCTWaiter wait on a predicate. XCTest logs that wait
# as one "Checking `Expect predicate ...`" step a second, with no "Waiting" step to mark where a
# wait begins. These are the test's steps as stamp noted them, from the earlier summary tap on.
E = "ThorbisUITests/SavedWorkReviewUITests/testUncachedJobBackAndNestedBannerReturnUseSameSheet"
CHECK = 'Checking `Expect predicate `hittable == 1` for object "schedule-title" StaticText`'
DONE_STEPS = (
    (29.03, 'Waiting 10.0s for "saved-work-review" ScrollView to not exist'),
    (30.22, "Get all elements bound by index for: Elements matching predicate '\"saved-work-summary\" IN identifiers'"),
    (30.31, 'Find the "saved-work-summary" Button'),
    (30.46, 'Find the "saved-work-summary" Button'),
    (30.58, 'Tap "saved-work-summary" Button'),
    (31.67, 'Checking existence of `"Saved on this phone" NavigationBar`'),
    (31.90, 'Waiting 5.0s for "Saved on this phone" NavigationBar to exist'),
    (32.99, 'Find the "saved-work-done" Button'),
    (33.07, "Find the Target Application 'com.thorbis.field'"),
    (33.30, "Added attachment named 'Nested job banner returns to same review'"),
    (33.47, "Added attachment named 'Full screen Nested job banner returns to same review'"),
    (33.47, 'Tap "saved-work-done" Button'),
    (34.97, CHECK),
    (35.97, CHECK),
    (36.97, CHECK),
    (37.97, CHECK),
    (38.95, CHECK),
)
DONE_TAP = 33.677
DONE_ERROR = "XCTAssertTrue failed - Leaving the review returns to Schedule"


def done_case(steps=DONE_STEPS, index=1):
    return case(E, "failed", index, took=46.430, steps=steps, error=DONE_ERROR)


class XCTWaiterWaitTests(unittest.TestCase):
    """A failure on an XCTWaiter predicate wait after a tap stands, even with the simulator's line.

    Its record cannot show that the checks are one wait: a wait that passed, then a second wait on
    the same predicate that failed, writes the same steps, each about a second after the last.
    """

    def test_the_xctwaiter_wait_after_the_cancelled_done_tap_stands(self):
        again, reasons = taps.decide(session(case(A, "passed", 0), done_case()), [at(1, DONE_TAP)])
        self.assertEqual(again, [])
        self.assertIn("it did not fail on the wait right after a tap", reasons[0])
        self.assertIn("This failure stands", reasons[0])
        self.assertIn("Not every failed test", reasons[-1])

    def test_a_passed_wait_then_a_failed_wait_on_the_same_predicate_stands_the_same_way(self):
        # The wait after the tap passed at its check at 34.97 s, and the next one began at once; its
        # first check came 1.05 s after the one that passed, within the spacing of one wait's checks.
        # With one check only, it could still be a wait that passed and a failure after it.
        merged = DONE_STEPS[:12] + tuple((offset, CHECK) for offset in (34.97, 36.02, 37.02, 38.02, 39.02, 40.00))
        for steps in (merged, DONE_STEPS[:13]):
            with self.subTest(checks=len(steps) - 12):
                again, reasons = taps.decide(session(done_case(steps)), [at(1, DONE_TAP)])
                self.assertEqual(again, [])
                self.assertIn("it did not fail on the wait right after a tap", reasons[0])

    def test_a_block_predicate_that_acts_at_each_check_stands(self):
        block = "Checking `Expect predicate `BLOCKPREDICATE(0x600000c2a0d0)` for object Target Application 'com.thorbis.field'`"
        steps = DONE_STEPS[:12] + tuple((offset, block) for offset in (34.97, 35.97, 36.97, 37.97, 38.97))
        self.assertEqual(taps.decide(session(done_case(steps)), [at(1, DONE_TAP)])[0], [])

    def test_the_same_tap_followed_by_a_waiting_step_is_run_again(self):
        # The wait the rule does recognise: the same tap, then a "Waiting" step that failed.
        steps = DONE_STEPS[:12] + ((33.97, 'Waiting 5.0s for "saved-work-review" ScrollView to not exist'),)
        again, reasons = taps.decide(session(done_case(steps)), [at(1, DONE_TAP)])
        self.assertEqual(again, [E])
        self.assertIn('cancelled the tap at t = 33.47s (Tap "saved-work-done" Button)', reasons[0])

    def test_stamp_notes_the_checks_of_an_xctwaiter_wait_and_not_those_inside_a_waiting_step(self):
        # Lines in the form xcodebuild printed them in that shard.
        text = (
            "Test Suite 'Selected tests' started at 2026-11-25 06:39:46.000.\n"
            "Test Case '-[ThorbisUITests.SavedWorkReviewUITests testUncachedJobBackAndNestedBannerReturnUseSameSheet]' started.\n"
            "    t =     0.00s Start Test at 2026-11-25 06:54:08.918\n"
            '    t =    31.90s Waiting 5.0s for "Saved on this phone" NavigationBar to exist\n'
            '    t =    32.91s     Checking `Expect predicate `existsNoRetry == 1` for object "Saved on this phone" NavigationBar`\n'
            '    t =    32.91s         Checking existence of `"Saved on this phone" NavigationBar`\n'
            '    t =    33.47s Tap "saved-work-done" Button\n'
            "    t =    33.64s     Synthesize event\n"
            f"    t =    34.97s {CHECK}\n"
            '    t =    34.97s     Find the "schedule-title" StaticText\n'
            f"    t =    35.97s {CHECK}\n"
            "/Users/runner/work/thorbis-ios/thorbis-ios/ThorbisUITests/SavedWorkReviewUITests.swift:111: error: "
            "-[ThorbisUITests.SavedWorkReviewUITests testUncachedJobBackAndNestedBannerReturnUseSameSheet] : "
            f"{DONE_ERROR}\n"
            "    t =    39.81s Tear Down\n"
            "Test Case '-[ThorbisUITests.SavedWorkReviewUITests testUncachedJobBackAndNestedBannerReturnUseSameSheet]' "
            "failed (46.430 seconds).\n"
        )
        with tempfile.TemporaryDirectory() as folder:
            times = os.path.join(folder, "times.tsv")
            subprocess.run([sys.executable, str(TOOL), "stamp", times], input=text.encode(), capture_output=True,
                           check=True, timeout=30)
            steps = [value for _, kind, value in taps.read_times(times) if kind == "step"]
        self.assertEqual(steps, ['31.90 Waiting 5.0s for "Saved on this phone" NavigationBar to exist',
                                 '33.47 Tap "saved-work-done" Button', f"34.97 {CHECK}", f"35.97 {CHECK}",
                                 "39.81 Tear Down"])


# The shape of the failure in run 45148171838, iPad shard 2 (app pid 15145, SpringBoard 1558): two
# presses of ⌘K, each sent to the app as a bare 'k' before it had registered its key commands, the
# registration 0.17 s after the second, and the wait that failed. Offsets are from the test's start.
K = "ThorbisUITests/KeyboardShortcutUITests/testCommandKOpensSearch"
N = "ThorbisUITests/KeyboardShortcutUITests/testShiftCommandNOpensTheCreateMenu"
CHORD_STEPS = (
    (6.77, "Waiting 30.0s for StaticText (First Match) to exist"),
    (10.74, "Waiting 30.0s for Button (First Match) to exist"),
    (11.80, 'Checking existence of `"search-field" TextField`'),
    (11.94, "Type 'k' key with modifiers '⌘' (0x10)"),
    (12.72, 'Waiting 4.0s for "search-field" TextField to exist'),
    (16.91, "Collecting debug information to assist test failure triage"),
    (17.11, "Type 'k' key with modifiers '⌘' (0x10)"),
    (17.74, 'Waiting 4.0s for "search-field" TextField to exist'),
    (22.04, "Collecting debug information to assist test failure triage"),
)
APP, SPRINGBOARD = 15145, 1558
CONNECTED, MISSES, REGISTERED = 4.790, (12.224, 17.405), 17.579
COMMANDS = (
    "    cmd|opt|shft: (v),\n"
    '    cmd: ((51:downArrow), (52:upArrow), ",", c, 8, 9, f, 1, "?", v, 2, "[", w, 3, x, 4, k, 5, z, 6, 7, n, a, '
    "(4F:rightArrow), (50:leftArrow)),\n"
    '    glb|ctrl|opt|shft|capslock|numpad: (" "),\n'
    "    cmd|shft: (n, z),\n"
    "    glb: (e, d),\n"
    "    cmd|opt: (w),\n"
    '    cmd|ctrl: (s, " ")'
)


def connected(pid=APP):
    return (f"Connection added: IOHIDEventSystemConnection uuid:7835800A-AF22-4F3A-B5A5-2D73BC0F71A4 pid:{pid} "
            "process:Thorbis type:Passive entitlements:0x0 caller:BackBoardServices: ___getHIDEventSystemClient_"
            'block_invoke + 276 attributes:{\n    HighFrequency = 0;\n    bundleID = "com.thorbis.field";\n}')


def bare_key(pid=APP):
    """What backboardd logs for a chord it finds no command for: the bare key goes to `pid`."""
    return [f"KCMD: no match in pid:{SPRINGBOARD} systemKeyCommandOverlay",
            f"KCMD: no match in pid:{SPRINGBOARD} keyboardFocus",
            "cache miss for Keyboard event",
            f"sequence starting with Keyboard event: <sq: 0x6000029317a0; (<keyboardFocus; display: builtin; "
            f"pid: {pid}; token: 0xBDCDB732>)>"]


def registration(pid=APP, commands=COMMANDS, environment="keyboardFocus"):
    return (f"new key command registrations for pid:{pid} environment: {environment}; token: 0xBDCDB732; "
            f"keyCommands: {{\n{commands}\n}}")


def chord_keys(index=1, *, connect=(CONNECTED,), misses=MISSES, routed_to=APP, registered=(REGISTERED,),
               commands=COMMANDS, extra=()):
    """backboardd's records for test `index`, as read_keys returns them."""
    records = [(at(index, offset), connected()) for offset in connect]
    for offset in misses:
        records += [(at(index, offset) + n * 0.0002, text) for n, text in enumerate(bare_key(routed_to))]
    records += [(at(index, offset), registration(commands=commands)) for offset in registered]
    records += [(at(index, offset), text) for offset, text in extra]
    return sorted(records)


def chord_case(name=K, index=1, steps=CHORD_STEPS, error="XCTAssertTrue failed - ⌘K opens Search", **extra):
    return case(name, "failed", index, took=23.300, steps=steps, error=error, **extra)


def compact(seconds, text):
    """A record as `log stream --style compact` prints it."""
    return (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(int(seconds))) + f".{round(seconds % 1 * 1000) % 1000:03d}"
            f" Df backboardd[1580:466d] [com.apple.BackBoard:EventDelivery] {text}\n")


class LostChordTests(unittest.TestCase):
    def test_a_test_that_failed_on_the_wait_after_a_chord_sent_as_a_bare_key_is_run_again(self):
        rows = session(case(A, "passed", 0), chord_case())
        again, reasons = taps.decide(rows, [], keys=chord_keys())
        self.assertEqual(again, [K])
        self.assertIn("did not deliver the key chord it failed on", reasons[0])
        self.assertIn("pid 15145", reasons[0])
        self.assertIn("failed on the wait that came next", reasons[0])

    def test_without_the_key_lines_the_failure_stands(self):
        again, reasons = taps.decide(session(chord_case()), [])
        self.assertEqual(again, [])
        self.assertIn("connections from the app", reasons[0])

    def test_the_never_idle_notice_between_a_chord_and_its_wait_is_not_a_step(self):
        notice = (17.40, "App animations complete notification not received, will attempt to continue.")
        steps = CHORD_STEPS[:7] + (notice,) + CHORD_STEPS[7:]
        again, reasons = taps.decide(session(chord_case(steps=steps)), [], keys=chord_keys())
        self.assertEqual(again, [K])
        self.assertIn("did not deliver the key chord it failed on", reasons[0])

    def test_a_chord_that_reached_the_app_stands(self):
        # The app was handed ⌘K as a command, matched or not: whatever happened next is the app's.
        for line in (f"KCMD: match in pid:{APP} keyboardFocus", f"KCMD: no match in pid:{APP} keyboardFocus"):
            for offset in (12.225, 17.406, 20.0):
                with self.subTest(line=line, offset=offset):
                    keys = chord_keys(extra=((offset, line),))
                    again, reasons = taps.decide(session(chord_case()), [], keys=keys)
                    self.assertEqual(again, [])
                    self.assertIn("so a chord reached it", reasons[0])

    def test_a_registration_before_the_last_chord_stands(self):
        for offset in (5.0, 12.5, 17.40):
            with self.subTest(offset=offset):
                keys = chord_keys(registered=(offset, REGISTERED))
                again, reasons = taps.decide(session(chord_case()), [], keys=keys)
                self.assertEqual(again, [])
                self.assertIn("before its last chord", reasons[0])

    def test_no_registration_after_the_chord_or_one_after_the_test_stands(self):
        for registered in ((), (23.5,), (40.0,)):
            with self.subTest(registered=registered):
                again, reasons = taps.decide(session(chord_case()), [], keys=chord_keys(registered=registered))
                self.assertEqual(again, [])
                self.assertIn("registered no key commands", reasons[0])

    def test_a_registration_without_that_chord_stands(self):
        without_k = COMMANDS.replace(" k,", "")
        only_shifted = COMMANDS.replace(" k,", "").replace("cmd|shft: (n, z)", "cmd|shft: (n, z, k)")
        for commands in (without_k, only_shifted):
            with self.subTest(commands=commands):
                keys = chord_keys(commands=commands)
                again, reasons = taps.decide(session(chord_case()), [], keys=keys)
                self.assertEqual(again, [])
                self.assertIn("do not include", reasons[0])
        keys = chord_keys(registered=()) + [(at(1, REGISTERED), registration(environment="systemKeyCommandOverlay"))]
        self.assertEqual(taps.decide(session(chord_case()), [], keys=sorted(keys))[0], [])

    def test_a_registration_that_cannot_be_read_stands(self):
        cut = registration().rsplit("\n", 1)[0]          # the stream stopped before its last line
        keys = chord_keys(registered=()) + [(at(1, REGISTERED), cut)]
        self.assertEqual(taps.decide(session(chord_case()), [], keys=sorted(keys))[0], [])
        odd = registration(commands=COMMANDS + "\n    something else")
        keys = chord_keys(registered=()) + [(at(1, REGISTERED), odd)]
        self.assertEqual(taps.decide(session(chord_case()), [], keys=sorted(keys))[0], [])

    def test_the_app_must_be_known_by_one_connection_before_the_first_chord(self):
        for connect, words in (((), "0 connections"), ((1.0, 4.79), "2 connections"),
                               ((12.5,), "only after its first chord"), ((-1.0,), "0 connections")):
            with self.subTest(connect=connect):
                again, reasons = taps.decide(session(chord_case()), [], keys=chord_keys(connect=connect))
                self.assertEqual(again, [])
                self.assertIn(words, reasons[0])

    def test_a_bare_key_sent_to_another_process_stands(self):
        again, reasons = taps.decide(session(chord_case()), [], keys=chord_keys(routed_to=SPRINGBOARD))
        self.assertEqual(again, [])
        self.assertIn("another process than the app", reasons[0])

    def test_every_chord_of_the_test_must_have_been_sent_as_a_bare_key(self):
        for misses in ((17.405,), (12.224,), (10.5, 17.405), (12.224, 18.6), (12.224, 16.0)):
            with self.subTest(misses=misses):
                again, reasons = taps.decide(session(chord_case()), [], keys=chord_keys(misses=misses))
                self.assertEqual(again, [])
                self.assertIn("This failure stands", reasons[0])
        # A bare key logged before the cache miss is not the chord's.
        keys = [(when, text) for when, text in chord_keys() if not text.startswith("cache miss")]
        keys.append((at(1, 17.41), "cache miss for Keyboard event"))
        self.assertEqual(taps.decide(session(chord_case()), [], keys=sorted(keys))[0], [])

    def test_the_bare_key_may_fall_a_little_before_the_chord_and_just_after_the_wait_began(self):
        self.assertEqual(taps.decide(session(chord_case()), [], keys=chord_keys(misses=(10.95, 17.405)))[0], [K])
        self.assertEqual(taps.decide(session(chord_case()), [], keys=chord_keys(misses=(13.21, 17.405)))[0], [K])
        self.assertEqual(taps.decide(session(chord_case()), [], keys=chord_keys(misses=(10.90, 17.405)))[0], [])
        self.assertEqual(taps.decide(session(chord_case()), [], keys=chord_keys(misses=(13.25, 17.405)))[0], [])

    def test_a_failure_that_is_not_the_wait_right_after_a_chord_stands(self):
        tap = CHORD_STEPS[:6] + ((17.11, 'Tap "search" Button'),) + CHORD_STEPS[7:]
        typed = CHORD_STEPS[:6] + ((17.11, "Type 'k' into TextField"),) + CHORD_STEPS[7:]
        later = CHORD_STEPS[:8] + ((19.0, "Type 'Kitchen' into Target Application 'com.thorbis.field'"),)
        found = CHORD_STEPS[:7] + ((17.74, 'Find the "search-field" TextField'),)
        for steps in (tap, typed, later, found, CHORD_STEPS[:3], ()):
            with self.subTest(steps=steps):
                again, reasons = taps.decide(session(chord_case(steps=steps)), [], keys=chord_keys())
                self.assertEqual(again, [])
                self.assertIn("This failure stands", reasons[0])

    def test_a_crash_a_launch_failure_or_an_unexpected_failure_at_a_lost_chord_stands(self):
        for error in ("Thorbis crashed in KeyboardCommand.search.post()",
                      "Failed to launch <XCUIApplicationImpl com.thorbis.field>",
                      "Application com.thorbis.field is not running",
                      "failed: caught error: \"NSInternalInconsistencyException\""):
            with self.subTest(error=error):
                again, reasons = taps.decide(session(chord_case(error=error)), [], keys=chord_keys())
                self.assertEqual(again, [])
                self.assertIn("is not a wait", reasons[0])
        self.assertEqual(taps.decide(session(chord_case(), unexpected=1), [], keys=chord_keys())[0], [])
        self.assertEqual(taps.decide(session(chord_case(error=None)), [], keys=chord_keys())[0], [])
        self.assertEqual(taps.decide(session(chord_case(begin=False)), [], keys=chord_keys())[0], [])

    def test_the_chord_must_be_a_command_key_the_app_registered_with_those_modifiers(self):
        def pressed(text):
            return tuple((offset, text if step.startswith("Type") else step) for offset, step in CHORD_STEPS)
        for text, expected in (("Type 'n' key with modifiers '⌘⇧' (0x12)", [N]),
                               ("Type 's' key with modifiers '⌘⌃' (0x14)", [N]),
                               ("Type 's' key with modifiers '⌘' (0x10)", []),
                               ("Type 'n' key with modifiers '⇧' (0x2)", []),
                               ("Type 'n' key with modifiers '⌘⇪' (0x11)", []),
                               ("Type 'n' key with modifiers '⌘' (0x30)", []),
                               ("Type 'kk' key with modifiers '⌘' (0x10)", [])):
            with self.subTest(text=text):
                rows = session(chord_case(name=N, steps=pressed(text), error="XCTAssertTrue failed"))
                self.assertEqual(taps.decide(rows, [], keys=chord_keys())[0], expected)

    def test_two_different_chords_stand(self):
        steps = tuple((offset, "Type 'f' key with modifiers '⌘' (0x10)" if offset == 11.94 else text)
                      for offset, text in CHORD_STEPS)
        again, reasons = taps.decide(session(chord_case(steps=steps)), [], keys=chord_keys())
        self.assertEqual(again, [])
        self.assertIn("more than one chord", reasons[0])

    def test_only_the_lines_inside_the_failed_test_count(self):
        rows = session(case(A, "passed", 0), chord_case(index=1))
        self.assertEqual(taps.decide(rows, [], keys=chord_keys(index=0))[0], [])
        self.assertEqual(taps.decide(rows, [], keys=chord_keys(index=2))[0], [])

    def test_a_cancelled_tap_and_a_lost_chord_in_one_shard_are_both_run_again(self):
        rows = session(case(A, "failed", 0), chord_case(index=1), case(C, "passed", 2))
        self.assertEqual(taps.decide(rows, [at(0, TAP)], keys=chord_keys(index=1))[0], [A, K])
        again, reasons = taps.decide(rows, [], keys=chord_keys(index=1))
        self.assertEqual(again, [])
        self.assertIn("Not every failed test", reasons[-1])
        self.assertEqual(taps.decide(rows, [at(0, TAP)], keys=chord_keys(index=1, registered=()))[0], [])
        # A cancelled tap never excuses a chord, and a lost chord never excuses a tap.
        self.assertEqual(taps.decide(session(chord_case()), [at(1, 17.2)], keys=[])[0], [])
        rows = session(case(B, "failed", 1))
        self.assertEqual(taps.decide(rows, [], keys=chord_keys(misses=(TAP - 0.3, TAP)))[0], [])

    def test_the_limit_counts_lost_chords_too(self):
        cases = [case(f"T/K/test{i}", "failed", i) for i in range(3)] + [chord_case(index=3)]
        events = [at(i, TAP) for i in range(3)]
        self.assertEqual(taps.decide(session(*cases), events, keys=chord_keys(index=3))[0], [])
        self.assertEqual(len(taps.decide(session(*cases), events, limit=4, keys=chord_keys(index=3))[0]), 4)


# Run 45573322329, iPad shard 1, head 1daa44b4: the real lines. backboardd's records come from the job's
# cancelled-taps.log (lines 138-157, 327-344 and 394-411) and the steps from its test-times.tsv (lines 985-1000
# and 1036-1052). SpringBoard (pid 1378) had registered ⌘F and ⌃⌘S in its own keyboardFocus table; the app had
# not registered yet, so backboardd matched each press in SpringBoard's table and sent the app nothing. The
# app's first registration came 0.47 s and 0.33 s after the second and last press.
F = "ThorbisUITests/KeyboardShortcutUITests/testCommandFOpensSearch"
S = "ThorbisUITests/KeyboardShortcutUITests/testTabletSidebarAndPlaceShortcuts"
# SpringBoard's system overlay table, logged at the same instant just before its keyboardFocus table (lines 138-148).
REAL_SPRINGBOARD_OVERLAY = r"""2026-11-25 08:23:59.963 Df backboardd[1400:7747] [com.apple.BackBoard:EventDelivery] new key command registrations for pid:1378 environment: systemKeyCommandOverlay; token: 0xFAD1D109; keyCommands: {
    glb|shft: ("`", a),
    cmd: (q, h, m, " ", "\134t", "`"),
    glb|opt: ((50:leftArrow), (4F:rightArrow)),
    glb|ctrl: ((4F:rightArrow), (50:leftArrow), "\134\134", c, (51:downArrow), (52:upArrow)),
    cmd|shft: ("\134t", "/", "`", (20:3), (21:4)),
    cmd|opt: (d, h),
    glb: ("`", h, a, q, (4F:rightArrow), c, "\134\134", (52:upArrow), s, (50:leftArrow), (51:downArrow), m, f, n),
    glb|ctrl|shft: ((52:upArrow), (4F:rightArrow), (50:leftArrow), (51:downArrow)),
    cmd|ctrl: (q)
}
"""
REAL_SPRINGBOARD_TABLE = REAL_SPRINGBOARD_OVERLAY + """\
2026-11-25 08:23:59.963 Df backboardd[1400:7747] [com.apple.BackBoard:EventDelivery] new key command registrations for pid:1378 environment: keyboardFocus; token: 0xFAD1D109; keyCommands: {
    cmd|opt|shft: (v),
    cmd: ("+", (code: 29), ",", b, c, "-", (50:leftArrow), (51:downArrow), (52:upArrow), e, f, g, u, "?", v, i, w, x, z, "{", "|", a, (4F:rightArrow), "}"),
    glb|ctrl|opt|shft|capslock|numpad: (" "),
    cmd|shft: (z, g),
    glb: (e, d),
    cmd|opt: (f, w),
    cmd|ctrl: (s, " ")
}
"""
REAL_F_LOG = """\
2026-11-25 08:35:26.370 Df backboardd[1400:161f4] [com.apple.iohid:default] Connection added: IOHIDEventSystemConnection uuid:89D57CE1-7F1A-4BB4-8324-A6E8DF4A3156 pid:33422 process:Thorbis type:Passive entitlements:0x0 caller:BackBoardServices: ___getHIDEventSystemClient_block_invoke + 276 attributes:{
    HighFrequency = 0;
    bundleID = "com.thorbis.field";
    pid = 33422;
} state:0x0 events:0 mask:0x0 dropped:0 dropStatus:0 droppedMask:0x0 lastDroppedTime:NONE
2026-11-25 08:35:35.691 Df backboardd[1400:15c15] [com.apple.BackBoard:EventDeliveryMatching] KCMD: no match in pid:1378 systemKeyCommandOverlay
2026-11-25 08:35:35.691 Df backboardd[1400:15c15] [com.apple.BackBoard:EventDeliveryMatching] KCMD: match in pid:1378 keyboardFocus
2026-11-25 08:35:40.934 Df backboardd[1400:15c15] [com.apple.BackBoard:EventDeliveryMatching] KCMD: no match in pid:1378 systemKeyCommandOverlay
2026-11-25 08:35:40.934 Df backboardd[1400:15c15] [com.apple.BackBoard:EventDeliveryMatching] KCMD: match in pid:1378 keyboardFocus
2026-11-25 08:35:41.402 Df backboardd[1400:176df] [com.apple.BackBoard:EventDelivery] new key command registrations for pid:33422 environment: keyboardFocus; token: 0xBBC770A7; keyCommands: {
    cmd|opt|shft: (v),
    cmd: ((51:downArrow), (52:upArrow), ",", c, 8, 9, f, 1, "?", v, 2, "[", w, 3, x, 4, k, 5, z, 6, 7, n, a, (4F:rightArrow), (50:leftArrow)),
    glb|ctrl|opt|shft|capslock|numpad: (" "),
    cmd|shft: (n, z),
    glb: (e, d),
    cmd|opt: (w),
    cmd|ctrl: (s, " ")
}
"""
REAL_S_LOG = """\
2026-11-25 08:37:17.634 Df backboardd[1400:1a2f0] [com.apple.iohid:default] Connection added: IOHIDEventSystemConnection uuid:C35B4BD6-12F7-4397-BBA8-B02E1E2E1182 pid:38131 process:Thorbis type:Passive entitlements:0x0 caller:BackBoardServices: ___getHIDEventSystemClient_block_invoke + 276 attributes:{
    HighFrequency = 0;
    bundleID = "com.thorbis.field";
    pid = 38131;
} state:0x0 events:0 mask:0x0 dropped:0 dropStatus:0 droppedMask:0x0 lastDroppedTime:NONE
2026-11-25 08:37:24.968 Df backboardd[1400:17e21] [com.apple.BackBoard:EventDeliveryMatching] KCMD: no match in pid:1378 systemKeyCommandOverlay
2026-11-25 08:37:24.968 Df backboardd[1400:17e21] [com.apple.BackBoard:EventDeliveryMatching] KCMD: match in pid:1378 keyboardFocus
2026-11-25 08:37:30.256 Df backboardd[1400:19d62] [com.apple.BackBoard:EventDeliveryMatching] KCMD: no match in pid:1378 systemKeyCommandOverlay
2026-11-25 08:37:30.256 Df backboardd[1400:19d62] [com.apple.BackBoard:EventDeliveryMatching] KCMD: match in pid:1378 keyboardFocus
2026-11-25 08:37:30.582 Df backboardd[1400:19d62] [com.apple.BackBoard:EventDelivery] new key command registrations for pid:38131 environment: keyboardFocus; token: 0xA50B9F97; keyCommands: {
    cmd|opt|shft: (v),
    cmd: ((51:downArrow), (52:upArrow), ",", c, 8, 9, f, 1, "?", v, 2, "[", w, 3, x, 4, k, 5, z, 6, 7, n, a, (4F:rightArrow), (50:leftArrow)),
    glb|ctrl|opt|shft|capslock|numpad: (" "),
    cmd|shft: (n, z),
    glb: (e, d),
    cmd|opt: (w),
    cmd|ctrl: (s, " ")
}
"""
REAL_F_TIMES = """\
1795595722.320\tstarted\tThorbisUITests/KeyboardShortcutUITests/testCommandFOpensSearch
1795595722.331\tbegin\t2026-11-25 08:35:22.320
1795595722.480\tstep\t0.13 Set Up
1795595723.267\tstep\t0.13 Open com.thorbis.field
1795595728.580\tstep\t6.23 Waiting 30.0s for StaticText (First Match) to exist
1795595734.188\tstep\t11.84 Waiting 30.0s for Button (First Match) to exist
1795595735.209\tstep\t12.90 Checking existence of `"search-field" TextField`
1795595735.371\tstep\t13.06 Type 'f' key with modifiers '⌘' (0x10)
1795595736.057\tstep\t13.75 Waiting 4.0s for "search-field" TextField to exist
1795595740.324\tstep\t18.02 Collecting debug information to assist test failure triage
1795595740.552\tstep\t18.24 Type 'f' key with modifiers '⌘' (0x10)
1795595741.583\tstep\t19.28 Waiting 4.0s for "search-field" TextField to exist
1795595745.809\tstep\t23.51 Collecting debug information to assist test failure triage
1795595746.802\terror\tThorbisUITests/KeyboardShortcutUITests/testCommandFOpensSearch XCTAssertTrue failed - ⌘F opens Search
1795595746.802\tstep\t24.49 Tear Down
1795595747.075\tfailed\tThorbisUITests/KeyboardShortcutUITests/testCommandFOpensSearch 24.737
"""
REAL_S_TIMES = """\
1795595832.192\tstarted\tThorbisUITests/KeyboardShortcutUITests/testTabletSidebarAndPlaceShortcuts
1795595832.192\tbegin\t2026-11-25 08:37:12.111
1795595832.265\tstep\t0.12 Set Up
1795595832.265\tstep\t0.13 Open com.thorbis.field
1795595839.648\tstep\t7.52 Waiting 30.0s for StaticText (First Match) to exist
1795595843.300\tstep\t11.15 Waiting 30.0s for Button (First Match) to exist
1795595844.359\tstep\t12.24 Checking existence of `"Toggle sidebar" Button`
1795595844.546\tstep\t12.43 Checking existence of `"sidebar-search" Button`
1795595844.686\tstep\t12.57 Type 's' key with modifiers '⌘⌃' (0x14)
1795595845.326\tstep\t13.19 Waiting 4.0s for "sidebar-search" Button to exist
1795595849.622\tstep\t17.51 Collecting debug information to assist test failure triage
1795595849.875\tstep\t17.75 Type 's' key with modifiers '⌘⌃' (0x14)
1795595850.811\tstep\t18.70 Waiting 4.0s for "sidebar-search" Button to exist
1795595855.222\tstep\t23.07 Collecting debug information to assist test failure triage
1795595855.436\terror\tThorbisUITests/KeyboardShortcutUITests/testTabletSidebarAndPlaceShortcuts XCTAssertTrue failed - ⌃⌘S shows the sidebar
1795595855.436\tstep\t23.30 Tear Down
1795595855.703\tfailed\tThorbisUITests/KeyboardShortcutUITests/testTabletSidebarAndPlaceShortcuts 23.564
"""
F_APP, S_APP = 33422, 38131
F_TAKEN = "2026-11-25 08:35:40.934 Df backboardd[1400:15c15] [com.apple.BackBoard:EventDeliveryMatching] KCMD: match in pid:1378 keyboardFocus\n"
F_FIRST_TAKEN = "2026-11-25 08:35:35.691 Df backboardd[1400:15c15] [com.apple.BackBoard:EventDeliveryMatching] KCMD: match in pid:1378 keyboardFocus\n"
F_REGISTERED_AT = "2026-11-25 08:35:41.402"
S_REGISTERED_AT = "2026-11-25 08:37:30.582"


def real_rows(*times, executed=None):
    """One session holding the given tests' real rows, summed up the way xcodebuild does."""
    rows = [(0.0, "session", "started")]
    for text in times:
        for line in text.splitlines():
            stamped, kind, value = line.split("\t")
            rows.append((float(stamped), kind, value))
    tests = sum(kind in ("passed", "failed", "skipped") for _, kind, _ in rows)
    errors = sum(kind == "error" for _, kind, _ in rows)
    rows.append((9999999999.0, "executed", executed or f"{tests} {errors} 0"))
    return rows


def real_keys(*logs):
    """backboardd's records, read from the given log text the way `decide` reads the job's log."""
    with tempfile.TemporaryDirectory() as folder:
        path = os.path.join(folder, "cancelled-taps.log")
        Path(path).write_text("Timestamp               Ty Process[PID:TID]\n" + "".join(logs), encoding="utf-8")
        return taps.read_keys(path)


def line_at(stamp, message, subsystem="EventDeliveryMatching"):
    """A backboardd line as the job's log stream wrote them."""
    return f"{stamp} Df backboardd[1400:15c15] [com.apple.BackBoard:{subsystem}] {message}\n"


def registration_block(log, stamp):
    """The app's registration message in `log`, from its stamp to the end (it is the log's last message)."""
    return log[log.index(stamp):]


class SpringBoardTookTheChordTests(unittest.TestCase):
    """The second form: before the app had registered, backboardd matched the chord in SpringBoard's own
    keyboardFocus table and sent the app nothing."""

    def decide(self, logs=(REAL_SPRINGBOARD_TABLE, REAL_F_LOG), times=(REAL_F_TIMES,)):
        return taps.decide(real_rows(*times), [], keys=real_keys(*logs))

    def test_both_real_failures_are_run_again(self):
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_LOG, REAL_S_LOG), (REAL_F_TIMES, REAL_S_TIMES))
        self.assertEqual(again, [F, S], reasons)
        self.assertEqual(reasons[0], (
            f"{F}: the simulator did not deliver the key chord it failed on: at t = 18.24s (Type 'f' key with "
            f"modifiers '⌘' (0x10)) backboardd matched it in the system's own key commands (pid 1378), not the "
            f"app's (pid 33422), at {taps.clock(taps.local_seconds('2026-11-25 08:35:40.934'))}, and sent the app "
            "nothing, as it did for every chord of the test, before the app had registered any key commands; the "
            f"app registered that chord at {taps.clock(taps.local_seconds(F_REGISTERED_AT))}, and the test failed "
            "on the wait that came next."))
        self.assertIn("(pid 1378), not the app's (pid 38131)", reasons[1])
        self.assertIn(f"registered that chord at {taps.clock(taps.local_seconds(S_REGISTERED_AT))}", reasons[1])

    def test_each_real_failure_alone_is_run_again(self):
        again, reasons = self.decide()
        self.assertEqual(again, [F])
        self.assertIn(f"{F}: the simulator did not deliver", reasons[0])
        self.assertIn("matched it in the system's own key commands (pid 1378), not the app's (pid 33422)", reasons[0])
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, REAL_S_LOG), (REAL_S_TIMES,))
        self.assertEqual(again, [S])
        self.assertIn(f"{S}: the simulator did not deliver", reasons[0])
        self.assertIn("matched it in the system's own key commands (pid 1378), not the app's (pid 38131)", reasons[0])

    def test_today_the_rule_stopped_at_the_first_chord(self):
        # The reason CI printed on the real run is still the reason when neither form is there.
        no_match = REAL_F_LOG.replace("KCMD: match in pid:1378 keyboardFocus", "KCMD: no match in pid:1378 keyboardFocus")
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, no_match))
        self.assertEqual(again, [])
        self.assertEqual(reasons[0], f"{F}: no chord the simulator failed to deliver at t = 13.06s "
                                     f"({taps.clock(taps.local_seconds('2026-11-25 08:35:34.380'))} to "
                                     f"{taps.clock(taps.local_seconds('2026-11-25 08:35:36.570'))}): backboardd did "
                                     "not log a cache miss and a bare key to the app. This failure stands.")

    def test_a_registration_by_the_app_before_the_last_chord_stands(self):
        for log, old, new in ((REAL_F_LOG, F_REGISTERED_AT, "2026-11-25 08:35:38.000"),   # between the presses
                              (REAL_F_LOG, F_REGISTERED_AT, "2026-11-25 08:35:30.000"),   # before the first
                              (REAL_F_LOG, F_REGISTERED_AT, "2026-11-25 08:35:40.934"),   # with the last press
                              (REAL_S_LOG, S_REGISTERED_AT, "2026-11-25 08:37:27.000")):
            with self.subTest(new=new):
                times = (REAL_F_TIMES,) if log is REAL_F_LOG else (REAL_S_TIMES,)
                again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, log.replace(old, new)), times)
                self.assertEqual(again, [])
                self.assertIn("before its last chord", reasons[0])
        # A registration before the last press as well as the real one after it.
        early = registration_block(REAL_F_LOG, F_REGISTERED_AT).replace(F_REGISTERED_AT, "2026-11-25 08:35:38.000")
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_LOG, early))
        self.assertEqual(again, [])
        self.assertIn("before its last chord", reasons[0])

    def test_a_key_command_matched_or_refused_in_the_app_during_the_test_stands(self):
        for message in (f"KCMD: match in pid:{F_APP} keyboardFocus", f"KCMD: no match in pid:{F_APP} keyboardFocus"):
            for stamp in ("2026-11-25 08:35:35.692", "2026-11-25 08:35:40.935", "2026-11-25 08:35:44.000"):
                with self.subTest(message=message, stamp=stamp):
                    again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_LOG, line_at(stamp, message)))
                    self.assertEqual(again, [])
                    self.assertIn("so a chord reached it", reasons[0])

    def test_the_apps_registration_must_list_the_pressed_key_under_exactly_the_pressed_modifiers(self):
        cases = (
            (REAL_F_LOG.replace(" 9, f, 1,", " 9, 1,"), REAL_F_TIMES),                                  # no ⌘F
            (REAL_F_LOG.replace(" 9, f, 1,", " 9, 1,").replace("cmd|shft: (n, z)", "cmd|shft: (n, z, f)"),
             REAL_F_TIMES),                                                                              # only ⇧⌘F
            (REAL_S_LOG.replace('cmd|ctrl: (s, " ")', 'cmd|ctrl: (" ")'), REAL_S_TIMES),                 # no ⌃⌘S
            (REAL_S_LOG.replace('cmd|ctrl: (s, " ")', 'cmd|ctrl: (" ")').replace(" z, 6,", " z, s, 6,"),
             REAL_S_TIMES),                                                                              # only ⌘S
        )
        for log, times in cases:
            with self.subTest(log=log[-200:]):
                again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, log), (times,))
                self.assertEqual(again, [])
                self.assertIn("do not include", reasons[0])

    def test_no_registration_by_the_app_after_the_last_chord_stands(self):
        removed = REAL_F_LOG.split(F_REGISTERED_AT)[0]
        after_the_test = REAL_F_LOG.replace(F_REGISTERED_AT, "2026-11-25 08:35:50.000")
        for log in (removed, after_the_test):
            with self.subTest(log=log[-120:]):
                again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, log))
                self.assertEqual(again, [])
                self.assertIn("registered no key commands", reasons[0])

    def test_a_match_that_names_the_apps_own_pid_is_not_this_form(self):
        own = REAL_F_LOG.replace("KCMD: match in pid:1378 keyboardFocus", f"KCMD: match in pid:{F_APP} keyboardFocus")
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, own))
        self.assertEqual(again, [])
        self.assertIn("This failure stands", reasons[0])

    def test_only_a_match_in_another_processs_keyboard_focus_table_counts(self):
        for replacement in ("KCMD: no match in pid:1378 keyboardFocus",
                            "KCMD: match in pid:1378 systemKeyCommandOverlay",
                            "KCMD: match in pid:1378 somethingElse"):
            with self.subTest(replacement=replacement):
                log = REAL_F_LOG.replace("KCMD: match in pid:1378 keyboardFocus", replacement)
                again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, log))
                self.assertEqual(again, [])
                self.assertIn("no chord the simulator failed to deliver at t = 13.06s", reasons[0])

    def test_the_other_processs_own_table_must_hold_the_pressed_chord(self):
        # Without SpringBoard's registration in the log, or with one that lacks ⌘F, the match line does not show
        # that it was this chord SpringBoard took.
        without_f = REAL_SPRINGBOARD_TABLE.replace(" e, f, g,", " e, g,")
        overlay = REAL_SPRINGBOARD_TABLE.replace("environment: keyboardFocus", "environment: systemKeyCommandOverlay")
        for logs in ((REAL_F_LOG,), (without_f, REAL_F_LOG), (overlay, REAL_F_LOG)):
            with self.subTest(logs=logs[0][:60]):
                again, reasons = self.decide(logs)
                self.assertEqual(again, [])
                self.assertIn("no chord the simulator failed to deliver at t = 13.06s", reasons[0])
        # Its table as it stood at the press counts, not one it registered later.
        later = REAL_SPRINGBOARD_TABLE.replace("2026-11-25 08:23:59.963", "2026-11-25 08:35:41.000")
        self.assertEqual(self.decide((later, REAL_F_LOG))[0], [])
        # Its latest table before the press counts: one that held ⌘F and was then replaced by one without it does not.
        replaced = without_f.replace("2026-11-25 08:23:59.963", "2026-11-25 08:30:00.000")
        self.assertEqual(self.decide((REAL_SPRINGBOARD_TABLE, replaced, REAL_F_LOG))[0], [])
        # ⌃⌘S is looked up under {cmd, ctrl}: a table with s only under ⌘ does not hold it.
        ctrl = REAL_SPRINGBOARD_TABLE.replace('cmd|ctrl: (s, " ")', 'cmd|ctrl: (" ")')
        self.assertEqual(self.decide((ctrl, REAL_S_LOG), (REAL_S_TIMES,))[0], [])

    def test_a_process_that_connected_as_the_app_is_not_another_process(self):
        # An earlier launch of the app (pid 32425 connected at 08:35:02.165, before this test) is not SpringBoard,
        # even when its table holds the chord.
        earlier = (line_at("2026-11-25 08:35:02.165", "Connection added: IOHIDEventSystemConnection uuid:92A9CABA-0D88-"
                           "43B3-8D3F-6736F42CBCEF pid:32425 process:Thorbis type:Passive entitlements:0x0", "default")
                   + registration_block(REAL_F_LOG, F_REGISTERED_AT).replace(F_REGISTERED_AT, "2026-11-25 08:35:03.000")
                   .replace("pid:33422", "pid:32425"))
        log = REAL_F_LOG.replace("KCMD: match in pid:1378 keyboardFocus", "KCMD: match in pid:32425 keyboardFocus")
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, earlier, log))
        self.assertEqual(again, [])
        self.assertIn("This failure stands", reasons[0])

    def test_a_key_sequence_sent_to_the_app_for_a_chord_stands(self):
        sequence = (f"sequence starting with Keyboard event: <sq: 0x600002934af0; (<keyboardFocus; display: builtin; "
                    f"pid: {F_APP}; token: 0xBBC770A7>)>")
        for stamp in ("2026-11-25 08:35:35.692", "2026-11-25 08:35:40.935"):
            with self.subTest(stamp=stamp):
                again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_LOG,
                                              line_at(stamp, sequence, "EventDelivery")))
                self.assertEqual(again, [])
                self.assertIn("This failure stands", reasons[0])
        # And to another process: as before, that stands too.
        to_springboard = sequence.replace(f"pid: {F_APP};", "pid: 1378;")
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_LOG,
                                      line_at("2026-11-25 08:35:35.692", to_springboard, "EventDelivery")))
        self.assertEqual(again, [])
        self.assertIn("another process than the app", reasons[0])

    def test_one_chord_in_this_form_and_one_with_neither_form_stands(self):
        first_gone = REAL_F_LOG.replace(F_FIRST_TAKEN, "")
        second_gone = REAL_F_LOG.replace(F_TAKEN, "")
        for log, at_ in ((first_gone, "13.06"), (second_gone, "18.24")):
            with self.subTest(at=at_):
                again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, log))
                self.assertEqual(again, [])
                self.assertIn(f"no chord the simulator failed to deliver at t = {at_}s", reasons[0])

    def test_one_match_does_not_stand_for_two_chords(self):
        # Two presses close enough for their windows to overlap, and one SpringBoard match between them.
        steps = REAL_F_TIMES.replace("18.24 Type 'f'", "14.00 Type 'f'").replace("19.28 Waiting", "14.50 Waiting")
        steps = steps.replace("18.02 Collecting", "13.90 Collecting")
        one = REAL_F_LOG.replace(F_TAKEN, "").replace(F_REGISTERED_AT, "2026-11-25 08:35:37.500")
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, one), (steps,))
        self.assertEqual(again, [])
        self.assertIn("no chord the simulator failed to deliver at t = 14.00s", reasons[0])

    def test_a_cache_miss_alone_is_not_proof(self):
        def miss(stamp):
            return (line_at(stamp, "KCMD: no match in pid:1378 keyboardFocus")
                    + line_at(stamp, "cache miss for Keyboard event"))
        missed = REAL_F_LOG.replace(F_FIRST_TAKEN, miss("2026-11-25 08:35:35.691")).replace(
            F_TAKEN, miss("2026-11-25 08:35:40.934"))
        self.assertEqual(missed.count("cache miss for Keyboard event"), 2)
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, missed))
        self.assertEqual(again, [])
        self.assertIn("did not log a cache miss and a bare key", reasons[0])

    def test_two_app_connections_before_the_first_chord_stand(self):
        second = line_at("2026-11-25 08:35:30.000", "Connection added: IOHIDEventSystemConnection uuid:0 pid:33500 "
                         "process:Thorbis type:Passive entitlements:0x0", "default")
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_LOG, second))
        self.assertEqual(again, [])
        self.assertIn("2 connections", reasons[0])

    def test_a_second_failed_test_in_the_shard_that_does_not_qualify_stops_every_rerun(self):
        rows = real_rows(REAL_F_TIMES, REAL_S_TIMES)
        tapped = session(case(B, "failed", 1))[1:-1]
        rows = rows[:-1] + tapped + [(9999999999.0, "executed", "3 3 0")]
        again, reasons = taps.decide(rows, [], keys=real_keys(REAL_SPRINGBOARD_TABLE, REAL_F_LOG, REAL_S_LOG))
        self.assertEqual(again, [])
        self.assertIn("did not deliver the key chord it failed on", reasons[0])
        self.assertIn("did not deliver the key chord it failed on", reasons[1])
        self.assertIn("no cancelled tap", reasons[2])
        self.assertIn("Not every failed test", reasons[-1])
        # With the cancelled tap in the log all three are run again; the limit of 3 still holds.
        self.assertEqual(taps.decide(rows, [at(1, TAP)], keys=real_keys(REAL_SPRINGBOARD_TABLE, REAL_F_LOG,
                                                                        REAL_S_LOG))[0], [F, S, B])
        self.assertEqual(taps.decide(rows, [at(1, TAP)], limit=2,
                                     keys=real_keys(REAL_SPRINGBOARD_TABLE, REAL_F_LOG, REAL_S_LOG))[0], [])

    def test_the_bare_key_form_decides_exactly_as_before(self):
        again, reasons = taps.decide(session(case(A, "passed", 0), chord_case()), [], keys=chord_keys())
        self.assertEqual(again, [K])
        self.assertEqual(reasons, [
            f"{K}: the simulator did not deliver the key chord it failed on: at t = 17.11s (Type 'k' key with "
            f"modifiers '⌘' (0x10)) backboardd sent the app (pid 15145) the bare key at "
            f"{taps.clock(at(1, 17.405) + 3 * 0.0002)}, as it did for every chord of the test, before the app had "
            f"registered any key commands; the app registered that chord at {taps.clock(at(1, REGISTERED))}, and the "
            "test failed on the wait that came next."])

    def test_a_bare_key_and_a_springboard_match_in_one_test_stand(self):
        # One press reached the app as the bare letter (backboardd found no match in SpringBoard's table for it),
        # the other matched in that same table. No real log shows this; the log contradicts itself, so it proves
        # nothing, in either order.
        bare = (line_at("2026-11-25 08:35:35.691", "KCMD: no match in pid:1378 keyboardFocus")
                + line_at("2026-11-25 08:35:35.691", "cache miss for Keyboard event")
                + line_at("2026-11-25 08:35:35.692", "sequence starting with Keyboard event: <sq: 0x600002934af0; "
                          f"(<keyboardFocus; display: builtin; pid: {F_APP}; token: 0xBBC770A7>)>", "EventDelivery"))
        mixed = REAL_F_LOG.replace(F_FIRST_TAKEN, bare)
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, mixed))
        self.assertEqual(again, [])
        self.assertIn("at t = 18.24s its chords had taken both routes", reasons[0])
        # The other way round (taken first, bare key last).
        second = bare.replace("08:35:35.69", "08:35:40.93")
        reverse = REAL_F_LOG.replace(F_TAKEN, second)
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, reverse))
        self.assertEqual(again, [])
        self.assertIn("at t = 18.24s its chords had taken both routes", reasons[0])
        # A first press that logged both a SpringBoard match and a bare key counts as a bare key, so with a second
        # press taken by SpringBoard the test still took both routes.
        both = REAL_F_LOG.replace(F_FIRST_TAKEN, F_FIRST_TAKEN + bare.split("\n", 1)[1])
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, both))
        self.assertEqual(again, [])
        self.assertIn("both routes", reasons[0])

    def test_three_chords_bare_then_taken_twice_stand(self):
        steps = REAL_F_TIMES.replace(
            "1795595746.802\terror",
            "1795595746.100\tstep\t23.80 Type 'f' key with modifiers '⌘' (0x10)\n"
            "1795595746.200\tstep\t23.90 Waiting 4.0s for \"search-field\" TextField to exist\n"
            "1795595746.802\terror").replace("19.28 Waiting", "19.28 Collecting")
        third = (line_at("2026-11-25 08:35:46.000", "KCMD: no match in pid:1378 systemKeyCommandOverlay")
                 + line_at("2026-11-25 08:35:46.000", "KCMD: match in pid:1378 keyboardFocus"))
        bare = (line_at("2026-11-25 08:35:35.691", "KCMD: no match in pid:1378 keyboardFocus")
                + line_at("2026-11-25 08:35:35.691", "cache miss for Keyboard event")
                + line_at("2026-11-25 08:35:35.692", "sequence starting with Keyboard event: <sq: 0x600002934af0; "
                          f"(<keyboardFocus; display: builtin; pid: {F_APP}; token: 0xBBC770A7>)>", "EventDelivery"))
        log = REAL_F_LOG.replace(F_FIRST_TAKEN, bare).replace(F_REGISTERED_AT, "2026-11-25 08:35:46.300")
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, log + third), (steps,))
        self.assertEqual(again, [])
        self.assertIn("This failure stands", reasons[0])

    def test_only_springboards_own_table_counts(self):
        # Review round 1, A5: another process (here pid 6682, or a new pid 4242) whose keyboardFocus table holds ⌘F
        # matches the press, as when another app is in front. It never registered a system overlay table, so it is
        # not SpringBoard, whatever the overlay line names.
        other = REAL_SPRINGBOARD_TABLE.split("2026-11-25 08:23:59.963", 2)[2].join(["2026-11-25 08:30:00.000", ""])
        for pid in ("6682", "4242"):
            table = other.replace("pid:1378", f"pid:{pid}")
            for overlay_too in (False, True):
                with self.subTest(pid=pid, overlay_too=overlay_too):
                    log = REAL_F_LOG.replace("KCMD: match in pid:1378 keyboardFocus", f"KCMD: match in pid:{pid} keyboardFocus")
                    if overlay_too:
                        log = log.replace("KCMD: no match in pid:1378 systemKeyCommandOverlay",
                                          f"KCMD: no match in pid:{pid} systemKeyCommandOverlay")
                    again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, table, log))
                    self.assertEqual(again, [])
                    self.assertIn("no chord the simulator failed to deliver at t = 13.06s", reasons[0])
        # The overlay refusal must be the record right before the match, at the same instant, in the same pid.
        for old, new in (("2026-11-25 08:35:40.934 Df backboardd[1400:15c15] [com.apple.BackBoard:EventDeliveryMatching] "
                          "KCMD: no match in pid:1378 systemKeyCommandOverlay\n", ""),
                         ("08:35:40.934 Df backboardd[1400:15c15] [com.apple.BackBoard:EventDeliveryMatching] KCMD: no",
                          "08:35:40.900 Df backboardd[1400:15c15] [com.apple.BackBoard:EventDeliveryMatching] KCMD: no")):
            with self.subTest(old=old[-50:]):
                again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_LOG.replace(old, new)))
                self.assertEqual(again, [])
                self.assertIn("no chord the simulator failed to deliver at t = 18.24s", reasons[0])
        # Without SpringBoard's overlay registration in the log, the match is not shown to be SpringBoard's.
        without_overlay = REAL_SPRINGBOARD_TABLE.replace(REAL_SPRINGBOARD_OVERLAY, "")
        self.assertEqual(self.decide((without_overlay, REAL_F_LOG))[0], [])

    def test_every_chord_is_taken_by_the_same_process(self):
        twin = REAL_SPRINGBOARD_TABLE.replace("pid:1378", "pid:1379")
        log = REAL_F_LOG.replace(F_TAKEN, F_TAKEN.replace("pid:1378", "pid:1379")).replace(
            "08:35:40.934 Df backboardd[1400:15c15] [com.apple.BackBoard:EventDeliveryMatching] KCMD: no match in pid:1378",
            "08:35:40.934 Df backboardd[1400:15c15] [com.apple.BackBoard:EventDeliveryMatching] KCMD: no match in pid:1379")
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, twin, log))
        self.assertEqual(again, [])
        self.assertIn("no chord the simulator failed to deliver at t = 18.24s", reasons[0])

    def test_springboard_refusing_a_key_in_its_table_during_the_test_stands(self):
        # Review round 1: backboardd found no command for some key in SpringBoard's keyboardFocus table while the test
        # ran. Then it is not shown that SpringBoard's table took every chord.
        for stamp in ("2026-11-25 08:35:30.000", "2026-11-25 08:35:44.000"):
            with self.subTest(stamp=stamp):
                again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_LOG,
                                              line_at(stamp, "KCMD: no match in pid:1378 keyboardFocus")))
                self.assertEqual(again, [])
                self.assertIn("also found no command for a key in the table of pid 1378", reasons[0])

    def test_a_key_sent_on_after_the_first_chord_stands(self):
        # Review round 1, A4e: a key sequence outside the chords' windows but during the test, to the app or not.
        for pid in (F_APP, 1378):
            with self.subTest(pid=pid):
                sequence = ("sequence starting with Keyboard event: <sq: 0x600002934af0; (<keyboardFocus; display: "
                            f"builtin; pid: {pid}; token: 0xBBC770A7>)>")
                again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_LOG,
                                              line_at("2026-11-25 08:35:43.000", sequence, "EventDelivery")))
                self.assertEqual(again, [])
                self.assertIn("sent a key on at", reasons[0])

    def test_the_apps_registration_must_follow_the_last_match_within_a_second(self):
        # Review round 1, A2: a registration 4 s after the last press, or after the failed assertion, is not the
        # app answering a keyboard that came to it. Observed gaps: 0.47 s and 0.33 s.
        for stamp in ("2026-11-25 08:35:42.034", "2026-11-25 08:35:45.000", "2026-11-25 08:35:47.000"):
            with self.subTest(stamp=stamp):
                again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_LOG.replace(F_REGISTERED_AT, stamp)))
                self.assertEqual(again, [])
                self.assertIn("more than 1.0 s after its last chord was taken", reasons[0])
        self.assertEqual(self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_LOG.replace(F_REGISTERED_AT,
                                                                                "2026-11-25 08:35:41.834")))[0], [F])

    def test_the_apps_registration_must_be_for_its_keyboard_focus(self):
        # Review round 1: the app's later registration in another environment does not show it declares the chord.
        log = REAL_F_LOG.replace("pid:33422 environment: keyboardFocus", "pid:33422 environment: systemKeyCommandOverlay")
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, log))
        self.assertEqual(again, [])
        self.assertIn("do not include", reasons[0])

    def test_the_last_of_two_matches_in_the_last_window_counts(self):
        # Review round 1: two SpringBoard matches in the last chord's window with the app's registration between
        # them. The later match is the chord's, so the app had registered before it.
        extra = (line_at("2026-11-25 08:35:41.600", "KCMD: no match in pid:1378 systemKeyCommandOverlay")
                 + line_at("2026-11-25 08:35:41.600", "KCMD: match in pid:1378 keyboardFocus"))
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_LOG, extra))
        self.assertEqual(again, [])
        self.assertIn("before its last chord", reasons[0])

    def test_the_real_command_k_test_whose_second_press_reached_the_app_stands(self):
        # Lines 345-364 of the same log: ⌘K's first press reached the app as a bare 'k', the app registered, and the
        # second press matched in the app's own table. Had that test failed after it, the failure would stand.
        log = (
            "2026-11-25 08:36:17.428 Df backboardd[1400:16a94] [com.apple.iohid:default] Connection added: IOHIDEventSystemConnection uuid:4265FB9F-AECF-44F1-B078-F6F319F06317 pid:34161 process:Thorbis type:Passive entitlements:0x0 caller:BackBoardServices: ___getHIDEventSystemClient_block_invoke + 276 attributes:{\n"
            "2026-11-25 08:36:27.721 Df backboardd[1400:17e21] [com.apple.BackBoard:EventDeliveryMatching] KCMD: no match in pid:1378 systemKeyCommandOverlay\n"
            "2026-11-25 08:36:27.721 Df backboardd[1400:17e21] [com.apple.BackBoard:EventDeliveryMatching] KCMD: no match in pid:1378 keyboardFocus\n"
            "2026-11-25 08:36:27.721 Df backboardd[1400:17e21] [com.apple.BackBoard:EventDeliveryMatching] cache miss for Keyboard event\n"
            "2026-11-25 08:36:27.722 Df backboardd[1400:17e21] [com.apple.BackBoard:EventDelivery] sequence starting with Keyboard event: <sq: 0x600002934af0; (<keyboardFocus; display: builtin; pid: 34161; token: 0xC17DB904>)>\n"
            + registration_block(REAL_F_LOG, F_REGISTERED_AT).replace(F_REGISTERED_AT, "2026-11-25 08:36:28.325")
            .replace("pid:33422", "pid:34161")
            + "2026-11-25 08:36:33.267 Df backboardd[1400:189dd] [com.apple.BackBoard:EventDeliveryMatching] KCMD: no match in pid:1378 systemKeyCommandOverlay\n"
            "2026-11-25 08:36:33.267 Df backboardd[1400:189dd] [com.apple.BackBoard:EventDeliveryMatching] KCMD: match in pid:34161 keyboardFocus\n")
        times = "\n".join([
            "1795595747.075\tstarted\tThorbisUITests/KeyboardShortcutUITests/testCommandKOpensSearch",
            "1795595747.075\tbegin\t2026-11-25 08:35:47.037",
            "1795595779.945\tstep\t32.90 Waiting 30.0s for StaticText (First Match) to exist",
            "1795595785.998\tstep\t38.76 Waiting 30.0s for Button (First Match) to exist",
            "1795595787.012\tstep\t39.92 Checking existence of `\"search-field\" TextField`",
            "1795595787.298\tstep\t40.24 Type 'k' key with modifiers '⌘' (0x10)",
            "1795595788.675\tstep\t41.60 Waiting 4.0s for \"search-field\" TextField to exist",
            "1795595792.857\tstep\t45.82 Collecting debug information to assist test failure triage",
            "1795595793.066\tstep\t46.01 Type 'k' key with modifiers '⌘' (0x10)",
            "1795595795.917\tstep\t48.87 Waiting 4.0s for \"search-field\" TextField to exist",
            "1795595800.000\terror\tThorbisUITests/KeyboardShortcutUITests/testCommandKOpensSearch XCTAssertTrue failed - ⌘K opens Search",
            "1795595801.888\tfailed\tThorbisUITests/KeyboardShortcutUITests/testCommandKOpensSearch 54.842"])
        again, reasons = taps.decide(real_rows(times), [], keys=real_keys(REAL_SPRINGBOARD_TABLE, log))
        self.assertEqual(again, [])
        self.assertIn("no chord the simulator failed to deliver at t = 46.01s", reasons[0])


# Review round 2. The real failures' last steps: the wait after the last chord began at 19.28 s (⌘F) and 18.70 s
# (⌃⌘S), each "Waiting 4.0s", and XCTest wrote "Collecting debug information" at 23.51 s and 23.07 s, after the
# wait had run out, before the failure. In the job's log (ipad1.log) each of its ten such notices follows a
# "Waiting <N>s" step at least N seconds later; the one assertion that failed without a "Waiting" step in run
# 45558161330, shard 3, has none before it.
F_NOTICE = "1795595745.809\tstep\t23.51 Collecting debug information to assist test failure triage\n"
F_ASSERT = "1795595746.802\terror\tThorbisUITests/KeyboardShortcutUITests/testCommandFOpensSearch XCTAssertTrue failed - ⌘F opens Search\n"
# Review round 2, case B7c: the last wait passed at once, and a different assertion failed 0.6 s after it began.
F_OTHER_ASSERT = ("1795595741.900\terror\tThorbisUITests/KeyboardShortcutUITests/testCommandFOpensSearch XCTAssertEqual "
                  'failed: ("3") is not equal to ("4") - job count\n')
F_PASSED_WAIT_TIMES = REAL_F_TIMES.replace(F_NOTICE + F_ASSERT, F_OTHER_ASSERT)


def bare_route(stamp, pid=F_APP):
    """What backboardd logs for a press SpringBoard's table has no command for: the bare key goes to `pid`."""
    later = stamp[:-1] + str(int(stamp[-1]) + 1)
    return (line_at(stamp, "KCMD: no match in pid:1378 keyboardFocus") + line_at(stamp, "cache miss for Keyboard event")
            + line_at(later, "sequence starting with Keyboard event: <sq: 0x600002934af0; (<keyboardFocus; display: "
                             f"builtin; pid: {pid}; token: 0xBBC770A7>)>", "EventDelivery"))


# Review round 2, case N8: the real ⌘F lines with each press sent to the app as a bare key (the first form).
REAL_F_BARE_LOG = REAL_F_LOG.replace(F_FIRST_TAKEN, bare_route("2026-11-25 08:35:35.691")).replace(
    F_TAKEN, bare_route("2026-11-25 08:35:40.934"))
# Review round 2, cases B5a and B10b: another pid that registered SpringBoard's two tables, named on both lines.
OTHER_TABLES = REAL_SPRINGBOARD_TABLE.replace("2026-11-25 08:23:59.963", "2026-11-25 08:35:30.000")


# What each route's reason says.
TAKEN_ROUTE = "matched it in the system's own key commands (pid 1378), not the app's (pid 33422)"
BARE_ROUTE = "backboardd sent the app (pid 33422) the bare key"
NOT_RAN_OUT = "XCTest's record does not show that its last wait"


def taken_by(pid, log=REAL_F_LOG):
    return log.replace("pid:1378 ", f"pid:{pid} ").replace("pid:1378\n", f"pid:{pid}\n")


class LastWaitAndSystemProcessTests(unittest.TestCase):
    """Review round 2: the wait after the last chord must have run out (both forms), and the process that took the
    chord must be the only one in the log that registered the system's own key commands."""

    def decide(self, logs=(REAL_SPRINGBOARD_TABLE, REAL_F_LOG), times=(REAL_F_TIMES,)):
        return taps.decide(real_rows(*times), [], keys=real_keys(*logs))

    def assertRunAgain(self, result, route, tests=(F,)):
        """`result` runs `tests` again, and its first reason names `route` (TAKEN_ROUTE or BARE_ROUTE)."""
        again, reasons = result
        self.assertEqual(again, list(tests), reasons)
        self.assertIn(f"{tests[0]}: the simulator did not deliver the key chord it failed on", reasons[0])
        self.assertIn(route, reasons[0])

    def assertStands(self, result, reason):
        again, reasons = result
        self.assertEqual(again, [], reasons)
        self.assertIn(reason, reasons[0])
        self.assertIn("This failure stands", reasons[0])

    def test_the_fixtures_change_only_what_they_name(self):
        self.assertIn(F_NOTICE + F_ASSERT, REAL_F_TIMES)
        self.assertNotIn("Collecting debug information to assist test failure triage\n1795595746", F_PASSED_WAIT_TIMES)
        self.assertEqual(REAL_F_BARE_LOG.count("cache miss for Keyboard event"), 2)
        self.assertNotIn("KCMD: match in pid:1378", REAL_F_BARE_LOG)

    def test_the_real_failures_waits_ran_out_and_they_are_run_again(self):
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_LOG, REAL_S_LOG), (REAL_F_TIMES, REAL_S_TIMES))
        self.assertEqual(again, [F, S], reasons)
        # The same real steps with the chords sent as bare keys: the first form, also run again.
        self.assertRunAgain(self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_BARE_LOG)), BARE_ROUTE)

    def test_a_last_wait_that_passed_then_another_failed_assertion_stands_in_the_second_form(self):
        # B7c: SpringBoard took both presses, the app registered, the wait found the field and a later assertion
        # failed. Every other proof is there; only XCTest's notice that the wait ran out is not.
        again, reasons = self.decide(times=(F_PASSED_WAIT_TIMES,))
        self.assertEqual(again, [])
        self.assertIn(f"{F}: XCTest's record does not show that its last wait", reasons[0])
        self.assertIn("This failure stands", reasons[0])

    def test_a_last_wait_that_passed_then_another_failed_assertion_stands_in_the_bare_key_form(self):
        # N8: the same on the real lines turned into the first form, and on the ⌘K fixture of run 45148171838.
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_BARE_LOG), (F_PASSED_WAIT_TIMES,))
        self.assertEqual(again, [])
        self.assertIn("does not show that its last wait", reasons[0])
        passed = CHORD_STEPS[:-1]
        again, reasons = taps.decide(session(chord_case(steps=passed, error='XCTAssertEqual failed: ("3") is not '
                                                                            'equal to ("4") - job count')),
                                     [], keys=chord_keys())
        self.assertEqual(again, [])
        self.assertIn(f"{K}: XCTest's record does not show that its last wait", reasons[0])

    def test_in_the_second_form_the_notice_must_come_no_sooner_than_the_wait_could_run_out(self):
        # The last wait began at 19.28 s with 4.0 s to run: a notice at 23.27 s is too soon, one at 23.28 s is not.
        for offset, expected in (("23.27", []), ("23.28", [F]), ("19.30", [])):
            with self.subTest(offset=offset):
                times = REAL_F_TIMES.replace("23.51 Collecting", f"{offset} Collecting")
                if expected:
                    self.assertRunAgain(self.decide(times=(times,)), TAKEN_ROUTE)
                else:
                    self.assertStands(self.decide(times=(times,)), NOT_RAN_OUT)
        # The first wait's notice (18.02 s) is before the last wait, so it does not count for it, in either form.
        for logs in ((REAL_SPRINGBOARD_TABLE, REAL_F_LOG), (REAL_SPRINGBOARD_TABLE, REAL_F_BARE_LOG)):
            again, reasons = self.decide(logs, (REAL_F_TIMES.replace(F_NOTICE, ""),))
            self.assertEqual(again, [])
            self.assertIn("does not show that its last wait", reasons[0])

    def test_in_the_bare_key_form_a_notice_no_sooner_than_the_last_wait_began_counts(self):
        # The bare-key form keeps one thing from before: scripts/tests/test_ci_run_ui_tests.py (unchanged since HEAD)
        # writes its lost chords with the notice straight after the wait, as a stand-in that does not wait, and
        # expects them to be run again. So in this form the notice must follow the last wait and come no sooner than
        # the wait began, but not N seconds after it.
        for offset in ("23.27", "19.28"):
            with self.subTest(offset=offset):
                times = REAL_F_TIMES.replace("23.51 Collecting", f"{offset} Collecting")
                self.assertRunAgain(self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_BARE_LOG), (times,)), BARE_ROUTE)
        steps = CHORD_STEPS[:-1] + ((17.74, CHORD_STEPS[-1][1]),)
        again, reasons = taps.decide(session(chord_case(steps=steps)), [], keys=chord_keys())
        self.assertEqual(again, [K], reasons)
        self.assertIn("the bare key", reasons[0])
        # Review round 3, C09 and C13: a notice whose offset is earlier than the last wait's own does not count,
        # wherever it is written (the first wait's 18.02 s copied after the last wait, or 19.27 s).
        for offset in ("18.02", "19.27"):
            with self.subTest(offset=offset):
                times = REAL_F_TIMES.replace("23.51 Collecting", f"{offset} Collecting")
                self.assertStands(self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_BARE_LOG), (times,)), NOT_RAN_OUT)

    def test_only_xctests_collecting_notice_counts(self):
        notice = "App animations complete notification not received, will attempt to continue."
        times = REAL_F_TIMES.replace("23.51 Collecting debug information to assist test failure triage",
                                     f"23.51 {notice}")
        self.assertStands(self.decide(times=(times,)), NOT_RAN_OUT)
        self.assertStands(self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_BARE_LOG), (times,)), NOT_RAN_OUT)
        # Both notices after the last wait: the Collecting one still counts.
        both = REAL_F_TIMES.replace(F_NOTICE, F_NOTICE.replace("23.51 Collecting debug information to assist test "
                                                               "failure triage", f"23.40 {notice}") + F_NOTICE)
        self.assertRunAgain(self.decide(times=(both,)), TAKEN_ROUTE)
        self.assertRunAgain(self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_BARE_LOG), (both,)), BARE_ROUTE)

    def test_a_wait_whose_time_cannot_be_read_stands(self):
        for wait in ('Waiting for "search-field" TextField to exist', "Waiting 4.0 s for \"search-field\" TextField",
                     "Waiting s for \"search-field\" TextField to exist"):
            with self.subTest(wait=wait):
                times = REAL_F_TIMES.replace('19.28 Waiting 4.0s for "search-field" TextField to exist', f"19.28 {wait}")
                self.assertNotEqual(times, REAL_F_TIMES)
                for logs in ((REAL_SPRINGBOARD_TABLE, REAL_F_LOG), (REAL_SPRINGBOARD_TABLE, REAL_F_BARE_LOG)):
                    again, reasons = self.decide(logs, (times,))
                    self.assertEqual(again, [])
                    self.assertIn("does not show that its last wait", reasons[0])
        # A whole number of seconds is read too.
        times = REAL_F_TIMES.replace('19.28 Waiting 4.0s for', "19.28 Waiting 4s for")
        self.assertRunAgain(self.decide(times=(times,)), TAKEN_ROUTE)

    def test_a_second_process_with_the_systems_own_table_stands(self):
        # B5a: pid 4242 registered both of SpringBoard's tables and is named on both lines at each press.
        for stamp in ("2026-11-25 08:35:30.000", "2026-11-25 08:20:00.000"):
            with self.subTest(stamp=stamp):
                tables = REAL_SPRINGBOARD_TABLE.replace("2026-11-25 08:23:59.963", stamp).replace("pid:1378", "pid:4242")
                again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, tables, taken_by(4242)))
                self.assertEqual(again, [])
                self.assertIn(f"{F}: more than one process registered the system's own key commands (pids 1378, "
                              "4242)", reasons[0])
        # And when 1378 took the presses but another pid registered an overlay table too, at any time in the log.
        for stamp in ("2026-11-25 08:35:30.000", "2026-11-25 08:50:00.000"):
            with self.subTest(taker=1378, stamp=stamp):
                tables = OTHER_TABLES.replace("2026-11-25 08:35:30.000", stamp).replace("pid:1378", "pid:4242")
                again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, tables, REAL_F_LOG))
                self.assertEqual(again, [])
                self.assertIn("more than one process registered the system's own key commands (pids 1378, 4242)",
                              reasons[0])
        # A keyboardFocus table alone, without an overlay table, does not make a process a system one.
        focus_only = OTHER_TABLES.replace(REAL_SPRINGBOARD_OVERLAY.replace("2026-11-25 08:23:59.963",
                                                                           "2026-11-25 08:35:30.000"), "")
        self.assertNotIn("systemKeyCommandOverlay", focus_only)
        self.assertRunAgain(self.decide((REAL_SPRINGBOARD_TABLE, focus_only.replace("pid:1378", "pid:4242"),
                                         REAL_F_LOG)), TAKEN_ROUTE)

    def test_springboard_restarted_under_a_new_pid_stands(self):
        # B10b: SpringBoard came back as pid 5555, registered both tables again, and took both presses.
        again, reasons = self.decide((REAL_SPRINGBOARD_TABLE, OTHER_TABLES.replace("pid:1378", "pid:5555"),
                                      taken_by(5555)))
        self.assertEqual(again, [])
        self.assertIn("(pids 1378, 5555)", reasons[0])
        # With only the new pid's tables in the log it is the one system process, and the presses are run again.
        self.assertRunAgain(self.decide((OTHER_TABLES.replace("pid:1378", "pid:5555"), taken_by(5555))),
                            TAKEN_ROUTE.replace("1378", "5555"))

    def test_an_earlier_launch_of_the_app_with_the_systems_tables_is_not_springboard(self):
        # Review round 2 (mut-r2/extra_launches.py): an earlier Thorbis launch, pid 32425, registered both tables
        # holding ⌘F and backboardd refused and matched the presses in it. With SpringBoard's tables in the log there
        # are two system processes; without them 32425 is the only one, and it is still not SpringBoard, because it
        # connected as the app.
        launch = line_at("2026-11-25 08:35:02.165", "Connection added: IOHIDEventSystemConnection uuid:0 pid:32425 "
                         "process:Thorbis type:Passive entitlements:0x0", "default")
        tables = OTHER_TABLES.replace("pid:1378", "pid:32425").replace("2026-11-25 08:35:30.000",
                                                                       "2026-11-25 08:35:03.000")
        log = taken_by(32425)
        self.assertNotIn("pid:1378", log)
        for logs in ((REAL_SPRINGBOARD_TABLE, launch, tables, log), (launch, tables, log)):
            with self.subTest(with_springboard=len(logs) == 4):
                self.assertStands(self.decide(logs), "no chord the simulator failed to deliver at t = 13.06s")
        # The same tables under a pid that never connected as Thorbis are taken for SpringBoard's.
        self.assertRunAgain(self.decide((tables.replace("pid:32425", "pid:5555"), taken_by(5555))),
                            TAKEN_ROUTE.replace("1378", "5555"))



# Review round 3, C32: three ⌘F presses, each matched in pid 1378's table. The wait after the middle press, at 18.10 s,
# passed (no notice after it), so that press did its job; the waits after the first and last ran out.
F_FIRST_NOTICE = "1795595740.324\tstep\t18.02 Collecting debug information to assist test failure triage\n"
F_THREE_TIMES = REAL_F_TIMES.replace(F_FIRST_NOTICE, F_FIRST_NOTICE
                                     + "1795595740.370\tstep\t18.05 Type 'f' key with modifiers '⌘' (0x10)\n"
                                     + "1795595740.420\tstep\t18.10 Waiting 4.0s for \"search-field\" TextField to exist\n")
F_MIDDLE_TAKEN = (line_at("2026-11-25 08:35:40.600", "KCMD: no match in pid:1378 systemKeyCommandOverlay")
                  + line_at("2026-11-25 08:35:40.600", "KCMD: match in pid:1378 keyboardFocus"))


class EveryChordAndTheSystemsRecordTests(unittest.TestCase):
    """Review round 3: in the second form the wait after EVERY chord ran out; any overlay registration counts as a
    system process; the record before each match is the overlay refusal in that pid; and no key is sent on between
    the presses."""

    decide = LastWaitAndSystemProcessTests.decide
    assertRunAgain = LastWaitAndSystemProcessTests.assertRunAgain
    assertStands = LastWaitAndSystemProcessTests.assertStands

    def test_the_three_chord_fixture_changes_only_what_it_names(self):
        self.assertEqual(F_THREE_TIMES.count("Type 'f' key"), 3)
        self.assertEqual(F_THREE_TIMES.count("Collecting debug information"), 2)
        self.assertEqual(F_THREE_TIMES.replace("1795595740.370\tstep\t18.05 Type 'f' key with modifiers '⌘' (0x10)\n"
                                               "1795595740.420\tstep\t18.10 Waiting 4.0s for \"search-field\" TextField "
                                               "to exist\n", ""), REAL_F_TIMES)

    def test_a_wait_that_passed_after_an_earlier_chord_stands_in_the_second_form(self):
        # C32: the middle press's wait passed. Every other proof is there, so the reason names that press.
        self.assertStands(self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_LOG, F_MIDDLE_TAKEN), (F_THREE_TIMES,)),
                          f"{F}: XCTest's record does not show that the wait after its chord at t = 18.05s ran out")
        # The real two presses with the first wait's notice gone, or 3.99 s after that wait began (13.75 s + 4.0 s).
        for first in ("", F_FIRST_NOTICE.replace("18.02 Collecting", "17.74 Collecting")):
            with self.subTest(first=first[15:30]):
                self.assertStands(self.decide(times=(REAL_F_TIMES.replace(F_FIRST_NOTICE, first),)),
                                  "the wait after its chord at t = 13.06s ran out")
        # The step after the first chord is not a wait.
        checking = REAL_F_TIMES.replace('13.75 Waiting 4.0s for "search-field" TextField to exist',
                                        '13.75 Checking existence of `"search-field" TextField`')
        self.assertStands(self.decide(times=(checking,)), "the wait after its chord at t = 13.06s ran out")
        # With the first wait's notice 4.0 s after it began, both presses are run again.
        self.assertRunAgain(self.decide(times=(REAL_F_TIMES.replace("18.02 Collecting", "17.75 Collecting"),)),
                            TAKEN_ROUTE)

    def test_in_the_bare_key_form_only_the_last_wait_is_checked(self):
        # HEAD's form, as scripts/tests/test_ci_run_ui_tests.py writes it: one notice, after the last wait.
        self.assertRunAgain(self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_BARE_LOG),
                                        (REAL_F_TIMES.replace(F_FIRST_NOTICE, ""),)), BARE_ROUTE)

    def test_an_overlay_registration_that_cannot_be_read_still_counts(self):
        # C22: pid 4242's overlay registration is an empty table on one line, which REGISTERED does not read.
        for message in ("new key command registrations for pid:4242 environment: systemKeyCommandOverlay; "
                        "keyCommands: {}",
                        "new key command registrations for pid:4242 environment: systemKeyCommandOverlay"):
            for stamp in ("2026-11-25 08:35:30.000", "2026-11-25 08:50:00.000"):
                with self.subTest(message=message[-20:], stamp=stamp):
                    extra = line_at(stamp, message, "EventDelivery")
                    self.assertStands(self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_LOG, extra)),
                                      "more than one process registered the system's own key commands (pids 1378, "
                                      "4242)")
        # Another environment for that pid, or the word only as a prefix, is not an overlay registration.
        for message in ("new key command registrations for pid:4242 environment: keyboardFocus; keyCommands: {}",
                        "new key command registrations for pid:4242 environment: systemKeyCommandOverlayX; "
                        "keyCommands: {}"):
            with self.subTest(message=message[50:80]):
                extra = line_at("2026-11-25 08:35:30.000", message, "EventDelivery")
                self.assertRunAgain(self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_LOG, extra)), TAKEN_ROUTE)

    def test_the_record_before_each_match_must_be_the_overlay_refusal_in_that_pid(self):
        # The refusal at both presses replaced by another line at the same instant, or by the same refusal in
        # another pid's overlay.
        for line in ("KCMD: something else entirely", "KCMD: no match in pid:4242 systemKeyCommandOverlay",
                     "KCMD: no match in pid:1378 keyboardFocus"):
            with self.subTest(line=line):
                log = REAL_F_LOG.replace("KCMD: no match in pid:1378 systemKeyCommandOverlay", line)
                self.assertEqual(log.count(line), 2)
                self.assertStands(self.decide((REAL_SPRINGBOARD_TABLE, log)),
                                  f"{F}: no chord the simulator failed to deliver at t = 13.06s")
        # At the last press only.
        log = REAL_F_LOG.replace("08:35:40.934 Df backboardd[1400:15c15] [com.apple.BackBoard:EventDeliveryMatching] "
                                 "KCMD: no match in pid:1378 systemKeyCommandOverlay",
                                 "08:35:40.934 Df backboardd[1400:15c15] [com.apple.BackBoard:EventDeliveryMatching] "
                                 "KCMD: no match in pid:4242 systemKeyCommandOverlay")
        self.assertStands(self.decide((REAL_SPRINGBOARD_TABLE, log)),
                          f"{F}: no chord the simulator failed to deliver at t = 18.24s")

    def test_a_key_sent_on_between_the_presses_stands(self):
        # A key sent to the app (or to SpringBoard) at 08:35:38.000: after the first press's window (to 08:35:36.570)
        # and before the second's (from 08:35:39.560), so neither press's own check sees it.
        for pid in (F_APP, 1378):
            with self.subTest(pid=pid):
                sequence = ("sequence starting with Keyboard event: <sq: 0x600002934af0; (<keyboardFocus; display: "
                            f"builtin; pid: {pid}; token: 0xBBC770A7>)>")
                self.assertStands(self.decide((REAL_SPRINGBOARD_TABLE, REAL_F_LOG,
                                               line_at("2026-11-25 08:35:38.000", sequence, "EventDelivery"))),
                                  f"backboardd sent a key on at {taps.clock(taps.local_seconds('2026-11-25 08:35:38.000'))}"
                                  ", after the test's first chord")

class ReadKeysTests(unittest.TestCase):
    def test_messages_are_joined_and_only_backboardds_count(self):
        with tempfile.TemporaryDirectory() as folder:
            log = os.path.join(folder, "taps.log")
            start = taps.local_seconds("2026-11-23 09:55:31.098")
            Path(log).write_text(
                'Filtering the log data using "process == "backboardd" AND (eventMessage CONTAINS "unknown digitizer" OR ...)"\n'
                "Timestamp               Ty Process[PID:TID]\n"
                + compact(start, registration())
                + compact(start - 5, "cache miss for Keyboard event")
                + "2026-11-23 09:55:32.000 E  backboardd[1580:3fcd5] [com.apple.BackBoard:TouchEvents] *** unknown digitizer <x>\n"
                + "2026-11-23 09:55:33.000 Df Thorbis[15145:1] [app] new key command registrations for pid:15145 a\n"
                + "    a later line of the app's own message\n"
                + compact(start + 3, "KCMD: match in pid:15145 keyboardFocus"))
            records = taps.read_keys(log)
        self.assertEqual([text for _, text in records],
                         ["cache miss for Keyboard event", registration(), "KCMD: match in pid:15145 keyboardFocus"])
        self.assertAlmostEqual(records[1][0], start, places=3)
        self.assertEqual(taps.key_commands(records[1][1])[0:2], (15145, "keyboardFocus"))
        groups = taps.key_commands(records[1][1])[2]
        self.assertIn("k", groups[frozenset({"cmd"})])
        self.assertEqual(groups[frozenset({"cmd", "ctrl"})], {"s", '" "'})
        self.assertIsNone(taps.key_commands("cache miss for Keyboard event"))

    def test_the_command_reads_both_kinds_of_line_from_the_one_log(self):
        with tempfile.TemporaryDirectory() as folder:
            times = os.path.join(folder, "times.tsv")
            log = os.path.join(folder, "taps.log")
            rows = session(case(A, "failed", 0), chord_case(index=1))
            Path(times).write_text("".join(f"{at_:.3f}\t{kind}\t{value}\n" for at_, kind, value in rows))
            Path(log).write_text(
                'Filtering the log data using "process == "backboardd" AND (eventMessage CONTAINS "unknown digitizer" OR ...)"\n'
                + time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(int(at(0, TAP)))) + f".{round(at(0, TAP) % 1 * 1000):03d}"
                + " E  backboardd[5334:3fcd5] [com.apple.BackBoard:TouchEvents] *** unknown digitizer <x>\n"
                + "".join(compact(when, text) for when, text in chord_keys(index=1)))
            result = subprocess.run([sys.executable, str(TOOL), "decide", times, log], capture_output=True, text=True,
                                    stdin=subprocess.DEVNULL, timeout=30)
        self.assertEqual((result.returncode, result.stdout), (0, f"{A}\n{K}\n"), result.stderr)
        self.assertIn("did not deliver the key chord", result.stderr)
        self.assertIn("cancelled the tap", result.stderr)

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
