# Thorbis 1.0 (14) — signed-in workspace branding

Date: 2026-10-27. Bundle `com.thorbis.field`, Apple ID `6827337706`, team `T677262U5B`.

## Changes

The signed-in workspace selectors now use the same official Thorbis shield asset as the app icon and existing branded screens. The workspace name and selector action remain visible.

## Verification

- Full iPhone 17 Pro / iOS 26.3.1 simulator suite: **192 tests passed, 0 failed**. Result bundle: `/Users/byronwade/Library/Developer/Xcode/DerivedData/Thorbis-dmuwxdzkujtkngcfxjqjbnvsarbv/Logs/Test/Test-Thorbis-2026.10.27_05-36-42--0400.xcresult`.
- Release iOS build passed.
- Release archive `/private/tmp/Thorbis-14-release.xcarchive` succeeded as version `1.0`, build `14`; `codesign --verify --deep --strict` passed.
- `xcodebuild -exportArchive` reported **Upload succeeded** at 5:41 AM EDT on 2026-10-27; Apple reports the package is processing.

## Distribution

App Store Connect sign-in has expired in the browser, so Build 14 is not yet assigned to Hayley Wade's external tester group and no invitation has been confirmed. Hayley is already in that group. Once signed in, assign Build 14 and confirm tester notification. External beta review still needs the App Review contact and demo-login details in `apple-record.md`.

This branding update does not establish full Paper/TanStack parity or authenticated live-device validation. See `beta-coverage.md` for remaining work.
