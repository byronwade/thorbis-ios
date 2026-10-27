# Native beta coverage — 27 October 2026

This is an initial staff beta, not full Thorbis-TanStack parity. The source reference is commit 448c238a11245d525d42cc542ce5fe9a512415ff. Native changes started at 811faf60fdcc929618292341c5081e84d65421db.

## Implemented native surfaces

- Better Auth sign-in, restore, workspace selection, capability/feature hydration, expiry and sign-out; all workspace state is invalidated when authority changes.
- Schedule and assigned-job filters; a local-day My Day list sorted by scheduled time with server-gated “On my way” and optional ETA; jobs, create job, notes, manual arrival/progress, pause/resume, scheduling and assignment, closeout requirements and office follow-ups.
- Customer search, details and creation, plus Paper-style contact create/edit, primary promotion, and confirmed removal with role, phone, and optional email. Service locations support create/edit/remove, address and notes, service/billing type, map pins, and access/parking details.
- Estimates: list, detail, create draft and revision-bound send/approve/decline. Invoices: list/detail, draft line editing, gated Price Book selection, reasoned Price Book overrides, revision-safe save/issue, and protected native PDF previews.
- Job media: selected photos/PDFs up to 8 MiB, signed upload/confirmation and protected download/preview.
- Staff notices, revenue report with incomplete-total disclosure, and paginated Price Book with separately gated detail.
- Device-local fleet, equipment, agreements and team records. Inbox drafts and queued items remain session-local and never imply delivery.
- Jobs opens on My Day to match the first Paper destination. The audited app-authored controls on My Day, scheduling, job detail, invoice editing, customer actions/sheets, workspace navigation, and Price Book now use 44 pt minimum hit frames; the visible Paper icon shapes stay compact. See [native UI evidence](../design/native-ui-evidence-2026-10-27.md).

## Outstanding parity

- Estimate editing/options/signatures; payment collection UI, reconciliation, refund/receipt workflows and hosted checkout. Invoice terms, due dates, tax totals, and customer delivery remain unavailable in the current invoice API.
- Remaining reports, exports, settings/admin, workflow and broader dispatch features.
- Canonical offline replication and command replay. Production readiness currently reports PowerSync not configured; a client cache is not a substitute.
- Separate Network/member and token-scoped customer flows. Their identities and contracts were discovered; they are not implemented in this staff binary. Portal and Brain packages contain scaffolds rather than completed upstream functionality.
- Camera capture, large multipart media, richer accessibility and authenticated device workflow testing.

## Validation evidence

- Swift 6 language mode with complete strict concurrency.
- 147 unit/contract tests passed with no failures in the iPhone 17 Pro simulator, including invoice revision handling, stale conflict recovery, line reordering, Price Book snapshot/source preservation, and editor validation. Latest result bundle: `/Users/byronwade/Library/Developer/Xcode/DerivedData/Thorbis-dmuwxdzkujtkngcfxjqjbnvsarbv/Logs/Test/Test-Thorbis-2026.10.27_01-49-14--0400.xcresult` (27 October 2026).
- My Day and Customer detail were visually checked in read-only Paper previews on iPhone. The location and contact editors, contact action menu, and remove confirmation were checked with sample data. Preview evidence verifies presentation/error handling only, not authenticated live workflow behavior.
- 18 Release transport tests passed, including rejection of development identity in Release.
- Release iOS device compile passed after the invoice editor change. Read-only editor preview was visually checked on iPhone 17 Pro at `/private/tmp/thorbis-invoice-editor-reordered.png`; it uses sample data and does not validate live invoice writes.
- The iOS Release build compiles after the My Day/hit-target pass. My Day and invoice previews were rechecked on iPhone 17 Pro; the adaptive schedule was checked on a 13-inch iPad simulator in landscape. Screenshots and untested native-rule areas are recorded in `docs/design/native-ui-evidence-2026-10-27.md`.
- Signed device archive and signature verification succeeded for Builds 6–9 (`1.0 (6)` through `1.0 (9)`). Build 7 introduced customer contact management; Build 8 introduced the canonical Thorbis shield app icon; Build 9 adds draft invoice line editing. Build 9 uploaded successfully and Apple reports that it is processing. App Store Connect is signed out, so the tester group assignment and invitation remain unverified. See `build-9.md` for current release evidence.
- iPhone and iPad native login screens launched and were visually inspected. Browser sign-in is confirmed; native authenticated end-to-end checks still await a separate app sign-in.
- Independent review found and drove fixes for logout overlap, central 401 invalidation, late preview cleanup, draft lifetime and roster truncation. Tests cover the corresponding transport/state behavior.

Do not describe an upload or a processed TestFlight build as proof of complete feature parity or live end-to-end validation.
