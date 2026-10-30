# Technician catalog search

Stage B of BYR-1580 brings the shared full Price Book search into draft invoices
while preserving estimate custom lines, grouping, pricing and editing. The source
range is 21106d0..0717f2c. Draft PR #76 is stacked on Stage A's #75.

Invoice selection remains immediate: every tap appends a separate quantity-one
line with catalog sell price, revision and provenance. The query and picker stay
open, quantities reflect the current draft, and Done returns to review before Save.
An explicit draft binding and a dedicated row view expose selection dependencies.
The bounded result list uses VStack after the native regression demonstrated a
stale badge under LazyVStack despite the mounted row receiving the changed value.
No identity-reset workaround or temporary diagnostic logging remains.

The shared loader reads every page, deduplicates IDs, coalesces same-context work
and retains a complete cache. Pagination is capped at 50 pages of 200. Reaching the
cap reports an error with retry instead of publishing a partial catalog. Cached
rows from a mismatched organization/session are hidden and unselectable.

## Review and verification

One fresh whole-branch review found one Important cancellation issue and two
Minor issues. Active-filter visibility and inaccurate spoken instructions were
regraded Important for their user impact. All three were accepted into one fix
pass, with failing regressions before fixes. The loader now owns its shared task;
closing the initial caller no longer strands another same-scope consumer. The
invoice picker keeps selected filters visible when idle, and the search field
announces the actual prompt.

A further lifecycle check identified the shared cookie-backed API's generation
handoff boundary. A deterministic regression first failed, then passed after the
loader captured API.requestGeneration at refresh entry and checked it before and
after each page. API.swift and SessionController were unchanged. No second review
was dispatched.

Final frozen-source full scheme: 458/458 passed, zero failures/skips, completed
2026-10-28 at 19:00:07 EDT on iPhone 17 Pro / iOS 26.0. All 161 Swift fingerprints
match that run. Release Python checks passed 12/12. The original draft head
69519c7 also passed hosted Xcode 26.3 CI; hosted CI for final source 0717f2c was not
used as the release verification claim. Local xcresults, source hashes, detailed
RED/GREEN ledger and review are retained in the plan workspace.

Same-ID price/revision redraw coverage remains a deferred Minor follow-up;
existing revision validation remains active. Inherited live-role transitions may
require reopening the editor, with save guards preserving authorization. A brief
old-context count footer may remain while the rows themselves are hidden. Recents,
cross-revision informational counts and estimate merge/group rules are retained.
No new iPad/iOS 18 or eager-stack performance certification is claimed.

## Delivery and remaining work

Source 0717f2c was archived as 1.0 (74). Strict signing/team, app/widget version,
Release preview isolation and disabled-reader audits passed. Xcode upload succeeded
at 19:08:11 EDT. Apple completed processing; Internal Testers is assigned with two
testers and What to Test shows Saved. See [the release record](../../release/build-74.md).
The archive is retained at /private/tmp/thorbis-74.hHys9c/Thorbis.xcarchive.

The native preview rejects writes and its synthetic fixtures are DEBUG-only.
Tap to Pay qualification remains separate and disabled. Customer-selectable
offered add-ons still need the canonical server quote/acceptance contract. Bulk
demo data is prepared locally; workspace selection and governed import, roster
and catalog-photo owner interfaces remain pending. BYR-1580 remains In Progress.

The native evidence image shows the invoice editor after catalog additions, with
the first new line partly visible below the original lines. Assertions, rather
than that single screenshot, establish both separate quantity-one additions.
