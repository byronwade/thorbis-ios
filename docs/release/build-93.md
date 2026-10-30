# Build 93 — customer job document return

- Runtime source: `f71e781c99b89408ee08b1f1cb00dd32d8e0ebaf`.
- Customer estimate review provides an explicit return to the current job's document book. Approved and other stale estimate statuses are not presented as current while refreshed; approval decisions require fresh job membership. Technician hand-back remains protected. Estimate and invoice hand-back now clear nested destinations before the protected exit.
- Exact-source iPhone SE focused verification passed: 25 job-document unit tests, 9 release-note tests, and 8 customer-document UI tests. Evidence and scope: `docs/design/evidence/customer-document-return/verification.md`; log `/private/tmp/customer-invoice-final-tests.log`.
- Read-only paper hand-back, paid invoices, pending payment and real-workspace journeys remain unverified. This build does not add customer-selected add-on quoting or combined checkout.
- Signed archive passed `/private/tmp/thorbis-93-final/audit-release.py`, including source, signature, version, preview isolation and disabled Tap to Pay. Distribution export was not separately audited.
- Xcode uploaded successfully on 2026-10-30. Apple reported the missing Stripe Terminal dSYM. App Store Connect shows processing complete, Internal Testers (2) assigned and testing notes saved. Evidence: `docs/design/evidence/customer-document-return/testflight-build-93.png`.
