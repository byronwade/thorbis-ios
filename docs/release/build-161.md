# Build 161

Uploaded to App Store Connect on 4 November 2026 from release merge
`c53296fe9c04a6e2abc30b5b448a3969483145aa` ([PR #299](https://github.com/byronwade/thorbis-ios/pull/299)). Xcode reported that the package began processing and the upload succeeded (`/tmp/thorbis-release-161-upload.log`). Processing completion, tester-group availability and installation have not been verified.

This build includes the [build 160](build-160.md) start-screen and routing improvements, plus Estimates and Invoices jump controls on the job Money page ([PR #298](https://github.com/byronwade/thorbis-ios/pull/298)). These controls scroll to the chosen section without changing document or payment selection. Focused iPhone simulator UI tests covered both jumps, large text and invoice-selection retention; see [Money section jump evidence](../design/evidence/money-section-jumps-2026-11-03.md). Native iPad, physical-device, VoiceOver, denied-role and long-list behavior remain unverified.

The signed archive at `/private/tmp/thorbis-release-161/Thorbis.xcarchive` reports 1.0 (161), app bundle `com.thorbis.field`, widget build 161 and team `T677262U5B`. Before/after source fingerprints match. Strict app/widget signature verification passed, release preview fixture strings were absent, and the Tap to Pay audit passed with Tap to Pay disabled. Upload reported the existing missing Stripe Terminal framework dSYM warning; see [build 148](build-148.md#stripe-terminal-symbol-investigation).
