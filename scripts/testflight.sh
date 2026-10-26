#!/usr/bin/env bash
# Archive Thorbis and upload it to App Store Connect for TestFlight.
#
# Run on a Mac with Xcode signed in to the Apple Developer account that owns
# com.thorbis.field. Requires APPLE_TEAM_ID. Bumps CURRENT_PROJECT_VERSION to a
# timestamp so every upload has a unique build number.
#
#   APPLE_TEAM_ID=XXXXXXXXXX scripts/testflight.sh            # archive + upload
#   APPLE_TEAM_ID=XXXXXXXXXX scripts/testflight.sh --no-upload # archive + export .ipa only
set -euo pipefail

cd "$(dirname "$0")/.."
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your Apple Developer team id}"

destination=upload
[[ "${1:-}" == "--no-upload" ]] && destination=export

build_number="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
root="$(mktemp -d /tmp/thorbis-archive.XXXXXX)"
archive="$root/Thorbis.xcarchive"

command -v xcodegen >/dev/null || { echo "Install XcodeGen: brew install xcodegen" >&2; exit 1; }
xcodegen generate

echo "Testing core package"
swift test --package-path Core

echo "Archiving build $build_number into $root"
xcodebuild -project Thorbis.xcodeproj -scheme Thorbis \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$root/DerivedData" \
  -archivePath "$archive" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_STYLE=Automatic \
  CURRENT_PROJECT_VERSION="$build_number" \
  -allowProvisioningUpdates archive

# Release builds must not ship the fixture workspace or preview switches.
binary="$archive/Products/Applications/Thorbis.app/Thorbis"
# grep reads all input (no -q) so strings never hits SIGPIPE under pipefail.
if strings "$binary" | grep -e '--ui-fixture' -e 'mike@example.com' >/dev/null; then
  echo "Release binary contains fixture data; refusing to upload" >&2
  exit 1
fi

cat > "$root/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$destination</string>
  <key>teamID</key><string>$APPLE_TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$archive" \
  -exportOptionsPlist "$root/ExportOptions.plist" \
  -exportPath "$root/export" \
  -allowProvisioningUpdates

if [[ "$destination" == upload ]]; then
  echo "Uploaded build $build_number. It appears in App Store Connect → TestFlight after processing (usually 5–30 minutes)."
else
  echo "Exported to $root/export"
fi
echo "Archive kept at $archive"
