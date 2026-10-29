#!/usr/bin/env python3
"""Check Tap release intent against signed artifacts; never grants a capability."""

import argparse
from pathlib import Path
import plistlib
import subprocess
import sys

POLICY = "ThorbisTapToPayEnabled"
ENTITLEMENT = "com.apple.developer.proximity-reader.payment.acceptance"


def validate(enabled, signed, allowed):
    if type(enabled) is not bool:
        return ["The build has no explicit Boolean Tap to Pay policy marker."]
    if not enabled:
        return []
    errors = []
    if signed.get(ENTITLEMENT) is not True:
        errors.append("The signed app does not hold the Tap to Pay entitlement.")
    if allowed.get(ENTITLEMENT) is not True:
        errors.append("The provisioning profile does not allow Tap to Pay.")
    return errors


def validate_sdk_purposes(info):
    errors = []
    for key in ("NSBluetoothAlwaysUsageDescription", "NSLocationWhenInUseUsageDescription"):
        value = info.get(key)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"The app must declare a nonempty {key} for its linked SDK and location features.")
    return errors


def validate_binding(info, signed, profile, distribution=False):
    errors = []
    bundle_id = info.get("CFBundleIdentifier")
    application_id = signed.get("application-identifier")
    allowed = profile.get("Entitlements", {})
    if (not isinstance(bundle_id, str) or not isinstance(application_id, str)
            or not application_id.endswith("." + bundle_id)
            or application_id != allowed.get("application-identifier")):
        errors.append("The app and provisioning profile do not bind the same explicit application.")
    team = signed.get("com.apple.developer.team-identifier")
    teams = profile.get("TeamIdentifier", [])
    if not isinstance(team, str) or not isinstance(teams, list) or team not in teams:
        errors.append("The app and provisioning profile do not bind the same team.")
    if distribution and (signed.get("get-task-allow") is not False
                         or allowed.get("get-task-allow") is not False
                         or allowed.get("beta-reports-active") is not True
                         or profile.get("ProvisionedDevices") is not None
                         or profile.get("ProvisionsAllDevices") is True):
        errors.append("Tap to Pay distribution needs an App Store provisioning profile.")
    return errors


def command_bytes(*args):
    result = subprocess.run(args, capture_output=True, check=False)
    if result.returncode:
        raise ValueError(f"Artifact verification failed: {Path(args[0]).name}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--distribution", action="store_true")
    args = parser.parse_args()
    try:
        with (args.app / "Info.plist").open("rb") as source:
            info = plistlib.load(source)
        command_bytes("/usr/bin/codesign", "--verify", "--deep", "--strict", str(args.app))
        enabled = info.get(POLICY)
        errors = validate_sdk_purposes(info)
        errors += validate(enabled, {}, {}) if enabled is not True else []
        if enabled is True:
            signed = plistlib.loads(command_bytes(
                "/usr/bin/codesign", "--display", "--entitlements", "-", "--xml", str(args.app)))
            profile = plistlib.loads(command_bytes(
                "/usr/bin/security", "cms", "-D", "-i", str(args.app / "embedded.mobileprovision")))
            errors += validate(enabled, signed, profile.get("Entitlements", {}))
            errors += validate_binding(info, signed, profile, args.distribution)
        if errors:
            for error in errors:
                print(error, file=sys.stderr)
            return 1
        print("Tap to Pay audit passed: " + ("signed entitlement verified" if enabled else "disabled in this build"))
        return 0
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"Tap to Pay audit refused this artifact: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
