# Native payment refunds — 27 October 2026

## Behavior

The invoice payment detail sheet offers a **full refund** for a recorded payment with no previous refunded amount when the active session has `invoice.refund` in the `payments` feature. The client treats this capability as a visibility gate only; the Thorbis API enforces current payment eligibility and amount-specific authorization. The mobile flow does not offer partial refunds.

The form requires a trimmed 3–2,000-character reason and sends `POST /v1/payments/{paymentId}/refund`. HTTP 200 must contain the canonical refunded Payment before the UI reports completion and refreshes invoice history. HTTP 202 is represented as pending or reconciliation-required. A timeout or other ambiguous failure remains uncertain and is never reported as success.

## Recovery and storage

The exact reason is saved before the network request in Keychain, scoped to actor, organization, and payment, with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. It is not stored in UserDefaults or synchronized to iCloud. Pending, reconciliation-required, and uncertain states require the user to explicitly check status; the client retries with the same payment ID and reason and relies on the server's idempotent workflow. The user may explicitly discard a saved draft; a submitted unresolved recovery intent cannot be discarded, so the app cannot offer a second refund with a different reason. Keychain read/write failures block a new refund request.

## Design preview

DEBUG-only preview routes use a paid sample invoice and a recorded sample payment. The preview transport intercepts every request and rejects mutations with HTTP 405; it cannot contact Thorbis or refund a payment. Launch with one of:

- `invoice-payment-refund`
- `invoice-payment-refund-form`
- `invoice-payment-refund-confirmation`
- `invoice-payment-refund-pending`
- `invoice-payment-refund-reconciliation`

These are sample-data design previews, not authenticated end-to-end tests. The iPhone 17 Pro simulator displayed an unrelated Apple Account sign-in prompt over the app during capture; no credentials were entered. The underlying payment and refund states were inspected, but screenshots are not used as clean release evidence.

## Verification

- API, refund-model, and preview tests: 37 passed, 0 failed on iPhone 17 Pro / iOS 26.3.1. Result bundle: `/Users/byronwade/Library/Developer/Xcode/DerivedData/Thorbis-dmuwxdzkujtkngcfxjqjbnvsarbv/Logs/Test/Test-Thorbis-2026.10.27_06-47-08--0400.xcresult`.
- Paper preview tests after adding the direct form/confirmation routes: 9 passed, 0 failed on iPhone 17 Pro / iOS 26.3.1. Result bundle: `/Users/byronwade/Library/Developer/Xcode/DerivedData/Thorbis-dmuwxdzkujtkngcfxjqjbnvsarbv/Logs/Test/Test-Thorbis-2026.10.27_06-51-16--0400.xcresult`.
- Full iPhone 17 Pro / iOS 26.3.1 simulator suite: 215 passed, 0 failed. Result bundle: `/Users/byronwade/Library/Developer/Xcode/DerivedData/Thorbis-dmuwxdzkujtkngcfxjqjbnvsarbv/Logs/Test/Test-Thorbis-2026.10.27_06-54-26--0400.xcresult`.
- Generic-iOS Release compile passed with build 17. Signed archive, upload, and TestFlight processing: pending.
- Device-only Keychain behavior, physical-device performance (HIG-018), accessibility runtime checks, and authenticated refund testing have not been verified.
