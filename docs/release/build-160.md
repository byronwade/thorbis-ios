# Build 160

Uploaded to App Store Connect on 4 November 2026 from release merge
`0328b09f79d99bb43afb7b5fc22173ea744132a7` ([PR #297](https://github.com/byronwade/thorbis-ios/pull/297)). Xcode reported that the package began processing and that the upload succeeded (`/tmp/thorbis-release-160-noted-upload.log`). Apple processing completion, tester-group availability and installation have not been verified.

This build lets a person choose a permitted start screen in Settings on this device, scoped to their account, workspace and server. It includes fixes for explicit links, search and the adaptive root handoff. Focused source and simulator evidence, including the limits of forced adaptive-shell and internal-request fixtures, is recorded in [startup destination verification](../design/evidence/startup-destination-2026-11-03.md). The What's New note passed nine tests and was visually previewed with sample data (`/tmp/thorbis-160-whats-new-preview2.png`). Real external links, native iPad behavior, real workspace switches and physical-device behavior remain unverified.

The signed archive at `/private/tmp/thorbis-release-160-noted/Thorbis.xcarchive` reports 1.0 (160), app bundle `com.thorbis.field`, widget build 160 and team `T677262U5B`. Before/after source fingerprints match. Strict app/widget signature verification passed, release preview fixture strings were absent, and the Tap to Pay audit passed with Tap to Pay disabled. The upload reported the existing missing Stripe Terminal framework dSYM warning; see [build 148](build-148.md#stripe-terminal-symbol-investigation).
