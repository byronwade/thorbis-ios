"""Tests for scripts/ci_cpu_load.py, the CPU time and load record of the UI test shards (BYR-1841).

Where the formats come from. The recorder's `p` lines are what macOS's `ps -Ao pid=,time=,ucomm=`
prints. This machine is not a Mac, so they are invented here from Apple's source of `/bin/ps`
(apple-oss-distributions/adv_cmds, ps/print.c and ps/keyword.c), since the ps(1) man page gives no
example of either column:
  - `time` is "accumulated CPU time, user + system" (ps.1). print.c `cputime()` prints it with
    `snprintf(obuff, sizeof(obuff), "%3ld:%02ld.%02ld", secs/60, secs%60, psecs)` right-aligned in
    9 columns: minutes, seconds, hundredths, with no hour field, so `  0:12.34`, `  4:05.00`, and
    two hours three minutes as `123:45.67`.
  - `ucomm` is "name to be used for accounting" (ps.1). print.c `ucomm()` prints the kernel's
    `p_comm`, left-justified to MAXCOMLEN (16) columns: `ThorbisUITests-Runner` would be
    `ThorbisUITests-R`.
  - `pid` is right-aligned in 5 columns. With every header given as `=`, "no header line is
    written" (ps.1).
The hour forms `1:02:03`, `01:02:03.50` and `2-03:04:05` are what other ps builds print (procps on
Linux prints `00:00:06`); the reader accepts them too, so a wrong guess about the Mac loses nothing.
The `vm.loadavg` form `{ 688.19 378.03 171.74 }` is the one CI printed (run 45573322329's job log).

The step rows are real: ROWS is what `scripts/ci_cancelled_taps.py stamp` writes for the failed test
of run 45573322329 (iPhone shard 1, phone1.log lines 13585-13627, the test that failed after the
first Customer view opening), made by running stamp's own patterns over those log lines with
GitHub's time for each line standing in for the time stamp read it. Every CPU number is invented.
"""
import calendar
import io
import os
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from contextlib import redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import ci_cpu_load as cpu  # noqa: E402

SCRIPT = ROOT / "scripts" / "ci_cpu_load.py"
TEST = "ThorbisUITests/JobEstimateHandoffUITests/testPackageChangedAfterFailedLinkIsRefused"

ROWS = textwrap.dedent("""\
    1795598087.483\tstarted\tThorbisUITests/JobEstimateHandoffUITests/testPackageChangedAfterFailedLinkIsRefused
    1795598087.500\tbegin\t2026-11-25 09:14:47.246
    1795598087.525\tstep\t0.07 Set Up
    1795598087.537\tstep\t0.07 Open com.thorbis.field
    1795598095.655\tstep\t8.35 Checking existence of `Button (First Match)`
    1795598096.146\tstep\t8.90 Waiting 30.0s for "Job actions" Button to exist
    1795598097.935\tstep\t10.68 Checking existence of `"job-section-money" Button`
    1795598098.413\tstep\t11.15 Waiting 3.0s for Button (First Match) to exist
    1795598099.668\tstep\t12.41 Checking existence of `Button (First Match)`
    1795598099.796\tstep\t12.51 Find the Button (First Match)
    1795598099.893\tstep\t12.64 Checking existence of `NavigationBar (First Match)`
    1795598099.910\tstep\t12.66 Find the NavigationBar (First Match)
    1795598099.991\tstep\t12.74 Find the "job-money-customer-view" Button
    1795598100.219\tstep\t12.96 Find the Target Application 'com.thorbis.field'
    1795598100.332\tstep\t13.06 Waiting 10.0s for "job-money-customer-view" Button to exist
    1795598101.502\tstep\t14.24 Checking existence of `Button (First Match)`
    1795598101.638\tstep\t14.38 Find the Button (First Match)
    1795598101.792\tstep\t14.54 Checking existence of `Window (First Match)`
    1795598101.805\tstep\t14.54 Find the Window (First Match)
    1795598101.815\tstep\t14.56 Find the "job-money-customer-view" Button
    1795598101.963\tstep\t14.70 Tap "job-money-customer-view" Button
    1795598103.023\tstep\t15.77 Waiting 45.0s for "handoff-select-00000000-0000-4000-8000-000000008101" Button to exist
    1795598135.670\terror\tThorbisUITests/JobEstimateHandoffUITests/testPackageChangedAfterFailedLinkIsRefused Failed to get matching snapshots: Timed out while evaluating UI query.
    1795598135.727\tstep\t48.37 Tear Down
    1795598139.980\tfailed\tThorbisUITests/JobEstimateHandoffUITests/testPackageChangedAfterFailedLinkIsRefused 52.607
    """)

T0 = calendar.timegm((2026, 11, 25, 9, 14, 40, 0, 0, 0))      # 09:14:40 UTC
ANCHOR = 1795598087.246                                         # "Start Test at 2026-11-25 09:14:47.246"
HOLD_START = ANCHOR + 15.77                                     # 09:15:03.016
HOLD_LENGTH = 48.37 - 15.77                                     # 32.60 s
HOLD_END = HOLD_START + HOLD_LENGTH


def mac_time(seconds):
    """`time` as macOS ps prints it: "%3ld:%02ld.%02ld" right-aligned in 9 columns."""
    whole = int(seconds)
    hundredths = int(round((seconds - whole) * 100))
    if hundredths == 100:
        whole, hundredths = whole + 1, 0
    return "%9s" % ("%3d:%02d.%02d" % (whole // 60, whole % 60, hundredths))


def ps_line(pid, seconds, name):
    return "%5d %s %-16s" % (pid, mac_time(seconds), name)


def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%03dZ" % int(round(t % 1 * 1000) % 1000)


def grows(base, rate_out, rate_in, start=HOLD_START, end=HOLD_END, origin=T0):
    """CPU seconds at time t for a process using rate_out of a CPU outside [start, end] and rate_in inside."""
    def at(t):
        inside = max(0.0, min(t, end) - start)
        return base + rate_out * (t - origin - inside) + rate_in * inside
    return at


def record_text(app_rate=0.98, *, app=None, skip=(), busy=2.9, first=T0, last=T0 + 65, ncpu=3, extra=()):
    """A record as the recorder writes it, one sample a second from 09:14:40 to 09:15:45 UTC.

    `app` maps a time to [(pid, cpu seconds)] for the Thorbis process(es) listed then; by default
    pid 27095 starts at 12.34 s and uses 20% of a CPU, and app_rate of one during the hold."""
    if app is None:
        cpu_at = grows(12.34, 0.2, app_rate)
        app = lambda t: [(27095, cpu_at(t))]                     # noqa: E731
    runner = grows(41.20, 0.05, 0.03)
    backboardd = grows(129.55, 0.3, 0.6)
    lines = [f"{iso(first - 0.9)}\tstart\tci_cpu_load 1\tinterval 1.0\tps -Ao pid=,time=,ucomm=\tpid 4971",
             f"{iso(first - 0.8)}\tncpu\t{ncpu}\tsysctl 3 | 3 | 3",
             f"{iso(first - 0.7)}\tloadraw\t{{ 688.19 378.03 171.74 }}"]
    count = 0
    for second in range(int(first), int(last) + 1):
        if second in skip:
            continue
        count += 1
        t = second + 0.1
        lines.append(f"{iso(t)}\tsample\t{count}\tload 412.60 378.11 171.80\tps 23 ms\tlines 742\tunread 0\tbusy {busy:.2f}")
        lines.append("p\t" + ps_line(4920, 62.34 + 0.05 * (t - T0), "xcodebuild"))
        lines.append("p\t" + ps_line(6150, runner(t), "ThorbisUITests-R"))
        lines.append("p\t" + ps_line(5334, backboardd(t), "backboardd"))
        for pid, seconds in app(t):
            lines.append("p\t" + ps_line(pid, seconds, "Thorbis"))
    lines.extend(extra)
    lines.append(f"{iso(last + 1)}\tstop\tsamples {count}\tmissed 0\trecorder cpu 0.81\tps cpu 1.30\twall 66.0\twhy signal")
    return "\n".join(lines) + "\n"


class ReaderCase(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(self.dir)]))

    def write(self, name, text):
        path = self.dir / name
        path.write_text(text)
        return str(path)

    def rows_for(self, record, times=ROWS, times_name="test-times.tsv"):
        rec = cpu.read_record(self.write("cpu-load.txt", record))
        steps = cpu.read_steps([self.write(times_name, times)])
        return rec, steps, [cpu.measure(rec, step) for step in steps]

    def long_row(self, record, **kw):
        rec, steps, rows = self.rows_for(record, **kw)
        long_rows = [row for row in rows if row.step.length >= cpu.LONG_STEP]
        self.assertEqual(len(long_rows), 1, [row.step.text for row in long_rows])
        return long_rows[0]

    def read_main(self, record, times=ROWS, times_name="test-times.tsv"):
        out = self.dir / "cpu-load-table.txt"
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            code = cpu.main(["read", self.write("cpu-load.txt", record), self.write(times_name, times), "--out", str(out)])
        self.assertEqual(code, 0)
        self.assertEqual(out.read_text(), buffer.getvalue())
        return buffer.getvalue()


class StepTests(ReaderCase):
    def test_the_anchor_and_the_long_step_come_from_xctests_own_clock(self):
        steps = cpu.read_steps([self.write("test-times.tsv", ROWS)])
        self.assertTrue(all(step.test == TEST and step.run == "first" for step in steps))
        long_steps = [step for step in steps if step.length >= cpu.LONG_STEP]
        self.assertEqual(len(long_steps), 1)
        hold = long_steps[0]
        self.assertAlmostEqual(hold.start - hold.t, ANCHOR, places=3)
        self.assertEqual(time.strftime("%H:%M:%S", time.gmtime(hold.start)) + ".%03d" % round(hold.start % 1 * 1000),
                         "09:15:03.016")
        self.assertAlmostEqual(hold.length, 32.60, places=2)
        self.assertTrue(hold.text.startswith('Waiting 45.0s for "handoff-select-'))
        self.assertTrue(hold.after_door)
        self.assertEqual([step.text for step in steps if step.after_door], [hold.text])
        # The last step ends at the test's own end row: Tear Down, 48.37 to 09:15:39.980.
        self.assertEqual(steps[-1].text, "Tear Down")
        self.assertAlmostEqual(steps[-1].start + steps[-1].length, 1795598139.980, places=3)

    def test_a_rerun_file_names_its_run(self):
        steps = cpu.read_steps([self.write("rerun-1-times.tsv", ROWS)])
        self.assertEqual({step.run for step in steps}, {"rerun-1"})
        table = self.read_main(record_text(), times_name="rerun-1-times.tsv")
        self.assertIn(f"{TEST.split('/', 1)[1]} (rerun-1)", table)


class MeasureTests(ReaderCase):
    def test_a_hold_with_cpu_growing_by_about_its_length_is_working(self):
        row = self.long_row(record_text(app_rate=0.98))
        self.assertAlmostEqual(row.app_cpu, 0.98 * HOLD_LENGTH, delta=0.3)
        self.assertGreaterEqual(row.app_share, 0.95)
        self.assertLessEqual(row.app_share, 1.0)
        self.assertLessEqual(row.app_low, row.app_cpu)
        self.assertGreaterEqual(row.app_high, row.app_cpu)
        self.assertEqual(row.app_pids, [27095])
        self.assertEqual(row.verdict, "working")
        self.assertAlmostEqual(row.runner_cpu, 0.03 * HOLD_LENGTH, delta=0.1)
        self.assertAlmostEqual(row.load, 412.60, places=2)
        self.assertEqual(row.busiest[0], "backboardd")
        table = self.read_main(record_text(app_rate=0.98))
        self.assertIn("Steps of 10 s or more (1): working 1, waiting 0, in between 0, not measured 0.", table)
        self.assertIn("First reads after the door tap (1): working 1, waiting 0, in between 0, not judged (under 10 s) 0, "
                      "not measured 0.", table)
        self.assertIn("09:15:03.016", table)
        self.assertIn("32.60s", table)
        self.assertIn("27095", table)
        self.assertIn("working", table)

    def test_a_hold_with_almost_no_cpu_growth_is_waiting(self):
        row = self.long_row(record_text(app_rate=0.04, busy=2.9))
        self.assertLess(row.app_share, 0.10)
        self.assertEqual(row.verdict, "waiting")
        self.assertGreater(row.host_busy, 0.90)
        self.assertIn("waiting 1", self.read_main(record_text(app_rate=0.04)))

    def test_half_a_cpu_is_in_between(self):
        row = self.long_row(record_text(app_rate=0.5))
        self.assertAlmostEqual(row.app_share, 0.5, delta=0.03)
        self.assertEqual(row.verdict, "in between")

    def test_an_app_pid_that_changes_inside_the_window_counts_both(self):
        old = grows(12.34, 0.2, 0.98)
        switch = T0 + 35                                          # 09:15:15
        new_first = switch + 0.1
        def app(t):
            if t < switch:
                return [(27095, old(t))]
            return [(27140, 0.40 + 0.98 * (t - new_first))]
        row = self.long_row(record_text(app=app))
        last_old = switch - 1 + 0.1                               # 27095's last sample, 09:15:14.1
        expected = (old(last_old) - old(HOLD_START)) + (0.40 + 0.98 * (HOLD_END - new_first))
        self.assertAlmostEqual(row.app_cpu, expected, delta=1.0)
        self.assertEqual(sorted(row.app_pids), [27095, 27140])
        self.assertEqual(row.app_pids[0], 27140)                  # the one that used more comes first
        self.assertIn("pid changed", row.note)
        self.assertIn("27140,27095 pid changed", self.read_main(record_text(app=app)))

    def test_an_app_that_starts_inside_the_step_is_named_and_not_judged(self):
        # Launched 10 s into the hold, then flat out: over the whole step that is about 70% of a CPU,
        # a share that says nothing about the 10 s the app did not exist. It used a whole CPU from the
        # moment it ran.
        launch = HOLD_START + 10
        def app(t):
            return [(500, 0.30 + 1.0 * (t - launch))] if t >= launch else []
        row = self.long_row(record_text(app=app))
        self.assertEqual(row.app_pids, [500])
        self.assertEqual(row.verdict, "not judged: app not running all step")
        self.assertRegex(row.note, r"no app process for (9|10|11)\.\d s of the step")
        self.assertIn("app started inside it", row.note)
        self.assertRegex(row.note, r"(9\d|1[01]\d)% of a CPU while it ran")
        table = self.read_main(record_text(app=app))
        self.assertIn("Steps of 10 s or more (1): working 0, waiting 0, in between 0, not measured 0, "
                      "not judged (app not running all step) 1.", table)
        self.assertIn("app started inside it", table)

    def test_an_app_that_ends_inside_the_step_is_named_and_not_judged(self):
        cpu_at = grows(12.34, 0.2, 0.98)
        gone = HOLD_START + 20
        row = self.long_row(record_text(app=lambda t: [(27095, cpu_at(t))] if t < gone else []))
        self.assertEqual(row.verdict, "not judged: app not running all step")
        self.assertIn("app ended inside it", row.note)

    def test_a_pid_handed_over_between_two_samples_is_still_judged(self):
        # The same as the pid change below: the app is listed in every sample, so nothing is missing.
        old = grows(12.34, 0.2, 0.98)
        switch = T0 + 35
        row = self.long_row(record_text(app=lambda t: [(27095, old(t))] if t < switch
                                        else [(27140, 0.40 + 0.98 * (t - switch - 0.1))]))
        self.assertEqual(row.verdict, "working")
        self.assertNotIn("no app process", row.note)

    def test_missing_samples_widen_the_range_and_are_named(self):
        steady = record_text(app_rate=0.6)
        gappy = record_text(app_rate=0.6, skip=range(int(T0) + 30, int(T0) + 37))   # 09:15:10 to 09:15:16
        whole = self.long_row(steady)
        gap = self.long_row(gappy)
        self.assertIn("gap 8.0 s", gap.note)
        self.assertNotIn("gap", whole.note)
        self.assertAlmostEqual(gap.app_cpu, 0.6 * HOLD_LENGTH, delta=0.5)
        self.assertGreaterEqual(gap.app_high - gap.app_low, whole.app_high - whole.app_low)

    def test_a_step_outside_the_record_is_not_measured(self):
        row = self.long_row(record_text(last=T0 + 30))              # the record stops at 09:15:10
        self.assertIsNone(row.app_cpu)
        self.assertEqual(row.verdict, "not measured: outside the record")
        self.assertIn("not measured 1", self.read_main(record_text(last=T0 + 30)))

    def test_a_record_with_no_app_process_is_not_measured(self):
        row = self.long_row(record_text(app=lambda t: []))
        self.assertEqual(row.verdict, "not measured: no app process")

    def test_a_short_first_read_after_the_door_is_listed_but_not_judged(self):
        # The real rows, with the wait after the tap cut to 3.2 s (Tear Down moved from 48.37 to 18.97).
        rows = ROWS.replace("1795598135.727\tstep\t48.37 Tear Down", "1795598106.300\tstep\t18.97 Tear Down")
        rows = rows.replace("1795598139.980\tfailed", "1795598110.000\tfailed")
        rec, steps, measured = self.rows_for(record_text(), times=rows)
        door = [row for row in measured if row.step.after_door]
        self.assertEqual(len(door), 1)
        self.assertAlmostEqual(door[0].step.length, 3.20, places=2)
        self.assertEqual(door[0].verdict, "-")
        table = self.read_main(record_text(), times=rows)
        self.assertIn("Steps of 10 s or more (0): working 0, waiting 0, in between 0, not measured 0.", table)
        self.assertIn("First reads after the door tap (1): working 0, waiting 0, in between 0, not judged (under 10 s) 1, "
                      "not measured 0.", table)


class FormatTests(unittest.TestCase):
    def test_cpu_time_forms(self):
        cases = {"  0:12.34": 12.34, "  4:05.00": 245.0, "123:45.67": 7425.67, "1:02:03": 3723.0,
                 "01:02:03.50": 3723.5, "2-03:04:05": 183845.0, "00:00:06": 6.0, "0:07": 7.0}
        for text, seconds in cases.items():
            with self.subTest(text=text):
                self.assertAlmostEqual(cpu.parse_cpu_time(text), seconds, places=2)
        for text in ("1:2x", ":30", "", "-", "1:75.00", "12.34", "a:bc.de"):
            with self.subTest(text=text):
                self.assertIsNone(cpu.parse_cpu_time(text))

    def test_the_helper_prints_what_macos_ps_prints(self):
        self.assertEqual(mac_time(12.34), "  0:12.34")
        self.assertEqual(mac_time(7425.67), "123:45.67")
        self.assertEqual(ps_line(27095, 12.34, "Thorbis"), "27095   0:12.34 Thorbis         ")

    def test_a_ps_line_with_a_name_in_parentheses_or_with_spaces(self):
        self.assertEqual(cpu.parse_ps_line("  612   3:01.00 (Thorbis)"), (612, 181.0, "Thorbis"))
        self.assertEqual(cpu.parse_ps_line("  613   0:01.00 Google Chrome He"), (613, 1.0, "Google Chrome He"))
        self.assertIsNone(cpu.parse_ps_line("  614 Thorbis"))
        self.assertIsNone(cpu.parse_ps_line("pid 0:01.00 Thorbis"))


class MalformedTests(ReaderCase):
    def test_malformed_lines_are_ignored_without_an_error(self):
        times = ("garbage without tabs\n"
                 "1795598080.000\tstep\t1.00 a step before any test\n"
                 "not-a-time\tstep\t1.00 Set Up\n"
                 "1795598080.100\ttwo fields\n"
                 + ROWS.replace("1795598087.537\tstep\t0.07 Open com.thorbis.field",
                                "1795598087.537\tstep\tOpen com.thorbis.field without a t\n"
                                "1795598087.537\tstep\t0.07 Open com.thorbis.field"))
        extra = ["p\t27095 not a time Thorbis", "something\tunknown\tkind", "\x00\x01 binary",
                 f"{iso(T0 + 66)}\tsample\t99\tload x y z\tps 1 ms\tlines 1\tunread 0\tbusy 1.00",
                 f"{iso(T0 + 66.5)}\tsamp"]
        record = "p\t 9999   0:01.00 Thorbis\n" + record_text(extra=extra) + "2026-11-25T09:16:0"   # cut off
        row = self.long_row(record, times=times)
        self.assertEqual(row.verdict, "working")
        table = self.read_main(record, times=times)
        self.assertIn("Steps of 10 s or more (1): working 1", table)
        self.assertNotIn("9999", table)

    def test_missing_or_empty_files_print_one_line_and_return_zero(self):
        for record, times in ((str(self.dir / "absent.txt"), str(self.dir / "absent.tsv")),
                              (self.write("empty.txt", ""), self.write("empty.tsv", ""))):
            with self.subTest(record=record):
                buffer = io.StringIO()
                with redirect_stdout(buffer):
                    self.assertEqual(cpu.main(["read", record, times]), 0)
                self.assertIn("Steps of 10 s or more (0)", buffer.getvalue())
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            self.assertEqual(cpu.main(["read"]), 0)
            self.assertEqual(cpu.main(["nonsense"]), 0)

    def test_an_unwritable_out_path_is_a_note(self):
        blocker = self.write("blocker", "")
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            code = cpu.main(["read", self.write("cpu-load.txt", record_text()), self.write("t.tsv", ROWS),
                             "--out", blocker + "/table.txt"])
        self.assertEqual(code, 0)
        self.assertIn("could not write", buffer.getvalue())

    def test_the_header_says_what_the_record_cost(self):
        table = self.read_main(record_text())
        self.assertIn("3 CPUs", table)
        self.assertIn("recorder and ps used 2.1 s of CPU in 66 s", table)

    def test_the_table_says_what_its_numbers_can_and_cannot_show(self):
        table = self.read_main(record_text())
        # The app's CPU is every thread of the process together: it can pass 100%, and 70% of one CPU
        # can be two threads at 35% each, so a high share says how much CPU the threads used between
        # them, not that any one thread, or the main thread, ran for most of the step.
        self.assertIn("all the app's threads together", table)
        self.assertIn("can be over 100%", table)
        self.assertIn("the app's threads together used at least 0.7 s of CPU per second of the step", table)
        self.assertIn("nor that the main thread was one of them", table)
        # A low share bounds every thread at once: for most of the step none of them was running.
        self.assertIn("at most 0.3 s of CPU per second of the step, so for most of the step no thread of the app "
                      "was running", table)
        self.assertIn("waiting for a CPU or blocked", table)
        self.assertIn('only a low share with a high "host busy"', table)
        # How the number is made.
        self.assertIn("interpolated", table)
        self.assertIn("samples inside the step", table)
        for text in (table, cpu.__doc__, (ROOT / "README.md").read_text()):
            flat = " ".join(text.split())
            self.assertIn("over 100%", flat)
            self.assertIn("threads together used at least 0.7 s of CPU per second of the step", flat)
            self.assertIn("nor that the main thread was one of them", flat)
            self.assertIn("at most 0.3 s of CPU per second", flat)
            self.assertIn("no thread of the app was running", flat)
            self.assertIn("or blocked", flat)
            # What process CPU time cannot show.
            self.assertNotIn("was running for most of the step", flat)
            self.assertNotIn("some thread of the app", flat)
            self.assertNotIn("main thread was working", flat)
            self.assertNotIn("This can:", flat)
        for text in (cpu.__doc__, (ROOT / "README.md").read_text()):
            self.assertIn("all its threads", " ".join(text.split()))

STAND_IN_PS = textwrap.dedent("""\
    import json, os, sys, time
    log = os.environ.get("PS_LOG") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "ps-calls.jsonl")
    with open(log, "a") as handle:
        handle.write(json.dumps({"argv": sys.argv[1:], "env": sorted(os.environ)}) + "\\n")
    mode = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "ps-mode")).read().strip()
    if mode == "slow":
        time.sleep(3)
    if mode == "fail":
        print("ps: time: requires entitlement", file=sys.stderr)
        sys.exit(1)
    n = sum(1 for _ in open(log))
    print("%5d %9s %-16s" % (27095, "  0:%02d.%02d" % (12 + n // 100, n % 100), "Thorbis"))
    print("%5d %9s %-16s" % (612, "  3:%02d.00" % (n % 60), "SomethingElse"))
    print("%5d %9s %-16s" % (6150, "  0:41.20", "ThorbisUITests-R"))
    """)

STAND_IN_SYSCTL = textwrap.dedent("""\
    import sys
    if sys.argv[1:] == ["-n", "vm.loadavg"]:
        print("{ 3.10 2.95 2.20 }")
    else:
        print("3"); print("3"); print("3")
    """)


class RecorderTests(unittest.TestCase):
    """The recorder, run here with stand-ins for macOS's ps and sysctl first on PATH."""

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(self.dir)]))
        self.bin = self.dir / "bin"
        self.bin.mkdir()
        for name, body in (("ps", STAND_IN_PS), ("sysctl", STAND_IN_SYSCTL)):
            path = self.bin / name
            path.write_text(f"#!{sys.executable}\n" + body)
            path.chmod(0o755)
        self.mode("ok")
        self.out = self.dir / "cpu-load.txt"

    def mode(self, text):
        (self.bin / "ps-mode").write_text(text)

    def env(self):
        return dict(os.environ, PATH=f"{self.bin}{os.pathsep}{os.environ['PATH']}", THORBIS_TEST_SECRET="abc123")

    def record(self, *args, timeout=20):
        return subprocess.run([sys.executable, str(SCRIPT), "record", str(self.out), *args], env=self.env(),
                              capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)

    def kinds(self):
        return [line.split("\t")[1] if not line.startswith("p\t") else "p" for line in self.out.read_text().splitlines()]

    def test_it_writes_samples_of_the_processes_of_interest_and_stops_at_its_limit(self):
        began = time.time()
        result = self.record("--interval", "0.2", "--max-seconds", "2")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout + result.stderr, "")
        self.assertLess(time.time() - began, 6)
        text = self.out.read_text()
        kinds = self.kinds()
        self.assertEqual(kinds[:3], ["start", "ncpu", "loadraw"])
        # A tick that comes while ps still runs is skipped by design, so on a busy machine there are
        # fewer samples; samples and missed ticks together always make up the 10 ticks of 2 s.
        self.assertGreaterEqual(kinds.count("sample"), 2)
        self.assertEqual(kinds[-1], "stop")
        self.assertIn("why time limit", text.splitlines()[-1])
        stop = text.splitlines()[-1]
        self.assertGreaterEqual(int(cpu.field(stop.split("\t"), "samples")) + int(cpu.field(stop.split("\t"), "missed")), 9)
        self.assertIn("\tsysctl 3 | 3 | 3", text)
        self.assertIn("{ 3.10 2.95 2.20 }", text)
        p_lines = [line for line in text.splitlines() if line.startswith("p\t")]
        self.assertTrue(p_lines)
        self.assertTrue(all(line.endswith(("Thorbis", "ThorbisUITests-R")) for line in p_lines), p_lines)
        self.assertNotIn("SomethingElse", "\n".join(p_lines))
        self.assertRegex(text, r"\tsample\t1\tload \d+\.\d\d \d+\.\d\d \d+\.\d\d\tps \d+ ms\tlines 3\tunread 0\tbusy ")
        self.assertRegex(text, r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z\tsample")
        calls = [line for line in (self.bin / "ps-calls.jsonl").read_text().splitlines()]
        import json
        for call in map(json.loads, calls):
            self.assertEqual(call["argv"], ["-Ao", "pid=,time=,ucomm="])
            self.assertEqual(set(call["env"]) - {"PATH", "LC_ALL"}, set(), call["env"])
        self.assertNotIn("abc123", text)
        self.assertNotIn("THORBIS_TEST_SECRET", text)

    def test_busy_counts_every_process_not_only_those_of_interest(self):
        self.record("--interval", "0.2", "--max-seconds", "1.2")
        samples = [line.split("\t") for line in self.out.read_text().splitlines() if "\tsample\t" in line]
        busy = [float(fields[-1].split()[1]) for fields in samples[1:]]
        # SomethingElse grows by 1.00 s a call, Thorbis by 0.01 s, the runner not at all.
        self.assertTrue(all(abs(value - 1.01) < 0.001 for value in busy), busy)

    def test_a_ps_that_does_not_finish_is_a_note_and_the_recorder_still_stops(self):
        self.mode("slow")
        began = time.time()
        result = self.record("--interval", "0.2", "--max-seconds", "1.5", "--ps-timeout", "0.5")
        self.assertEqual(result.returncode, 0)
        self.assertLess(time.time() - began, 6)
        text = self.out.read_text()
        self.assertIn("\tnote\tps did not finish in 0.5 s", text)
        self.assertIn("\tps failed\t", text)
        self.assertRegex(text.splitlines()[-1], r"\tstop\t.*\tmissed [1-9]")

    def test_a_ps_that_fails_is_a_note_and_the_samples_keep_the_load(self):
        self.mode("fail")
        result = self.record("--interval", "0.2", "--max-seconds", "1")
        self.assertEqual(result.returncode, 0)
        text = self.out.read_text()
        self.assertIn("\tnote\tps exited 1: ps: time: requires entitlement", text)
        self.assertRegex(text, r"\tsample\t\d+\tload \d+\.\d\d .*\tps failed\t")
        self.assertNotIn("\np\t", text)

    def test_sigterm_writes_the_stop_line_and_exits_zero(self):
        process = subprocess.Popen([sys.executable, str(SCRIPT), "record", str(self.out), "--interval", "0.2"],
                                   env=self.env(), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL)
        self.addCleanup(lambda: process.poll() is None and process.kill())
        deadline = time.time() + 10
        while time.time() < deadline and (not self.out.exists() or "\tsample\t" not in self.out.read_text()):
            time.sleep(0.05)
        process.send_signal(signal.SIGTERM)
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertIn("why signal", self.out.read_text().splitlines()[-1])

    def test_it_stops_by_itself_when_its_parent_dies(self):
        parent = subprocess.Popen(["bash", "-c", f'"{sys.executable}" "{SCRIPT}" record "{self.out}" --interval 0.2 & sleep 30'],
                                  env=self.env(), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL)
        self.addCleanup(lambda: parent.poll() is None and parent.kill())
        deadline = time.time() + 10
        while time.time() < deadline and (not self.out.exists() or "\tsample\t" not in self.out.read_text()):
            time.sleep(0.05)
        parent.kill()
        parent.wait()
        deadline = time.time() + 3
        while time.time() < deadline and "\tstop\t" not in self.out.read_text():
            time.sleep(0.05)
        last = self.out.read_text().splitlines()[-1]
        self.assertIn("why parent gone", last)
        pid = int(self.out.read_text().splitlines()[0].rsplit("pid ", 1)[1])
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    def test_an_unwritable_path_exits_zero_and_says_nothing(self):
        blocker = self.dir / "blocker"
        blocker.write_text("")
        result = subprocess.run([sys.executable, str(SCRIPT), "record", str(blocker / "cpu-load.txt"),
                                 "--max-seconds", "1"], env=self.env(), capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout + result.stderr, "")

    def test_the_real_ps_here_is_read(self):
        """On this machine (Linux in CI's lint job) the real ps prints procps's own `time` form."""
        if not Path("/bin/ps").exists() and not Path("/usr/bin/ps").exists():
            self.skipTest("no ps here")
        result = subprocess.run([sys.executable, str(SCRIPT), "record", str(self.out), "--interval", "0.2",
                                 "--max-seconds", "0.7"], capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0)
        rec = cpu.read_record(str(self.out))
        self.assertGreaterEqual(len(rec.samples), 2)
        self.assertTrue(all(sample.unread == 0 for sample in rec.samples if sample.valid))


if __name__ == "__main__":
    unittest.main()
