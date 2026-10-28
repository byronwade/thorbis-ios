# Thorbis 1.0 (4) — authentic brand mark and schedule DST fixes

Date: 2026-10-26. Bundle `com.thorbis.field`, Apple app ID `6827337706`, team `T677262U5B`.

## Changes

Uses the authentic Thorbis shield from `Thorbis-TanStack/apps/showcase/public/logo-source.png` for the native login mark. The app icon in this build was still a generic geometric T and is corrected in build 8. Tightens schedule selection around daylight-saving transitions: keeping the same day preserves the selected fall-back occurrence, changing days selects the first repeated occurrence, and nonexistent spring-forward times are rejected with a consistent explanation. Accepted date/time choices clear old errors. The schedule sheet cannot be dismissed while its save request is pending.

This is an incremental presentation beta, **not full Paper/TanStack parity**. See `docs/design/README.md` and `docs/release/beta-coverage.md` for remaining gaps. This build does not claim the remaining workflows are complete.

## Verification

- Final iPhone 17 Pro simulator suite: **117 tests, zero failures**; log `../outputs/schedule-full-tests.log`.
- Swift 6 Release archive: **ARCHIVE SUCCEEDED** at `/private/tmp/Thorbis-4-final.xcarchive`; log `../outputs/thorbis-4-archive.log`.
- `codesign --verify --deep --strict`: valid on disk and satisfies its designated requirement.
- Archived plist verified bundle `com.thorbis.field`, version `1.0`, build `4`.
- Archived binary has no DEBUG preview marker strings.
- Thorbis mark asset matches the TanStack source byte-for-byte; app icon is a 1024×1024 PNG.
- Independent schedule review found no blockers.

## Distribution

`xcodebuild -exportArchive` uploaded build 4 successfully to App Store Connect at 11:02 PM EDT on 2026-10-26; log `../outputs/testflight-upload-4.log`. App Store Connect showed build 4 as **Processing** at the last check. The external `External Testers` group contains Hayley Wade (`hayleywoods15@gmail.com`) and has no build assigned yet. The external beta review record still needs an App Review contact phone and a demo login; no invitation has been sent.
