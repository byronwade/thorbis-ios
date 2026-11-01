# Build 115 — search and correctness fixes

Runtime source: `1cb9789` (`release/104-integration`).

- **Search** (PR #186): grouped results (Top hit, Jobs, Customers, Estimates, Invoices, Places and actions); matches street, phone digits, numbers and problem words with highlights; instant results from the phone, then the server; action rows (book, new job, settings…); recents with Clear; offline search of saved data; Return opens the top hit; iPad arrow keys. Fixed server-only results that did nothing on iPhone.
- **Correctness fixes** (PR #187): invoices, estimates, payments, permissions and the price book always read fresh (no 10-second reuse), so receipts reconcile and "Check status" is current; the pre-signature estimate check no longer passes on a saved copy when the network drops.

**Tests:** for PR #187 only, unit tests ran 714 with 0 failures; key UI test classes updated for the redesign. Three customer-handoff UI tests still fail (accessibility tree empty after a session change, also fails before #179 — needs a VoiceOver check on device). The stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** on 31 October 2026.

Not verified: iPad search, hardware arrow keys, search with no signal, real payments.

**Processing, tester groups and What to Test are not verified.**
