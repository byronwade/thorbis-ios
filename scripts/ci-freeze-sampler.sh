#!/bin/bash
# Evidence for BYR-1841, not a test.
#
# The first time Customer view opens on Estimates in a launch, the app's main thread is held
# while that page is pushed: a median of 2.3 s and up to 22.9 s on CI simulators. Nothing in the
# logs says what the thread waits for. About 0.7 s into each hold the simulator's backboardd logs
# "timed out fence <id>". This script follows the simulator's log, and on each such line it takes
# a two second stack sample (one stack every 10 ms) of the newest Thorbis process. Each sample
# goes to freeze-NN-HHMMSS-pidN.txt in the output directory, and beside it a .trigger.txt file
# with the log line that set it off, the time sampling began and sample's own messages.
#
# It is started in the background beside the UI tests and stopped when they end. It never fails,
# and it stops sampling after its limit so the tests are disturbed as little as possible.
#
# usage: ci-freeze-sampler.sh <simulator-id> <output-directory> [limit]
set -u

simulator_id=${1:?simulator id}
out=${2:?output directory}
limit=${3:-10}

mkdir -p "$out"
taken=0

xcrun simctl spawn "$simulator_id" log stream --style compact --level default \
  --predicate 'process == "backboardd" AND eventMessage CONTAINS "timed out fence"' |
while IFS= read -r line; do
  # The stream's header line quotes the predicate, so match only an event line: one from
  # backboardd that names a numeric fence id.
  case "$line" in *backboardd*"timed out fence "[0-9]*) ;; *) continue ;; esac
  # Past the limit, stop reading: the stream ends on its next write.
  [ "$taken" -lt "$limit" ] || break
  pid=$(pgrep -n -x Thorbis || true)
  [ -n "$pid" ] || continue
  taken=$((taken + 1))
  file="$out/freeze-$(printf '%02d' "$taken")-$(date -u +%H%M%S)-pid$pid.txt"
  trigger="${file%.txt}.trigger.txt"
  printf 'trigger: %s\nsampling from: %s\n' "$line" "$(date -u +%H:%M:%S)" >"$trigger"
  # 2 s at one stack per 10 ms. No -mayDie: it reads every image's symbols before the first
  # stack, which on a loaded runner can outlast the hold. Neither command may read the log pipe.
  # The sidecar is this user's file on purpose; only the sample itself is written as root.
  # shellcheck disable=SC2024
  sudo -n sample "$pid" 2 10 -file "$file" </dev/null >>"$trigger" 2>&1 ||
    sample "$pid" 2 10 -file "$file" </dev/null >>"$trigger" 2>&1 || true
  # Lines that arrived while sampling describe freezes that are already over. Drop them, and
  # go on once the log has been quiet for a second.
  while IFS= read -r -t 1 _; do :; done
done

exit 0
