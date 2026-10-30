# Build 95 — truthful customer invoice balance

- Runtime source: `014a5b37a2f123d3038b123fa7caaddbaab8ce7d`.
- Customer invoice headings distinguish draft totals, amounts due, zero balances and verified paid invoices. Stale records show last-known status/balance. Paid in full requires paid status, positive recorded aggregate and complete reconciled payment history. Payment actions and monetary calculations are unchanged.
- Exact-source iPhone SE verification passed 37 unit tests and four customer invoice UI tests covering draft, zero-dollar, partial payment, paid deposit, unavailable history, discounts/refunds and paging. Independent review found no concrete blocker. Evidence: `docs/design/evidence/customer-invoice-balance/verification.md`.
- Live reconciliation, physical-device appearance, long descriptions, iPad, VoiceOver and largest text were not tested in this batch.
- `/private/tmp/thorbis-95-invoice/audit-release.py` verified signed archive source, app/widget version, DEBUG fixtures and disabled Tap to Pay; distribution export was not independently audited.
- Xcode uploaded successfully 2026-10-30; Apple reported the missing Stripe Terminal dSYM. Processing and intended tester access must be confirmed in App Store Connect.
