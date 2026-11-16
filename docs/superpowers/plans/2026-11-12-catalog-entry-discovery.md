# Make catalog entry easier to reach

## Finding and scope

Technicians asked to build estimates and invoices like a simple catalog/cart, with fewer steps. The current invoice editor puts its only Add item control after every line in `InvoiceLineEditorView.content`; the estimate builder does the same inside each `EstimateLineGroupSection` in `EstimateBuilder.swift`. A long document forces a technician to pass all existing lines to add a part. Existing controls already open the shared `PriceBookCartPicker` and preserve the context of the invoice or estimate section. This proposal makes those supported controls easier to reach; it does not add editable issued estimates or a new draft-save path.

## Design

Add a 44-point “Add item” action in the heading of each editable invoice or estimate section. Keep the existing bottom action for someone already working at the end of a long list. Both actions invoke the same existing closure and disabled/limit logic; the estimate action retains its section/option destination, and the invoice action retains its currency, catalog permission, provenance, and current draft revision checks. At accessibility sizes, stack the header action below the heading/menu rather than squeezing labels or the overflow control. Reuse existing typography, tokens and controls; do not introduce a second save, new customer-facing controls, or a new financial mutation.

The two entry points are intentional: one is available immediately when entering a long section, and one remains where a technician finishes reviewing lines. Short sections retain the current bottom-only action if a second action would add unnecessary repetition; use a clearly defined threshold and verify the action never disappears when no alternate remains reachable.

## Verification before integration

- Baseline: mount a preview invoice with many representative line items and show the heading-level action is missing. Add a similar multiple-option estimate fixture if existing preview cannot cover it.
- After implementation, mount a long invoice and a multi-section estimate. From the initial view, open the catalog from the heading without scrolling through all rows; add an item, return, and verify it lands in the exact intended invoice/option and the existing line editor opens as before. Verify the bottom action remains usable when it is shown.
- Verify 500-line limits, unsupported provenance, busy/permission/currency behavior, stale authority and context changes still block or close the picker exactly as before. Verify custom-item fallback and signed/issued invoice safeguards remain unchanged.
- Exercise the heading actions at largest Dynamic Type and verify labels are whole, separate from overflow, and at least 44 points. Check keyboard and save/discard controls remain reachable. Verify accessibility labels distinguish estimate section or option; a simulator accessibility tree is not a real-device VoiceOver pass.
- Run existing focused catalog/invoice editor and estimate builder regressions, plus the new mounted tests. Independently review the final diff for wrong-destination, draft-loss and permission regressions. Measure large-list performance separately before making any speed claim; this entry-point change does not implement server pagination.

## Dependencies and release boundaries

The estimate default-editable experience remains blocked on a canonical, durable draft-save contract and recovery for held features/policy changes. Do not infer it from this navigation improvement. Do not alter or remove existing features, customer presentation, provider behavior, saved-draft rules or invoice revision checks. Release only after focused checks and ordinary signed build qualification; no build was made as part of this planning step.
