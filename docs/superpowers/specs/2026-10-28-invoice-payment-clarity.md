# Invoice collection clarity — BYR-1579

28 October 2026 · Thorbis Field Management · SwiftUI · iOS/iPadOS 18+

Working issue: https://linear.app/byronwade/issue/BYR-1579
Baseline: iOS27e325b (TestFlight70), backend contract db80ec547.
Working checkout: /private/tmp/thorbis-ios-payment-ux. The original Documents
checkout stalled on file reads; its uncommitted execution-log copy remains there.

## Outcome

Make the existing invoice flow clearer and faster to hand to a customer. Preserve
all current features, financial permissions, validation, pending intent identity,
reconciliation locks and server authority. Follow the continuous UX goal and
upload another verified TestFlight beta after this batch.

## Interaction

- Collecting a new payment and recording funds already received use distinct
  wording. Card checkout remains a server-issued link. Cash and check remain
  direct choices with their current fast path.
- Put less frequent recorded methods in one native menu. Make ACH transfer
  received and card collected elsewhere understandable in ordinary words.
  Retain every canonical recorded tender: card, ach, cash and check.
- A received ACH transfer uses the existing receipt-recording endpoint and its
  confirmation. It does not initiate a debit. Show the reviewed amount and
  preserve the same amount/method/idempotency key when retrying.
- After creating the exact-balance card link, show a QR on the existing Payment
  link destination, with Share and Copy alternatives. The customer scans it on
  their own phone. Done returns to the invoice (MF-10).
- QR encodes only the validated server HTTPS URL; it adds no amount, provider,
  tenant, query or credential data. Use bounded local QR rendering, a quiet
  zone, black on white, and a readable fallback when encoding fails.
- Expired or malformed links offer a fresh-link action rather than an active
  QR. Check invoice state during the handoff; show Invoice paid only from the
  refreshed canonical invoice/payment model, never a checkout redirect.
- Use scrollable native content, shared typography/amount hierarchy and
  comfortable targets. Enlarged text must wrap; QR geometry remains scannable.

## Tap to Pay availability

Build70's signed development archive lacks the payment.acceptance entitlement.
The Developer portal shows the Thorbis capability unchecked and exposes only
Development provisioning support; distribution approval is unconfirmed. The
portal and blank request form cannot establish whether a prior request exists.
Original Apple correspondence was later found: development-only approval on
27 October, Case23157370; distribution requires separate flow videos and checklist
review. BYR-436 holds that evidence. No distribution approval was found.

Keep the implementation, but fail closed on offering it in an unqualified
build. A build-policy marker expresses release intent and grants no Apple
capability. An enabled build must be checked against its signed entitlement and
provisioning allowance before release. Runtime feature/permission/device checks
remain additional gates. Do not parse a provisioning profile inside iOS or use
private entitlement APIs. Unavailable builds must not create a provider attempt.

Exact-attempt reconciliation and distribution qualification remain tracked under
BYR-350/BYR-436. This batch does not claim those issues complete.

## Authority and future methods

Current methods are recorded card/ach/cash/check, actual card hosted checkout,
and the existing gated Terminal adapter. The collection-decision kernel is
advisory and does not authorize eleven executable rails. Actual ACH debit is a
separate planned capability, covered by BYR-352, with BYR-344 still In Review and
provider vault/callback/qualification work outstanding. Wire/bank-transfer push
and financing remain separate capabilities. Keep that implementation work
explicit; never advertise a new executable rail based on a label or design rule.

## Source receipts

Consulted 28 October 2026:

- Thorbis Native D-025, HIG-001–HIG-022: https://design.thorbis.com/skills/native
- Thorbis durable records/scoped transactions: https://design.thorbis.com/files/DESIGN.md
- Thorbis honest pending/recovery states: https://design.thorbis.com/skills/resilience
- Apple Menus: https://developer.apple.com/design/human-interface-guidelines/menus
- Apple Sheets: https://developer.apple.com/design/human-interface-guidelines/sheets
- Apple Buttons: https://developer.apple.com/design/human-interface-guidelines/buttons
- Stripe hosted Apple Pay: https://docs.stripe.com/apple-pay?platform=ios
- Stripe ACH/mandate/verification: https://docs.stripe.com/payments/ach-direct-debit/accept-a-payment?payment-ui=mobile&platform=ios
- Stripe method support: https://docs.stripe.com/payments/payment-methods/payment-method-support
- Apple Tap entitlement: https://developer.apple.com/documentation/proximityreader/setting-up-the-entitlement-for-tap-to-pay-on-iphone
- Apple profile audit: https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles
- Stripe Terminal support checks: https://github.com/stripe/stripe-terminal-ios/blob/master/PublicHeaders/SCPTerminal.h

Customer-device checkout avoids opening the technician's own Wallet for a
customer payment. This is a role/UX inference from Apple Pay and Tap to Pay's
respective platform roles. Hosted checkout offers eligible wallet choices;
merchant/customer availability still governs what it actually displays.
