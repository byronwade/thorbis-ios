# Build 163 upload

Build 163 was archived from merged release commit `02523785fc4de5c732eb94d8505141b8f1cc3a6c` and uploaded to App Store Connect on 2026-11-04. Xcode reported `ARCHIVE SUCCEEDED` and `EXPORT SUCCEEDED`; the upload reported that the package was processing. TestFlight processing completion and tester availability were not verified by this upload receipt.

The signed archive's build number is 163. Code-signature validation passed, and the tracked app, widget, shared source and project manifest matched before and after archive (`/tmp/thorbis-release-163-before.sha`, `/tmp/thorbis-release-163-after.sha`). Logs are `/tmp/thorbis-release-163-archive.log` and `/tmp/thorbis-release-163-upload.log`. Xcode warned that the StripeTerminal framework's matching dSYM was absent; upload succeeded despite the warning.

This build adds read-only details for sent estimates before selection. Approved-estimate details and automatic detection of external changes without a refresh remain separate work; this upload does not establish live server behavior.
