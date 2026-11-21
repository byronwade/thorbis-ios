#!/usr/bin/env bash
# Print the id of the first available iPhone simulator on the newest installed iOS runtime.
# CI uses it so every job tests on the same kind of device.
set -euo pipefail

xcrun simctl list devices available -j | python3 -c '
import json, sys

devices = json.load(sys.stdin)["devices"]
for runtime in sorted((key for key in devices if "iOS" in key), reverse=True):
    for device in devices[runtime]:
        if device["name"].startswith("iPhone"):
            print(device["udid"])
            sys.exit(0)
sys.exit("No available iPhone simulator")
'
