# Paper Invoice and Tap to Pay Implementation Plan

> **For agentic workers:** Use the existing checkout and preserve all existing user changes. Tasks use checkbox syntax for tracking.

**Goal:** Match the Paper Mobile invoice and collection artboards, then add real, retry-safe Stripe Terminal card-present collection to the native iPhone app.

**Architecture:** The job Invoice tab and payment collection sheet use the saved Paper layouts and live Thorbis records. The native app remains a thin client: Stripe Terminal connection, payment attempt creation, processor confirmation, and canonical payment settlement belong to Thorbis-TanStack; manual “record already collected” remains a separate cash/check bookkeeping action.

**Tech Stack:** SwiftUI, Swift 6, XcodeGen, XCTest, Stripe Terminal iOS SDK, Thorbis API and provider contracts.

**Spec:** `docs/design/paper-R7U-0.json`, `docs/design/paper-PVJ-0.json`, and `docs/design/README.md`.

## Global Constraints

- R7U-0 is the source of truth for the inline job invoice tab; PVJ-0 is the source of truth for collection layout.
- Use live API data and existing Paper tokens; never add sample payment, receipt, or activity data to production views.
- Do not route card-present payments through the existing online-card or manual-record endpoint.
- Keep collection tenant-scoped, capability-checked, invoice-balance-checked, and gated by canonical real-world-service evidence.
- Persist a canonical payment only after Stripe confirms success; preserve idempotency and unresolved-attempt recovery.
- Tap to Pay requires an approved Stripe Terminal integration, a real Terminal location, supported iPhone, merchant terms/configuration, and Apple’s distribution entitlement before TestFlight collection can be enabled.
- No raw payment credentials, short-lived connection tokens, or card data are persisted or logged by the app.

## Review Focus

- Several invoices linked to one job must remain visible and independently actionable.
- Partial payments and refunded payments must show the correct remaining balance.
- Missing or stale payment history must disable record/charge actions until reconciled.
- An interrupted or uncertain Terminal result must not create a second charge on retry.
- Missing merchant location, unsupported device, missing entitlement, or unaccepted Tap to Pay terms must be presented as unavailable states, not successful collection.

---

### Task 1: Paper invoice detail in the job tab

**Files:**
- Modify: `Thorbis/Sources/PaperJobDetailView.swift`
- Modify: `Thorbis/Sources/FinancialViews.swift`
- Modify: `Thorbis/Sources/InvoicePaymentCollection.swift`
- Test: `ThorbisTests/PaperPreviewTests.swift`

**Interfaces:**
- Consume the existing `InvoiceRecord`, `InvoicePaymentCollectionModel`, and payment-history API.
- Keep `InvoiceDetailView` available for the invoices workspace and document actions.

- [ ] Add a fixture-level test for issued invoice balance, line items, and payment-history states used by the Paper view.
- [ ] Run the focused XCTest and verify it fails for the missing fixture/state.
- [ ] Render the R7U-0 balance/status block, line-item card, payments summary, activity, and docked actions inline in the job Invoice tab.
- [ ] Build and run the focused XCTest; compare the populated iPhone preview with R7U-0.

### Task 2: Paper collection screen and honest payment options

**Files:**
- Modify: `Thorbis/Sources/InvoicePaymentCollection.swift`
- Modify: `Thorbis/Sources/FinancialActionAPI.swift`
- Modify: `Thorbis/Sources/FieldAPI.swift`
- Modify: `Thorbis/Sources/PaperPreview.swift`
- Test: `ThorbisTests/InvoicePaymentCollectionTests.swift`
- Test: `ThorbisTests/PaperPreviewTests.swift`

**Interfaces:**
- Consume the existing manual payment model only for recording a payment that has already been received.
- Consume the canonical pay-link API only for sending a customer payment link.
- Keep Tap to Pay visibly unavailable until Task 3 and Task 4 report backend and device readiness.

- [ ] Add tests for amount bounds, payment-history reconciliation, and unavailable Tap to Pay state.
- [ ] Run the focused XCTest and verify the new expectations fail.
- [ ] Implement the PVJ-0 amount hero, prominent Tap to Pay panel, alternative payment rows, receipt destination, and docked action.
- [ ] Keep cash/check recording explicitly distinct from card charging; do not imply a check scan is deposit or payment authorization.
- [ ] Build and run focused tests; compare the populated iPhone preview with PVJ-0.

### Task 3: Canonical Stripe Terminal backend

**Files:**
- Modify: `domains/payments/src/processor.ts`, `domains/payments/src/commands.ts`, payment schemas and tests
- Modify: `packages/providers-stripe/src/request-builder.ts`, `collect.ts`, `adapter.ts`, and transport/types
- Modify: provider capability and Stripe matrix contracts and their tests
- Modify: API composition, invoice payment routes, route manifest, OpenAPI, API client, and API tests
- Modify: applicable mobile commerce/privacy contracts and checks

**Interfaces:**
- Add a distinct card-present payment-attempt path with invoice-scoped authorization and short-lived connection-token delivery.
- Resolve a verified Stripe Terminal location for the connected merchant; never guess or create arbitrary locations from client data.
- Reuse canonical payment settlement and reconciliation only after confirmed processor success.

- [ ] Add failing provider, domain, API, and contract tests for supported, unauthorized, over-balance, stale-evidence, and uncertain outcomes.
- [ ] Run focused tests to verify they fail for the missing Terminal path.
- [ ] Implement the narrow Terminal contract and register its Stripe capability and API surface.
- [ ] Run focused payment/provider/API checks and all required mobile commerce/privacy gates.

### Task 4: Native Stripe Terminal and device readiness

**Files:**
- Modify: `project.yml`
- Create: `Thorbis/Sources/TerminalPaymentCollection.swift`
- Modify: `Thorbis/Sources/InvoicePaymentCollection.swift`, app configuration, and privacy manifest as required
- Test: native payment and preview tests

**Interfaces:**
- Use the server-issued connection token and configured Terminal location from Task 3.
- Process payment intents with the official Stripe Terminal iOS SDK; never create or settle a card-present payment solely in the client.
- Disable charging when the device, entitlement, merchant setup, or invoice evidence is not ready.

- [ ] Add failing tests for device unsupported, missing configuration, success, cancellation, and uncertain retry states.
- [ ] Verify the failure cases before implementing the SDK coordinator.
- [ ] Implement Terminal discovery/connect, Tap to Pay configuration, collection, processing, and server reconciliation callbacks.
- [ ] Build and run simulator tests; verify physical Tap to Pay only after Apple grants the distribution entitlement and merchant configuration is available.

### Task 5: Final visual and release verification

- [ ] Run `git diff --check`, focused XCTest, the full iOS test target, and a signed archive build.
- [ ] Capture populated R7U-0 and PVJ-0 simulator frames and compare to Paper.
- [ ] Confirm TestFlight remains gated until the Terminal distribution entitlement and server setup are verified.
- [ ] Record exact build, test, and readiness evidence in release notes.
