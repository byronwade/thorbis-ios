"""Tests for scripts/ci_log_compare.py (BYR-1896): the stored simulator log against the live stream.

The entries are invented in the compact style the stream's tests already use (test_ci_cancelled_taps.py);
`log show` is assumed to print the same style, with its own header and statistics lines, which are
invented here too. Nothing here has run on macOS.
"""
import io
import os
import re
import shutil
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import ci_log_compare as lc  # noqa: E402

BEGAN = int(time.time()) - 3600
HEADER = 'Filtering the log data using "process == \\"backboardd\\""\nTimestamp               Ty Process[PID:TID]\n'
STATS = ("--------------------------------------------------------------------------------------------------------\n"
         "Log      - Default:          4, Info:                0, Debug:             0, Error:          0, Fault:          0\n"
         "Activity - Create:           0, Transition:          0, Actions:           0\n")
REGISTRATION = ("new key command registrations for pid:42 environment: keyboardFocus; token: 0xBD; keyCommands: {\n"
                "    cmd: (f, k, n),\n}")


def entry(offset, message, pid=5334, tid="466d"):
    t = BEGAN + offset
    stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t)) + ".%03d" % int(round(t % 1 * 1000) % 1000)
    return f"{stamp} Df backboardd[{pid}:{tid}] [com.apple.BackBoard:EventDelivery] {message}\n"


class CompareCase(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)

    def files(self, stream, store, show="exit 0 seconds 3\n", window=(0, 100)):
        (self.dir / "window.txt").write_text(f"began {BEGAN + window[0]}\nended {BEGAN + window[1]}\n")
        if stream is not None:
            (self.dir / "stream.log").write_text(HEADER + "".join(stream))
        if store is not None:
            (self.dir / "store.log").write_text(store)
        if show is not None:
            (self.dir / "log-show.txt").write_text(show)

    def compare(self, *extra):
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            code = lc.main(["compare", str(self.dir), *extra])
        self.assertEqual(code, 0)
        text = buffer.getvalue()
        self.assertEqual((self.dir / "compare.txt").read_text(), text)
        return text

    def last(self, text):
        return text.strip().splitlines()[-1]


class EntryTests(CompareCase):
    def test_continuation_lines_stay_with_their_entry_and_headers_are_dropped(self):
        path = self.dir / "log"
        path.write_text(HEADER + entry(1, REGISTRATION) + entry(2, "KCMD: match in pid:42 keyboardFocus") + STATS)
        entries, dropped, stray = lc.read_entries(str(path))
        self.assertEqual(len(entries), 2)
        self.assertIn("cmd: (f, k, n),", entries[0].message)
        self.assertEqual(entries[0].raw[-1], "}")
        self.assertEqual(dropped, 2 + 3)
        self.assertEqual(stray, 0)

    def test_statistics_lines_with_other_spacing_are_dropped(self):
        path = self.dir / "log"
        path.write_text(entry(1, "KCMD: match in pid:42 keyboardFocus") + "Log - Default: 1, Info: 0\n  Activity  -  Create: 0\n")
        entries, dropped, _ = lc.read_entries(str(path))
        self.assertEqual(entries[0].message, "[com.apple.BackBoard:EventDelivery] KCMD: match in pid:42 keyboardFocus")
        self.assertEqual(dropped, 2)

    def test_the_kinds(self):
        self.assertEqual(lc.kind_of("*** unknown digitizer <x>"), "unknown digitizer")
        self.assertEqual(lc.kind_of("KCMD: match in pid:4 keyboardFocus"), "KCMD: match")
        self.assertEqual(lc.kind_of("KCMD: no match in pid:4 keyboardFocus"), "KCMD: no match")
        self.assertEqual(lc.kind_of(REGISTRATION), "registrations")
        self.assertEqual(lc.kind_of("something"), "other")


class CompareTests(CompareCase):
    def test_a_store_holding_every_entry_is_yes(self):
        lines = [entry(1, REGISTRATION), entry(2, "KCMD: match in pid:42 keyboardFocus"),
                 entry(3, "Connection added: IOHIDEventSystemConnection uuid:A pid:42 process:Thorbis type:Passive")]
        self.files(lines, HEADER + "".join(lines) + STATS)
        text = self.compare()
        self.assertEqual(self.last(text), "log compare: store holds every stream entry: yes (3 of 3 stream entries found in the store)")
        self.assertIn("total: stream 3, store 3, both 3, only in stream 0, only in store 0", text)
        self.assertIn("kind registrations: stream 1, store 1", text)
        self.assertIn("reads the stream and the matched store entries the same way: yes", text)
        clean = (self.dir / "store-clean.log").read_text()
        self.assertNotIn("Log      - Default", clean)
        self.assertIn("cmd: (f, k, n),", clean)

    def test_a_match_needs_the_same_message_within_one_second(self):
        self.files([entry(10, "KCMD: match in pid:42 keyboardFocus")], entry(10.9, "KCMD: match in pid:42 keyboardFocus"))
        self.assertIn(": yes (", self.last(self.compare()))
        self.files([entry(5, "cache miss for Keyboard event"), entry(10, "KCMD: match in pid:42 keyboardFocus")],
                   entry(5, "cache miss for Keyboard event") + entry(8, "KCMD: match in pid:42 keyboardFocus")
                   + entry(12, "KCMD: match in pid:42 keyboardFocus"))
        text = self.compare()
        self.assertIn(": no (1 stream entries are not in the store)", self.last(text))
        self.assertIn("only in stream: ", text)

    def test_duplicates_count_as_a_multiset(self):
        line = entry(5, "KCMD: match in pid:42 keyboardFocus")
        self.files([line, line], line)
        self.assertIn(": no (1 stream entries", self.last(self.compare()))
        self.files([line], line + line)
        text = self.compare()
        self.assertIn(": yes", self.last(text))
        self.assertIn("log compare: the live stream lost 1 entries (see above)", text)

    def test_store_only_entries_before_the_streams_first_line_are_counted_apart(self):
        self.files([entry(20, "KCMD: match in pid:42 keyboardFocus")],
                   entry(5, "cache miss for Keyboard event") + entry(20, "KCMD: match in pid:42 keyboardFocus"))
        text = self.compare()
        self.assertIn("only in store: 1 before the stream's first entry", text)
        self.assertNotIn("the live stream lost", text)

    def test_store_entries_outside_the_window_are_not_compared(self):
        self.files([entry(20, "KCMD: match in pid:42 keyboardFocus")],
                   entry(-20, "cache miss for Keyboard event") + entry(20, "KCMD: match in pid:42 keyboardFocus")
                   + entry(130, "cache miss for Keyboard event"))
        text = self.compare()
        self.assertIn("store entries outside it, not compared: 2", text)
        self.assertIn(": yes", self.last(text))

    def test_a_stream_entry_outside_its_own_window_is_not_known(self):
        self.files([entry(500, "KCMD: match in pid:42 keyboardFocus")], entry(500, "KCMD: match in pid:42 keyboardFocus"))
        self.assertIn(": not known (1 stream entries lie outside", self.last(self.compare()))

    def test_a_late_store_is_no(self):
        # The stream's first entry is in the store, but the store starts later: impossible unless
        # the matching is wrong, so it is refused. Built by giving the store a later first entry.
        self.files([entry(10, "KCMD: match in pid:42 keyboardFocus"), entry(30, "KCMD: match in pid:42 keyboardFocus")],
                   entry(30, "KCMD: match in pid:42 keyboardFocus"))
        self.assertIn(": no (", self.last(self.compare()))

    def test_an_empty_or_missing_store_is_never_yes(self):
        self.files([entry(10, "KCMD: match in pid:42 keyboardFocus")], "")
        self.assertIn(": not known (the store gave nothing)", self.last(self.compare()))
        (self.dir / "store.log").unlink()
        self.assertIn(": not known (the store gave nothing)", self.last(self.compare()))
        self.files([entry(10, "KCMD: match in pid:42 keyboardFocus")], HEADER + STATS)
        self.assertIn(": not known (no stream entry was found in the store", self.last(self.compare()))
        self.files(None, "x")
        (self.dir / "stream.log").unlink(missing_ok=True)
        self.assertIn(": not known (no stream.log)", self.last(self.compare()))

    def test_log_show_exit_status(self):
        line = entry(10, "KCMD: match in pid:42 keyboardFocus")
        self.files([line], line, show="exit 1 seconds 2\n")
        self.assertIn(": no (log show exited 1", self.last(self.compare()))
        self.files([line], line, show="exit 142 seconds 240\n")
        self.assertIn(": not known (log show did not finish in its alarm, 240 s)", self.last(self.compare()))
        self.files([line], line, show=None)
        (self.dir / "log-show.txt").unlink(missing_ok=True)
        self.assertIn(": not known (no log-show.txt)", self.last(self.compare()))

    def test_the_rule_reads_both_files_the_same_way_only_when_they_hold_the_same(self):
        stream = [entry(1, REGISTRATION), entry(2, "KCMD: match in pid:42 keyboardFocus")]
        self.assertEqual(lc.agreement(lc.read_entries(self.write("a", HEADER + "".join(stream)))[0],
                                      lc.read_entries(self.write("b", HEADER + "".join(stream)))[0], str(self.dir)), "yes")
        self.assertTrue(lc.agreement(lc.read_entries(self.write("a", HEADER + "".join(stream)))[0],
                                     lc.read_entries(self.write("b", HEADER + stream[0]))[0], str(self.dir)).startswith("no"))

    def write(self, name, text):
        path = self.dir / name
        path.write_text(text)
        return str(path)

    def test_store_only_entries_are_placed_against_diagnosticd_changes_and_tests(self):
        def iso(t):
            return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".000Z"
        record = [f"{iso(BEGAN)}\tstart\tci_cpu_load 2\tinterval 1.0\tps -Ao pid=,time=,ucomm=\tpid 9", f"{iso(BEGAN)}\tncpu\t3\tsysctl 3"]
        for second in range(0, 60):
            record.append(f"{iso(BEGAN + second)}\tsample\t{second + 1}\tload 1 1 1\tps 5 ms\tlines 3\tunread 0\tbusy 1.00")
            record.append("p\t%5d   0:%02d.00 diagnosticd" % (2793 if second < 30 else 77401, second % 60))
        self.write("cpu-load.txt", "\n".join(record) + "\n")
        self.write("test-times.tsv", f"{BEGAN + 25}.0\tstarted\tA/B/c\n{BEGAN + 40}.0\tpassed\tA/B/c 1.0\n")
        self.files([entry(10, "KCMD: match in pid:42 keyboardFocus")],
                   entry(10, "KCMD: match in pid:42 keyboardFocus") + entry(31, "cache miss for Keyboard event"))
        text = self.compare(str(self.dir / "cpu-load.txt"), str(self.dir / "test-times.tsv"))
        self.assertIn("1 after it, of which 1 inside a test", text)
        self.assertRegex(text, r"only in store: .* cache miss for Keyboard event; \+1\.0 s from diagnosticd 77401 first seen")

    def test_garbage_never_fails(self):
        (self.dir / "window.txt").write_bytes(b"\xff\xfe began x\n")
        (self.dir / "stream.log").write_bytes(b"\x00\xff" * 100)
        (self.dir / "store.log").write_bytes(b"\x00\xff" * 100)
        (self.dir / "log-show.txt").write_text("exit 0 seconds 1\n")
        self.assertIn("not known", self.last(self.compare()))
        self.assertIn("not known", self.compare("/nonexistent/x", "/nonexistent/y"))


class BoundsAndFilterTests(CompareCase):
    def test_bounds_are_thirty_seconds_outside_the_window_in_local_time(self):
        self.files(None, None, show=None, window=(0, 100))
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            self.assertEqual(lc.main(["bounds", str(self.dir / "window.txt")]), 0)
        self.assertEqual(buffer.getvalue().splitlines(), [
            time.strftime("%Y-%m-%d %H:%M:%S%z", time.localtime(BEGAN - 30)),
            time.strftime("%Y-%m-%d %H:%M:%S%z", time.localtime(BEGAN + 130))])
        (self.dir / "window.txt").write_text("began 5\n")
        self.assertEqual(lc.main(["bounds", str(self.dir / "window.txt")]), 1)

    def test_the_filter_is_the_one_the_test_step_streams_with(self):
        text = (ROOT / "scripts" / "ci-run-ui-tests.sh").read_text()
        on_file = re.findall(r"log stream --style compact --level default \\\n\s+--predicate '([^']*)'", text)
        self.assertEqual(len(on_file), 1)
        self.assertEqual(lc.predicate(), on_file[0])
        self.assertTrue(on_file[0].startswith('process == "backboardd" AND (eventMessage CONTAINS "unknown digitizer"'))
        missing = self.dir / "none.sh"
        self.assertIsNone(lc.predicate(str(missing)))
        missing.write_text("nothing here\n")
        self.assertIsNone(lc.predicate(str(missing)))


if __name__ == "__main__":
    unittest.main()
