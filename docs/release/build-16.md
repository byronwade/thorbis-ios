# Thorbis 1.0 (16) — Native primary navigation and official branding

Date: 2026-10-27. Bundle `com.thorbis.field`, Apple ID `6827337706`, team `T677262U5B`.

## Changes

- Includes the reviewed native Jobs, Arrive, and Inbox tab navigation, with the adaptive iPad sidebar and schedule/list/detail layout preserved.
- Uses the verified Thorbis shield in signed-in workspace selectors, the Thorbis lockup on sign-in and public estimate screens, and the shield as the app icon. The shield asset SHA-256 is `07b9cb8803e215ad6a45b17daadd05ef27e0a72799c9cf0e83310a848273d737`.

## Verification

- Full iPhone 17 Pro / iOS 26.3.1 simulator suite: **196 tests passed, 0 failed**. Result bundle: `/Users/byronwade/Library/Developer/Xcode/DerivedData/Thorbis-dmuwxdzkujtkngcfxjqjbnvsarbv/Logs/Test/Test-Thorbis-2026.10.27_06-08-52--0400.xcresult`.
- iOS device archive `/private/tmp/Thorbis-16-release.xcarchive` succeeded as version `1.0`, build `16`. Bundle ID: `com.thorbis.field`. `codesign --verify --deep --strict` passed.
- App Store Connect upload completed at 6:11 AM EDT; Apple reported **Upload succeeded** and **Uploaded package is processing**.

## Distribution

Build 16 is uploaded and processing in App Store Connect. Hayley Wade (`hayleywoods15@gmail.com`) is already in the external tester group, but assignment of Build 16 and invitation delivery are not confirmed. A valid signed-in App Store Connect session is needed to complete and verify those steps. External beta review still needs the App Review contact and reviewer demo-login details documented in `apple-record.md`.

This incremental beta does not establish full Paper/TanStack parity, authenticated live-device validation, or Universal Link readiness. See `beta-coverage.md` for remaining work.
