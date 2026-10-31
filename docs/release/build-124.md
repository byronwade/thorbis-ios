# Build 124 — redesign phase 3

Runtime source: `b21575c` (`release/104-integration`).

- **Redesign phase 3** (PR #205): estimate and invoice detail with 30pt titles and status/customer/job/date/total chips (new `DocumentStatus` glyph mapping), grouped wells for lines and payments, semibold amounts; Collect payment amount and method well; Estimates, Invoices and Needs attention lists grouped by status with glyph rows; owner Home with "N of M done" progress, glyph-led counts, place-marked money rows; Book job, Settings, Inbox (All / Unread text tabs, day sections) and Price book on grouped wells. Customer-facing presentation unchanged.

**Tests run: DocumentStatusTests, StatusGlyphTests, ListRowsTests, InvoicePaymentCollectionTests, WhatsNewTests only; UI suite compiled, not run, at the owner's request.** Contrast script 0 failures; the stock-control lint passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** on 31 October 2026.

Not verified: UI tests touching estimate/invoice lists, payment, Inbox and Price book; invoice due/overdue and estimate "viewed" (no data); iPad; empty/error states; refund sheets.

**Processing, tester groups and What to Test are not verified.**
