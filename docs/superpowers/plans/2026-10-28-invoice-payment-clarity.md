# Invoice Payment Clarity Implementation Plan

> Use superpowers:executing-plans inline, with TDD and one fresh whole-branch review.

Spec: docs/superpowers/specs/2026-10-28-invoice-payment-clarity.md
Issue: BYR-1579. Baseline27e325b. Working root /private/tmp/thorbis-ios-payment-ux.

## Global constraints

Preserve all current main features and every existing recorded tender, permission,
amount check, locked request and reconciliation state. Keep cash/check direct.
QR shares only the server URL. Actual ACH debit remains a separate backend rail.
A build marker never grants an Apple entitlement. No live charge or account/capability
mutation is part of verification. Add What's new notes and ship a verified beta.

## Review Focus

- An unqualified Tap build never creates a card-present intent even on supported hardware.
- Pending recorded ACH/card/cash/check requests retain their exact method and amount.
- Existing cash/check collection is still direct; advanced tender choices are native menus.
- QR payload is the exact validated HTTPS URL, bounded and independently decodable.
- Expired/invalid links cannot present an active QR; Share/Copy remain usable when encoding alone fails.
- Payment status comes from canonical invoice data; no redirect or unrelated count proves a specific attempt.
- All current features, native navigation, Dynamic Type and authoritative server amount remain intact.

### Task 1: Make Tap build availability truthful

**Files:** new TapToPayReadiness.swift and tests; TapToPay.swift; InvoicePaymentCollection.swift;
Info.plist; a release-artifact audit helper and testflight.sh.

**Interface:** pure readiness policy combines build intent, device support, backend feature and
permission. Build intent defaults false. Release helper verifies an enabled build's signed
payment.acceptance entitlement and provisioning allowance; it never grants them.

- [x] Write meaningful tests proving an unqualified build overrides other eligibility and starts no provider request. Run RED before implementation.
- [x] Add the fail-closed policy and guard both UI selection and controller entry. Use clear unavailable copy; keep all Terminal implementation paths.
- [x] Add artifact audit to release preparation. Verify legacy archive70 is rejected as unverifiable, the next explicit-disabled archive passes, and enabled-policy fixtures missing signed/profile allowance fail.
- [x] Run readiness/API/payment-state checks. Expected: green, no new provider request in unavailable cases.
- [x] For this first useful release, run the full scheme and a fresh review, archive/audit/upload the next unused build, and verify internal distribution before starting the QR/receipt feature batch.

### Task 2: Clarify received-payment choices

**Files:** InvoicePaymentCollection.swift; extracted InvoiceCollectionOption presentation policy;
FinancialActionAPI.swift display names; choice/API tests; native UI checks.

**Interface:** received ACH maps to existing .ach, external card to .card. Pending requests
restore their same method and amount. Retained last-used behavior stays cash/check/link.

- [x] Add tests for pending-method restoration and bank/card receipt mapping; run RED.
- [x] Keep Cash and Check direct. Replace the duplicate advanced row/picker with one native
  menu for ACH transfer received and card collected elsewhere, retaining all four tenders.
- [x] Use received-payment copy and confirmations; keep mutation/idempotency/recovery handlers.
- [x] Verify native selection/reachability and canonical API payloads without submitting real payments.

### Task 3: Add scan-to-pay handoff

**Files:** new PaymentLinkPresentation/QRCode/SwiftUI destination and tests; current collection
sheet destination; DEBUG-only ready-link preview; native UI checks; ReleaseNotes.swift.

**Interface:** link policy resolves validated URL and expiry at a supplied date; QR renderer
returns a bounded scannable image or nil. Destination uses the existing model and recreate/share/copy
handlers; cancellation and Done preserve invoice context.

- [x] Write expiry/invalid-URL and independent QR decode tests; run RED.
- [x] Extract the existing destination, add QR with Share/Copy alternatives, clear expiry/error
  recovery, and canonical invoice refresh. Avoid duplicate link/provider attempts.
- [x] Verify normal, enlarged and dark layouts and the native handoff/receipt menu paths.
- [x] Add current What's new notes. Run the appropriate focused checks, then one full scheme.
- [x] Fresh review; resolve blocking findings with tests. Archive/upload next unused build and
  verify Apple processing and intended group distribution. Record native test gaps honestly.
