# Thorbis 1.0 (8) — Thorbis shield app icon

Date: 2026-10-27. Bundle `com.thorbis.field`, Apple ID `6827337706`, team `T677262U5B`.

## Changes

Build 8 includes the customer contact management changes from build 7 and uses the canonical Thorbis shield in the app icon. The icon generator now composites the original `ThorbisMark.png` asset onto the app's dark square background instead of drawing a generic geometric T. The login mark and icon therefore use the same brand symbol.

This remains an incremental staff beta, **not full Paper/TanStack parity**. See `beta-coverage.md` and `../design/README.md` for implemented and outstanding workflows.

## Verification

- Swift 6 iPhone 17 Pro simulator suite: **136 tests passed, zero failed or skipped**. Result bundle: `/Users/byronwade/Library/Developer/Xcode/DerivedData/Thorbis-dmuwxdzkujtkngcfxjqjbnvsarbv/Logs/Test/Test-Thorbis-2026.10.27_00-47-40--0400.xcresult`.
- Release archive succeeded at `/private/tmp/Thorbis-8-release.xcarchive`; its signature verifies for team `T677262U5B`, bundle `com.thorbis.field`, version `1.0`, build `8`. The Release binary contains no DEBUG Paper preview markers. Archive log: `/private/tmp/Thorbis-8-archive.log`.
- The login mark SHA-256 matches the TanStack source `apps/showcase/public/logo-source.png`. The 1024×1024 app icon is generated directly from that shield asset and was visually inspected.

## Distribution

`xcodebuild -exportArchive` uploaded build 8 successfully at 12:53 AM EDT on 2026-10-27. Apple reports **Uploaded package is processing**. Upload log: `../../outputs/testflight-upload-8.log`. App Store Connect is currently signed out, so processing and tester assignment have not been rechecked. Hayley Wade (`hayleywoods15@gmail.com`) is already in the external `External Testers` group; build 8 has not been assigned and no invitation has been sent. External beta review still needs an App Review contact phone and reviewer demo login. Build 8 supersedes build 7, which was uploaded before the icon correction.
