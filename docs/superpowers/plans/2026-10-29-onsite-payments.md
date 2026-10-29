# Onsite payments implementation plan

> Execute inline using superpowers:executing-plans. Continue under the user's existing implementation authorization.

**Goal:** Confirm only the exact Tap transaction and establish the remaining onsite method requirements.
**Architecture:** Keep SDK collection in TapToPayController. Pass the returned intent into the refresh closure; InvoicePaymentCollectionModel validates its canonical receipt against fresh scoped history.
**Tech Stack:** Swift, SwiftUI, XCTest, pinned Stripe Terminal 5.8.1.
**Spec:** ../specs/2026-10-29-onsite-payments.md

## Global constraints

- Preserve all payment methods and partial receipts.
- Keep Tap distribution qualification disabled; no provider charges or dependency upgrades.
- Never persist client secrets or raw card data.
- Check scanning is not deposit or clearance.

## Review focus

- Another receipt pays the invoice: must not confirm the Tap attempt.
- Correct key with wrong amount/method: must not confirm.
- Refunded matching receipt: must not present Paid.
- Failed, canceled or foreign history: must not confirm from stale rows.
- SDK refresh uses the created attempt rather than an inferred balance.

### Task 1: Exact receipt confirmation

Files: TapToPay.swift, InvoicePaymentCollection.swift, TapToPayReadinessTests.swift,
InvoicePaymentCollectionTests.swift.

Consumes CardPresentIntent and validated FieldPaymentRecord history. Produces
`hasRecordedCardPresentPayment(_ intent: CardPresentIntent) -> Bool` on the model;
controller refresh becomes `(CardPresentIntent) async -> Bool`.

- [x] Add model tests for unrelated fully paying receipt, correct receipt, mismatched amount/method, refunded receipt and invalid history. Observe the missing capability before implementation.
- [x] Implement exact receipt matching and pass the intent through the SDK refresh closure. Update the unavailable-build test closure; no SDK invocation in tests.
- [x] Run InvoicePaymentCollectionTests, TapToPayReadinessTests and affected payment-link/option tests on the owned simulator. Expected: executed tests, zero failures.
- [x] Review the changed branch; commit verified source and evidence. Keep manual-card/check integration work pending its real contract and check-deposit scope.
