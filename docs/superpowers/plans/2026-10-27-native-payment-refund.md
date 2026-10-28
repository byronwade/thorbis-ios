# Native Payment Refund Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the authorized full-refund flow from invoice payment details with safe recovery for pending and uncertain server outcomes.

**Architecture:** Decode the canonical Payment and HTTP 202 accepted outcomes through a status-aware API method. A small MainActor refund model owns a Keychain-backed intent scoped to actor, workspace, and payment; the native payment-detail flow requires a reason and a destructive confirmation, then exposes explicit status recovery. The server remains authoritative for amount limits and final permission checks.

**Tech Stack:** Swift 6, SwiftUI, XCTest, URLProtocol fixture, Security.framework, existing `APIClient`.

**Spec:** `docs/superpowers/specs/2026-10-27-native-payment-refund-design.md`.

## Global Constraints

- Offer only a full refund for a recorded payment with no prior refunded amount.
- Require `invoice.refund` in the `payments` feature for visibility; the server alone decides amount-specific authorization and final eligibility.
- Trim and validate a 3–2000-character reason and send it to `POST /v1/payments/{id}/refund`.
- Retain the exact reason in Keychain using `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, keyed by actor, organization, and payment; never sync it to iCloud.
- Do not automatically retry; pending and uncertain recovery is an explicit action that replays the same payment ID and exact reason.
- Only canonical server payment data may report a completed refund.
- Preserve the verified Thorbis logo asset already used by the iOS login and workspace selector.

## Review Focus

- HTTP 202 must decode as pending or reconciliation-required and must not be shown as completed.
- A timeout or app termination during POST must leave a recoverable, same-reason intent that cannot be discarded into a second-refund path.
- A server permission or eligibility refusal must retain the reason and not trigger hidden retries.
- Reopening the sheet must restore an unsent draft; a user may explicitly discard that draft, while submitted unresolved intents remain available only for same-reason recovery.
- A partially refunded payment must never expose another full-refund action.

---

### Task 1: Refund API contract

**Files:**
- Modify: `Thorbis/Sources/API.swift`
- Modify: `Thorbis/Sources/FinancialActionAPI.swift`
- Modify: `ThorbisTests/FinancialActionAPITests.swift`

**Interfaces:**
- Produces `FieldPaymentRefundOutcome` (`pending` or `reconciliationRequired`) and `FieldPaymentRefundResponse` with `.completed(FieldPaymentRecord)` and `.accepted(outcome:paymentID:)` cases.
- Produces `APIClient.refundFieldPayment(_:reason:) async throws -> FieldPaymentRefundResponse`.

- [x] Add API tests for the exact refund path, trimmed reason body, 200 canonical payment, 202 pending, 202 reconciliation-required, and 403/409 refusal without retry.
- [x] Run the focused API tests and confirm they fail because the refund contract is missing.
- [x] Add a status-returning decode helper that keeps the existing transport error handling, then implement the refund request and reject mismatched status/body shapes.
- [x] Run the focused API tests and confirm all response variants pass.

### Task 2: Secure refund-intent model

**Files:**
- Create: `Thorbis/Sources/PaymentRefundIntentStore.swift`
- Create: `Thorbis/Sources/InvoicePaymentRefundModel.swift`
- Create: `ThorbisTests/InvoicePaymentRefundTests.swift`
- Modify: `ThorbisTests/URLProtocolFixture.swift` only if the existing response fixture needs a testable request gate.

**Interfaces:**
- `FieldPaymentRefundIntentState` (`draft`, `pending`, `reconciliationRequired`, or `uncertain`) and `FieldPaymentRefundIntent` retain only the reason and state.
- `PaymentRefundIntentStoring` exposes throwing `load(actorID:organizationID:paymentID:) -> FieldPaymentRefundIntent?`, `save(_:actorID:organizationID:paymentID:)`, and `remove(actorID:organizationID:paymentID:)`, all scoped by the three supplied IDs.
- `KeychainPaymentRefundIntentStore` stores only the minimal Codable reason/outcome payload with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- `InvoicePaymentRefundModel(api:actorID:payment:intentStore:)` exposes `canOfferRefund`, `canSubmitRefund`, `updateReasonDraft(_:)`, `submitRefund() async -> Bool`, `checkRefundStatus() async -> Bool`, `discardSavedIntent()`, and published payment/intent/loading/error state.

- [x] Add failing model tests for full-refund eligibility, reason validation, save-before-network, draft restoration, duplicate-submit blocking, exact same-reason 202 recovery, and canonical completion clearing the intent.
- [x] Run the focused tests and confirm they fail because the refund model/store are missing.
- [x] Implement the injectable Keychain store and minimal refund model to satisfy those tests.
- [x] Add tests for pending versus reconciliation-required, retained intent after 4xx/network uncertainty, draft-only discard, unresolved-intent retention, and fully/partially refunded gating.
- [x] Run the focused tests and confirm they pass (12 refund-model tests; the original 11 were included in the 37-test focused API/model/preview run).

### Task 3: Native payment-detail refund flow

**Files:**
- Modify: `Thorbis/Sources/InvoicePaymentCollection.swift`
- Modify: `Thorbis/Sources/PaperPreview.swift`
- Modify: `ThorbisTests/PaperPreviewTests.swift` only if a read-only preview route is added.

**Interfaces:**
- Payment detail receives the existing API/session dependencies and constructs one `InvoicePaymentRefundModel` for its selected payment.
- Payment detail displays the server-confirmed payment, only offers the reasoned full-refund path when session capability/feature and payment eligibility permit it, and refreshes invoice/payment history after canonical completion.

- [x] Add read-only invoice/payment preview fixtures and a preview-transport test proving refund POSTs are rejected locally; model/API tests already cover permission-independent server refusal and 202 states.
- [x] Run the focused preview tests and confirm the refund preview fixture is missing.
- [x] Add a reason editor with saved-draft restoration, standard confirmation dialog with Cancel, in-flight dismissal lock, and explicit pending/reconciliation/uncertain recovery controls.
- [x] Add explicit discard confirmation and preserve normal Done/back, safe-area, VoiceOver, Dynamic Type, and iPad layout behavior.
- [x] Run focused tests and build the app for the iPhone 17 Pro simulator (preview tests pass; simulator app launched with isolated read-only fixture).
- [x] Inspect payment details, reason entry, destructive confirmation, pending, and reconciliation in the intercepted preview. An unrelated Apple Account prompt obscured part of simulator captures; no credentials were entered.

### Task 4: Release evidence and verification

**Files:**
- Modify: `docs/design/native-ui-evidence-2026-10-27.md`
- Modify: `docs/release/beta-coverage.md`
- Create: `docs/release/payment-refund.md`

- [x] Record the refund coverage and the official Thorbis mark checksum already verified against `Thorbis-TanStack/apps/showcase/public/logo-source.png`.
- [x] Run the focused refund tests and full iPhone simulator test suite (215 passed, 0 failed), then build the iOS Release configuration (passed).
- [ ] Run `git diff --check` and report physical-device HIG-018 measurements as not tested and still required for release.
