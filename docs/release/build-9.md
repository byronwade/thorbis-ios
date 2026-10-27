# Thorbis 1.0 (9) — draft invoice editing

Date: 2026-10-27. Bundle `com.thorbis.field`, Apple ID `6827337706`, team `T677262U5B`.

## Changes

Build 9 adds Paper-aligned draft invoice line editing: add, remove and reorder lines; select current Price Book revisions behind the matching capability gates; preserve estimate and Price Book provenance; and save or issue against the server's latest line revision. Save is disabled for unchanged drafts, and unsupported provenance locks the editor rather than risking data loss. The authentic Thorbis shield remains the sign-in and app icon mark.

This is an incremental staff beta, **not full Paper/TanStack parity**. See `beta-coverage.md` and `../design/README.md` for remaining workflows.

## Verification

- Swift 6 iPhone 17 Pro simulator suite: **147 tests passed, zero failed**. Result bundle: `/Users/byronwade/Library/Developer/Xcode/DerivedData/Thorbis-dmuwxdzkujtkngcfxjqjbnvsarbv/Logs/Test/Test-Thorbis-2026.10.27_01-28-11--0400.xcresult`.
- Release device build succeeded. Release archive succeeded at `/private/tmp/Thorbis-9-release.xcarchive`; its signature verifies for team `T677262U5B`, bundle `com.thorbis.field`, version `1.0`, build `9`. The Release binary contains no DEBUG Paper preview flag. Archive log: `/private/tmp/thorbis-9-archive.log`.
- The invoice editor was visually checked on iPhone 17 Pro using read-only sample data at `/private/tmp/thorbis-invoice-editor-reordered.png`.

## Distribution

`xcodebuild -exportArchive` uploaded build 9 successfully at 1:36 AM EDT on 2026-10-27. Apple reports **Uploaded package is processing**. Upload log: `/private/tmp/thorbis-9-upload.log`. App Store Connect is signed out, so processing and tester assignment have not been rechecked. Hayley Wade (`hayleywoods15@gmail.com`) is already in the external `External Testers` group; build 9 has not yet been assigned and no new invitation has been sent. External beta review still needs an App Review contact phone and reviewer demo login. Build 9 supersedes build 8.
