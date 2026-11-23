#!/usr/bin/env bash
# Print the id of the simulator CI tests on: the first available iPhone on the newest installed
# iOS runtime, so every job tests on the same kind of device.
#
#   scripts/ci-simulator-id.sh          # an iPhone
#   scripts/ci-simulator-id.sh iPad     # an iPad, for the iPad layout's run (BYR-1843)
#
# For an iPad it prefers the 13-inch Pro, then any Pro, then any iPad. Every current iPad is at
# least 1100 points wide in landscape, which is where the app docks its sidebar.
set -euo pipefail

kind=${1:-iPhone}
case "$kind" in
  iPhone | iPad) ;;
  *) echo "usage: ci-simulator-id.sh [iPhone|iPad]" >&2; exit 2 ;;
esac

xcrun simctl list devices available -j | KIND="$kind" python3 -c '
import json, os, sys

kind = os.environ["KIND"]
preferred = ["iPad Pro 13-inch", "iPad Pro", "iPad"] if kind == "iPad" else ["iPhone"]
devices = json.load(sys.stdin)["devices"]
for runtime in sorted((key for key in devices if "iOS" in key), reverse=True):
    for prefix in preferred:
        for device in devices[runtime]:
            if device["name"].startswith(prefix):
                print("Simulator:", device["name"], "on", runtime.rsplit(".", 1)[-1], file=sys.stderr)
                print(device["udid"])
                sys.exit(0)
sys.exit(f"No available {kind} simulator")
'
