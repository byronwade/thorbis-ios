# Invoice Payment Collection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Paper-aligned invoice payment history and manual recording of already-collected payment methods to the native invoice detail.

**Architecture:** Reuse the existing `fieldPayments(_:)` and `recordFieldPayment(_:request:)` API methods. Add a small observable payment model to own history, recording retry state, and canonical invoice/payment refresh; keep the payment form in a SwiftUI sheet and keep invoice balance derived only from a refreshed `InvoiceRecord`.

**Tech Stack:** Swift 5, SwiftUI, XCTest, existing `APIClient` and URL protocol fixture.

**Spec:** `docs/design/paper-R7U-0.json`, `Thorbis/Sources/FinancialActionAPI.swift`, and TanStack invoice detail payment behavior.

## Global Constraints

- Match the Paper invoice `Payments` section and bottom `Collect payment` action.
- Accept only positive USD amounts in integer cents and methods `card`, `ach`, `cash`, or `check`; this records a payment already collected and does not charge a card or initiate ACH.
- Reuse an idempotency key on retries of the same intent; block concurrent submissions.
- Treat server payment records and refreshed invoice totals as authoritative; never optimistically change the invoice balance.
- Preserve server-derived collection evidence and capability checks; processor-backed card and hosted checkout remain separate workflows.

## Review Focus

- A non-issued invoice must not offer collection; a draft shows why recording is unavailable.
- A server permission denial must preserve the amount and expose a recoverable error.
- A failed POST followed by retry must send the same amount, method, and idempotency key.
- A successful POST whose projections have not caught up must retain a pending state without changing the displayed balance.
- Pagination, malformed payment records, and server conflicts must produce recoverable errors without discarding the user's amount.

---

### Task 1: Payment collection model and contract tests

**Files:**
- Create: `Thorbis/Sources/InvoicePaymentCollection.swift`
- Create: `ThorbisTests/InvoicePaymentCollectionTests.swift`
- Modify: `ThorbisTests/FinancialActionAPITests.swift` only if an uncovered API-boundary contract needs a direct assertion.

**Interfaces:**
- Consumes: `InvoiceRecord`, `FieldPaymentRecord`, `FieldPaymentMethod`, `FieldRecordPaymentRequest`, and the existing payment methods on `APIClient`.
- Produces: a `@MainActor` observable model for invoice payments, validated collection drafts, retry-safe submission, and canonical refresh.

- [x] Write `testPaymentAmountUsesExactMinorUnitsAndCanonicalLimit` to verify exact cents, non-cent rejection, and the server's 1e12-cent upper bound.
- [x] Write `testRetryAfterTransientFailureReusesSamePaymentIntent` to verify a retry after model recreation restores and sends identical cents, method, and key.
- [x] Write `testDuplicateSubmitDuringRequestDoesNotPostTwice` to verify two taps create one POST.
- [x] Write `testInvoiceAndHistoryStayLockedUntilReceiptReconciles` to verify POST response alone does not update invoice balance or unlock recording.
- [x] Run the focused tests and confirm they fail because the model is missing.
- [x] Implement the model and input validation to pass those tests.
- [x] Run the focused tests and full native suite (159 passed).

### Task 2: Paper payment history and recorded-tender sheet

**Files:**
- Modify: `Thorbis/Sources/FinancialViews.swift`
- Modify: `Thorbis/Sources/InvoicePaymentCollection.swift`
- Modify: `ThorbisTests/InvoicePaymentCollectionTests.swift`

**Interfaces:**
- Consumes: the payment model from Task 1 and the existing invoice payment endpoints.
- Produces: a `Payments` history section and Card/ACH/Cash/Check recording sheet wired to the existing server API.

- [x] Add tests for issued versus non-issued gating, complete-history reconciliation, overpayment prevention, refunded payment handling, issue-refresh failure, successful retry, and recoverable server errors.
- [x] Run the focused tests before implementing the model and confirm the required model behavior was absent.
- [x] Implement the Paper Payments history rows and count, read-only payment detail sheet, Collect payment action, and Card/ACH/Cash/Check recording sheet while retaining the existing invoice detail layout.
- [x] Run the full iPhone simulator tests (161 passed) and iOS Release build; inspect the invoice detail and collection sheet previews.
- [x] Update the design/release evidence.

### Review follow-up

- [x] Persist uncertain payment intents by organization and invoice so retries after view recreation or app restart reuse the original idempotency key; clear only after reconciliation or a definitive client error.
- [x] Count a fully refunded payment as zero when the response omits `netAmount`.
- [x] Apply a successful issue mutation response before refreshing payment history so a failed refresh cannot restore the draft footer.
- [x] Independent review confirmed all three fixes; no actionable findings remain.
