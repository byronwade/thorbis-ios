# Build 128 — design.thorbis.com redesign across the app

Runtime source: `0f3b8ff` (`release/104-integration`). The first attempt failed in Release because #216 used the DEBUG-only `PaperPreviewScrollAnchor`; #217 guarded it.

- **Lists, Customer, Search, Inbox** (PR #214):
  - Canvas rows, street or name first, status word trailing, status groups.
  - Filter popover.
  - Customer facts shown once.
  - Search is a pushed route.
  - Inbox has All / Unread and day groups.
  - Empty states name the action.
- **Money, Home, Settings, forms** (PR #216):
  - Invoices and estimates read as paper, with two-decimal tabular money.
  - Collect payment has method chips and a `$` well. A pending payment shows "Not confirmed yet" and offers "Check payment status".
  - Refunds use a danger commit.
  - Owner Home shows rows with words.
  - Settings is a single column, with danger set apart.
  - Forms follow design.thorbis.com: label above, example placeholder, help under the field, errors replacing the help, no pre-disabled commits.
- **Today / Schedule and Job** (PR #215):
  - Today has a tabular time column and the list-room rows, plus a calm Now panel.
  - Board has Open / En route / On site / Done columns.
  - Record rooms have no panels.
  - Job shows each fact once and wrap-up uses Done / To do.
  - The status popover is grouped (current, forward moves, pause / move back).

**Tests run: touched unit suites (19 + 37 + 47); UI suite compiled, not run, at the owner's request.** The stock-control lint passed (0), contrast passed (0), the Release archive succeeded, and Xcode reported **Upload succeeded** on 31 October 2026.

Not verified: live status moves from the server, Tap to Pay on device, iPad, the UI suite. A consistency sweep (time and money formats, row truncation, dark mode, iPad, stale UI tests) is in progress.

**Processing, tester groups and What to Test are not verified.**
