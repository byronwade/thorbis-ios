# Native beta coverage — 26 October 2026

This is an initial staff beta, not full Thorbis-TanStack parity. The source reference is commit 448c238a11245d525d42cc542ce5fe9a512415ff. Native changes started at 811faf60fdcc929618292341c5081e84d65421db.

## Implemented native surfaces

- Better Auth sign-in, restore, workspace selection, capability/feature hydration, expiry and sign-out; all workspace state is invalidated when authority changes.
- Schedule and assigned-job filters; jobs, create job, notes, manual arrival/progress, pause/resume, scheduling and assignment, closeout requirements and office follow-ups.
- Customer search, details, creation, contacts and service locations.
- Estimates: list, detail, create draft and revision-bound send/approve/decline. Invoices: list, detail and issue. Protected native PDF previews.
- Job media: selected photos/PDFs up to 8 MiB, signed upload/confirmation and protected download/preview.
- Staff notices, revenue report with incomplete-total disclosure, and paginated Price Book with separately gated detail.
- Device-local fleet, equipment, agreements and team records. Inbox drafts and queued items remain session-local and never imply delivery.

## Outstanding parity

- Full estimate/invoice editing, payment collection UI, reconciliation, refund/receipt workflows and hosted checkout.
- Remaining reports, exports, settings/admin, workflow and broader dispatch features.
- Canonical offline replication and command replay. Production readiness currently reports PowerSync not configured; a client cache is not a substitute.
- Separate Network/member and token-scoped customer flows. Their identities and contracts were discovered; they are not implemented in this staff binary. Portal and Brain packages contain scaffolds rather than completed upstream functionality.
- Camera capture, large multipart media, richer accessibility and authenticated device workflow testing.

## Validation evidence

- Swift 6 language mode with complete strict concurrency.
- 98 unit/contract tests passed in the iPad simulator, including continued roster pagination beyond four reach-filtered empty pages. Result bundle: `/private/tmp/thorbis-all-tests-5.xcresult`.
- 18 Release transport tests passed, including rejection of development identity in Release.
- Signed device archive and signature verification succeeded for an earlier core snapshot. The final upload must use a new archive containing the latest changes.
- iPhone and iPad native login screens launched and were visually inspected. Browser sign-in is confirmed; native authenticated end-to-end checks still await a separate app sign-in.
- Independent review found and drove fixes for logout overlap, central 401 invalidation, late preview cleanup, draft lifetime and roster truncation. Tests cover the corresponding transport/state behavior.

Do not describe an upload or a processed TestFlight build as proof of complete feature parity or live end-to-end validation.
