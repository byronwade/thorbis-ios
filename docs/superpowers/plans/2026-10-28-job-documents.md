# Job Documents Implementation Plan

> Use superpowers:executing-plans inline, TDD and one fresh released-batch review.

**Goal:** Show every verified commercial document belonging to the current job.
**Architecture:** Extract scoped GET-result loading/selection from the existing
job view; reuse financial detail/presentation flows and their mutation authority.
**Tech Stack:** SwiftUI, current FieldAPI, native customer mode.
**Spec:** docs/superpowers/specs/2026-10-28-job-documents-design.md

## Global Constraints

Stage A only; catalog/customer add-on quote work remains next. Preserve all current
features, permissions, revision/provenance, signature and payment reconciliation.
No live billing mutations in verification. Never infer job membership by customer.
Keep TechJobFlow intact. Use explicit /private/tmp/thorbis-ios-payment-ux paths.

## Review Focus

- Same customer on two jobs must never merge their documents or actions.
- Partial failures retain good rows but never report completeness or offer duplicate creation.
- Authoritative empty results cannot resurrect cached records.
- Old-session fallback/detail responses cannot publish or update memory.
- Customer selection signs/pays the exact fresh saved document, never a draft local sum.

### Task 1: Scoped, recoverable document reads

**Files:** new JobCommercialDocuments.swift, JobCommercialDocumentsTests.swift;
PaperJobDetailView.swift loadJobEstimates/loadInvoices/updateInvoice/selection.

**Interfaces:** JobDocumentScope(jobID:organizationID:customerID:originEstimateID:).
JobDocumentRead<Record> exposes scope, records, freshIDs and isComplete, with a
human-readable issue on incomplete reads. JobDocumentsLoader.estimates(scope:api:
retaining:isCurrent:) and invoices(scope:api:knownIDs:retaining:isCurrent:) are
MainActor async and return nil if authority changed. Selection policy prioritizes
an explicit actionable invoice, then issued balance, draft, other records.

- [x] Write API-fixture tests for multiple links, duplicate/foreign links, one detail
  failure, retained same-scope rows, foreign/nil-job invoices, wrong tenant/customer,
  authoritative empty vs404/405 compatibility, all pages and authority switch.
  Run focused tests; Expected: RED on missing helper/behavior.
- [x] Implement scoped result loading and pure selection, keeping fresh IDs separate
  from retained rows. Validate requested detail identity. No writes in the loader.
- [x] Integrate into the job view. Reset snapshots on session generation; publish
  and remember IDs only while current. Preserve successful rows on partial failure;
  show retry and block misleading empty/create/next-step states. Keep money logic.
- [x] Run focused helper/API/TechJobFlow tests; Expected: all pass. Commit.

### Task 2: All-document navigation and customer handoff

**Files:** PaperJobDetailView.swift, new JobDocumentRows.swift and
JobCustomerDocumentsView.swift; JobBrief.swift JobMenu actions; native tests.

**Interfaces:** rows consume scoped snapshots; customer hub receives exact job
scope and document references, refreshes before presenting, uses
CustomerModeContainer and existing CustomerEstimatePresentation/
CustomerInvoicePresentation. Draft/declined/void papers are read-only. Customer
payment requests retain exact invoiceID and require staff hand-back before opening
existing collection. Old contact self-edit is retained as Customer details.

- [x] Add meaningful regression tests/DEBUG read-only fixtures with multiple papers
  on A and B for the same customer, a newer paid deposit and older unpaid invoice,
  and partial estimates. Expected: existing one-document UI fails new checks.
- [x] Replace hidden invoice selector with visible document cards and existing
  detail routes. Keep estimate creation and draft review available. Include retry
  and stale states, exact reference/status/amount, no combined alternative totals.
- [x] Route Show to customer to the job's commercial hub; retain contact editing.
  Reuse lifecycle-safe presenters and owner hand-back, no automatic draft issue.
- [x] Verify every intended A row and no B row, selected detail identity, customer
  document browsing/hand-back, large text/dark mode and invoice collection route.
  Expected: native checks pass without real writes. Commit.

### Task 3: Review and frequent beta delivery

**Files:** ReleaseNotes.swift, release/evidence/execution notes.

- [x] Add What's new. Run full scheme once after final source changes. Expected:
  zero failures/skips. Investigate failures; never hide them with automatic retries.
- [x] Fresh most-capable review of this batch. Fix blockers RED→GREEN and full suite;
  ledger minors/rulings. Preserve contracts and current released features.
- [x] Archive/audit/upload next unused build, verify Apple processing/Internal
  Testers and save testing notes. Record evidence, push and attach a draft PR.
- [ ] Continue technician catalog/cart and explicit customer quote work under
  BYR-1580; do not mark that umbrella complete after Stage A alone.
