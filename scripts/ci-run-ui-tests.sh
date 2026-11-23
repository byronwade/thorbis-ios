#!/usr/bin/env bash
# Run one shard's UI tests, and run a failed test once more only when the simulator itself
# cancelled the tap that test failed on.
#
#   scripts/ci-run-ui-tests.sh <xctestrun> <simulator-id> <result-bundle> <evidence-dir> \
#       -only-testing:ThorbisUITests/SomeClass [...]
#
# Why: XCTest taps through a virtual touchscreen it attaches for each gesture. On a busy runner
# the simulator's input server sometimes registers that touchscreen twice, drops the lift and
# cancels the touch, and logs "*** unknown digitizer". The app sees a cancelled touch and does
# nothing, so the test fails on a tap no person made (BYR-1835; scripts/ci_cancelled_taps.py
# has the detail).
#
# What this does NOT do: retry failures. A failed test is run again only when ALL of these hold.
#   - xcodebuild exited 65, its status for failed tests, and nothing else went wrong.
#   - The run is fully accounted for: one session, every started test finished, and xcodebuild's
#     own count of tests and failures matches the log, with no unexpected failure.
#   - EVERY failed test failed on the wait right after a tap, its first failure speaks of no
#     crash or launch, and backboardd logged that error at that tap.
#   - There are at most three of them, and the job has time left to run them.
# Each is then run once, by itself. The step passes only if each of those runs shows that one
# test passing. Anything else leaves the first run's failure standing. Every re-run is announced
# as a warning on the job, with the reasons, and listed in the step summary.
#
# While the tests run, a filter on the simulator's log keeps only that one error. It reads the
# log; it does not touch the app. Evidence (the times, the log lines, the decision, each re-run's
# times and result bundle) goes to <evidence-dir>, which is created only when a test failed.
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

# The one error, as it is logged. `cat` keeps the stream writing to a pipe: into a pipe it handed
# over each line as it was logged (seen in run 45119132156), and into a file it may hold lines back.
xcrun simctl spawn "$simulator_id" log stream --style compact --level default \
  --predicate 'process == "backboardd" AND eventMessage CONTAINS "unknown digitizer"' </dev/null 2>/dev/null |
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

# The job stops at 90 minutes. A re-run started after 70 minutes of this script may not finish,
# and a cancelled job would lose this decision from its summary, so the failure stands instead.
count=0
for test in $again; do
  count=$((count + 1))
  if ((SECONDS > 4200)); then
    echo "::error::No time is left to run $test once more before the job's limit. The failure stands."
    exit "$status"
  fi
  echo "::warning::Running $test once more by itself: the simulator cancelled the tap it failed on (backboardd logged \"unknown digitizer\"). The first run's result is in this shard's result bundle. BYR-1835."
  rerun_times="$evidence/rerun-$count-times.tsv"
  : >"$rerun_times"
  stamped "$rerun_times" "$evidence/rerun-$count.xcresult" "-only-testing:$test"
  if ((ran != 0)) || ! python3 "$here/ci_cancelled_taps.py" confirm "$rerun_times" "$test"; then
    echo "::error::$test did not pass when run once more by itself (xcodebuild exited $ran). The failure stands."
    exit "$status"
  fi
done

echo "Every failed test failed on a tap the simulator cancelled, and each passed when run once more by itself:"
echo "$again"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Tests run once more after a cancelled tap"
    echo
    echo "Each of these failed on the wait right after a tap the simulator cancelled (backboardd logged \"unknown digitizer\"), and passed when run once more by itself. The first run's failure is in this shard's result bundle; the times, the log lines and each re-run are in this shard's re-run evidence. BYR-1835."
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
