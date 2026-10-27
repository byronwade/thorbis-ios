# Thorbis 1.0 (7) — Customer contact management

Date: 2026-10-27. Bundle `com.thorbis.field`, Apple ID `6827337706`, team `T677262U5B`.

## Changes

Customer details now support creating and editing contacts, promoting a primary contact, and removing a contact after confirmation. Blank optional fields clear their server values, failed mutations preserve the current row and draft, and stale refreshes cannot replace a completed mutation. The contact section retains its Paper styling and capability checks. The displayed Thorbis shield is the original `apps/showcase/public/logo-source.png` asset from the TanStack repository, copied byte-for-byte.

This is an incremental staff beta, **not full Paper/TanStack parity**. See `beta-coverage.md` and `../design/README.md` for implemented and outstanding workflows.

## Verification

- Swift 6 iPhone 17 Pro simulator suite: **136 tests passed, zero failed or skipped**. Result bundle: `/Users/byronwade/Library/Developer/Xcode/DerivedData/Thorbis-dmuwxdzkujtkngcfxjqjbnvsarbv/Logs/Test/Test-Thorbis-2026.10.27_00-47-40--0400.xcresult`.
- Focused contact API/state tests passed, including nullable-field clearing, primary promotion, bodyless removal, invalid UUID rejection, and stale-refresh protection.
- Release archive succeeded at `/private/tmp/Thorbis-7-release.xcarchive`; its signature verifies for team `T677262U5B`, bundle `com.thorbis.field`, version `1.0`, build `7`. The Release binary contains no DEBUG Paper preview markers. Archive command output was captured in the current task log.
- The login mark uses the real Thorbis shield and its source asset SHA-256 matches the TanStack source file exactly. Build 7's app icon was subsequently found to use a generic geometric T; Build 7 is superseded by Build 8, which uses the canonical shield for both the app icon and login mark.

## Distribution

`xcodebuild -exportArchive` uploaded build 7 successfully at 12:49 AM EDT on 2026-10-27. Apple reports **Uploaded package is processing**. Upload log: `../../outputs/testflight-upload-7.log`. App Store Connect is currently signed out, so processing and tester assignment have not been rechecked. Hayley Wade (`hayleywoods15@gmail.com`) is already in the `External Testers` group; build 7 has not been assigned and no invitation has been sent. External beta review still needs an App Review contact phone and reviewer demo login.
