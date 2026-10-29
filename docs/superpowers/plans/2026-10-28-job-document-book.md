# Customer job document book Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Present every job estimate and invoice together with swipe navigation and clear discounts/payment history, then deliver a verified TestFlight update.

**Architecture:** Reuse scoped JobDocumentCollections and existing protected customer decision flows. Pure checked amount projection supports invoice display and collection. The read-only book uses stable kind/ID selection; financial actions remain in existing canonical flows.

**Tech Stack:** Swift6, SwiftUI, XCTest/XCUITest, existing URLSession HTTP API; no new dependencies.

**Spec:** docs/superpowers/specs/2026-10-28-job-document-book-design.md

**App-wide context:** Apply docs/design/ios-golden-rules.md and
docs/design/ios-implementation-process.md throughout this in-progress plan,
including its offline/state, accessibility, native navigation and release gates.
All original customer document and feature-retention requirements remain required.

## Global Constraints

- Exact current job/tenant/customer/location only; no organization-wide paper leaks.
- Paper/Theme/CustomerType,17pt minimum,20/22pt body,34/40pt totals,56pt targets.
- Gestures are optional; Previous/Next and overview stay reachable.
- No live financial action, provider change or backend exposure; Tap to Pay gate retained.
- Preserve C0 immutable review, signature, decline, authenticated hand-back and collection.
- Incomplete history is explicit; integer minor units and matching record identities only.
- C1-C3 add-on work remains required; no reduced completion claim.

## Review Focus

- Refund/net evidence cannot make a payment count twice or hide a refund: Task1 history tests.
- Same customer on a different job cannot enter book/history: Task1 scope and Task2 native exclusion tests.
- Selection changes/removed pages must not reuse terms, consent or payment target: Task2 stable-identity tests.
- Huge text, small phone and iPad must retain all controls without gesture-only navigation: Task2 native journeys.
- Workspace/cancellation or failed reads cannot publish former history as fresh: Task1 guarded transport tests.

### Task 1: Exact amounts and safe payment history

**Files:** Create Thorbis/Sources/CustomerDocumentAmounts.swift; modify InvoicePaymentCollection.swift; test ThorbisTests/CustomerDocumentAmountsTests.swift and InvoicePaymentCollectionTests.swift.

**Interfaces:** CustomerDocumentAmounts.init?(lines:[FieldLine],currency:String,amountPaid:Int=0), subtotal/credits/total/paid/due:Int. InvoicePaymentCollectionModel.totalCents/outstandingCents reuse this projection; load validates full history against verified invoice and API generation before publishing.

- [x] Write tests for25000charges-2500credits=22500total,10000paid=12500due; overflow/mixed currency/negative totals refuse. Discounted issued invoice permits valid collection; foreign/duplicate/malformed payment histories refuse without publication or collection; session/cancellation refuses late results.
- [x] Run focused test RED (compile absence then behavioral failing stubs where necessary); inspect counts/output.
- [x] Implement checked display projection and guarded history load; no vendor calls or new money rules.
- [x] Run focused unit tests and full relevant payment suites; expected zero failures/skips.
- [x] Commit locally with evidence.

### Task 2: Browse all job documents

**Files:** Create CustomerJobDocumentBook.swift; modify JobCustomerDocumentsView.swift, CustomerPresentation.swift, PaperPreview.swift, ReleaseNotes.swift; add CustomerJobDocumentBookTests.swift and extend JobDocumentsUITests.swift.

**Interfaces:** Stable CustomerJobDocumentID(kind,id) and ordered selection with previous/next; book consumes exact-scope reads, payment history state and Task1 amount projection. Existing openEstimate/openInvoice and authentication own actions. Read-only pages never mint/sign/pay automatically.

- [x] Write model/native RED for two estimates/two invoices, swipe/button navigation, overview jump, foreign exclusion, removed selection and stale refusal; show original credit descriptions, labelled savings/paid/due and dated refunds; preserve canonical approval and selected-invoice handoff.
- [x] Implement book using native paging and explicit buttons, narrow state and lazy child pages; keep decisions outside swipe surface. Reuse CustomerLinesCard and price rows; history in a disclosure, no internal data.
- [x] Extend read-only preview fixtures with actual multiple documents, a discount and recorded/refunded payments; no requests escape fixture.
- [x] Run model/native journeys, largest text/dark/iPad visual checks, important affected suites and release notes tests; expected zero failures/skips.
- [ ] Commit and record screenshots/fingerprints.

### Task 3: Review and TestFlight delivery

**Files:** execution evidence, release notes as needed; existing archive/export workflow.

- [x] Fresh whole-branch review; fix Important/Critical in one RED/GREEN pass and affected suites, record rulings/minors.
- [ ] Verify source fingerprints and release boundaries; create signed archive with unique next build after ASC preflight.
- [ ] Upload, then verify processing, notes saved and existing tester group assignment. Attach new draft PR; no duplicate tester invites.
- [ ] Report exact available build and any unfinished larger app work. Do not mark full persistent goal complete.
