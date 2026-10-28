# Technician price book search and continuous-add design

**Status:** design ready for planned implementation  
**Repository baseline:** `21106d0` (app source verified at `5f48e17`) in `/private/tmp/thorbis-ios-payment-ux`; existing Stage A job-document changes are unrelated and must be preserved.

## Goal

Give technicians one consistent, full-catalog search and add flow while preparing estimates, estimate revisions, and draft invoices. Search uses the active organization’s cached and refreshed `PriceBookCatalog`, its ranked local `PriceBookSearchIndex`, recent items, and kind filters. Selecting a result adds it immediately to the currently selected draft target and leaves search open so the technician can keep adding items. Do not insert a required cart review or “Add N” confirmation step: estimate screens already add on tap, and the invoice picker should match that interaction.

The result list may show how many copies are already in the current draft, but that count is informational. It must not turn a tap into a quantity increment unless the existing estimate editor’s safe merge rule applies.

## Current behavior and intended change

- `NewEstimateView` and `EstimateRevisionEditorView` already use `PriceBookCatalog.shared`, `EstimateSearchBar`, and `PriceBookResultsList`. Taps add directly, search remains available, and estimate lines support grouping, custom entries, edits, whole-option packages, reorder, deletion, and undo.
- `PaperPriceBookPicker` in `InvoiceLineEditorView.swift` independently pages 50 items, filters only loaded descriptions/kind/unit, offers a “Load more items” row, and dismisses on the first selection. Replace that catalog browsing path with the shared catalog-backed ranked results while retaining the picker’s currency/customer context and the invoice editor’s existing manual line entry action.
- After a successful invoice selection, keep the picker open, preserve the query and kind, and reflect the new draft count. On a validation or selection failure, leave it open and surface the error. Record recent use only after the line is successfully added.
- Continue using immediate local draft mutation. Nothing is sent until the existing estimate/invoice save action is used.

## State and commercial invariants

1. **Organization and request generation.** Catalog results belong to the active organization and current session generation. Extend `PriceBookCatalog.refresh` to accept the existing `session.generation` UUID and guard publication/loading ownership by `(organizationID, sessionGeneration)`. A response from an earlier organization or session generation must not replace current results, even if the organization ID is the same. Keep the cache keyed by organization ID, plus existing pagination, deduplication, error, and retry behavior. Never show one organization’s cached entries as another organization’s results.
2. **Catalog provenance.** An added line captures the selected catalog item ID, server revision, description/price baseline and the existing source/provenance fields. The selected server revision remains attached to the line; search does not synthesize new catalog revisions or commercial fields.
3. **Estimate merge behavior.** Preserve `EstimateRevisionLineDraft.addPriceBookItem(_:to:)`: an unchanged entry with the same item, revision, description, and price may merge by incrementing quantity. If the prior line was edited or catalog values/revision differ, add a distinct line. Preserve the 500-line limit and existing quantity validation.
4. **Invoice behavior.** `InvoiceLineEditorState.addPriceBookItem(_:)` continues to append a new quantity-one line with the selected item’s revision and baseline. Do not merge invoice taps or change line identity semantics. Preserve current 500-line, currency, active-item, revision, amount, and quantity validation. Member price is informational display only; invoice selection continues to use the catalog sell price.
5. **Target boundaries.** Add only to the current estimate/editor target. `EstimateBuilderTarget.optionID` and `.group` remain authoritative. Whole-option packages and their lines remain separate; do not combine a base estimate or one option’s selection state with another option. Customer-facing add-on choices are a distinct later server-contract stage.
6. **Pending edits and save guards.** Keep estimate and invoice edits local until the user saves. Preserve invoice `expectedLinesRevision` and stale-revision handling in `makeRequest()`/`replaceFieldInvoiceLines`; do not auto-save, issue, or send from a catalog tap. Preserve the existing draft-only invoice edit gate.
7. **Custom lines and existing editor tools.** Retain custom estimate lines, custom invoice line creation, line editing, grouping, reorder, duplicate, remove/undo, and reset-to-price-book controls. The invoice price-book picker itself does not create typed custom entries; the existing “Add line item” flow remains the entry point for those.
8. **Limits and eligibility.** Respect catalog currency/active status, capability and feature gates, current editor target, and all existing 500-line/quantity/revision boundaries. Do not bypass server validation or silently trim pending edits.

## Shared results-list interface

Refactor `PriceBookResultsList` so the result presentation can serve both estimate and invoice drafts without knowing either editor’s data model. Keep `PriceBookCatalog` as the shared source and `PriceBookSearchIndex` as the search implementation. Provide closures for the current draft’s item count, optional secondary price text, selection, optional typed custom-line action, and retry. Estimate callers keep their existing custom-line behavior; invoice caller passes no custom-line action and may supply member-price text. The exact proposed interface is recorded in the implementation plan and may be adjusted locally if Swift type inference or view composition makes a small equivalent signature clearer.

The list must preserve current result ordering, result cap, recents, kind filters, search normalization/ranking, and error/empty states. Accessibility labels and hints should describe adding one catalog item to the current draft, not promise a cart commit or imply that tapping changes quantity in every editor.

## Out of scope

- Customer-selectable estimate add-ons, option acceptance, customer-facing catalog browsing, or any new server contract for offered choices.
- Catalog photos, image URLs, attachments, or a media contract.
- New API endpoints, database fields, fabricated provenance, catalog schema, price substitution, or payment/Tap to Pay work.
- Persistent carts, a mandatory multi-select/commit stage, background saving, invoice issuance, or changes to refund/retry behavior.
- Broad redesign of the Paper layouts or unrelated Stage A job-document code.

## Verification outcomes

The implementation is complete when tests establish all of the following: catalog search loads and deduplicates every available page; stale organization or session-generation work cannot replace current results; estimate same-item taps retain their current safe merge-versus-separate behavior; invoice same-item taps remain separate quantity-one lines and preserve revision/provenance; invoice search stays open for a second successful add and continues to display a full-catalog search result beyond the first server page; and existing save revision guards and editor operations remain intact. Tests should be written RED before the corresponding implementation and then run GREEN. Do not test customer add-ons or photos in this stage because their server contracts are not defined here.
