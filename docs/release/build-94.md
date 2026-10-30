# Build 94 — read-only customer document hand-back

- Runtime source: `f8b00642512f3b29575bc1c8f1c2db2dbdcbb8ac`.
- Fixes hand-back when an estimate or invoice becomes read-only between opening the job document book and the final decision refresh. It uses the existing technician-authenticated hand-back transition.
- Both estimate and invoice regressions failed before the fix and passed after. Exact-source verification passed 25 job-document unit tests, nine release-note tests and ten customer-document UI tests on iPhone SE. See `docs/design/evidence/readonly-document-handback/verification.md`.
- Independent review found no concrete regression. Live status races, physical-device authentication, iPad and VoiceOver remain unverified.
- Signed archive passed `/private/tmp/thorbis-94-readonly/audit-release.py`, including the new DEBUG preview flag, source fingerprints, signing and disabled Tap to Pay. Distribution export was not independently audited.
- Xcode upload succeeded 2026-10-30; Apple reported the missing Stripe Terminal dSYM. Processing and tester availability must be verified in App Store Connect.
