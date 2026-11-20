# Build 262

Uploaded to TestFlight from `paper-v2-tokens` at 3ed2b8d on 2026-11-17 (PR #563, Paper redesign merged with `release/104-integration`).

- Paper redesign across the app, with the release branch's fixes merged in.
- New places kept on this phone: Time clock, Receipts, Truck stock, Training, Pipeline, Vendors and POs, Marketing.
- Help and support in Settings.
- Owner menu ends with Business settings.
- Customer service invites no longer fail; Accountant can be invited.
- Sheet title rows stay on one line at large text.

Checks: 1,279 unit tests pass (1 skipped); stock-control lint 0. UI tests: the 28 that failed after the merge were rerun, 26 pass; the two left need a software keyboard and a rotating simulator. Upload warning only: no dSYM for StripeTerminal.framework.
