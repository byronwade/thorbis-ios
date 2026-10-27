# Thorbis 1.0 (6) — Customer service locations

Date: 2026-10-27. Bundle `com.thorbis.field`, Apple ID `6827337706`, team `T677262U5B`.

## Changes

Customer details now support creating, editing, and removing service and billing locations. The Paper-style editor covers label, address, notes, map coordinates, gate and alarm codes, dog-on-site, and parking details, using the canonical customer-location API. A generation guard prevents an older refresh response from replacing a successful edit or removal.

This is an incremental staff beta, **not full Paper/TanStack parity**. See `beta-coverage.md` and `../design/README.md` for implemented and outstanding workflows.

## Verification

- Swift 6 iPhone 17 Pro simulator suite: **132 tests passed, zero failed or skipped**. Result bundle: `/Users/byronwade/Library/Developer/Xcode/DerivedData/Thorbis-dmuwxdzkujtkngcfxjqjbnvsarbv/Logs/Test/Test-Thorbis-2026.10.27_00-28-03--0400.xcresult`.
- The focused stale-refresh regression passed, covering both an edit and a removal while an older request was pending.
- Release archive succeeded at `/private/tmp/Thorbis-6-release.xcarchive`; its app signature verified for team `T677262U5B`, bundle `com.thorbis.field`, version `1.0`, build `6`. Archive log: `../../outputs/thorbis-6-archive.log`.
- The app was exported with automatic signing for App Store Connect upload.

## Distribution

`xcodebuild -exportArchive` uploaded build 6 successfully at 12:32 AM EDT on 2026-10-27. Apple reports **Uploaded package is processing**. Upload log: `../../outputs/testflight-upload-6.log`. App Store Connect has not yet been rechecked because the browser session is signed out. Hayley Wade (`hayleywoods15@gmail.com`) is already in the `External Testers` group; build 6 has not been assigned and no invitation has been sent. External beta review still needs an App Review contact phone and reviewer demo login.
