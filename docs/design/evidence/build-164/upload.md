# Build 164 upload

Build 164 was archived from merged release commit `d298698649ff23582ff563df2faa097bc4733439` and uploaded to App Store Connect on 2026-11-04. Xcode reported `ARCHIVE SUCCEEDED`, `EXPORT SUCCEEDED`, and that the uploaded package was processing. Processing completion, assignment to testers and installation were not verified.

The signed app and widget both report build 164; the app reports version 1.0, bundle `com.thorbis.field`, and team `T677262U5B`. Strict signatures, tracked-source fingerprints, tested-source fingerprints, Release preview-string check and disabled Tap to Pay audit passed. Archive and upload logs: `/tmp/thorbis-release-164-archive.log` and `/tmp/thorbis-release-164-upload.log`; source fingerprints: `/tmp/thorbis-release-164-before.sha` and `/tmp/thorbis-release-164-after.sha`. The upload reported a missing StripeTerminal framework dSYM; upload succeeded despite that warning.

The build adds per-response invoice provenance and stops payment-history pagination when the saved workspace scope, scope revision, origin or request generation changes. The focused simulator run passed 32 tests; nine What's New checks and the visual preview passed. This is not a durable invoice-denial fix and does not establish reauthorization after app relaunch. Tap to Pay remains disabled.
