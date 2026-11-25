#!/usr/bin/env bash
# Run one shard's UI tests, and run a failed test once more only when the simulator itself
# cancelled the tap, or failed to deliver the key chord, that test failed on.
#
#   scripts/ci-run-ui-tests.sh <xctestrun> <simulator-id> <result-bundle> <evidence-dir> \
#       -only-testing:ThorbisUITests/SomeClass [...]
#
# Why: XCTest taps through a virtual touchscreen it attaches for each gesture. On a busy runner
# the simulator's input server sometimes registers that touchscreen twice, drops the lift and
# cancels the touch, and logs "*** unknown digitizer". The app sees a cancelled touch and does
# nothing, so the test fails on a tap no person made (BYR-1835; scripts/ci_cancelled_taps.py
# has the detail). XCTest also presses each keyboard chord through a virtual keyboard it attaches
# for that one press. backboardd hands a ⌘ chord to the app as a key command only once the app
# has registered its key commands with it, and on the iPad that registration now and then comes
# only after the test has pressed twice. Until then it logs a cache miss and hands the app the
# bare letter, or, for a chord SpringBoard's own table holds, lets SpringBoard take it and sends
# the app nothing, so the test fails on a chord the app never received (BYR-1843).
#
# What this does NOT do: retry failures. A failed test is run again only when ALL of these hold.
#   - xcodebuild exited 65, its status for failed tests, and nothing else went wrong.
#   - The run is fully accounted for: one session, every started test finished, and xcodebuild's
#     own count of tests and failures matches the log, with no unexpected failure.
#   - EVERY failed test failed on the wait right after a tap, its first failure speaks of no
#     crash or launch, and backboardd logged that error at that tap; or it failed on the wait
#     right after a key chord, XCTest's record shows that wait ran out, and before the app had
#     registered any key commands backboardd
#     either sent every chord of the test to the app as a bare key or matched every one in
#     SpringBoard's own table and sent the app nothing, matched no command against the app, and
#     the app's first registration after the last chord lists that chord.
#   - There are at most three of them, and the job has time left to run them.
#   - While THORBIS_LOAD_SHARD is set (the runner load experiment, BYR-1896): the shard is one the
#     experiment's plan names as a control. A treated shard, or one the plan cannot place, runs none.
# Each is then run once, by itself. The step passes only if each of those runs shows that one
# test passing. Anything else leaves the first run's failure standing. Every re-run is announced
# as a warning on the job, with the reasons, and listed in the step summary.
#
# While the tests run, a filter on the simulator's log keeps only backboardd's lines for that
# error and for how it routes keys: the app's connection, its key command registrations, each
# key command match and each bare key it hands on. It reads the log; it does not touch the app.
# Evidence (the times, the log lines, the decision, each re-run's times and result bundle) goes
# to <evidence-dir>, which is created only when a test failed.
set -uo pipefail

if [[ $# -lt 5 ]]; then
  echo "usage: ci-run-ui-tests.sh <xctestrun> <simulator-id> <result-bundle> <evidence-dir> -only-testing:... [...]" >&2
  exit 2
fi
test_run=$1
simulator_id=$2
result_bundle=$3
evidence=$4
shift 4

here=$(cd "$(dirname "$0")" && pwd)

run_tests() { # <result bundle> <-only-testing:...>...
  local bundle=$1
  shift
  xcodebuild -xctestrun "$test_run" \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    -resultBundlePath "$bundle" \
    -parallel-testing-enabled NO \
    "$@" test-without-building
}

# Without a scratch directory nothing can be noted, so the tests run as they always did.
if ! scratch=$(mktemp -d "${TMPDIR:-/tmp}/ui-tests.XXXXXX"); then
  run_tests "$result_bundle" "$@"
  exit
fi
trap 'rm -rf "$scratch"' EXIT
times="$scratch/test-times.tsv"
taps="$scratch/cancelled-taps.log"
: >"$times"
: >"$taps"

# BYR-1841, evidence and not a test. When THORBIS_CPU_LOAD names a directory, scripts/ci_cpu_load.py
# writes cpu-load.txt there: once a second, from before the first test to after the last re-run,
# the host's load and the CPU time used so far by the app, the test runner, xcodebuild and the
# simulator's busiest services. When this script ends, however it ends, the recorder is stopped and
# cpu-load-table.txt (also printed to the log) lists each test step of 10 s or more with how much of
# one CPU the app used in it. ps is asked for pid, CPU time and the kernel's short name only, never a
# command line or the environment. None of it changes this script's status, which tests run, or
# anything the re-run rule reads. Unset, none of it runs.
cpu_load=${THORBIS_CPU_LOAD:-}
cpu_recorder=
if [[ -n "$cpu_load" ]] && mkdir -p "$cpu_load" 2>/dev/null; then
  python3 "$here/ci_cpu_load.py" record "$cpu_load/cpu-load.txt" </dev/null >/dev/null 2>&1 &
  cpu_recorder=$!
fi
# shellcheck disable=SC2329 # run by the EXIT trap below
finish() {
  # A cancel signals the whole group, so the stamper may be gone already. A write to its fifo
  # must not end this before the scratch directory is removed and the table is written.
  trap '' PIPE
  if [[ -n "$cpu_recorder" ]]; then
    local waited=0 file
    kill -TERM "$cpu_recorder" 2>/dev/null || true
    while kill -0 "$cpu_recorder" 2>/dev/null && ((waited < 20)); do
      sleep 0.1
      waited=$((waited + 1))
    done
    kill -KILL "$cpu_recorder" 2>/dev/null || true
    cpu_times=("$times")
    for file in "$evidence"/rerun-*-times.tsv; do [[ -f "$file" ]] && cpu_times+=("$file"); done
    python3 "$here/ci_cpu_load.py" read "$cpu_load/cpu-load.txt" "${cpu_times[@]}" \
      --out "$cpu_load/cpu-load-table.txt" </dev/null >&2 2>/dev/null || true
  fi
  rm -rf "$scratch"
}
trap finish EXIT

# BYR-1896, evidence and not a test: when THORBIS_LOG_COMPARE names a directory, the stream's lines and
# its start and stop times are kept there, for a later step to compare with the simulator's stored log
# (scripts/ci_log_compare.py). Nothing here changes the stream, the re-run rule or any exit status.
log_compare=${THORBIS_LOG_COMPARE:-}
if [[ -n "$log_compare" ]]; then
  if mkdir -p "$log_compare" && echo "began $(date +%s)" >"$log_compare/window.txt"; then
    :
  else
    echo "log compare: could not note the stream's start in $log_compare (exit $?)" >&2
    log_compare=
  fi
fi

# The lines, as they are logged. `cat` keeps the stream writing to a pipe: into a pipe it handed
# over each line as it was logged (seen in run 45119132156), and into a file it may hold lines back.
# The first clause is the one stop_watcher looks for; keep it first and keep its words.
xcrun simctl spawn "$simulator_id" log stream --style compact --level default \
  --predicate 'process == "backboardd" AND (eventMessage CONTAINS "unknown digitizer" OR eventMessage CONTAINS "KCMD: " OR eventMessage CONTAINS "cache miss for Keyboard event" OR eventMessage CONTAINS "sequence starting with Keyboard event" OR eventMessage CONTAINS "new key command registrations for pid:" OR (eventMessage CONTAINS "Connection added: " AND eventMessage CONTAINS " process:Thorbis "))' </dev/null 2>/dev/null |
  cat >"$taps" &
watcher=$!

# Stop the reader and the stream. Never wait for either: a stream that outlived both signals
# would hold the step until the job's time ran out, and it holds nothing of the step's.
stop_watcher() {
  kill "$watcher" 2>/dev/null || true
  pkill -f 'eventMessage CONTAINS "unknown digitizer"' 2>/dev/null || true
}

# Run the tests with their output copied to the job's log through `stamp`, which notes each test
# fact in <times file>. Sets $ran to xcodebuild's own exit status. The script waits for
# xcodebuild, not for the end of its output: the copy is given ten seconds after xcodebuild
# exits and is then stopped, so a process xcodebuild started that still holds its output cannot
# hold the step. A copy stopped early loses facts, and lost facts never lead to a re-run.
stamped() { # <times file> <result bundle> <-only-testing:...>...
  local times_file=$1 output="$scratch/xcodebuild-output" stamper waited=0
  shift
  ran=0
  rm -f "$output"
  if ! mkfifo "$output"; then
    run_tests "$@" 2>&1 | python3 "$here/ci_cancelled_taps.py" stamp "$times_file" || ran=${PIPESTATUS[0]}
    return 0
  fi
  python3 "$here/ci_cancelled_taps.py" stamp "$times_file" <"$output" &
  stamper=$!
  run_tests "$@" >"$output" 2>&1 || ran=$?
  while kill -0 "$stamper" 2>/dev/null && ((waited < 50)); do
    sleep 0.2
    waited=$((waited + 1))
  done
  kill "$stamper" 2>/dev/null || true
  rm -f "$output"
}

stamped "$times" "$result_bundle" "$@"
status=$ran
stop_watcher
if [[ -n "$log_compare" ]]; then
  if echo "ended $(date +%s)" >>"$log_compare/window.txt" && cp "$taps" "$log_compare/stream.log"; then
    :
  else
    echo "log compare: could not keep the stream's lines in $log_compare (exit $?)" >&2
  fi
fi

# Say on every run whether that filter started. The log tool prints the filter it accepted as
# its first line, so a filter it refused shows on a green run too, not only when a test failed.
if [[ -s "$taps" ]]; then
  echo "Simulator log filter: $(head -n 1 "$taps")" >&2
else
  echo "Simulator log filter: the log stream wrote nothing, so no failed test in this shard can be run once more." >&2
fi

if ((status == 0)); then
  exit 0
fi

mkdir -p "$evidence"
cp "$times" "$taps" "$evidence/" 2>/dev/null || true

# 65 is xcodebuild's status when tests failed. Any other status (the run itself failed, the
# result bundle could not be written) is not a test's failure and is never run again.
if ((status != 65)); then
  echo "xcodebuild exited $status, not 65 (tests failed). Nothing is run again." | tee "$evidence/decision.txt" >&2
  exit "$status"
fi

decided=0
again=$(python3 "$here/ci_cancelled_taps.py" decide "$evidence/test-times.tsv" "$evidence/cancelled-taps.log" 2>"$evidence/decision.txt") || decided=$?
cat "$evidence/decision.txt" >&2
if ((decided != 0)) || [[ -z "$again" ]]; then
  exit "$status"
fi

# BYR-1896, the runner load experiment (scripts/ci-load-experiment.sh). A treated shard changed the
# simulator or the host before its tests, and whether the stream above still held every line is
# checked only after this step. Two routes of the rule can accept on lost lines, so such a shard runs
# no failed test once more: the failure stands, as it does when the stream wrote nothing. Only a shard
# the plan names as a control ("none") keeps the rule. A plan that cannot be read holds it too.
if [[ -n "${THORBIS_LOAD_SHARD:-}" ]]; then
  load_word=$("$here/ci-load-experiment.sh" plan "$THORBIS_LOAD_SHARD") || load_word="not read, exit $?"
  if [[ "$load_word" != none ]]; then
    held="Load experiment (BYR-1896): this shard was treated ($load_word), so no failed test is run once more. The rule would have run: $(tr '\n' ' ' <<<"$again")"
    echo "::warning::$held"
    echo "$held" >>"$evidence/decision.txt"
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then echo "$held" >>"$GITHUB_STEP_SUMMARY"; fi
    exit "$status"
  fi
  echo "Load experiment (BYR-1896): this shard is a control (plan none), so the re-run rule applies as always." >&2
fi

# The job stops at 90 minutes. A re-run started after 70 minutes of this script may not finish,
# and a cancelled job would lose this decision from its summary, so the failure stands instead.
count=0
for test in $again; do
  count=$((count + 1))
  if ((SECONDS > 4200)); then
    echo "::error::No time is left to run $test once more before the job's limit. The failure stands."
    exit "$status"
  fi
  # BYR-1896: steps before this one take job time this script's clock does not see. When the job's own
  # start is known (THORBIS_JOB_STARTED, from the load experiment's first step), 70 minutes of the job
  # with 2 more for its set-up is the limit too. This can only refuse a re-run, never allow one.
  if [[ "${THORBIS_JOB_STARTED:-}" =~ ^[0-9]+$ ]] && (($(date +%s) - THORBIS_JOB_STARTED + 120 > 4200)); then
    echo "::error::No time is left in the job to run $test once more before its limit (70 minutes of the job have passed). The failure stands."
    exit "$status"
  fi
  if grep -qF "$test: the simulator did not deliver the key chord" "$evidence/decision.txt"; then
    why="the simulator did not deliver the key chord it failed on (backboardd sent the app only the bare key, or SpringBoard took the chord, before the app had registered its key commands; the decision says which). BYR-1843."
  else
    why="the simulator cancelled the tap it failed on (backboardd logged \"unknown digitizer\"). BYR-1835."
  fi
  echo "::warning::Running $test once more by itself: $why The first run's result is in this shard's result bundle."
  rerun_times="$evidence/rerun-$count-times.tsv"
  : >"$rerun_times"
  stamped "$rerun_times" "$evidence/rerun-$count.xcresult" "-only-testing:$test"
  if ((ran != 0)) || ! python3 "$here/ci_cancelled_taps.py" confirm "$rerun_times" "$test"; then
    echo "::error::$test did not pass when run once more by itself (xcodebuild exited $ran). The failure stands."
    exit "$status"
  fi
done

echo "Every failed test failed on a tap the simulator cancelled or a key chord it did not deliver, and each passed when run once more by itself:"
echo "$again"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Tests run once more after a cancelled tap or a lost key chord"
    echo
    echo "Each of these failed on the wait right after a tap the simulator cancelled (backboardd logged \"unknown digitizer\", BYR-1835) or right after a key chord it did not deliver (backboardd sent the app only the bare key, or SpringBoard took the chord, before the app had registered its key commands, BYR-1843), and passed when run once more by itself. The decision below says which. The first run's failure is in this shard's result bundle; the times, the log lines and each re-run are in this shard's re-run evidence."
    echo
    while IFS= read -r test; do echo "- \`$test\`"; done <<<"$again"
    echo
    echo "The decision:"
    echo
    echo '```'
    cat "$evidence/decision.txt"
    echo '```'
  } >>"$GITHUB_STEP_SUMMARY"
fi
exit 0
