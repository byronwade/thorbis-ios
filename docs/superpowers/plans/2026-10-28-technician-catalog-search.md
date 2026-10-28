# Technician Catalog Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Let technicians search the active organization’s full Price Book and add items continuously to estimate, revision, and draft invoice editors without a mandatory cart commit.

**Architecture:** Reuse `PriceBookCatalog.shared` and `PriceBookSearchIndex` for all three editors. Generalize `PriceBookResultsList` with current-draft quantity, optional secondary-price text, and an optional custom-line action; replace `PaperPriceBookPicker`’s independent 50-item browsing with that shared list. Result taps continue to mutate only the current in-memory draft; preserve invoice line-per-tap behavior and estimate safe merge behavior.

**Tech Stack:** SwiftUI, Swift concurrency, XCTest, existing `URLProtocolFixture`, existing PaperPreview/XCUITest harness.

**Spec:** `docs/superpowers/specs/2026-10-28-technician-catalog-search-design.md`

## Global Constraints

- `PriceBookCatalog.refresh(api:organizationID:sessionGeneration:force:)` remains the only catalog load path and stays scoped to the active organization and the current `session.generation` UUID.
- Search uses existing `PriceBookSearchIndex.search(_:kind:usage:now:)`, ranked results, recent items, kind filters, and the 50-result display cap.
- Keep immediate add on tap; do not require cart review or an “Add N” action.
- Estimate lines merge only when item ID, revision, description, and price still match; edited or changed-revision entries remain separate.
- Invoice taps append separate quantity-one lines with item ID, server revision, source, and baseline; do not merge them.
- Preserve existing 500-line, quantity, currency, active-item, revision, and amount validation.
- Keep member price display-only; the invoice line uses catalog sell price.
- Keep estimate custom lines, edit/group/reorder/duplicate/remove/undo/reset actions and separate whole-option package targets.
- Keep invoice manual line entry separate, edits pending until save, and `expectedLinesRevision` conflict protection.
- Add no customer add-on, photo, image URL, backend, payment, or new provenance contract.
- Preserve unrelated Stage A changes in `/private/tmp/thorbis-ios-payment-ux`; specifically retain existing changes in `PaperPreview.swift` while adding only the preview fixture needed by Task 2.

## Review Focus

1. A query matching an item after the first server page must find and add it — pin with `PriceBookPickerUITests.testInvoicePickerSearchesLaterPageAndStaysOpenForMultipleAdds` in Task 2.
2. A delayed response for a prior organization or session generation must not replace current results — pin with `PriceBookCatalogTests.testLatePriorOrganizationRefreshCannotReplaceCurrentCatalog` and `testLatePriorGenerationRefreshCannotReplaceCurrentCatalogForSameOrganization` in Task 3.
3. Two taps on one invoice item must produce separate quantity-one lines with the same selected revision — pin with `InvoiceLineEditorTests.testRepeatedPriceBookSelectionKeepsSeparateLinesAndReportsQuantity` in Task 1.
4. A same-ID estimate line whose description, price, or revision was edited must remain separate from a new catalog add — retain `EstimateBuilderTests.testAnEditedLineIsNotBumpedAndCanResetToThePriceBook` and `EstimateBuilderTests.testSecondTapAddsOneMoreInsteadOfADuplicate` in Task 3.
5. Manual, estimate-sourced, unsupported, inactive, non-USD, invalid-revision, or over-limit invoice entries must not be counted or accepted as a catalog selection — pin count provenance in the Task 1 test and retain `InvoiceLineEditorTests.testEditorAddsOnlyActivePriceBookItemWithServerRevision`, `testEditorRejectsEmptyLinesInvalidQuantityAndMoreThanTwoDecimalPlaces`, and `testEditorRefusesUnknownLineProvenanceInsteadOfDroppingIt` in Task 3.

---

## File Structure

- Modify `Thorbis/Sources/PriceBookSearch.swift`: include session generation in catalog refresh identity and reject stale responses.
- Modify `Thorbis/Sources/InvoiceLineEditorState.swift`: add a read-only current-draft catalog quantity lookup for shared result badges.
- Modify `Thorbis/Sources/EstimateBuilder.swift`: make `PriceBookResultsList` work with estimate or invoice draft closures and optional secondary price/custom-line actions.
- Modify `Thorbis/Sources/NewEstimateView.swift` and `Thorbis/Sources/EstimateRevisionEditorView.swift`: adapt call sites without changing their target, add, or save behavior.
- Modify `Thorbis/Sources/InvoiceLineEditorView.swift`: adapt `PaperPriceBookPicker` to shared results, organization/session-generation refresh, and stay-open selection.
- Modify `Thorbis/Sources/PaperPreview.swift`: add an opt-in, schema-valid 2-page catalog fixture to exercise search past the first 50 results; retain all unrelated current Stage A edits.
- Create `ThorbisTests/PriceBookCatalogTests.swift`: verify all-page hydration and stale organization/session-generation isolation with `URLProtocolFixture`.
- Modify `ThorbisTests/InvoiceLineEditorTests.swift`: test separate invoice additions and count lookup.
- Create `ThorbisUITests/PriceBookPickerUITests.swift`: verify full-catalog search and continuous-add behavior in the existing invoice-editor preview.

## Task 1: Expose invoice draft quantity for shared result rows

**Files:**
- Modify: `Thorbis/Sources/InvoiceLineEditorState.swift`
- Test: `ThorbisTests/InvoiceLineEditorTests.swift`

**Interfaces:**
- Consumes: `InvoiceLineDraft.source: FieldInvoiceLineSourceInput?`, `InvoiceLineDraft.quantity: String`, `FieldInvoiceLineSourceInput.priceBookSelection(itemID:revision:)`, and `.retainedPriceBook(FieldLineSource)`.
- Produces: `func quantity(ofPriceBookItem itemID: String) -> Int?` on `InvoiceLineEditorState`. Return `nil` when no matching retained or newly selected Price Book line has a valid positive integer quantity; otherwise return the sum across matching Price Book lines. Ignore manual, estimate, unsupported, and other-item provenance. Do not mutate drafts or normalize text.

- [x] **Step 1: Write a failing state test**

Add `testRepeatedPriceBookSelectionKeepsSeparateLinesAndReportsQuantity` using existing invoice/item fixtures. Add the same valid item twice through `addPriceBookItem(_:)`; assert two distinct lines remain, each quantity is `"1"`, both sources retain the selected item ID and revision, and `quantity(ofPriceBookItem:)` is `2`. Include a manual or estimate-sourced same-description line and assert it does not increase that item’s count. Add a retained Price Book line with the matching item ID and valid quantity to prove retained provenance is counted; invalid/non-positive quantity text must not contribute.

- [x] **Step 2: Run the test and confirm the intended RED**

Run: `xcodebuild test -project Thorbis.xcodeproj -scheme Thorbis -destination 'platform=iOS Simulator,id=FA43B63E-98C9-4336-B1F7-A55E9D4B4B0A' -derivedDataPath /private/tmp/thorbis-ios-payment-derived -clonedSourcePackagesDirPath /private/tmp/thorbis-spm -skipPackageUpdates -jobs 2 -parallel-testing-enabled NO -only-testing:ThorbisTests/InvoiceLineEditorTests/testRepeatedPriceBookSelectionKeepsSeparateLinesAndReportsQuantity`

Expected: compile/test failure because `quantity(ofPriceBookItem:)` does not exist yet. Existing add behavior assertions should match the current append-per-tap contract.

- [x] **Step 3: Implement `quantity(ofPriceBookItem:)` in `InvoiceLineEditorState.swift`**

Match only `.priceBookSelection` with the requested `itemID` and `.retainedPriceBook` whose `FieldLineSource.kind == "price_book"` and `priceBookItemId` matches. Parse the draft quantity as a positive `Int`; sum valid quantities with overflow-safe accumulation. Return `nil` if no valid matching quantity exists.

- [x] **Step 4: Run the state test GREEN**

Run the command from Step 2. Expected: PASS; two invoice additions remain separate and report total quantity two.

- [x] **Step 5: Commit the state contract**

```bash
git add Thorbis/Sources/InvoiceLineEditorState.swift ThorbisTests/InvoiceLineEditorTests.swift
git commit -m "feat: expose invoice price book draft quantity"
```

## Task 2: Share catalog search and keep invoice selection open

**Files:**
- Modify: `Thorbis/Sources/PriceBookSearch.swift`
- Modify: `Thorbis/Sources/EstimateBuilder.swift`
- Modify: `Thorbis/Sources/NewEstimateView.swift`
- Modify: `Thorbis/Sources/EstimateRevisionEditorView.swift`
- Modify: `Thorbis/Sources/InvoiceLineEditorView.swift`
- Modify: `Thorbis/Sources/PaperPreview.swift`
- Create: `ThorbisUITests/PriceBookPickerUITests.swift`

**Interfaces:**
- Consumes: Task 1 `InvoiceLineEditorState.quantity(ofPriceBookItem:)`; updated `PriceBookCatalog.refresh(api:organizationID:sessionGeneration:force:)`; existing `PriceBookResultsList.addItem` tap behavior; invoice selection validation `InvoiceLineEditorState.addPriceBookItem(_:) throws`.
- Produces: a shared list initializer with these semantic parameters: `catalog`, `query`, `kind`, `canUsePriceBook`, `quantityInCurrentDraft: (String) -> Int?`, `secondaryPriceText: (PriceBookListItem) -> String?`, `addItem: (PriceBookListItem) -> Void`, `addCustomLine: ((String) -> Void)?`, and `retry`. Preserve `PriceBookResultsList`’s existing `@ObservedObject` catalog and current search/filter inputs. Change `PaperPriceBookPicker`’s selection callback to `let onSelect: (PriceBookListItem) throws -> Void` so a failure is displayed in the picker and a success can leave it open.

- [x] **Step 1: Add a deterministic preview fixture and write the UI regression test**

In `PaperPreview.swift`’s `/v1/query` fixture, add a launch-argument-gated Price Book pagination mode for the `invoice-editor` preview. Return 50 first-page entries with the existing `price_book_items` field schema and a valid UUID cursor, followed by one uniquely named second-page sentinel item and `nextCursor: null`. Keep the fixture disabled for all other previews and preserve existing sample catalog contents/Stage A work.

Create `PriceBookPickerUITests.testInvoicePickerSearchesLaterPageAndStaysOpenForMultipleAdds`. Launch `--paper-preview --paper-preview-screen invoice-editor` with the new fixture flag. Open “Add from price book,” search for the second-page sentinel, assert the result is visible, select it, then assert the picker and query remain visible and its current-draft quantity updates to 1. Select it again and assert quantity 2 while the picker remains open. Close the picker and assert the editor contains two distinct quantity-one lines.

Add stable accessibility identifiers `price-book-search` and `price-book-item-<item ID>` where needed for reliable selection and assertions. Do not add saved server writes to this preview journey.

- [x] **Step 2: Run the new UI test and confirm the intended RED**

Run: `xcodebuild test -project Thorbis.xcodeproj -scheme Thorbis -destination 'platform=iOS Simulator,id=FA43B63E-98C9-4336-B1F7-A55E9D4B4B0A' -derivedDataPath /private/tmp/thorbis-ios-payment-derived -clonedSourcePackagesDirPath /private/tmp/thorbis-spm -skipPackageUpdates -jobs 2 -parallel-testing-enabled NO -only-testing:ThorbisUITests/PriceBookPickerUITests/testInvoicePickerSearchesLaterPageAndStaysOpenForMultipleAdds`

Expected: after the fixture is active, the existing picker cannot find the sentinel because it searches only its loaded first page. After adding full-catalog search, the same test must still fail at the assertion that the picker remains open, because current selection dismisses it.

- [x] **Step 3: Generalize `PriceBookResultsList`**

In `EstimateBuilder.swift`, replace the estimate-specific `quantityOnEstimate` input with `quantityInCurrentDraft: (String) -> Int?`. Add `secondaryPriceText: (PriceBookListItem) -> String?` and make `addCustomLine` optional. Preserve ranked result generation, recents, filters, error/retry/empty states and result count. Render optional secondary price text without changing the catalog sell price; update accessibility hints to say the tap adds one item to the current draft.

- [x] **Step 4: Adapt both estimate call sites without changing editor semantics**

In `NewEstimateView.swift` and `EstimateRevisionEditorView.swift`, pass their existing `quantity(ofPriceBookItem:)` closure and custom-line action to `addCustomLine`; provide no secondary price. Keep `EstimateBuilderTarget.optionID` and `.group` as the destination and leave `add(_:)`, whole-option state, save, reorder, undo, and custom-line behavior intact. In the same integration step, change `PriceBookCatalog.refresh` to `func refresh(api: APIClient, organizationID: String?, sessionGeneration: UUID, force: Bool = false) async`, update both estimate callers to pass `session.generation`, and track current/in-flight identity as `(organizationID, sessionGeneration)`. A session-generation change for the same organization must force a new request while retaining that organization’s cache; gate results, errors, and loading cleanup on both identity fields so an old request cannot publish or clear the new request’s state. Keep disk cache keyed only by organization ID.

- [x] **Step 5: Replace invoice-only pagination with the shared results list**

In `InvoiceLineEditorView.swift`, remove `PaperPriceBookPicker`’s independent `items`, `cursor`, `visibleItems`, `refresh()`, and `loadMore()` path. Bind it to `PriceBookCatalog.shared`; refresh with captured `session.activeOrganization?.id` and `session.generation` through `catalog.refresh(api:organizationID:sessionGeneration:force:)`. Key the view task by both values and, after awaits, guard `!Task.isCancelled`, the current organization ID, and the current session generation before applying view-local state. Keep the existing customer member-pricing task and pass its display value through `secondaryPriceText`; do not use it as the invoice line price.

Pass `editor.quantity(ofPriceBookItem:)` as the current-draft closure and `nil` for `addCustomLine`. Use a throwing selection closure that calls `editor.addPriceBookItem(_:)`; on success clear the local picker error and call `catalog.recordUse(item.id)`, and on failure show the message in the picker without dismissing it. Keep search, query, and kind selection intact after success. Retain the picker’s existing close control and the invoice editor’s separate “Add line item” action.

- [x] **Step 6: Run the UI regression test GREEN**

Run the command from Step 2. Expected: the sentinel from page two is searchable; two taps leave the picker open, show count two, and create two separate quantity-one invoice lines.

- [x] **Step 7: Commit the shared picker behavior**

```bash
git add Thorbis/Sources/EstimateBuilder.swift Thorbis/Sources/NewEstimateView.swift Thorbis/Sources/EstimateRevisionEditorView.swift Thorbis/Sources/InvoiceLineEditorView.swift Thorbis/Sources/PaperPreview.swift ThorbisUITests/PriceBookPickerUITests.swift
git commit -m "feat: share full catalog search across draft editors"
```

## Task 3: Pin catalog pagination, organization/session isolation, and existing editor contracts

**Files:**
- Create: `ThorbisTests/PriceBookCatalogTests.swift`
- Test: `ThorbisTests/PriceBookSearchTests.swift`
- Test: `ThorbisTests/EstimateBuilderTests.swift`
- Test: `ThorbisTests/InvoiceLineEditorTests.swift`

**Interfaces:**
- Consumes: `PriceBookCatalog.refresh(api:organizationID:sessionGeneration:force:)`, `PriceBookCatalog.items`, existing `URLProtocolFixture` request handler and `Gate`, and Task 1 quantity lookup.
- Produces: regression coverage for complete multi-page hydration, duplicate-ID handling, stale organization and same-organization/session-generation response rejection, and prior estimate/invoice commercial rules. Do not alter catalog API payload shape.

- [ ] **Step 1: Add `PriceBookCatalogTests.testRefreshLoadsAllPagesAndDeduplicatesIDs`**

Use a unique organization UUID and `URLProtocolFixture` to return two pages from `/v1/query`; overlap one item ID between pages and place a unique active USD item on page two. Force refresh and assert every distinct item is present once, including the later-page item. Use the fixture’s existing envelope and `price_book_items` field keys only. Clean only this test’s per-organization cache file.

- [ ] **Step 2: Add `PriceBookCatalogTests.testLatePriorOrganizationRefreshCannotReplaceCurrentCatalog`**

With one `PriceBookCatalog` and a gated response for organization A, start A’s forced refresh, start and complete organization B’s refresh, then release A. Assert the catalog remains scoped to B and contains B’s items, not A’s. Use unique organization IDs and clean only their cache files.

- [ ] **Step 3: Add `PriceBookCatalogTests.testLatePriorGenerationRefreshCannotReplaceCurrentCatalogForSameOrganization`**

With the same organization ID, start a gated refresh using generation A, then start and complete a refresh using generation B. Release A and assert the catalog still contains generation B’s data and the old task cannot clear B’s loading/error state. Use a unique organization UUID and clean only its per-organization cache file.

- [ ] **Step 4: Run the catalog tests as characterization checks**

Run: `xcodebuild test -project Thorbis.xcodeproj -scheme Thorbis -destination 'platform=iOS Simulator,id=FA43B63E-98C9-4336-B1F7-A55E9D4B4B0A' -derivedDataPath /private/tmp/thorbis-ios-payment-derived -clonedSourcePackagesDirPath /private/tmp/thorbis-spm -skipPackageUpdates -jobs 2 -parallel-testing-enabled NO -only-testing:ThorbisTests/PriceBookCatalogTests`

Expected: PASS. Pagination and organization checks pin existing guarantees; the same-organization/session-generation check confirms the Task 2 refresh identity. These are characterization checks, while Task 2’s UI journey is the behavior-changing RED/GREEN test.

- [ ] **Step 5: Run focused existing behavior suites**

Run: `xcodebuild test -project Thorbis.xcodeproj -scheme Thorbis -destination 'platform=iOS Simulator,id=FA43B63E-98C9-4336-B1F7-A55E9D4B4B0A' -derivedDataPath /private/tmp/thorbis-ios-payment-derived -clonedSourcePackagesDirPath /private/tmp/thorbis-spm -skipPackageUpdates -jobs 2 -parallel-testing-enabled NO -only-testing:ThorbisTests/PriceBookSearchTests -only-testing:ThorbisTests/EstimateBuilderTests -only-testing:ThorbisTests/InvoiceLineEditorTests`

Expected: PASS. Confirm exact same-item estimate merge/separate behavior, custom lines, grouping, reorder, delete/undo, valid catalog provenance, line limits, and invoice expected-revision request remain intact.

- [ ] **Step 6: Commit regression coverage**

```bash
git add ThorbisTests/PriceBookCatalogTests.swift
git commit -m "test: cover price book pagination and session scope"
```

## Task 4: Run the complete native regression set and review the diff

**Files:** no additional source files.

**Interfaces:** consumes all implementation and tests from Tasks 1–3.

- [ ] **Step 1: Run all unit and UI tests**

Run: `xcodebuild test -project Thorbis.xcodeproj -scheme Thorbis -destination 'platform=iOS Simulator,id=FA43B63E-98C9-4336-B1F7-A55E9D4B4B0A' -derivedDataPath /private/tmp/thorbis-ios-payment-derived -clonedSourcePackagesDirPath /private/tmp/thorbis-spm -skipPackageUpdates -jobs 2 -parallel-testing-enabled NO`

Expected: all existing and new test targets pass. If the target simulator is unavailable, use the project’s available iOS simulator destination and report the exact destination used; do not change app behavior to work around a local simulator issue.

- [ ] **Step 2: Review the focused diff**

Run: `git diff --check` and inspect the Task 1–3 file diff. Confirm no edit touches customer add-on contracts, catalog photo fields, payment/refund/retry flows, invoice issuance, or unrelated Stage A behavior. Confirm the preview fixture is opt-in and uses the existing Price Book envelope only.

- [ ] **Step 3: Request code review and stop before release actions**

Request an independent review of this Stage B diff. Do not build/archive for TestFlight, change signing, upload, or add testers as part of this plan; these are separate release actions.
