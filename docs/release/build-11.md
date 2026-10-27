# Thorbis 1.0 (11) — invoice payment history and collection

Date: 2026-10-27. Bundle `com.thorbis.field`, Apple ID `6827337706`, team `T677262U5B`.

## Changes

Build 11 adds the invoice Payments section, read-only payment details, and a native form to record a payment already collected by Card, ACH, Cash, or Check. It reconciles the payment history against the server's invoice balance, blocks overpayment, and persists an uncertain retry intent by organization and invoice so the same idempotency key is reused after view recreation or app restart. It does not charge a card or bank account. The sign-in screen and app icon continue to use the canonical Thorbis shield from the TanStack repository.

This is an incremental staff beta, not full Paper/TanStack parity. See `beta-coverage.md` and `../design/README.md` for remaining workflows.

## Verification

- Full Swift 6 simulator suite: **161 tests passed, zero failed** on iPhone 17 Pro / iOS 26.3.1. Result bundle: `/tmp/ThorbisReviewFixTests.xcresult`.
- Release build and signed archive succeeded. Archive: `/private/tmp/Thorbis-11-release.xcarchive`. Its app plist reports bundle `com.thorbis.field`, version `1.0`, build `11`; `codesign --verify --deep --strict` passed. The production executable contains no Paper preview launch markers.
- Canonical logo SHA-256 matched both repos: `07b9cb8803e215ad6a45b17daadd05ef27e0a72799c9cf0e83310a848273d737`.
- Independent review confirmed the payment-intent persistence, fully-refunded reconciliation, and issue-refresh fixes.

## Distribution

`xcodebuild -exportArchive` reported **Upload succeeded** and **Uploaded package is processing** at 3:10 AM EDT on 2026-10-27. App Store Connect processing and build assignment have not been rechecked because the Chrome session is signed out. Hayley Wade (`hayleywoods15@gmail.com`) is already listed in the external `External Testers` group, but Build 11 has not been assigned and no invitation is confirmed. External beta review still needs the App Review contact and demo-login details documented in `apple-record.md`.
