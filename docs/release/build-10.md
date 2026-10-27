# Thorbis 1.0 (10) — customer history parity

Date: 2026-10-27. Bundle `com.thorbis.field`, Apple ID `6827337706`, team `T677262U5B`.

## Changes

Build 10 adds the TanStack customer-list scopes (Recent, All customers, Archived) with the separate Active/Archived state filter. Customer Activity now reads `/v1/customers/{id}/history`, displays the kind icon, summary, and relative age, and follows `nextCursor` with a retryable “Load earlier activity” button. It does not add archive or restore actions absent from the web customer UI. The sign-in screen and app icon use the authentic Thorbis shield asset.

This remains an incremental staff beta, not full Paper/TanStack parity. See `beta-coverage.md` and `../design/README.md` for remaining workflows.

## Verification

- Swift 6 iPhone 17 Pro simulator suite: **151 tests passed, zero failed**. Result bundle: `/Users/byronwade/Library/Developer/Xcode/DerivedData/Thorbis-dmuwxdzkujtkngcfxjqjbnvsarbv/Logs/Test/Test-Thorbis-2026.10.27_02-19-27--0400.xcresult`.
- iOS Release build and archive succeeded. The signed archive is `/private/tmp/Thorbis-10-release.xcarchive`; its app plist reports bundle `com.thorbis.field`, version `1.0`, build `10`, and `codesign --verify --deep --strict` passed. Archive log: `/private/tmp/thorbis-10-archive.log`.
- Customer history contract tests cover the endpoint, required item fields, the 50-item page size, and cursor requests. Customer-list tests cover the archived-inclusive query across pages and the Recent/All/Archived predicates.

## Distribution

`xcodebuild -exportArchive` reported **Upload succeeded** and **EXPORT SUCCEEDED** at 2:22 AM EDT on 2026-10-27. Upload log: `/private/tmp/thorbis-10-upload.log`. App Store Connect processing and tester assignment have not been rechecked; the browser session is on Apple's sign-in page and Xcode reports its Apple session expired. Hayley Wade (`hayleywoods15@gmail.com`) is listed in the external `External Testers` group, but Build 10 has not been assigned and no new invitation has been confirmed. External testing still requires the TestFlight review details documented in `apple-record.md`.
