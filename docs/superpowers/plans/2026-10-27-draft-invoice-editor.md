# Draft invoice editor implementation plan

## Goal

Add native editing for draft invoice line items in the Paper V97 visual language, preserving the canonical invoice API's authority, provenance, and revision behavior.

## Scope

- Enable a draft editor only when `invoice.edit` and the `invoicing` feature are available.
- Edit, add, remove, and reorder supported invoice lines; select current active Price Book revisions only when the `price_book` feature and `pricebook.view` are available.
- Preserve estimate and retained Price Book provenance exactly. Newly selected Price Book lines submit only item ID and revision for server resolution.
- Submit `expectedLinesRevision`, adopt the returned invoice/revision, and never retry a stale 409 against an old revision.
- Do not fabricate tax/total, due date, payment terms, or customer/job display data absent from the current invoice contract. Keep the server-supported Issue invoice action accurately labeled.

## Steps

- [x] Add failing tests for invoice line payload encoding (manual, direct Price Book selection, retained snapshot, estimate source), line reordering, editor validation, and revision-aware save/issue. Include a 409 stale conflict test.
- [x] Add lossless Codable source snapshots and dedicated invoice-line request types without changing estimate request payloads.
- [x] Implement a pure editor draft model with bounds aligned to the server schema, exact cents parsing, source preservation, and override-reason handling.
- [x] Add a Paper-aligned native editor with editable line rows and an entitled Price Book picker, including stale-revision recovery.
- [x] Connect the detail view to the editor under the `invoice.edit` gate; keep issue under its independent `invoice.issue` gate and pass the latest server revision.
- [x] Run the full simulator suite and Release device compile; inspect the rendered read-only Paper preview.

The Save draft action is disabled and guarded when the editor has no changes, preventing unnecessary line replacement and revision churn. Reordering uses accessible move-up and move-down controls, and unsupported line provenance locks all editing controls.

## Verification evidence

- 147 simulator tests passed with no failures on iPhone 17 Pro. Result bundle: `/Users/byronwade/Library/Developer/Xcode/DerivedData/Thorbis-dmuwxdzkujtkngcfxjqjbnvsarbv/Logs/Test/Test-Thorbis-2026.10.27_01-28-11--0400.xcresult`.
- Release device build passed with `xcodebuild build -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`.
- Read-only design preview screenshot: `/private/tmp/thorbis-invoice-editor-reordered.png`.

## Acceptance

- Every save and issue uses the exact latest server revision.
- Price Book authority and estimate evidence are not invented or dropped.
- Invalid lines cannot be submitted from the editor; server remains the final authority for discount and invoice rules.
- A 409 preserves the user's draft and offers a fresh server reload/review path.
- Unsupported Paper mock fields are not shown as editable or presented as persisted.
