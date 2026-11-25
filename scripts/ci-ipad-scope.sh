#!/usr/bin/env bash
# Decide whether this run needs the iPad layout's UI tests (BYR-1843). Prints "true" or "false".
#
# The iPad run takes two more macOS runners for most of an hour, so it runs only when the change
# is one it can speak to: the iPad layout itself and the switch that picks it, a UI test with an
# iPad path, the layout helpers those tests share, or the workflow and scripts that plan and
# place the run. A run started by hand always includes it.
#
# A pull request is what changed since it left its base branch, on every push: a newer push
# cancels the run before it (cancel-in-progress), and an iPad run that was cancelled or failed
# must not be dropped by the next push. A push to main is what changed since the previous head of
# main. When neither can be read, the answer is "true": running it is the safe mistake.
#
# Reads EVENT_NAME, BEFORE_SHA, HEAD_SHA and BASE_SHA from the environment; needs full history.
set -euo pipefail

event=${EVENT_NAME:-}
before=${BEFORE_SHA:-}
head=${HEAD_SHA:-HEAD}
base=${BASE_SHA:-}

if [[ "$event" == "workflow_dispatch" ]]; then
  echo true
  exit 0
fi

known() { [[ -n "$1" && ! "$1" =~ ^0+$ ]] && git cat-file -e "$1^{commit}" 2>/dev/null; }

if ! known "$head"; then
  echo true
  exit 0
fi
if [[ "$event" == "pull_request" ]] && known "$base"; then
  changed=$(git diff --name-only "$base...$head")
elif known "$before"; then
  changed=$(git diff --name-only "$before" "$head")
elif known "$base"; then
  changed=$(git diff --name-only "$base...$head")
else
  echo true
  exit 0
fi

# The files that give a UI test class an iPad path, as the shard planner reads them.
tablet_tests=$(grep -rlw --include='*.swift' usesTabletLayout ThorbisUITests || true)

while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  case "$file" in
    Thorbis/Sources/TabletLayout.swift | Thorbis/Sources/PaperTabletSchedule.swift | Thorbis/Sources/PaperNavigation.swift) echo true; exit 0 ;;
    scripts/ci-ipad-scope.sh | scripts/ci-simulator-id.sh | scripts/ui_test_shards.py | .github/workflows/ios.yml) echo true; exit 0 ;;
    scripts/ci-run-ui-tests.sh | scripts/ci_cancelled_taps.py | scripts/ci_cpu_load.py) echo true; exit 0 ;;
    scripts/ci-load-experiment.sh | scripts/ci_log_compare.py) echo true; exit 0 ;;
  esac
  if grep -qxF "$file" <<<"$tablet_tests"; then
    echo true
    exit 0
  fi
done <<<"$changed"

echo false
