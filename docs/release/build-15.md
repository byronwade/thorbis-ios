# Thorbis 1.0 (15) — Native primary navigation

Date: 2026-10-27. Bundle `com.thorbis.field`, Apple ID `6827337706`, team `T677262U5B`.

## Changes

- The iPhone shell now uses native labeled Jobs, Arrive, and Inbox tabs. Jobs opens the full jobs workflow, Arrive opens the existing My Day/on-the-way workflow, and Inbox displays only server-backed staff notices. Each primary tab retains its own navigation stack. Schedule, customers, device-local drafts, Price Book, search, workspace selection, settings, and job creation remain reachable through More and their existing gates.
- The iPad keeps its workspace sidebar and adaptive schedule/list/detail layout. All signed-in workspace selectors use the verified Thorbis shield, matching the authentic app icon and the Thorbis mark-and-wordmark lockup used on sign-in and public estimates.

## Verification

- Full iPhone 17 Pro / iOS 26.3.1 simulator suite: **196 tests passed, 0 failed**. Result bundle: `/Users/byronwade/Library/Developer/Xcode/DerivedData/Thorbis-dmuwxdzkujtkngcfxjqjbnvsarbv/Logs/Test/Test-Thorbis-2026.10.27_05-53-43--0400.xcresult`.
- Release build for iPad Pro 13-inch (M5) simulator passed.
- Read-only previews: `/private/tmp/thorbis-primary-tabs-build15.png` and `/private/tmp/thorbis-ipad-primary-nav-after.png`. These use intercepted sample data; they do not verify authenticated live workflows.
- Archive `/private/tmp/Thorbis-15-release.xcarchive` succeeded as version `1.0`, build `15`. `codesign --verify --deep --strict` passed.
- `xcodebuild -exportArchive` reported **Upload succeeded** and **Uploaded package is processing** at 6:00 AM EDT on 2026-10-27.

## Distribution

Build 15 was uploaded and processing in App Store Connect, then superseded by Build 16. Hayley Wade (`hayleywoods15@gmail.com`) is already in the external tester group, but Build 15 assignment and invitation delivery were not confirmed. See `build-16.md` for the current build status. External beta review still needs the App Review contact and reviewer demo-login details documented in `apple-record.md`.

This incremental beta does not establish full Paper/TanStack parity, authenticated live-device validation, or Universal Link readiness. See `beta-coverage.md` for remaining work.
