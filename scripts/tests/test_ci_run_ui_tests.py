"""Drive scripts/ci-run-ui-tests.sh with stand-ins for xcodebuild and the simulator's log stream.

The stand-ins are small Python programs put first on PATH. They do not race the script: the
xcodebuild stand-in waits until the script has noted a test's start before it makes the stream
log a cancelled tap, and waits until that line has reached the script's log file before it
goes on. Every wait is bounded, so a broken script fails a test instead of hanging it.
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
SCRIPT = ROOT / "scripts" / "ci-run-ui-tests.sh"
A = "ThorbisUITests/CustomerDocumentBookUITests/testEstimateReview"
B = "ThorbisUITests/JobEstimateHandoffUITests/testLongEstimateTitle"
SHARD = ["-only-testing:ThorbisUITests/CustomerDocumentBookUITests",
         "-only-testing:ThorbisUITests/JobEstimateHandoffUITests"]

# Shared by both stand-ins: where things are, and a bounded wait.
COMMON = textwrap.dedent("""\
    import glob, json, os, sys, time
    STUB = os.environ["STUB_DIR"]
    def scratch_file(name):
        found = glob.glob(os.path.join(os.environ["TMPDIR"], "ui-tests.*", name))
        return found[0] if found else None
    def wait_for(check, limit=5.0):
        end = time.time() + limit
        while time.time() < end:
            if check():
                return True
            time.sleep(0.01)
        return False
    def contains(name, text):
        path = scratch_file(name)
        if not path:
            return False
        with open(path, encoding="utf-8", errors="replace") as handle:
            return text in handle.read()
    """)

XCRUN = COMMON + textwrap.dedent("""\
    # `xcrun simctl spawn <id> log stream ...`: a header, then each event the xcodebuild
    # stand-in asks for, stamped with the local time it is written: a cancelled tap, or
    # backboardd's lines about a key (a message may span lines, as in compact style). Lives
    # until signalled, as the real stream does, but never longer than 15 s.
    with open(os.path.join(STUB, "calls.jsonl"), "a") as calls:
        calls.write(json.dumps(["xcrun"] + sys.argv[1:]) + "\\n")
    if os.environ.get("STREAM_BROKEN"):
        sys.exit(1)
    print('Filtering the log data using "process == "backboardd" AND eventMessage CONTAINS "unknown digitizer""', flush=True)
    print("Timestamp               Ty Process[PID:TID]", flush=True)
    asked = os.path.join(STUB, "events")
    sent = 0
    end = time.time() + 15
    while time.time() < end:
        try:
            with open(asked) as handle:
                wanted = handle.read().splitlines()
        except FileNotFoundError:
            wanted = []
        for tag in wanted[sent:]:
            now = time.time()
            stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now)) + ".%03d" % int((now % 1) * 1000)
            if tag.startswith("{"):
                for message in json.loads(tag)["key"]:
                    print(f"{stamp} Df backboardd[5334:466d] [com.apple.BackBoard:EventDelivery] {message}", flush=True)
                continue
            print(f"{stamp} E  backboardd[5334:3fcd5] [com.apple.BackBoard:TouchEvents] *** unknown digitizer <BKIOHIDService: 0x{tag}>", flush=True)
        sent = len(wanted)
        time.sleep(0.01)
    """)

XCODEBUILD = COMMON + textwrap.dedent("""\
    args = sys.argv[1:]
    with open(os.path.join(STUB, "calls.jsonl"), "a") as calls:
        calls.write(json.dumps(["xcodebuild"] + args) + "\\n")
    bundle = args[args.index("-resultBundlePath") + 1]
    os.makedirs(bundle, exist_ok=True)
    with open(os.path.join(STUB, "scenario.json")) as handle:
        scenario = json.load(handle)
    taps = 0
    began = None
    def say(line):
        print(line, flush=True)
    def step(text):
        if began is not None:     # a tap outside any test logs the error and no step
            say(f"    t = {time.time() - began:8.2f}s {text}")
    def case_name(name):
        module, klass, test = name.split("/")
        return f"-[{module}.{klass} {test}]"
    def tap():
        # A Tap step, the error logged at it, and the wait that comes next. The stand-in goes on
        # only once the line is in the script's file.
        global taps
        taps += 1
        step('Tap "row" Button')
        with open(os.path.join(STUB, "events"), "a") as handle:
            handle.write(f"{taps}\\n")
        wait_for(lambda: contains("cancelled-taps.log", f"0x{taps}>"))
        time.sleep(0.02)
        step('Waiting 10.0s for "next" Button to exist')
    def key_lines(marker, *messages):
        # backboardd's lines about a key. The stand-in goes on only once they are in the file.
        with open(os.path.join(STUB, "events"), "a") as handle:
            handle.write(json.dumps({"key": list(messages)}) + "\\n")
        wait_for(lambda: contains("cancelled-taps.log", marker))
        time.sleep(0.02)
    keyed = 0
    def connect(pid):
        key_lines(f"pid:{pid} process:Thorbis ", f"Connection added: IOHIDEventSystemConnection uuid:A pid:{pid} "
                  f"process:Thorbis type:Passive attributes:{{\\n    pid = {pid};\\n}}")
    def chord(pid, reached=False):
        # A ⌘K press: sent to the app as a command when it has reached it, else as a bare key.
        global keyed
        keyed += 1
        step("Type 'k' key with modifiers '⌘' (0x10)")
        if reached:
            key_lines(f"#c{keyed}", "KCMD: no match in pid:1558 systemKeyCommandOverlay",
                      f"KCMD: match in pid:{pid} keyboardFocus #c{keyed}")
        else:
            key_lines(f"0xc{keyed};", "KCMD: no match in pid:1558 systemKeyCommandOverlay",
                      "KCMD: no match in pid:1558 keyboardFocus", "cache miss for Keyboard event",
                      f"sequence starting with Keyboard event: <sq: 0xc{keyed}; (<keyboardFocus; display: builtin; "
                      f"pid: {pid}; token: 0xBDCDB732>)>")
        step('Waiting 4.0s for "search-field" TextField to exist')
    def register(pid):
        global keyed
        keyed += 1
        key_lines(f"(r{keyed})", f"new key command registrations for pid:{pid} environment: keyboardFocus; token: "
                  f"0xBDCDB732; keyCommands: {{\\n    cmd: (f, k, n),\\n    cmd|shft: (n),\\n    glb: (r{keyed})\\n}}")
    def started(name):
        global began
        say(f"Test Case '{case_name(name)}' started.")
        began = time.time()
        say("    t =     0.00s Start Test at " + time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(began))
            + ".%03d" % (int(began % 1 * 1000)))
        wait_for(lambda: contains("test-times.tsv", f"started\\t{name}"))
        time.sleep(0.02)
    def ended(name, outcome, message="XCTAssertTrue failed"):
        if outcome == "failed":
            step("Collecting debug information to assist test failure triage")
            say(f"/x/Tests.swift:94: error: {case_name(name)} : {message}")
        say(f"Test Case '{case_name(name)}' {outcome} ({time.time() - began:.3f} seconds).")
    if "/ui-test-evidence/rerun-" in bundle:
        # A re-run: by default the one test it names runs and passes.
        test = [arg for arg in args if arg.startswith("-only-testing:")][0].split(":", 1)[1]
        reruns = scenario["reruns"]
        index = int(bundle.rsplit("rerun-", 1)[1].split(".")[0]) - 1
        answer = reruns[index] if index < len(reruns) else "passed"
        say("Test Suite 'Selected tests' started at now.")
        say("the re-run's own output")
        if answer == "nothing":
            say("\\t Executed 0 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds")
            sys.exit(0)
        started(test)
        ended(test, "failed" if answer == "failed" else answer)
        failures = 1 if answer == "failed" else 0
        noun = "failure" if failures == 1 else "failures"
        skipped = "1 test skipped and " if answer == "skipped" else ""
        say(f"\\t Executed 1 test, with {skipped}{failures} {noun} (0 unexpected) in 0.1 (0.1) seconds")
        sys.exit(65 if answer == "failed" else 0)
    if not os.environ.get("STREAM_BROKEN"):
        wait_for(lambda: contains("cancelled-taps.log", "Timestamp"))
    say("Test Suite 'Selected tests' started at now.")
    for item in scenario["first"]:
        kind = item[0]
        if kind == "tap":
            tap()
        elif kind == "connect":
            connect(item[1])
        elif kind == "chord":
            chord(*item[1:])
        elif kind == "register":
            register(item[1])
        elif kind == "started":
            started(item[1])
        elif kind == "say":
            say(item[1])
        elif kind == "stderr":
            print(item[1], file=sys.stderr, flush=True)
        elif kind == "exit":
            sys.exit(item[1])
        else:
            ended(item[1], kind, *item[2:])
    """)


def run_case(name, outcome, *, tap=False, message=None):
    steps = [["started", name]]
    if tap:
        steps.append(["tap"])
    steps.append([outcome, name] + ([message] if message else []))
    return steps


def summary(executed, failures, unexpected=0):
    noun = "test" if executed == 1 else "tests"
    word = "failure" if failures == 1 else "failures"
    return [["say", f"\\t Executed {executed} {noun}, with {failures} {word} ({unexpected} unexpected) in 1.0 (1.0) seconds"]]


class RunUITestsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("pgrep") is None or shutil.which("pkill") is None:
            raise unittest.SkipTest("needs pgrep and pkill")

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        self.addCleanup(self.kill_stand_ins)
        self.bin = self.dir / "bin"
        self.bin.mkdir()
        for name, body in (("xcrun", XCRUN), ("xcodebuild", XCODEBUILD)):
            path = self.bin / name
            path.write_text(f"#!{sys.executable}\n" + body)
            path.chmod(0o755)
        self.stub = self.dir / "stub"
        self.stub.mkdir()
        self.tmp = self.dir / "tmp"
        self.tmp.mkdir()
        self.evidence = self.dir / "ui-test-evidence"
        self.summary = self.dir / "summary.md"

    def kill_stand_ins(self):
        found = subprocess.run(["pgrep", "-f", str(self.bin)], capture_output=True, text=True).stdout.split()
        for pid in found:
            try:
                os.kill(int(pid), signal.SIGKILL)
            except (ProcessLookupError, ValueError):
                pass

    def run_script(self, first, reruns=(), stream_broken=False):
        """Run the script once. `first` is the first run's steps; ["say", line] prints a line."""
        steps = []
        for step in first:
            steps.append(step)
        (self.stub / "scenario.json").write_text(json.dumps({"first": steps, "reruns": list(reruns)}))
        env = dict(os.environ, PATH=f"{self.bin}{os.pathsep}{os.environ['PATH']}", STUB_DIR=str(self.stub),
                   TMPDIR=str(self.tmp), GITHUB_STEP_SUMMARY=str(self.summary))
        env.pop("STREAM_BROKEN", None)
        if stream_broken:
            env["STREAM_BROKEN"] = "yes"
        began = time.time()
        # Output goes to files, not pipes: a process the script leaves behind must not be able
        # to hold this test open by keeping a pipe of ours.
        with open(self.dir / "stdout.txt", "w+") as out, open(self.dir / "stderr.txt", "w+") as err:
            process = subprocess.Popen(["bash", str(SCRIPT), "fake.xctestrun", "SIM-1", str(self.dir / "first.xcresult"),
                                        str(self.evidence), *SHARD], env=env, stdout=out, stderr=err,
                                       stdin=subprocess.DEVNULL)
            try:
                code = process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
                self.fail("the script did not finish within 30 s")
            out.seek(0)
            err.seek(0)
            result = subprocess.CompletedProcess(process.args, code, out.read(), err.read())
        self.assertLess(time.time() - began, 20)
        left = subprocess.run(["pgrep", "-f", str(self.bin)], capture_output=True, text=True).stdout.split()
        self.assertEqual(left, [], "a stand-in outlived the script")
        self.assertEqual(os.listdir(self.tmp), [], "the script left its scratch directory behind")
        return result

    def calls(self):
        path = self.stub / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def reruns(self):
        return [call[1:] for call in self.calls()
                if call[0] == "xcodebuild" and "/ui-test-evidence/rerun-" in call[call.index("-resultBundlePath") + 1]]

    def assert_rerun_of(self, call, test, number):
        self.assertEqual(call, ["-xctestrun", "fake.xctestrun", "-destination", "platform=iOS Simulator,id=SIM-1",
                                "-resultBundlePath", str(self.evidence / f"rerun-{number}.xcresult"),
                                "-parallel-testing-enabled", "NO", f"-only-testing:{test}", "test-without-building"])

    def assert_evidence(self):
        self.assertLessEqual({"cancelled-taps.log", "test-times.tsv"}, set(os.listdir(self.evidence)))
        self.assertIn("unknown digitizer", (self.evidence / "cancelled-taps.log").read_text())
        self.assertIn("\tsession\tstarted", (self.evidence / "test-times.tsv").read_text())

    def test_a_shard_that_passes_leaves_no_evidence(self):
        result = self.run_script(run_case(A, "passed") + summary(1, 0) + [["exit", 0]])
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.reruns(), [])
        self.assertFalse(self.evidence.exists())
        self.assertFalse(self.summary.exists())
        self.assertIn(f"Test Case '-[ThorbisUITests.CustomerDocumentBookUITests testEstimateReview]' passed", result.stdout)
        first = [call for call in self.calls() if call[0] == "xcodebuild"][0]
        self.assertEqual(first[-3:], SHARD + ["test-without-building"])

    def test_a_failure_with_a_cancelled_tap_runs_that_test_once_more_and_passes_if_it_does(self):
        result = self.run_script(run_case(A, "failed", tap=True) + [["stderr", "error: on stderr"]] + summary(1, 1) + [["exit", 65]])
        self.assertEqual(result.returncode, 0, result.stderr)
        reruns = self.reruns()
        self.assertEqual(len(reruns), 1)
        self.assert_rerun_of(reruns[0], A, 1)
        self.assert_evidence()
        self.assertIn(f"::warning::Running {A} once more by itself", result.stdout)
        self.assertIn(f"- `{A}`", self.summary.read_text())
        self.assertIn("error: on stderr", result.stdout)    # xcodebuild's stderr reaches the log
        self.assertIn("the re-run's own output", result.stdout)
        self.assertIn("failed on the wait that came next", self.summary.read_text())
        self.assertTrue((self.evidence / "rerun-1-times.tsv").exists())
        self.assertTrue((self.evidence / "decision.txt").exists())

    def test_a_failure_with_a_cancelled_tap_that_fails_again_stands(self):
        result = self.run_script(run_case(A, "failed", tap=True) + summary(1, 1) + [["exit", 65]], reruns=["failed"])
        self.assertEqual(result.returncode, 65)
        self.assertEqual(len(self.reruns()), 1)
        self.assertIn(f"::error::{A} did not pass when run once more", result.stdout)
        self.assertFalse(self.summary.exists())

    def test_a_failure_without_a_cancelled_tap_stands(self):
        result = self.run_script(run_case(A, "failed") + summary(1, 1) + [["exit", 65]])
        self.assertEqual(result.returncode, 65)
        self.assertEqual(self.reruns(), [])
        self.assertIn("This failure stands", result.stderr)
        self.assertTrue((self.evidence / "test-times.tsv").exists())
        self.assertFalse(self.summary.exists())

    def test_a_cancelled_tap_before_the_test_started_does_not_excuse_it(self):
        result = self.run_script([["tap"]] + run_case(A, "failed") + summary(1, 1) + [["exit", 65]])
        self.assertEqual(result.returncode, 65)
        self.assertEqual(self.reruns(), [])
        self.assert_evidence()

    def test_two_failures_and_one_cancelled_tap_stand(self):
        first = run_case(A, "failed", tap=True) + run_case(B, "failed") + summary(2, 2) + [["exit", 65]]
        result = self.run_script(first)
        self.assertEqual(result.returncode, 65)
        self.assertEqual(self.reruns(), [])

    def test_two_failures_with_a_cancelled_tap_each_run_once_more_each_by_itself(self):
        first = run_case(A, "failed", tap=True) + run_case(B, "failed", tap=True) + summary(2, 2) + [["exit", 65]]
        result = self.run_script(first)
        self.assertEqual(result.returncode, 0, result.stderr)
        reruns = self.reruns()
        self.assertEqual(len(reruns), 2)
        self.assert_rerun_of(reruns[0], A, 1)
        self.assert_rerun_of(reruns[1], B, 2)

    def test_the_second_rerun_failing_fails_the_step(self):
        first = run_case(A, "failed", tap=True) + run_case(B, "failed", tap=True) + summary(2, 2) + [["exit", 65]]
        result = self.run_script(first, reruns=["passed", "failed"])
        self.assertEqual(result.returncode, 65)
        self.assertEqual(len(self.reruns()), 2)

    def test_a_crash_mid_test_keeps_xcodebuilds_status(self):
        result = self.run_script([["started", A], ["tap"], ["exit", 70]])
        self.assertEqual(result.returncode, 70)
        self.assertEqual(self.reruns(), [])
        self.assert_evidence()

    def test_a_failed_run_with_no_failed_test_keeps_its_status(self):
        result = self.run_script([["tap"]] + run_case(A, "passed", tap=True) + summary(1, 0) + [["exit", 70]])
        self.assertEqual(result.returncode, 70)
        self.assertEqual(self.reruns(), [])

    def test_a_broken_log_stream_means_no_rerun(self):
        result = self.run_script(run_case(A, "failed") + summary(1, 1) + [["exit", 65]], stream_broken=True)
        self.assertEqual(result.returncode, 65)
        self.assertEqual(self.reruns(), [])
        self.assertTrue((self.evidence / "cancelled-taps.log").exists())
        self.assertIn("Simulator log filter: the log stream wrote nothing", result.stderr)

    def test_every_run_says_which_filter_the_log_stream_accepted(self):
        result = self.run_script(run_case(A, "passed") + summary(1, 0) + [["exit", 0]])
        self.assertEqual(result.returncode, 0)
        self.assertIn('Simulator log filter: Filtering the log data using "process == "backboardd"', result.stderr)
        broken = self.run_script(run_case(A, "passed") + summary(1, 0) + [["exit", 0]], stream_broken=True)
        self.assertEqual(broken.returncode, 0)
        self.assertIn("Simulator log filter: the log stream wrote nothing", broken.stderr)

    def test_a_rerun_that_skips_the_test_or_runs_nothing_stands(self):
        for answer in ("skipped", "nothing"):
            with self.subTest(answer=answer):
                result = self.run_script(run_case(A, "failed", tap=True) + summary(1, 1) + [["exit", 65]], reruns=[answer])
                self.assertEqual(result.returncode, 65)
                self.assertEqual(len(self.reruns()), 1)
                self.assertIn(f"::error::{A} did not pass when run once more", result.stdout)
                self.assertFalse(self.summary.exists())
                (self.stub / "calls.jsonl").unlink()
                shutil.rmtree(self.evidence)

    def test_a_crash_at_a_cancelled_tap_stands(self):
        first = run_case(A, "failed", tap=True, message="Thorbis crashed in JobOverview.body.getter") + summary(1, 1)
        result = self.run_script(first + [["exit", 65]])
        self.assertEqual(result.returncode, 65)
        self.assertEqual(self.reruns(), [])
        self.assertIn("is not a wait", result.stderr)
        result = self.run_script(run_case(A, "failed", tap=True) + summary(1, 1, unexpected=1) + [["exit", 65]])
        self.assertEqual(result.returncode, 65)
        self.assertEqual(self.reruns(), [])

    def test_a_failure_that_is_not_xcodebuilds_test_failure_status_stands(self):
        first = run_case(A, "failed", tap=True) + summary(1, 1)
        first += [["say", "Testing failed:"], ["say", "\tThorbis encountered an error outside any test"], ["exit", 70]]
        result = self.run_script(first)
        self.assertEqual(result.returncode, 70)
        self.assertEqual(self.reruns(), [])
        self.assertIn("not 65", result.stderr)

    def lost_chord(self, name, reached=False):
        """A test that pressed ⌘K twice, each time before the app (pid 4242) had registered."""
        return ([["started", name], ["connect", 4242], ["chord", 4242], ["chord", 4242, reached],
                 ["register", 4242], ["failed", name, "XCTAssertTrue failed - ⌘K opens Search"]])

    def test_a_failure_on_a_chord_the_simulator_did_not_deliver_runs_once_more_and_passes_if_it_does(self):
        result = self.run_script(self.lost_chord(A) + summary(1, 1) + [["exit", 65]])
        self.assertEqual(result.returncode, 0, result.stderr)
        reruns = self.reruns()
        self.assertEqual(len(reruns), 1)
        self.assert_rerun_of(reruns[0], A, 1)
        self.assertIn(f"::warning::Running {A} once more by itself: the simulator did not deliver the key chord",
                      result.stdout)
        self.assertIn("did not deliver the key chord it failed on", (self.evidence / "decision.txt").read_text())
        log = (self.evidence / "cancelled-taps.log").read_text()
        self.assertIn("cache miss for Keyboard event", log)
        self.assertIn("    glb: (r", log)       # a registration's later lines, as logged
        self.assertIn(f"- `{A}`", self.summary.read_text())
        self.assertIn("lost key chord", self.summary.read_text())

    def test_a_lost_chord_that_fails_again_stands(self):
        result = self.run_script(self.lost_chord(A) + summary(1, 1) + [["exit", 65]], reruns=["failed"])
        self.assertEqual(result.returncode, 65)
        self.assertEqual(len(self.reruns()), 1)
        self.assertIn(f"::error::{A} did not pass when run once more", result.stdout)
        self.assertFalse(self.summary.exists())

    def test_a_chord_that_reached_the_app_stands(self):
        result = self.run_script(self.lost_chord(A, reached=True) + summary(1, 1) + [["exit", 65]])
        self.assertEqual(result.returncode, 65)
        self.assertEqual(self.reruns(), [])
        self.assertIn("so a chord reached it", result.stderr)
        self.assertFalse(self.summary.exists())

    def test_a_cancelled_tap_and_a_lost_chord_each_run_once_more_each_by_itself(self):
        first = run_case(A, "failed", tap=True) + self.lost_chord(B) + summary(2, 2) + [["exit", 65]]
        result = self.run_script(first)
        self.assertEqual(result.returncode, 0, result.stderr)
        reruns = self.reruns()
        self.assertEqual(len(reruns), 2)
        self.assert_rerun_of(reruns[0], A, 1)
        self.assert_rerun_of(reruns[1], B, 2)
        self.assertIn(f"::warning::Running {A} once more by itself: the simulator cancelled the tap", result.stdout)
        self.assertIn(f"::warning::Running {B} once more by itself: the simulator did not deliver the key chord",
                      result.stdout)

    def test_the_stream_keeps_the_key_lines_and_the_stopper_still_finds_it(self):
        self.run_script(run_case(A, "passed") + summary(1, 0) + [["exit", 0]])
        stream = [call for call in self.calls() if call[0] == "xcrun"][0]
        predicate = stream[stream.index("--predicate") + 1]
        self.assertTrue(predicate.startswith('process == "backboardd" AND (eventMessage CONTAINS "unknown digitizer" OR '))
        for clause in ('eventMessage CONTAINS "KCMD: "', 'eventMessage CONTAINS "cache miss for Keyboard event"',
                       'eventMessage CONTAINS "sequence starting with Keyboard event"',
                       'eventMessage CONTAINS "new key command registrations for pid:"',
                       '(eventMessage CONTAINS "Connection added: " AND eventMessage CONTAINS " process:Thorbis ")'):
            self.assertIn(clause, predicate)
        self.assertEqual(predicate.count("("), predicate.count(")"))
        self.assertIn('eventMessage CONTAINS "unknown digitizer"', SCRIPT.read_text().split("stop_watcher() {", 1)[1])

    def test_a_wrong_command_line_is_refused(self):
        result = subprocess.run(["bash", str(SCRIPT), "a", "b", "c", "d"], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
