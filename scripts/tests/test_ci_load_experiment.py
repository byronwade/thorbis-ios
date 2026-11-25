"""Drive scripts/ci-load-experiment.sh (BYR-1896) with stand-ins for the macOS commands it runs.

This machine is Linux, so xcrun, sudo, mdutil, ps, pkill and sw_vers are one small Python program put
first on PATH under each name. It notes every call and answers from a list of (pattern, answers) the
test writes: the first pattern that matches the command line gives the answer, the n-th call the n-th
answer (the last one repeats). The answers' texts are invented; nothing here has run on macOS. perl,
awk, python3 and bash are the real ones. Every wait is bounded.
"""
import json
import os
import re
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
SCRIPT = ROOT / "scripts" / "ci-load-experiment.sh"
NAMES = ("xcrun", "sudo", "mdutil", "ps", "pkill", "sw_vers", "kill")
REAL_KILL = shutil.which("kill") or "/bin/kill"

STAND_IN = textwrap.dedent("""\
    import json, os, re, sys, time
    stub = os.environ["STUB_DIR"]
    name = os.path.basename(sys.argv[0])
    line = " ".join([name] + sys.argv[1:])
    if name == "kill" and "-TERM" not in sys.argv:
        # Ending one of the script's own streams: the real kill. A -TERM is aimed at a simulator
        # daemon's pid, which on this machine is no such process, so it never reaches the real one.
        os.execv(os.environ["REAL_KILL"], ["kill"] + sys.argv[1:])
    with open(os.path.join(stub, "calls.jsonl"), "a") as calls:
        calls.write(json.dumps([name] + sys.argv[1:]) + "\\n")
    with open(os.path.join(stub, "answers.json")) as handle:
        answers = json.load(handle)
    for index, (pattern, replies) in enumerate(answers):
        if re.search(pattern, line):
            count_file = os.path.join(stub, f"count-{index}")
            n = int(open(count_file).read()) if os.path.exists(count_file) else 0
            open(count_file, "w").write(str(n + 1))
            reply = replies[min(n, len(replies) - 1)]
            break
    else:
        reply = {}
    sys.stdout.write(reply.get("out", ""))
    sys.stdout.flush()
    sys.stderr.write(reply.get("err", ""))
    if reply.get("append"):
        with open(os.path.join(stub, "stream-lines"), "a") as handle:
            handle.write(reply["append"] + "\\n")
    if reply.get("stream"):
        # A log stream: its first line is the filter it accepted (as the real one prints it), then
        # its lines come from a file the test appends to, until it is signalled.
        if reply.get("first"):
            print(reply["first"], flush=True)
        sent, end = 0, time.time() + 30
        while time.time() < end:
            path = os.path.join(stub, "stream-lines")
            lines = open(path).read().splitlines() if os.path.exists(path) else []
            for text in lines[sent:]:
                print(text, flush=True)
            sent = len(lines)
            time.sleep(0.05)
    time.sleep(reply.get("sleep", 0))
    sys.exit(reply.get("rc", 0))
    """)

CENSUS = (" 1   0 root 10:00 launchd\n"
          " 2793     1 root 09:00 diagnosticd\n"
          " 900      1 runner 08:00 launchd_sim\n"
          " 2798   900 runner 07:00 diagnosticd\n"
          " 1450   900 runner 07:00 apsd\n"
          " 600      1 root 07:00 mds_stores\n")
CENSUS_NO_APSD = CENSUS.replace(" 1450   900 runner 07:00 apsd\n", "")
LIST = "PID\tStatus\tLabel\n1450\t0\tcom.apple.apsd\n77\t0\tcom.apple.backboardd\n"
LIST_NO_APSD = "PID\tStatus\tLabel\n77\t0\tcom.apple.backboardd\n"
ENABLED = "/:\n\tIndexing enabled. \n/System/Volumes/Data:\n\tIndexing enabled. \n"
DISABLED = "/:\n\tIndexing disabled. \n/System/Volumes/Data:\n\tIndexing disabled. \n"
ADDED = ("2026-11-25 12:00:00.000 Df backboardd[5334:466d] [com.apple.BackBoard:EventDelivery] Connection added: "
         "IOHIDEventSystemConnection uuid:A pid:4242 process:Thorbis type:Passive")
DATA_ONLY_ON = "/:\n\tIndexing disabled. \n/System/Volumes/Data:\n\tIndexing enabled. \n"
OFF_CALLS = [["sudo", "-n", "mdutil", "-i", "off", "/"], ["sudo", "-n", "mdutil", "-i", "off", "/System/Volumes/Data"]]
# The log tool's first line quotes the filter it accepted, and that filter holds "Connection added: ".
FILTER = subprocess.run([sys.executable, "-I", str(ROOT / "scripts" / "ci_log_compare.py"), "predicate"],
                        capture_output=True, text=True, check=True).stdout.strip()
HEADER = f'Filtering the log data using "{FILTER}"'
SIM_JSON = json.dumps({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
    {"name": "iPhone 17 Pro", "udid": "AAAAAAAA-1111-2222-3333-444444444444"},
    {"name": "iPad Pro 13-inch (M5)", "udid": "BBBBBBBB-1111-2222-3333-444444444444"}]}})


class ExperimentCase(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        self.addCleanup(self.kill_stand_ins)
        self.bin = self.dir / "bin"
        self.bin.mkdir()
        for name in NAMES:
            path = self.bin / name
            path.write_text(f"#!{sys.executable}\n" + STAND_IN)
            path.chmod(0o755)
        self.stub = self.dir / "stub"
        self.stub.mkdir()
        self.cpu = self.dir / "cpu-load"
        self.exp = self.dir / "load-experiment"
        self.github_env = self.dir / "github-env"
        self.summary = self.dir / "summary.md"
        self.answers([])

    def kill_stand_ins(self):
        found = subprocess.run(["pgrep", "-f", str(self.bin)], capture_output=True, text=True).stdout.split()
        for pid in found:
            try:
                os.kill(int(pid), signal.SIGKILL)
            except (ProcessLookupError, ValueError):
                pass

    def answers(self, items):
        (self.stub / "answers.json").write_text(json.dumps(items))
        for path in self.stub.glob("count-*"):
            path.unlink()

    def env(self, **extra):
        # THORBIS_LOAD_PAUSE makes each of the script's waits (up to 20 s on CI) a tenth of a second.
        env = dict(os.environ, PATH=f"{self.bin}{os.pathsep}{os.environ['PATH']}", STUB_DIR=str(self.stub),
                   GITHUB_ENV=str(self.github_env), GITHUB_STEP_SUMMARY=str(self.summary), THORBIS_LOAD_PAUSE="0.1",
                   REAL_KILL=REAL_KILL)
        for key in ("THORBIS_JOB_STARTED", "THORBIS_LOAD_ALARM_CAP", "THORBIS_RERUN_EVIDENCE", "THORBIS_LOAD_SHARDS",
                    "THORBIS_LOAD_DEVICE"):
            env.pop(key, None)
        env.update(extra)
        return env

    def run_phase(self, phase, shard, sim="SIM-1", timeout=60, **extra):
        args = ["bash", str(SCRIPT), phase, shard, str(self.cpu), str(self.exp)] + ([sim] if sim is not None else [])
        began = time.time()
        result = subprocess.run(args, env=self.env(**extra), capture_output=True, text=True, timeout=timeout,
                                stdin=subprocess.DEVNULL)
        self.took = time.time() - began
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"ci-load-experiment.sh {phase}: ended with status", result.stdout)
        return result.stdout + result.stderr

    def calls(self):
        path = self.stub / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def treatment(self):
        path = self.cpu / "treatment.txt"
        return path.read_text() if path.exists() else ""

    def started_now(self, minutes_ago=0):
        return str(int(time.time()) - minutes_ago * 60)


class PlanTests(ExperimentCase):
    def test_each_shard_gets_its_plan_word_and_nothing_else_is_printed(self):
        expected = {"phone1": "none", "phone2": "none", "ipad1": "none", "phone3": "spotlight-off",
                    "phone6": "spotlight-off", "phone4": "apsd-off", "phone5": "apsd-off", "ipad2": "apsd-off",
                    "phone9": "unknown", "": "unknown"}
        for shard, word in expected.items():
            result = subprocess.run(["bash", str(SCRIPT), "plan", shard], capture_output=True, text=True, timeout=10)
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, word + "\n", ""), shard)

    def test_a_shard_not_in_the_plan_is_untreated_and_says_so(self):
        out = self.run_phase("host", "phone9")
        self.assertIn("::warning::Load experiment: shard phone9 is not in the plan, so it is untreated", out)
        self.assertIn("LOAD EXPERIMENT phone9 plan unknown (not in the plan, untreated)", self.treatment())
        self.assertFalse([call for call in self.calls() if call[0] == "sudo"])

    def test_a_wrong_command_line_still_exits_zero_with_a_warning(self):
        for args in (["nonsense", "phone1", "a", "b"], ["host", "phone1"]):
            result = subprocess.run(["bash", str(SCRIPT), *args], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0)
            self.assertIn("usage:", result.stdout)
            self.assertIn("::warning::Load experiment: the", result.stdout)


class HostTests(ExperimentCase):
    def test_a_control_notes_the_job_start_and_changes_nothing(self):
        self.answers([[r"^ps -Ao", [{"out": CENSUS}]], [r"^mdutil -s -a", [{"out": ENABLED}]],
                      [r"^sw_vers", [{"out": "ProductVersion:\t15.7\n"}]]])
        out = self.run_phase("host", "phone1", THORBIS_LOAD_SHARDS="6")
        self.assertRegex(self.github_env.read_text(), r"^THORBIS_JOB_STARTED=\d+\n$")
        self.assertIn("LOAD EXPERIMENT phone1 plan none (control)", self.treatment())
        self.assertFalse([call for call in self.calls() if call[0] == "sudo"])
        self.assertIn(" 2798   900 runner 07:00 diagnosticd", out)
        self.assertIn("+ ps -Ao pid=,ppid=,user=,etime=,ucomm= (alarm 10 s)", out)
        facts = (self.cpu / "runner-facts.txt").read_text()
        self.assertIn("runner image", facts)
        self.assertRegex(facts, r"shard list sha256 [0-9a-f]{16} \(exit 0; ui_test_shards.py +--shards 6 --index 1\)")

    def test_spotlight_off_runs_mdutil_once_and_proves_it_after(self):
        self.answers([[r"^mdutil -s / ", [{"out": ENABLED}, {"out": DISABLED}]], [r"^sudo -n mdutil -i off", [{"out": "/:\n\tIndexing disabled.\n"}]]])
        out = self.run_phase("host", "phone3")
        sudo = [call for call in self.calls() if call[0] == "sudo"]
        # By name, never -a: -a also reaches every mounted image, and one refusing would spoil the exit.
        self.assertEqual(sudo, OFF_CALLS)
        self.assertIn(["mdutil", "-s", "-a"], self.calls()[-1:])
        self.assertIn("LOAD EXPERIMENT phone3 host spotlight-off: started", self.treatment())
        self.assertIn("LOAD EXPERIMENT phone3 host spotlight-off: applied yes", self.treatment())
        self.assertIn("::notice::Load experiment: spotlight-off was applied in phone3", out)
        self.assertIn("applied yes", self.summary.read_text())

    def test_spotlight_still_on_for_data_is_not_applied(self):
        self.answers([[r"^mdutil -s / ", [{"out": ENABLED}, {"out": DATA_ONLY_ON}]]])
        out = self.run_phase("host", "phone6")
        self.assertIn("LOAD EXPERIMENT phone6 host spotlight-off: applied no", self.treatment())
        self.assertIn("::warning::Load experiment: spotlight-off was NOT applied in phone6", out)
        self.assertIn("This shard counts as untreated.", out)

    def test_a_sudo_that_fails_is_printed_with_its_stderr_and_status(self):
        self.answers([[r"^mdutil -s / ", [{"out": ENABLED}]],
                      [r"^sudo", [{"err": "sudo: a password is required\n", "rc": 1}]]])
        out = self.run_phase("host", "phone3")
        self.assertIn("stderr:\nsudo: a password is required", out)
        self.assertIn("exit 1 (spotlight-off-root)", out)
        self.assertIn("::warning::Load experiment: spotlight-off-root exited 1 (output above). The job goes on.", out)
        self.assertIn("applied no", self.treatment())

    def test_one_volume_that_refuses_is_not_known_even_when_both_read_disabled(self):
        self.answers([[r"^mdutil -s / ", [{"out": ENABLED}, {"out": DISABLED}]],
                      [r"^sudo -n mdutil -i off /System", [{"err": "Error: unknown indexing state.\n", "rc": 1}]]])
        out = self.run_phase("host", "phone3")
        self.assertIn("exit 1 (spotlight-off-data)", out)
        self.assertIn("applied not known (sudo -n mdutil -i off: / exit 0, /System/Volumes/Data exit 1;", self.treatment())

    def test_a_volume_list_without_the_data_volume_is_not_known(self):
        self.answers([[r"^mdutil -s / ", [{"out": "/:\n\tIndexing disabled.\n"}]]])
        self.run_phase("host", "phone3")
        self.assertIn("applied not known", self.treatment())

    def test_a_command_that_hangs_is_stopped_by_its_alarm(self):
        self.answers([[r"^ps -Ao", [{"sleep": 60}]]])
        out = self.run_phase("host", "phone1", THORBIS_LOAD_ALARM_CAP="1")
        self.assertIn("exit 142 (host-census: stopped by its 1 s alarm)", out)
        self.assertLess(self.took, 15)

    def test_a_missing_command_prints_why(self):
        (self.bin / "mdutil").unlink()
        out = self.run_phase("host", "phone3")
        self.assertIn("cannot run mdutil", out)
        self.assertRegex(out, r"exit [1-9]\d* \(spotlight-all\)")


class SimTests(ExperimentCase):
    def test_a_control_runs_nothing_in_the_simulator(self):
        for shard in ("phone1", "phone2", "ipad1", "phone9"):
            out = self.run_phase("sim", shard)
            self.assertIn("nothing is done in the simulator", out)
        self.assertEqual(self.calls(), [])

    def test_spotlight_found_on_after_boot_is_turned_off_again(self):
        (self.cpu).mkdir()
        (self.cpu / "treatment.txt").write_text("LOAD EXPERIMENT phone3 host spotlight-off: applied yes (x)\n")
        self.answers([[r"^mdutil -s / ", [{"out": ENABLED}, {"out": DISABLED}]]])
        self.run_phase("sim", "phone3")
        self.assertEqual([c for c in self.calls() if c[0] == "sudo"], OFF_CALLS)
        self.assertIn("LOAD EXPERIMENT phone3 sim spotlight-off: applied yes", self.treatment())

    def test_spotlight_still_off_after_boot_is_left_alone(self):
        (self.cpu).mkdir()
        (self.cpu / "treatment.txt").write_text("LOAD EXPERIMENT phone3 host spotlight-off: applied yes (x)\n")
        self.answers([[r"^mdutil -s / ", [{"out": DISABLED}]]])
        self.run_phase("sim", "phone3")
        self.assertEqual([c for c in self.calls() if c[0] == "sudo"], [])
        self.assertIn("sim spotlight-off: applied yes", self.treatment())

    def apsd_answers(self, bootout=None, list_after=LIST_NO_APSD, census_after=CENSUS_NO_APSD, list_before=None):
        return [[r"launchctl list", [list_before or {"out": LIST}, {"out": list_after}]],
                [r"launchctl print", [{"err": "Could not find service\n", "rc": 113}]],
                [r"launchctl bootout", [bootout or {}]],
                [r"^ps -p 1450", [{"rc": 1}]],
                [r"^ps -Ao", [{"out": census_after}]]]

    def test_apsd_off_boots_apsd_out_and_proves_it_gone(self):
        self.answers(self.apsd_answers())
        out = self.run_phase("sim", "phone4")
        spawned = [c[4:] for c in self.calls() if c[:2] == ["xcrun", "simctl"]]
        self.assertIn(["launchctl", "bootout", "system/com.apple.apsd"], spawned)
        self.assertIn("LOAD EXPERIMENT phone4 sim apsd-off: started", self.treatment())
        self.assertIn("LOAD EXPERIMENT phone4 sim apsd-off: applied yes", self.treatment())
        self.assertIn("apsd pid 1450 gone: yes", out)
        self.assertNotIn("::warning::Load experiment: apsd-print-before", out)

    def test_apsd_bootout_that_fails_is_not_applied(self):
        self.answers(self.apsd_answers(bootout={"rc": 5, "err": "Boot-out failed: 5: Input/output error\n"},
                                       list_after=LIST, census_after=CENSUS))
        out = self.run_phase("sim", "ipad2")
        self.assertIn("Boot-out failed: 5", out)
        self.assertIn("exit 5 (apsd-bootout)", out)
        self.assertIn("sim apsd-off: applied no (launchctl bootout exited 5; launchctl list still has com.apple.apsd)",
                      self.treatment())

    def test_a_bootout_stopped_by_its_alarm_is_not_known_whatever_follows(self):
        # The alarm ends xcrun, not launchctl inside the simulator, so the list after proves nothing.
        self.answers(self.apsd_answers(bootout={"sleep": 30}, list_after=LIST, census_after=CENSUS))
        out = self.run_phase("sim", "phone4", THORBIS_LOAD_ALARM_CAP="1")
        self.assertIn("exit 142 (apsd-bootout: stopped by its 1 s alarm)", out)
        self.assertIn("sim apsd-off: applied not known (launchctl bootout was stopped by its alarm", self.treatment())

    def test_the_sim_phase_notes_its_seconds_in_every_shard(self):
        self.run_phase("sim", "phone1")
        self.assertRegex(self.treatment(), r"LOAD EXPERIMENT phone1 sim none: took \d+ s of the warm step\n")

    def test_no_apsd_in_the_list_stops_nothing(self):
        self.answers(self.apsd_answers(list_before={"out": LIST_NO_APSD + "88\t0\tcom.apple.apsd.helper\n"}))
        out = self.run_phase("sim", "phone5")
        self.assertFalse([c for c in self.calls() if "bootout" in c])
        self.assertIn("com.apple.apsd.helper", out)
        self.assertIn("applied no (launchctl list (exit 0) has no com.apple.apsd row; nothing was stopped)", self.treatment())

    def test_a_list_that_fails_stops_nothing(self):
        self.answers(self.apsd_answers(list_before={"rc": 64, "err": "Unrecognized subcommand\n"}))
        self.run_phase("sim", "phone5")
        self.assertFalse([c for c in self.calls() if "bootout" in c])
        self.assertIn("launchctl list in the simulator exited 64", self.treatment())

    def test_apsd_still_under_launchd_sim_is_not_applied(self):
        self.answers(self.apsd_answers(census_after=CENSUS.replace("1450", "1460")))
        self.run_phase("sim", "phone4")
        self.assertIn("applied no (launchctl bootout exited 0; an apsd runs under launchd_sim)", self.treatment())

    def test_no_simulator_id_stops_nothing(self):
        out = self.run_phase("sim", "phone4", sim="")
        self.assertEqual(self.calls(), [])
        self.assertIn("applied no (no simulator id, so nothing was stopped)", self.treatment())
        self.assertIn("This shard counts as untreated.", out)

    def test_a_phase_cut_by_its_outer_alarm_reads_not_known(self):
        # As the warm step runs it: perl's alarm, kept across exec, stops the script itself.
        self.answers(self.apsd_answers(bootout={"sleep": 4}))
        env = self.env()
        result = subprocess.run(["perl", "-e", 'alarm shift; exec { $ARGV[0] } @ARGV or die "cannot run"', "2", "bash",
                                 str(SCRIPT), "sim", "phone4", str(self.cpu), str(self.exp), "SIM-1"],
                                env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("got SIGALRM", result.stdout)
        self.assertIn("LOAD EXPERIMENT phone4 sim apsd-off: started", self.treatment())
        self.assertIn("applied not known (the sim phase ended (status 142) before its verdict)", self.treatment())


class AfterTests(ExperimentCase):
    def test_after_says_whether_apsd_came_back(self):
        self.answers([[r"^ps -Ao", [{"out": CENSUS}]], [r"launchctl list", [{"out": LIST_NO_APSD}]]])
        self.run_phase("after", "phone4", THORBIS_JOB_STARTED=self.started_now(30))
        self.assertIn("LOAD EXPERIMENT phone4 after apsd-off: came back yes", (self.exp / "after.txt").read_text())
        self.answers([[r"^ps -Ao", [{"out": CENSUS_NO_APSD}]], [r"launchctl list", [{"out": LIST_NO_APSD}]]])
        self.run_phase("after", "phone5", THORBIS_JOB_STARTED=self.started_now(30))
        self.assertIn("LOAD EXPERIMENT phone5 after apsd-off: came back no", (self.exp / "after.txt").read_text())

    def test_after_says_whether_spotlight_is_still_off(self):
        self.answers([[r"^mdutil -s / ", [{"out": ENABLED}]]])
        self.run_phase("after", "phone3", THORBIS_JOB_STARTED=self.started_now(30))
        self.assertIn("after spotlight-off: still disabled no", (self.exp / "after.txt").read_text())

    def test_the_phases_after_the_tests_look_the_simulator_up_themselves_once(self):
        self.answers([[r"^ps -Ao", [{"out": CENSUS}]], [r"launchctl list", [{"out": LIST_NO_APSD}]],
                      [r"simctl list devices available -j", [{"out": SIM_JSON}]]])
        out = self.run_phase("after", "ipad2", sim=None, THORBIS_JOB_STARTED=self.started_now(30), THORBIS_LOAD_DEVICE="iPad")
        self.assertIn("Simulator: iPad Pro 13-inch (M5) on iOS-26-2", out)
        spawned = [c for c in self.calls() if c[:3] == ["xcrun", "simctl", "spawn"]]
        self.assertEqual(spawned[0][3], "BBBBBBBB-1111-2222-3333-444444444444")
        now = int(time.time()) - 100
        (self.exp / "window.txt").write_text(f"began {now}\nended {now + 50}\n")
        (self.exp / "stream.log").write_text(HEADER + "\n")
        out = self.run_phase("compare", "ipad2", sim=None, THORBIS_JOB_STARTED=self.started_now(30), THORBIS_LOAD_DEVICE="iPad")
        self.assertIn(["xcrun", "simctl", "spawn", "BBBBBBBB-1111-2222-3333-444444444444", "log", "show"],
                      [c[:6] for c in self.calls()])
        self.assertIn("simulator id from the lookup of an earlier phase: BBBBBBBB-", out)
        self.assertEqual(len([c for c in self.calls() if "list" in c and "devices" in c]), 1)

    def test_a_simulator_lookup_that_hangs_costs_its_alarm_only(self):
        self.answers([[r"^ps -Ao", [{"out": CENSUS}]], [r"simctl list devices", [{"sleep": 60}]]])
        out = self.run_phase("after", "phone4", sim=None, THORBIS_JOB_STARTED=self.started_now(30),
                             THORBIS_LOAD_DEVICE="iPhone", THORBIS_LOAD_ALARM_CAP="1")
        self.assertLess(self.took, 20)
        self.assertIn("exit 142 (simulator-id: stopped by its 1 s alarm)", out)
        self.assertIn("came back not known (no simulator id)", (self.exp / "after.txt").read_text())
        out = self.run_phase("probe", "phone4", sim=None, THORBIS_JOB_STARTED=self.started_now(30), THORBIS_LOAD_DEVICE="iPhone")
        self.assertIn("simulator id from the lookup of an earlier phase: none (that lookup failed)", out)
        self.assertIn("probe: not run (no simulator id)", out)

    def test_every_phase_after_the_tests_skips_without_time(self):
        for phase, minutes in (("after", None), ("after", 79), ("compare", 74), ("probe", 71)):
            extra = {} if minutes is None else {"THORBIS_JOB_STARTED": self.started_now(minutes)}
            out = self.run_phase(phase, "phone2", **extra)
            self.assertIn(f"::notice::Load experiment: {phase} skipped in phone2", out)
        self.assertEqual(self.calls(), [])
        out = self.run_phase("probe", "phone2", THORBIS_JOB_STARTED="12x")
        self.assertIn("THORBIS_JOB_STARTED is not set or not a time", out)


class CompareTests(ExperimentCase):
    STREAM = ('Filtering the log data using "process == \\"backboardd\\""\n'
              "Timestamp               Ty Process[PID:TID]\n")

    def stream_files(self, began, ended, lines=()):
        self.exp.mkdir(parents=True, exist_ok=True)
        (self.exp / "window.txt").write_text(f"began {began}\nended {ended}\n")
        (self.exp / "stream.log").write_text(self.STREAM + "".join(lines))

    def entry(self, t, message):
        stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t)) + ".%03d" % int(t % 1 * 1000)
        return f"{stamp} Df backboardd[5334:466d] [com.apple.BackBoard:EventDelivery] {message}\n"

    def test_compare_runs_log_show_on_the_streams_window_and_reads_the_store(self):
        now = int(time.time()) - 100
        line = self.entry(now + 10, "Connection added: IOHIDEventSystemConnection uuid:A pid:42 process:Thorbis type:Passive")
        self.stream_files(now, now + 50, [line])
        self.answers([[r"log show", [{"out": "Timestamp               Ty Process[PID:TID]\n" + line +
                                      "--------------------------------------------------------------------------\n"
                                      "Log      - Default:          1, Info:                0, Debug:             0\n"}]]])
        out = self.run_phase("compare", "phone2", THORBIS_JOB_STARTED=self.started_now(20))
        show = [c for c in self.calls() if "show" in c][0]
        expected_start = time.strftime("%Y-%m-%d %H:%M:%S%z", time.localtime(now - 30))
        expected_end = time.strftime("%Y-%m-%d %H:%M:%S%z", time.localtime(now + 80))
        self.assertEqual(show[:7], ["xcrun", "simctl", "spawn", "SIM-1", "log", "show", "--style"])
        self.assertEqual(show[show.index("--start") + 1], expected_start)
        self.assertEqual(show[show.index("--end") + 1], expected_end)
        predicate = show[show.index("--predicate") + 1]
        self.assertTrue(predicate.startswith('process == "backboardd" AND (eventMessage CONTAINS "unknown digitizer"'))
        self.assertTrue((self.exp / "store.log").exists())
        self.assertRegex((self.exp / "log-show.txt").read_text(), r"^exit 0 seconds \d+\n$")
        self.assertIn("log compare: store holds every stream entry: yes", out)
        self.assertIn("::notice::Load experiment (phone2): log compare: store holds every stream entry: yes", out)

    def test_a_log_show_stopped_by_its_alarm_is_not_known(self):
        now = int(time.time()) - 100
        self.stream_files(now, now + 50, [self.entry(now + 10, "KCMD: match in pid:42 keyboardFocus")])
        self.answers([[r"log show", [{"sleep": 30}]]])
        out = self.run_phase("compare", "phone2", THORBIS_JOB_STARTED=self.started_now(20), THORBIS_LOAD_ALARM_CAP="1")
        self.assertIn("exit 142 (log-show: stopped by its 1 s alarm)", out)
        self.assertIn("store holds every stream entry: not known (log show did not finish in its alarm", out)
        self.assertIn("::warning::Load experiment (phone2)", out)

    def test_no_stream_file_is_not_known_and_runs_nothing(self):
        out = self.run_phase("compare", "phone2", THORBIS_JOB_STARTED=self.started_now(20))
        self.assertIn("not known (no stream.log", out)
        self.assertEqual(self.calls(), [])

    def test_a_failed_shard_compares_the_rules_decision_on_both_logs(self):
        now = int(time.time()) - 100
        self.stream_files(now, now + 50, [self.entry(now + 10, "KCMD: match in pid:42 keyboardFocus")])
        evidence = self.dir / "ui-test-reruns"
        evidence.mkdir()
        (evidence / "test-times.tsv").write_text(f"{now + 1}.0\tsession\tstarted\n")
        self.answers([[r"log show", [{"out": "Timestamp               Ty Process[PID:TID]\n"
                                      + self.entry(now + 10, "KCMD: match in pid:42 keyboardFocus")}]]])
        out = self.run_phase("compare", "phone2", THORBIS_JOB_STARTED=self.started_now(20),
                             THORBIS_RERUN_EVIDENCE=str(evidence))
        self.assertIn("exit 1 (decide-stream)", out)
        self.assertIn("exit 1 (decide-store)", out)
        self.assertIn("log compare: decide gives the same tests on the stream and on the store", out)


class ProbeTests(ExperimentCase):
    def probe_answers(self, fail=False):
        bad = {"rc": 1, "err": "failed\n"}
        return [[r"log stream", [{"stream": True, "first": HEADER}]],
                [r"simctl launch", [bad if fail else {"out": "com.thorbis.field: 4242\n", "append": ADDED}]],
                [r"simctl terminate", [bad if fail else {}]],
                [r"launchctl unload", [bad if fail else {}]],
                [r"launchctl print", [{"rc": 113} if not fail else {"rc": 0}]],
                [r"^ps -Ao", [{"out": CENSUS}, {"out": CENSUS.replace(" 2793     1 root 09:00 diagnosticd\n", "")},
                              {"out": CENSUS.replace(" 2793     1 root 09:00 diagnosticd\n", "")
                               .replace("2798   900", "3001   900")}]],
                [r"^ps -o pid=,time=", [{"out": " 2793   1:00.00 diagnosticd\n 2798   0:30.00 diagnosticd\n"},
                                        {"out": " 2793   1:04.00 diagnosticd\n 2798   0:32.00 diagnosticd\n"}]],
                [r"^kill", [bad if fail else {}]],
                [r"^pkill", [{"rc": 1}]]]

    def test_the_probe_unloads_after_s1_kills_after_s2_and_ends_every_stream(self):
        self.answers(self.probe_answers())
        out = self.run_phase("probe", "phone2", timeout=150, THORBIS_JOB_STARTED=self.started_now(20))
        calls = self.calls()
        streams = [i for i, c in enumerate(calls) if "stream" in c]
        unload = [i for i, c in enumerate(calls) if "unload" in c]
        self.assertEqual(len(streams), 3)
        self.assertEqual(len(unload), 1)
        self.assertLess(streams[0], unload[0])
        self.assertLess(unload[0], streams[1])
        self.assertNotIn("-w", calls[unload[0]])
        self.assertIn("probe: diagnosticd 2793 host (parent 1)", out)
        self.assertIn("probe: diagnosticd 2798 sim (parent 900)", out)
        self.assertIn("probe: host unload applied yes", out)
        self.assertIn("probe: sim diagnosticd came back after", out)
        self.assertIn("exit 1 (pkill-streams)", out)
        self.assertRegex(out, r"exit \d+ \(stream-end-3\)")
        self.assertIn("+ kill -TERM 2798", out)
        # Each launch is a fresh start: the app is ended and 3 s pass before every launch.
        launches = [i for i, c in enumerate(calls) if c[:2] == ["xcrun", "simctl"] and c[2] == "launch"]
        self.assertEqual(len(launches), 3)
        for i in launches:
            self.assertEqual(calls[i - 1][2], "terminate")
        self.assertIn("probe: before any change: S1 yes", out)
        self.assertIn("probe: after host unload: S1 yes S2 yes", out)
        self.assertIn("probe: after sim kill: S1 yes S2 yes S3 yes", out)
        left = subprocess.run(["pgrep", "-f", str(self.bin)], capture_output=True, text=True).stdout.split()
        self.assertEqual(left, [], "a stream outlived the probe")

    def test_a_late_header_that_quotes_the_filter_is_not_a_launch_seen(self):
        self.assertIn("Connection added: ", HEADER)
        answers = self.probe_answers()
        # The launch puts only the stream's header line out, after `before` was counted.
        answers[1] = [r"simctl launch", [{"out": "com.thorbis.field: 4242\n", "append": HEADER}]]
        self.answers(answers)
        out = self.run_phase("probe", "phone2", timeout=150, THORBIS_JOB_STARTED=self.started_now(20))
        self.assertIn("probe: before any change: S1 no", out)
        self.assertIn("probe: after sim kill: S1 no S2 no S3 no", out)

    def test_a_stream_that_ended_reads_not_known_not_no(self):
        answers = self.probe_answers()
        answers[0] = [r"log stream", [{"rc": 3, "err": "stream refused\n"}]]
        self.answers(answers)
        out = self.run_phase("probe", "phone2", timeout=150, THORBIS_JOB_STARTED=self.started_now(20))
        self.assertIn("S1 not known (stream ended, exit 3)", out)
        self.assertIn("stream refused", out)

    def test_a_probe_where_everything_fails_still_exits_zero(self):
        self.answers(self.probe_answers(fail=True))
        out = self.run_phase("probe", "phone2", timeout=150, THORBIS_JOB_STARTED=self.started_now(20))
        self.assertIn("probe: host unload applied no", out)
        self.assertIn("exit 1 (launch-1)", out)


class TextTests(unittest.TestCase):
    def test_the_script_keeps_to_bash_3_2_and_never_hides_a_failure(self):
        text = SCRIPT.read_text()
        code = "\n".join(line.split(" #", 1)[0] for line in text.splitlines() if not line.lstrip().startswith("#"))
        for construct in ("declare -A", "mapfile", "readarray", "wait -n", ",,}", "^^}", "@Q}", "[[ -v", "local -n",
                          "coproc", "|&", "&>>", "[-1]}", "EPOCHSECONDS", "timeout ", "date -d", "date -r", "sed -i",
                          "grep -P", "stat -c", "readlink -f", ">/dev/null", "2>/dev/null", "|| true", "set -e",
                          "mdutil -a -i", "-a -i off"):
            self.assertNotIn(construct, code, construct)
        self.assertTrue(os.access(SCRIPT, os.X_OK))
        self.assertTrue(text.startswith("#!/usr/bin/env bash\n"))
        self.assertEqual(subprocess.run(["bash", "-n", str(SCRIPT)]).returncode, 0)

    def test_shellcheck_passes_when_installed(self):
        if shutil.which("shellcheck") is None:
            self.skipTest("shellcheck is not installed")
        for path in (SCRIPT, ROOT / "scripts" / "ci-run-ui-tests.sh"):
            result = subprocess.run(["shellcheck", str(path)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout)

    def test_the_workflow_passes_each_shard_its_own_name(self):
        workflow = (ROOT / ".github" / "workflows" / "ios.yml").read_text()
        for kind in ("phone", "ipad"):
            for phase in ("host", "sim", "after", "probe"):
                self.assertRegex(workflow, rf"ci-load-experiment\.sh[ \\\n]+(\"\$phase\"|{phase}) {kind}\$\{{\{{ matrix\.shard \}}\}}")
            self.assertIn(f"THORBIS_LOAD_SHARD: {kind}${{{{ matrix.shard }}}}", workflow)
        self.assertEqual(workflow.count("THORBIS_LOG_COMPARE:"), 2)
        # After the tests the script looks the simulator up under its own alarm; the workflow does not.
        for step in re.findall(r"- name: Load experiment \(BYR-1896\), [34] of 4.*?(?=\n      - )", workflow, re.S):
            self.assertNotIn("ci-simulator-id.sh", step)
            self.assertRegex(step, r"THORBIS_LOAD_DEVICE: (iPhone|iPad)\n")
        self.assertEqual(workflow.count("THORBIS_LOAD_DEVICE:"), 4)


if __name__ == "__main__":
    unittest.main()
