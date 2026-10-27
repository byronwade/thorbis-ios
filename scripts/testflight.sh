#!/usr/bin/env bash
# Archive Thorbis and upload it to App Store Connect for TestFlight, the way
# builds 1-16 were uploaded (docs/release/build-1.md).
#
# Run on a Mac with Xcode signed in to the Apple account for team T677262U5B.
# BUILD_NUMBER is the next whole number after the latest build in App Store
# Connect; builds are sequential.
#
#   BUILD_NUMBER=17 scripts/testflight.sh             # test, archive, upload
#   BUILD_NUMBER=17 scripts/testflight.sh --no-upload # test, archive, export .ipa only
set -euo pipefail

cd "$(dirname "$0")/.."
build_number="${BUILD_NUMBER:?Set BUILD_NUMBER to the next build after the latest one in App Store Connect}"
[[ "$build_number" =~ ^[0-9]+$ ]] || { echo "BUILD_NUMBER must be a whole number" >&2; exit 1; }

destination=upload
[[ "${1:-}" == "--no-upload" ]] && destination=export

# Derived data stays outside Documents so FileProvider metadata can't break signing.
root="$(mktemp -d /private/tmp/thorbis-$build_number.XXXXXX)"
archive="$root/Thorbis.xcarchive"
options="$root/ExportOptions.plist"

xcodegen generate

simulator_id=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(v["udid"] for key,values in sorted(d["devices"].items(), reverse=True) if "iOS" in key for v in values if v["name"].startswith("iPhone")))')
xcodebuild -project Thorbis.xcodeproj -scheme Thorbis \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath "$root/test" -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test

xcodebuild -project Thorbis.xcodeproj -scheme Thorbis -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$root/archive" \
  -archivePath "$archive" CURRENT_PROJECT_VERSION="$build_number" \
  -allowProvisioningUpdates archive

cp docs/release/ExportOptions.plist "$options"
/usr/libexec/PlistBuddy -c "Set :destination $destination" "$options"
# Keep the number we chose; Xcode would otherwise renumber the upload.
/usr/libexec/PlistBuddy -c "Set :manageAppVersionAndBuildNumber false" "$options"

xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$options" \
  -exportPath "$root/export" -allowProvisioningUpdates

echo "Build $build_number: $destination finished. Archive: $archive"
