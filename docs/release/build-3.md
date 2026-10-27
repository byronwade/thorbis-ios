# Thorbis 1.0 (3) — Paper presentation beta

Date: 2026-10-26. Code revision: `4b89be6` (following Paper UI integration `48dac2e` and scoped screen commits). Bundle `com.thorbis.field`, team `T677262U5B`, App Store Connect app `6827337706`.

## Changes

Uses current Thorbis Mobile Paper exports for native typography, colors, compact work screens, navigation dock/drawer, customer/job detail, financial and Price Book presentation. Adds iPad sidebar and split schedule/detail, real password-reset requests, and DEBUG-only isolated visual fixtures. Includes build 2's cookie-mutation Origin fix.

This is an incremental presentation beta, **not full Paper/TanStack parity**. See `docs/design/README.md` for exact remaining gaps, including operational forms and unsupported workflows. No sample record, fake payment, delivered-message claim, or offline-sync claim is enabled in Release.

## Verification

- Final Debug simulator suite: **105 tests, zero failures**, including four preview transport/session tests. Log: workspace `outputs/paper-build3-tests.log`.
- Swift 6 complete strict concurrency Release archive: **ARCHIVE SUCCEEDED**. Archive `/private/tmp/Thorbis-3.xcarchive`; log `outputs/paper-build3-archive.log`.
- `codesign --verify --deep --strict`: valid on disk and satisfies designated requirement.
- Archived plist verified `CFBundleVersion=3`, marketing version 1.0, correct bundle and both bundled font registrations.
- Archived binary verified absent `--paper-preview`, `DESIGN PREVIEW`, and fixture-email markers. All font resources present.
- iPhone populated Schedule/Jobs/Customer views inspected against Paper; Schedule→job→Back and Customers→detail checked through simulator UI. iPad portrait/landscape split layout inspected. Screenshot artifacts under workspace `outputs/paper/` are clearly labeled sample/read-only previews.
- Independent review found a large-text job-header issue; fixed by scrolling header with content. Customer metadata wraps and login fields grow with text. Navigation and financial-handler review found no remaining blocking regression.
- Physical-device authenticated end-to-end verification remains unconfirmed.

## Distribution

Upload succeeded at 21:06 EDT on 2026-10-26: `Upload succeeded`, `Uploaded Thorbis`, and `EXPORT SUCCEEDED` in `outputs/testflight-upload-3.log`. Apple processing/group availability is pending confirmation.

Build 2 was verified processed and assigned to Internal Testers before this upload, with one invite. No new tester invitation is required to receive an update to the existing app.
