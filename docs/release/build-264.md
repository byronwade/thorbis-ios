# Build 264

Uploaded to TestFlight from `paper-v2-tokens` at cf5e600 on 2026-11-17 (PR #563).

The Paper design pass: screens compared with the Paper artboards side by side and rebuilt to match.

- Shared pieces: header, menu and "+" buttons, search field, tabs, cards, rows, status marks, floating side menu, times as "10:30 AM".
- Schedule, Jobs, Job details, Field mode (Driving, Arrived, Working, Wrap up, Paid).
- Dashboards, Money, Reports, Payments, Payouts, Team, role picker.
- Customers, the customer's tabbed page, Messages, Search, Notifications, Properties, Equipment, plans.
- Estimates, invoices, New estimate, Edit invoice, Collect payment.
- Settings, Business settings, Login, Sign up, guided setup, Help.
- Time clock, Receipts, Truck stock, Training, Pipeline, Vendors and POs, Marketing and their detail screens.

Checks: 1,352 unit tests pass (1 skipped); stock-control lint 0; release configuration compiles. Full UI suite on the commit before this one: 425 run, 361 pass, 21 skipped, 43 fail; the failures were being triaged when this build was uploaded and it was sent as a look-and-feel build. Not every artboard was compared: see the PR discussion for the list still open.
