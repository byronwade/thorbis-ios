#!/usr/bin/env bash
# The runner load experiment (BYR-1896): CI only, for one run, then removed or made permanent.
#
#   scripts/ci-load-experiment.sh plan <shard>        # prints the shard's plan word, nothing else
#   scripts/ci-load-experiment.sh <phase> <shard> <cpu-load dir> <experiment dir> [simulator id]
#
# With no simulator id and THORBIS_LOAD_DEVICE set to iPhone or iPad, the after, compare and probe
# phases look the id up themselves (ci-simulator-id.sh under a 30 s alarm, kept for the next phase),
# and only after the phase's time check, so a simctl that hangs after the tests costs 30 s at most.
#
# <shard> is phone1..phone6 or ipad1..ipad2. Each shard gets one plan word:
#   none           phone1, phone2, ipad1   controls: nothing is changed
#   spotlight-off  phone3, phone6          the host's Spotlight indexing is turned off before the tests
#   apsd-off       phone4, phone5, ipad2   the simulator's push daemon (com.apple.apsd) is booted out
#                                          after boot, before the app is installed
# Any other name is "unknown": untreated.
#
# Phases, in the order the workflow runs them:
#   host     first step after checkout: notes the job's start, the runner's facts, a census of the
#            services, and in spotlight-off shards `sudo -n mdutil -i off` for / and for
#            /System/Volumes/Data, by name (not -a, which also reaches every mounted image)
#   sim      in the warm step right after boot: apsd-off shards boot apsd out; spotlight-off shards
#            check indexing is still off and turn it off again if it is not; controls do nothing
#   after    after the tests and their evidence are saved: is the treatment still in place
#   compare  the simulator's stored log against the stream the re-run rule read (ci_log_compare.py)
#   probe    every shard, after the tests: which diagnosticd is which, what stopping the host's one
#            and killing the simulator's one does to a new log stream. This stops a system logging
#            service, so it runs only after every test, every re-run and every upload of evidence.
#
# What keeps the tests' evidence whole: a shard whose plan word is not exactly "none" runs no failed
# test once more (ci-run-ui-tests.sh asks `plan` and holds the re-runs, and says so in the log). The
# phases after the tests run after the test step has ended, so nothing they do reaches the rule.
#
# It never fails the job: every command runs through `run`, under its own alarm, with its stdout,
# its stderr and its exit status printed, and the script always exits 0. A phase after the tests
# starts only when the job has time for it (see time_left). Each verdict is one line:
#   LOAD EXPERIMENT <shard> <phase> <plan word>: applied yes|no|not known (<reason>)
# in <cpu-load dir>/treatment.txt (host and sim, uploaded with the CPU load record), in the job log
# and in the step summary. "not known" is counted apart from treated and untreated.
set -u

phase=${1:-?}
shard=${2:-?}

plan_word() {
  case "$1" in
    phone1 | phone2 | ipad1) echo none ;;
    phone3 | phone6) echo spotlight-off ;;
    phone4 | phone5 | ipad2) echo apsd-off ;;
    *) echo unknown ;;
  esac
}

if [[ "$phase" == plan ]]; then
  plan_word "$shard"
  exit 0
fi

word=$(plan_word "$shard")
verdict_due=
stream_pids=()

# shellcheck disable=SC2317,SC2329 # run by the traps below
on_exit() {
  local rc=$1
  trap '' ALRM TERM INT
  if [[ "$phase" == probe ]]; then end_streams; fi
  if [[ -n "$verdict_due" ]]; then
    verdict "$verdict_due" "not known" "the $phase phase ended (status $rc) before its verdict"
  fi
  echo "ci-load-experiment.sh $phase: ended with status $rc"
  ((rc == 0)) || echo "::warning::Load experiment: the $phase phase itself ended with status $rc. The job goes on."
  exit 0
}
trap 'on_exit $?' EXIT
trap 'echo "Load experiment: the $phase phase got SIGALRM (its outer alarm)"; exit 142' ALRM
trap 'echo "Load experiment: the $phase phase got SIGTERM"; exit 143' TERM
trap 'echo "Load experiment: the $phase phase got SIGINT"; exit 130' INT

here=$(cd "$(dirname "$0")" && pwd)
cpu_load=${3:-}
exp=${4:-}
sim=${5:-}
case "$phase" in
  host | sim | after | compare | probe) ;;
  *) echo "usage: ci-load-experiment.sh plan <shard> | <host|sim|after|compare|probe> <shard> <cpu-load dir> <experiment dir> [simulator id]"; exit 2 ;;
esac
if [[ -z "$cpu_load" || -z "$exp" ]]; then
  echo "usage: ci-load-experiment.sh $phase <shard> <cpu-load dir> <experiment dir> [simulator id]"
  exit 2
fi
if ! mkdir -p "$exp" "$cpu_load"; then
  fallback=$(mktemp -d "${TMPDIR:-/tmp}/load-experiment.XXXXXX") || fallback=
  echo "::warning::Load experiment: $exp or $cpu_load could not be made; output goes to ${fallback:-nowhere} and is not uploaded"
  [[ -n "$fallback" ]] || exit 1
  exp=$fallback
  cpu_load=$fallback
fi
treatment="$cpu_load/treatment.txt"

# Run one command under its own alarm, never through a shell. Its stdout goes to
# $exp/<phase>-<label>.out and its stderr to .err, and both are printed, then its exit status.
# Sets $rc. LOAD_CHECK=1: a non-zero exit is the expected proof, so no warning (the exit is still
# printed). LOAD_QUIET=1: only the first 20 lines are printed; the file keeps all of them.
rc=0
run() { # <label> <seconds> <command> [args...]
  local label=$1 limit=$2 out err lines
  shift 2
  if [[ "${THORBIS_LOAD_ALARM_CAP:-}" =~ ^[0-9]+$ ]] && ((THORBIS_LOAD_ALARM_CAP < limit)); then
    limit=$THORBIS_LOAD_ALARM_CAP
  fi
  out="$exp/$phase-$label.out"
  err="$exp/$phase-$label.err"
  echo "+ $* (alarm $limit s)"
  perl -e 'alarm shift; exec { $ARGV[0] } @ARGV or die "cannot run $ARGV[0]: $!\n"' "$limit" "$@" </dev/null >"$out" 2>"$err"
  rc=$?
  if [[ -n "${LOAD_QUIET:-}" ]]; then
    head -n 20 "$out"
    lines=$(wc -l <"$out")
    echo "($((lines)) lines of output in $out)"
  else
    cat "$out"
  fi
  if [[ -s "$err" ]]; then
    echo "stderr:"
    if [[ -n "${LOAD_QUIET:-}" ]]; then head -n 20 "$err"; else cat "$err"; fi
  fi
  if ((rc == 142)); then
    echo "exit 142 ($label: stopped by its $limit s alarm)"
  else
    echo "exit $rc ($label)"
  fi
  if ((rc != 0)) && [[ -z "${LOAD_CHECK:-}" ]]; then
    echo "::warning::Load experiment: $label exited $rc (output above). The job goes on."
  fi
  return 0
}

# Every wait goes through here. THORBIS_LOAD_PAUSE is for the unit tests only: each wait is then that long.
pause() { # <seconds>
  if [[ "${THORBIS_LOAD_PAUSE:-}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then sleep "$THORBIS_LOAD_PAUSE"; else sleep "$1"; fi
}

# Add a line to a file; a failed write is printed with its status.
append() { # <file> <line>
  local status
  printf '%s\n' "$2" >>"$1"
  status=$?
  ((status == 0)) || echo "load experiment: could not write $1 (exit $status)"
}

# Print a line and add it to a file and to the step summary.
record_line() { # <file> <line>
  echo "$2"
  append "$1" "$2"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then append "$GITHUB_STEP_SUMMARY" "- $2"; fi
}

# Written before a phase changes anything, so a phase cut short reads "not known", not "untreated".
started_line() { # <file>
  if [[ -z "$verdict_due" ]]; then
    record_line "$1" "LOAD EXPERIMENT $shard $phase $word: started"
    verdict_due=$1
  fi
}

verdict() { # <file> <yes|no|not known> <reason>
  verdict_due=
  record_line "$1" "LOAD EXPERIMENT $shard $phase $word: applied $2 ($3)"
  case "$2" in
    yes) echo "::notice::Load experiment: $word was applied in $shard ($3)." ;;
    no) echo "::warning::Load experiment: $word was NOT applied in $shard ($3). This shard counts as untreated." ;;
    *) echo "::warning::Load experiment: whether $word was applied in $shard is not known ($3). This shard is counted apart from treated and untreated." ;;
  esac
}

# Minutes since the host phase noted the job's start, plus 2 for the set-up and checkout before it.
job_minutes() {
  local started=${THORBIS_JOB_STARTED:-} now
  [[ "$started" =~ ^[0-9]+$ ]] || return 1
  now=$(date +%s) || return 1
  [[ "$now" =~ ^[0-9]+$ ]] || return 1
  echo $(((now - started + 120) / 60))
}

# A phase after the tests starts only if it can end by the job's 80th minute: the job stops at 90,
# and a job stopped by its limit fails, which would turn a green shard red.
time_left() { # <the phase's worst case in minutes>
  local worst=$1 minutes why
  if ! minutes=$(job_minutes); then
    why="THORBIS_JOB_STARTED is not set or not a time, so how long the job has run is not known"
  elif ((minutes + worst > 80)); then
    why="the job has run about $minutes min (2 min for set-up included) and this phase can take $worst min; the job stops at 90"
  else
    echo "Load experiment: the job has run about $minutes min (2 min for set-up included); this phase can take $worst min, so it runs."
    return 0
  fi
  record_line "$exp/$phase.txt" "LOAD EXPERIMENT $shard $phase $word: skipped ($why)"
  echo "::notice::Load experiment: $phase skipped in $shard ($why)."
  return 1
}

census() { # <label>: every process with its parent; then the rows of the services this is about
  run "$1" 10 ps -Ao pid=,ppid=,user=,etime=,ucomm=
  echo "Rows of interest (pid ppid user elapsed name):"
  awk '$NF ~ /^(diagnosticd|logd|launchd_sim|apsd|mds|mds_stores|mdworker_shared|searchd)$/' "$exp/$phase-$1.out"
}

# disabled, enabled or unknown, read from the blocks for / and /System/Volumes/Data only.
spotlight_state() { # <mdutil -s output>
  awk '
    /^\/.*:[[:space:]]*$/ { volume = $0; sub(/:[[:space:]]*$/, "", volume); next }
    volume == "/" || volume == "/System/Volumes/Data" {
      if ($0 ~ /Indexing enabled/) on[volume] = 1
      if ($0 ~ /Indexing disabled/) off[volume] = 1
    }
    END {
      if (on["/"] || on["/System/Volumes/Data"]) print "enabled"
      else if (off["/"] && off["/System/Volumes/Data"]) print "disabled"
      else print "unknown"
    }' "$1"
}

spotlight_status() { # <label>: sets $state
  run "$1" 10 mdutil -s / /System/Volumes/Data
  state=$(spotlight_state "$exp/$phase-$1.out")
  echo "Spotlight on / and /System/Volumes/Data: $state (mdutil exit $rc)"
}

# The pid column of com.apple.apsd's row in `launchctl list` output ("-" when it has none); fails
# when no field of any row is exactly that label.
apsd_listed() { # <launchctl list output>
  awk '{ for (i = 1; i <= NF; i++) if ($i == "com.apple.apsd") { print $1; found = 1; exit } }
       END { exit (found ? 0 : 1) }' "$1"
}

apsd_under_sim() { # <census output>: apsd rows whose parent is a launchd_sim pid
  awk 'NR == FNR { if ($NF == "launchd_sim") sim[$1] = 1; next } $NF == "apsd" && ($2 in sim)' "$1" "$1"
}

# The simulator's id for the phases after the tests (see the top). Sets $sim; prints why when none.
find_simulator() {
  local saved="$exp/simulator-id.txt" id
  [[ -z "$sim" && -n "${THORBIS_LOAD_DEVICE:-}" ]] || return 0
  if [[ -f "$saved" ]]; then
    sim=$(head -n 1 "$saved")
    echo "Load experiment: simulator id from the lookup of an earlier phase: ${sim:-none (that lookup failed)}"
    return 0
  fi
  run simulator-id 30 "$here/ci-simulator-id.sh" "$THORBIS_LOAD_DEVICE"
  id=$(tail -n 1 "$exp/$phase-simulator-id.out")
  if ((rc == 0)) && [[ "$id" =~ ^[0-9A-Fa-f-]+$ ]]; then
    sim=$id
  else
    echo "Load experiment: no simulator id (ci-simulator-id.sh exited $rc, last line '${id}')"
  fi
  append "$saved" "$sim"
}

# ---- treatments: one function each ----------------------------------------------------------

# Indexing off for / and /System/Volumes/Data, by name: `-a` also reaches every mounted image, such
# as the simulator runtimes, and one of those refusing would make the exit not 0. Sets $off_rcs.
spotlight_off() { # <label>
  local root_rc
  run "$1-root" 30 sudo -n mdutil -i off /
  root_rc=$rc
  run "$1-data" 30 sudo -n mdutil -i off /System/Volumes/Data
  off_rcs="/ exit $root_rc, /System/Volumes/Data exit $rc"
  [[ "$root_rc" == 0 && "$rc" == 0 ]]
}

spotlight_off_host() {
  local off_ok=no
  started_line "$treatment"
  spotlight_status spotlight-before
  if spotlight_off spotlight-off; then off_ok=yes; fi
  spotlight_status spotlight-after
  run spotlight-all-after 10 mdutil -s -a
  if [[ "$off_ok" == yes && "$state" == disabled ]]; then
    verdict "$treatment" yes "sudo -n mdutil -i off: $off_rcs; / and /System/Volumes/Data say Indexing disabled"
  elif [[ "$state" == enabled ]]; then
    verdict "$treatment" no "sudo -n mdutil -i off: $off_rcs; / or /System/Volumes/Data still says Indexing enabled"
  else
    verdict "$treatment" "not known" "sudo -n mdutil -i off: $off_rcs; mdutil -s says $state for / and /System/Volumes/Data"
  fi
}

spotlight_off_sim() {
  local again_rc=none host=no
  if grep -qF "LOAD EXPERIMENT $shard host spotlight-off: applied yes" "$treatment"; then host=yes; fi
  spotlight_status spotlight-status
  if [[ "$state" != disabled ]]; then
    started_line "$treatment"
    if spotlight_off spotlight-off-again; then again_rc=0; else again_rc="($off_rcs)"; fi
    spotlight_status spotlight-after-again
  fi
  if [[ "$state" == disabled ]] && { [[ "$host" == yes ]] || [[ "$again_rc" == 0 ]]; }; then
    verdict "$treatment" yes "after boot / and /System/Volumes/Data say Indexing disabled; host phase applied: $host; turned off again: $again_rc"
  elif [[ "$state" == enabled ]]; then
    verdict "$treatment" no "after boot / or /System/Volumes/Data still says Indexing enabled; host phase applied: $host; turned off again: exit $again_rc"
  else
    verdict "$treatment" "not known" "after boot mdutil says $state; host phase applied: $host; turned off again: exit $again_rc"
  fi
}

apsd_off_sim() {
  local listed after_pid under bootout_rc after_rc census_rc k gone=no began still=no
  if [[ -z "$sim" ]]; then
    verdict "$treatment" no "no simulator id, so nothing was stopped"
    return
  fi
  started_line "$treatment"
  run apsd-list-before 15 xcrun simctl spawn "$sim" launchctl list
  if ((rc != 0)); then
    verdict "$treatment" no "launchctl list in the simulator exited $rc, so whether com.apple.apsd is loaded is not known; nothing was stopped"
    return
  fi
  if ! listed=$(apsd_listed "$exp/sim-apsd-list-before.out"); then
    echo "Rows of launchctl list that name aps:"
    grep -i aps "$exp/sim-apsd-list-before.out" || echo "(none, grep exit $?)"
    verdict "$treatment" no "launchctl list (exit 0) has no com.apple.apsd row; nothing was stopped"
    return
  fi
  echo "launchctl list has com.apple.apsd; its pid column: $listed"
  LOAD_CHECK=1 run apsd-print-before 10 xcrun simctl spawn "$sim" launchctl print system/com.apple.apsd
  run apsd-bootout 15 xcrun simctl spawn "$sim" launchctl bootout system/com.apple.apsd
  bootout_rc=$rc
  if [[ "$listed" =~ ^[0-9]+$ ]]; then
    began=$SECONDS
    for k in 1 2 3 4 5; do
      LOAD_CHECK=1 run "apsd-gone-$k" 3 ps -p "$listed" -o pid=,ucomm=
      if ((rc == 1)) && [[ ! -s "$exp/sim-apsd-gone-$k.out" ]]; then gone=yes; break; fi
      pause 1
    done
    echo "apsd pid $listed gone: $gone after $((SECONDS - began)) s"
  fi
  run apsd-list-after 15 xcrun simctl spawn "$sim" launchctl list
  after_rc=$rc
  if after_pid=$(apsd_listed "$exp/sim-apsd-list-after.out"); then still=yes; echo "launchctl list still has com.apple.apsd ($after_pid)"; fi
  run apsd-census-after 10 ps -Ao pid=,ppid=,user=,etime=,ucomm=
  census_rc=$rc
  under=$(apsd_under_sim "$exp/sim-apsd-census-after.out")
  echo "apsd under launchd_sim now: ${under:-none}"
  if ((bootout_rc == 0 && after_rc == 0 && census_rc == 0)) && [[ "$still" == no && -z "$under" ]]; then
    verdict "$treatment" yes "launchctl bootout exited 0; launchctl list (exit 0) has no com.apple.apsd; no apsd whose parent is launchd_sim; old pid gone: $gone"
  elif ((bootout_rc == 142)); then
    # The alarm ends xcrun, not the launchctl inside the simulator, which may still finish later.
    verdict "$treatment" "not known" "launchctl bootout was stopped by its alarm and may still finish in the simulator; launchctl list after: exit $after_rc, still listed: $still; apsd under launchd_sim: ${under:-none}"
  elif ((after_rc == 0)) && [[ "$still" == yes ]]; then
    verdict "$treatment" no "launchctl bootout exited $bootout_rc; launchctl list still has com.apple.apsd"
  elif [[ -n "$under" ]]; then
    verdict "$treatment" no "launchctl bootout exited $bootout_rc; an apsd runs under launchd_sim"
  else
    verdict "$treatment" "not known" "launchctl bootout exited $bootout_rc, launchctl list after exited $after_rc, the census exited $census_rc"
  fi
}

# ---- phases ---------------------------------------------------------------------------------

host_phase() {
  local list_args=() index count
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    append "$GITHUB_ENV" "THORBIS_JOB_STARTED=$(date +%s)"
  else
    echo "Load experiment: GITHUB_ENV is not set, so THORBIS_JOB_STARTED is not passed on and the phases after the tests will skip"
  fi
  echo "Load experiment (BYR-1896) plan: phone1, phone2, ipad1 none (controls); phone3, phone6 spotlight-off; phone4, phone5, ipad2 apsd-off."
  if [[ "$word" == unknown ]]; then
    echo "::warning::Load experiment: shard $shard is not in the plan, so it is untreated, and its failed tests are not run once more because the plan cannot place it."
  else
    echo "::notice::Load experiment: shard $shard has plan word $word."
  fi
  case "$word" in
    none) record_line "$treatment" "LOAD EXPERIMENT $shard plan none (control)" ;;
    unknown) record_line "$treatment" "LOAD EXPERIMENT $shard plan unknown (not in the plan, untreated)" ;;
  esac
  append "$cpu_load/runner-facts.txt" "runner image ${ImageVersion:-not set}"
  append "$cpu_load/runner-facts.txt" "host phase began $(date -u '+%Y-%m-%dT%H:%M:%SZ') (queue time is not visible to the job)"
  cat "$cpu_load/runner-facts.txt"
  run sw-vers 10 sw_vers
  run time-zone 5 date +%z
  index=${shard//[!0-9]/}
  count=${THORBIS_LOAD_SHARDS:-}
  if [[ -n "$index" && "$count" =~ ^[0-9]+$ ]]; then
    case "$shard" in ipad*) list_args=(--tablet) ;; esac
    run shard-list 20 python3 "$here/ui_test_shards.py" "${list_args[@]+"${list_args[@]}"}" --shards "$count" --index "$index"
    run shard-list-hash 10 python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest()[:16])' "$exp/host-shard-list.out"
    append "$cpu_load/runner-facts.txt" "shard list sha256 $(cat "$exp/host-shard-list-hash.out") (exit $rc; ui_test_shards.py ${list_args[*]+"${list_args[*]}"} --shards $count --index $index)"
  else
    echo "Load experiment: THORBIS_LOAD_SHARDS is not a number, so the shard's test list is not hashed"
  fi
  census host-census
  run spotlight-all 10 mdutil -s -a
  if [[ "$word" == spotlight-off ]]; then spotlight_off_host; fi
}

sim_phase() {
  local began=$SECONDS
  case "$word" in
    spotlight-off) spotlight_off_sim ;;
    apsd-off) apsd_off_sim ;;
    *) echo "Load experiment: $shard is $word, so nothing is done in the simulator." ;;
  esac
  # These seconds come out of the warm loop's 180 s from boot, so a treated shard may get fewer warm
  # launches than a control before its first test: the warm step prints each launch.
  record_line "$treatment" "LOAD EXPERIMENT $shard sim $word: took $((SECONDS - began)) s of the warm step"
}

after_phase() {
  local out="$exp/after.txt" under listed still
  time_left 2 || return 0     # at most 65 s of alarms, the id lookup included
  census after-census
  case "$word" in
    spotlight-off)
      spotlight_status spotlight-end
      case "$state" in disabled) still=yes ;; enabled) still=no ;; *) still="not known" ;; esac
      record_line "$out" "LOAD EXPERIMENT $shard after $word: still disabled $still (mdutil -s exited $rc)"
      ;;
    apsd-off)
      find_simulator
      if [[ -z "$sim" ]]; then
        record_line "$out" "LOAD EXPERIMENT $shard after $word: came back not known (no simulator id)"
        return 0
      fi
      run apsd-list-end 15 xcrun simctl spawn "$sim" launchctl list
      local list_rc=$rc
      under=$(apsd_under_sim "$exp/after-after-census.out")
      if listed=$(apsd_listed "$exp/after-apsd-list-end.out") || [[ -n "$under" ]]; then
        record_line "$out" "LOAD EXPERIMENT $shard after $word: came back yes (launchctl list: ${listed:-no row}; apsd under launchd_sim: ${under:-none})"
      elif ((list_rc == 0)); then
        record_line "$out" "LOAD EXPERIMENT $shard after $word: came back no"
      else
        record_line "$out" "LOAD EXPERIMENT $shard after $word: came back not known (launchctl list exited $list_rc)"
      fi
      ;;
    *) record_line "$out" "LOAD EXPERIMENT $shard after $word: nothing to check" ;;
  esac
}

compare_phase() {
  local start end predicate began last evidence=${THORBIS_RERUN_EVIDENCE:-} times=
  time_left 8 || return 0     # id lookup 30 s, log show 240 s, the compare 60 s, two decides 30 s each, the rest 30 s
  if [[ ! -s "$exp/stream.log" ]]; then
    record_line "$exp/compare.txt" "log compare: store holds every stream entry: not known (no stream.log: the test step kept no stream lines)"
    return 0
  fi
  if ! grep -q '^ended ' "$exp/window.txt"; then
    record_line "$exp/compare.txt" "log compare: store holds every stream entry: not known (window.txt has no ended line)"
    return 0
  fi
  find_simulator
  if [[ -z "$sim" ]]; then
    record_line "$exp/compare.txt" "log compare: store holds every stream entry: not known (no simulator id)"
    return 0
  fi
  run bounds 10 python3 "$here/ci_log_compare.py" bounds "$exp/window.txt"
  start=$(sed -n 1p "$exp/compare-bounds.out")
  end=$(sed -n 2p "$exp/compare-bounds.out")
  run predicate 10 python3 "$here/ci_log_compare.py" predicate
  predicate=$(cat "$exp/compare-predicate.out")
  if [[ -z "$start" || -z "$end" || -z "$predicate" ]]; then
    record_line "$exp/compare.txt" "log compare: store holds every stream entry: not known (the window or the filter could not be read)"
    return 0
  fi
  began=$SECONDS
  LOAD_QUIET=1 run log-show 240 xcrun simctl spawn "$sim" log show --style compact --predicate "$predicate" --start "$start" --end "$end"
  append "$exp/log-show.txt" "exit $rc seconds $((SECONDS - began))"
  cp "$exp/compare-log-show.out" "$exp/store.log" || echo "load experiment: could not copy the store's lines (exit $?)"
  if [[ -f "$evidence/test-times.tsv" ]]; then times="$evidence/test-times.tsv"; fi
  run compare 60 python3 "$here/ci_log_compare.py" compare "$exp" "$cpu_load/cpu-load.txt" ${times:+"$times"}
  last=$(tail -n 1 "$exp/compare-compare.out")
  case "$last" in
    *"entry: yes "*) echo "::notice::Load experiment ($shard): $last" ;;
    *) echo "::warning::Load experiment ($shard): ${last:-log compare gave no answer}" ;;
  esac
  if [[ -n "$times" && -s "$exp/store-clean.log" ]]; then
    # The rule's own decision on the store's lines, beside the one it made on the stream's.
    LOAD_CHECK=1 run decide-stream 30 python3 "$here/ci_cancelled_taps.py" decide "$times" "$exp/stream.log"
    LOAD_CHECK=1 run decide-store 30 python3 "$here/ci_cancelled_taps.py" decide "$times" "$exp/store-clean.log"
    if cmp -s "$exp/compare-decide-stream.out" "$exp/compare-decide-store.out"; then
      echo "log compare: decide gives the same tests on the stream and on the store: $(tr '\n' ' ' <"$exp/compare-decide-stream.out")"
    else
      echo "::warning::log compare ($shard): decide on the stream ran $(tr '\n' ' ' <"$exp/compare-decide-stream.out" | sed 's/ *$//;s/^$/nothing/'); on the store it would run $(tr '\n' ' ' <"$exp/compare-decide-store.out" | sed 's/ *$//;s/^$/nothing/')"
    fi
  fi
}

# ---- probe ----------------------------------------------------------------------------------

start_stream() { # <k>: a new log stream with the test step's filter, its lines in s<k>.log
  local k=$1
  echo "+ xcrun simctl spawn $sim log stream --style compact --level default --predicate <the test step's filter> (alarm 600 s) >s$k.log 2>s$k.err &"
  perl -e 'alarm shift; exec { $ARGV[0] } @ARGV or die "cannot run $ARGV[0]: $!\n"' 600 \
    xcrun simctl spawn "$sim" log stream --style compact --level default --predicate "$probe_filter" \
    </dev/null >"$exp/s$k.log" 2>"$exp/s$k.err" &
  stream_pids[k]=$!
  echo "S$k is pid ${stream_pids[k]}"
}

# Only entry lines, which start with their date: the stream's first line quotes the filter, and the
# filter holds the same words, so a header that comes late must not read as a launch seen.
added() { # <k>: how many "Connection added" entries S<k> has (grep prints 0 and exits 1 for none)
  local n
  n=$(grep -c '^[0-9]\{4\}-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9].*Connection added: ' "$exp/s$1.log")
  echo "${n:-0}"
}

how=
alive() { # <k>: 0 when S<k> still runs; else 1, with how it ended in $how. Not in a subshell: wait needs this one.
  local pid=${stream_pids[$1]:-}
  if [[ -z "$pid" ]]; then how="never started"; return 1; fi
  if kill -0 "$pid"; then return 0; fi
  wait "$pid"
  how="stream ended, exit $?"
  return 1
}

launch() { # <k>: one fresh start of the app, as the warm step does it; then which streams got it
  local k=$1 j before=()
  LOAD_CHECK=1 run "pre-stop-$k" 15 xcrun simctl terminate "$sim" com.thorbis.field
  pause 3
  for j in 1 2 3; do
    [[ -n "${stream_pids[j]:-}" ]] && before[j]=$(added "$j")
  done
  run "launch-$k" 45 xcrun simctl launch "$sim" com.thorbis.field --paper-preview
  pause 8
  LOAD_CHECK=1 run "stop-$k" 15 xcrun simctl terminate "$sim" com.thorbis.field
  got=""
  for j in 1 2 3; do
    [[ -n "${stream_pids[j]:-}" ]] || continue
    if alive "$j"; then
      if (($(added "$j") > ${before[j]:-0})); then got+=" S$j yes"; else got+=" S$j no"; fi
    else
      got+=" S$j not known ($how)"
    fi
  done
}

end_streams() {
  local k
  for k in 1 2 3; do
    [[ -n "${stream_pids[k]:-}" ]] || continue
    LOAD_CHECK=1 run "stream-end-$k" 5 kill "${stream_pids[k]}"
    echo "s$k.err:"
    cat "$exp/s$k.err"
    stream_pids[k]=
  done
  if [[ -n "${probe_filter:-}" ]]; then
    LOAD_CHECK=1 run pkill-streams 10 pkill -f 'eventMessage CONTAINS "unknown digitizer"'
    probe_filter=
  fi
}

cpu_rates() { # <a label> <b label> <seconds>: CPU seconds per second per pid between two samples
  awk -v secs="$3" '
    function seconds(text,   parts, n, i, total) { n = split(text, parts, ":"); total = 0; for (i = 1; i <= n; i++) total = total * 60 + parts[i]; return total }
    NR == FNR { a[$1] = seconds($2); next }
    ($1 in a) && secs > 0 { printf "probe: diagnosticd %s cpu %.2f s/s without our stream\n", $1, (seconds($2) - a[$1]) / secs }
  ' "$exp/probe-$1.out" "$exp/probe-$2.out"
}

diag_rows() { # <census label>: "pid side ppid" for each diagnosticd
  awk 'NR == FNR { if ($NF == "launchd_sim") sim[$1] = 1; next }
       $NF == "diagnosticd" { print $1, (($2 in sim) ? "sim" : ($2 == 1 ? "host" : "unknown")), $2 }' \
    "$exp/probe-$1.out" "$exp/probe-$1.out"
}

sample_cpu() { # <a label> <b label> <pids...>
  local a=$1 b=$2 args=() pid t0 t1
  shift 2
  for pid in "$@"; do args+=(-p "$pid"); done
  ((${#args[@]})) || { echo "probe: no diagnosticd to sample"; return; }
  t0=$(date +%s)
  run "$a" 10 ps -o pid=,time=,ucomm= "${args[@]}"
  pause 20
  t1=$(date +%s)
  run "$b" 10 ps -o pid=,time=,ucomm= "${args[@]}"
  cpu_rates "$a" "$b" "$((t1 - t0))" | tee -a "$exp/probe.txt"
}

probe_phase() {
  local rows pids=() sims=() pid side ppid unload_rc print_rc host_left k began came=
  time_left 10 || return 0    # about 8.5 min when every command runs to its alarm, the id lookup included
  find_simulator
  if [[ -z "$sim" ]]; then
    record_line "$exp/probe.txt" "probe: not run (no simulator id)"
    return 0
  fi
  echo "probe: the test step has ended and its evidence is saved; nothing here runs a test or reaches the re-run rule."
  run filter 10 python3 "$here/ci_log_compare.py" predicate
  probe_filter=$(cat "$exp/probe-filter.out")
  if [[ -z "$probe_filter" ]]; then
    record_line "$exp/probe.txt" "probe: not run (the test step's filter could not be read)"
    return 0
  fi
  census census-1
  rows=$(diag_rows census-1)
  while read -r pid side ppid; do
    [[ -n "$pid" ]] || continue
    pids+=("$pid")
    record_line "$exp/probe.txt" "probe: diagnosticd $pid $side (parent $ppid)"
  done <<<"$rows"
  sample_cpu cpu-a cpu-b "${pids[@]+"${pids[@]}"}"

  start_stream 1
  pause 3
  launch 1
  record_line "$exp/probe.txt" "probe: before any change:$got"

  run host-unload 15 sudo -n launchctl unload /System/Library/LaunchDaemons/com.apple.diagnosticd.plist
  unload_rc=$rc
  LOAD_CHECK=1 run host-print 15 sudo -n launchctl print system/com.apple.diagnosticd
  print_rc=$rc
  census census-2
  host_left=$(diag_rows census-2 | awk '$2 == "host"')
  if ((print_rc != 0 && rc == 0)) && [[ -z "$host_left" ]]; then
    record_line "$exp/probe.txt" "probe: host unload applied yes (unload exited $unload_rc; launchctl print exited $print_rc; no diagnosticd with parent 1)"
  elif ((print_rc == 0)) || [[ -n "$host_left" ]]; then
    record_line "$exp/probe.txt" "probe: host unload applied no (unload exited $unload_rc; launchctl print exited $print_rc; diagnosticd with parent 1: ${host_left:-none})"
  else
    record_line "$exp/probe.txt" "probe: host unload applied not known (unload exited $unload_rc; launchctl print exited $print_rc; the census exited $rc)"
  fi
  start_stream 2
  pause 3
  launch 2
  record_line "$exp/probe.txt" "probe: after host unload:$got"
  pids=()
  while read -r pid side ppid; do
    [[ -n "$pid" ]] || continue
    pids+=("$pid")
    [[ "$side" == sim ]] && sims+=("$pid")
  done <<<"$(diag_rows census-2)"
  sample_cpu cpu-c cpu-d "${pids[@]+"${pids[@]}"}"

  for pid in "${sims[@]+"${sims[@]}"}"; do
    run "sim-kill-$pid" 5 kill -TERM "$pid"
  done
  if ((${#sims[@]})); then
    began=$SECONDS
    k=0
    while ((SECONDS - began < 20)) && [[ -z "$came" ]]; do
      k=$((k + 1))
      census "poll-$k"
      came=$(diag_rows "poll-$k" | awk -v old=" ${sims[*]} " '$2 == "sim" && index(old, " " $1 " ") == 0 { print $1 }')
      [[ -n "$came" ]] || pause 1
    done
    if [[ -n "$came" ]]; then
      record_line "$exp/probe.txt" "probe: sim diagnosticd came back after $((SECONDS - began)) s (pid $came)"
    else
      record_line "$exp/probe.txt" "probe: sim diagnosticd did not come back in 20 s"
    fi
  else
    record_line "$exp/probe.txt" "probe: no diagnosticd under launchd_sim was found, so none was killed"
  fi
  start_stream 3
  pause 3
  launch 3
  record_line "$exp/probe.txt" "probe: after sim kill:$got"
  end_streams
}

case "$phase" in
  host) host_phase ;;
  sim) sim_phase ;;
  after) after_phase ;;
  compare) compare_phase ;;
  probe) probe_phase ;;
esac
exit 0
