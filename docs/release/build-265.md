# Build 265

Uploaded to TestFlight from `paper-v2-tokens` at 43c3d2c9 on 2026-11-18 (PR #563).

Build 264 plus the fixes found while repairing the UI tests after the Paper design pass.

- Collect payment from a job opens only while you are still on the job's Money section.
- An invoice opened from a job's Money section closes when the sign-in or permissions change, and will not open from an out-of-date read.
- Invoice line editor: the gap between Done and Remove is back to 24 points (16 at large text).

Checks: 1,352 unit tests pass (1 skipped); stock-control lint 0; release configuration compiles. UI tests: the 14 failing tests outside the job screens and the eight job and customer-document classes (160 tests) pass when run by class; the full suite was not re-run on this commit. Four email-draft recovery tests and two customer "Your details" tests need a signed build (keychain).
