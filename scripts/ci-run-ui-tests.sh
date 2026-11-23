#!/usr/bin/env bash
# Run one shard's UI tests, and run a failed test once more only when the simulator itself
# cancelled a tap that test had made.
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
#   - The run is fully accounted for: one session, every started test finished, and xcodebuild's
#     own count of tests and failures matches the log.
#   - EVERY failed test has that error from backboardd in the simulator's log while it ran.
#   - There are at most three of them.
# Each is then run once, by itself. The step passes only if each passes. Anything else leaves
# the first run's failure standing. Every re-run is announced as a warning on the job.
#
# While the tests run, a filter on the simulator's log keeps only that one error. It reads the
# log; it does not touch the app. Evidence (the times, the log lines, each re-run's result
# bundle) goes to <evidence-dir>, which is created only when a test failed.
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
scratch=$(mktemp -d "${TMPDIR:-/tmp}/ui-tests.XXXXXX")
times="$scratch/test-times.tsv"
taps="$scratch/cancelled-taps.log"
: >"$times"
: >"$taps"

# The one error, as it is logged. `cat` keeps the stream writing to a pipe, as it does for the
# freeze sampler, so each line reaches the file when it is logged.
xcrun simctl spawn "$simulator_id" log stream --style compact --level default \
  --predicate 'process == "backboardd" AND eventMessage CONTAINS "unknown digitizer"' 2>/dev/null |
  cat >"$taps" &
watcher=$!

# Stop the reader and the stream. Never wait for either: a stream that outlived both signals
# would hold the step until the job's time ran out, and it holds nothing of the step's.
stop_watcher() {
  kill "$watcher" 2>/dev/null || true
  pkill -f 'eventMessage CONTAINS "unknown digitizer"' 2>/dev/null || true
}

run_tests() { # <result bundle> <-only-testing:...>...
  local bundle=$1
  shift
  xcodebuild -xctestrun "$test_run" \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    -resultBundlePath "$bundle" \
    -parallel-testing-enabled NO \
    "$@" test-without-building
}

status=0
run_tests "$result_bundle" "$@" 2>&1 | python3 "$here/ci_cancelled_taps.py" stamp "$times" || status=${PIPESTATUS[0]}
stop_watcher

if ((status == 0)); then
  rm -rf "$scratch"
  exit 0
fi

mkdir -p "$evidence"
cp "$times" "$taps" "$evidence/" 2>/dev/null || true
rm -rf "$scratch"

if ! again=$(python3 "$here/ci_cancelled_taps.py" decide "$evidence/test-times.tsv" "$evidence/cancelled-taps.log"); then
  exit "$status"
fi
[[ -n "$again" ]] || exit "$status"

count=0
for test in $again; do
  count=$((count + 1))
  echo "::warning::Running $test once more by itself: the simulator cancelled a tap XCTest had synthesized while it ran (backboardd logged \"unknown digitizer\"). BYR-1835."
  if ! run_tests "$evidence/rerun-$count.xcresult" "-only-testing:$test"; then
    echo "::error::$test failed again when run by itself. The failure stands."
    exit "$status"
  fi
done

echo "Every failed test had a cancelled tap in the simulator's log, and each passed when run once more by itself:"
echo "$again"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Tests run once more after a cancelled tap"
    echo
    echo "The simulator cancelled a tap XCTest had synthesized (backboardd logged \"unknown digitizer\") while each of these ran. Each passed when run once more by itself. BYR-1835."
    echo
    while IFS= read -r test; do echo "- \`$test\`"; done <<<"$again"
  } >>"$GITHUB_STEP_SUMMARY"
fi
exit 0
