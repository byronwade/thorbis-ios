# Build 167 upload

On 2026-11-04, Xcode archived and uploaded build 167 successfully. Apple reported the uploaded package was processing; processing completion and tester-group availability have not been verified. Archive and upload logs: `/tmp/thorbis-release-167-archive.log` and `/tmp/thorbis-release-167-upload.log`.

The archive was built from reviewed PR head `35f00d680dde7486aedfe10825545c92ac2ab73f`, tree `7760f105b81d07868f4331270c0814585f792207`. Merged release commit `8c0afa771345634d494e90376a569e3c1ec0eec7` has the identical tree. The app and widget report build 167; the app is `com.thorbis.field`, signed by team `T677262U5B`. Deep signature verification passed. The archived executable SHA-256 is `db2cf873edeb0ca41d1511ed14d65a0af73cb65bae99600afa33c84596515266`. The Tap to Pay audit passed with Tap to Pay disabled in this build.

This build adds direct access to job Photos and preserves the payment-route changes from build 166. It does not add customer photo handoff. Validation and the original payment revocation test failure are documented in `docs/design/evidence/job-photos-2026-11-04.md`. The merged PR's remote iOS build check remained pending at upload time.

Xcode warned that the StripeTerminal framework dSYM for UUID `6B66F53A-307E-3AD8-AC4E-A2E5AF652AE9` was missing, which may limit symbolication of crashes in that framework.
