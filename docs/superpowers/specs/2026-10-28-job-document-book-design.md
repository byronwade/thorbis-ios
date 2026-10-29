# Every document for the customer's job

App-wide context: [iOS golden rules](../../design/ios-golden-rules.md) and
[implementation process](../../design/ios-implementation-process.md). Apply the
full supplied field-management guidance to this existing work as well as later
features; this spec retains the customer's complete document/interaction scope.

The customer can see every estimate and invoice belonging to the current job in
one handoff and swipe between them. Invoice pages show payments, refunds,
discounts/credits, total and remaining balance clearly. Existing review, signature,
decline, payment and authenticated technician hand-back remain available. The
user explicitly wants continuous implementation and frequent TestFlight releases.

Use the existing SwiftUI client and CustomerPresentation Guided pattern. Keep the
Paper Thorbis Mobile Q6N-0 / R5C-0 / R7U-0 design, token hash2803f4aa, existing
Theme and CustomerType:17pt smallest,20/22pt body,34/40pt totals,56pt targets,
weights400/500. Refine hierarchy and disclosures without removing information.
Swiping is convenient; visible Previous/Next and an all-documents selector must
provide equivalent navigation. No wraparound or automatic advance. Every page
has its reference and position. Preserve the current job documents overview.

Use a stable document identity (kind plus recordID) rather than array index or
record contents. The book is assembled only from JobDocumentCollections whose
scope exactly matches current job/tenant/customer/location. Keep unavailable and
stale references explicit, with refresh and no decision from stale data. Workspace
changes clear pages/history and prevent late reads from publishing old data.

Browse full read-only paper in the book, with explicit actions opening the existing
canonical review/signing flows. Signing is outside the swipe surface so drawing a
signature cannot change documents or carry consent to another estimate. Sent
estimate actions retain C0's exact immutable revision/public hash validation.
Drafts/declined/void paper stay read-only and are labelled. A selected invoice's
payment action always authenticates the device owner and targets that invoice.

Amounts are presentation of server-owned lines, not new pricing authority. Use
checked integer minor-unit arithmetic. Positive charges form Subtotal, negative
lines form Discounts and credits (retain each original description), then Total,
Paid and Amount due. Do not call all credits a discount or invent savings. Reject
mixed currencies, overflow, negative final total or negative paid amounts. A valid
discount must not disable payment collection.

Only payment records matching exact invoiceID, organization and currency may be
published; duplicate IDs or malformed amounts/refund/net evidence refuse the
whole history, show a recoverable error and disable collection. Partial history
is never shown as complete or as zero payments. Show dates and method in customer
words; show refunds and net received distinctly. Keep internal idempotency keys,
source/provenance, actors and provider identifiers private. Reuse existing paged
payment API and reconciliation gates; no new financial request or live payment.

Native unit/API fixtures must cover identity, discounts, overflow, payment history,
navigation boundaries, stale/session/cancellation. Native journeys must swipe and
use buttons through at least two estimates and two invoices for one job, exclude
another job, display discount/payment/refund details, preserve review/payment
handoffs, and exercise large Dynamic Type/dark mode. Run full native scheme,
independent whole-branch review, release notes, archive/sign/upload and verify
existing TestFlight tester group before claiming delivery.

This delivery complements ongoing C1-C3 add-on server/billing/Swift work and does
not mark it complete. Tap to Pay stays under its separate distribution gate.

Research: Paper export inspected directly; current Linear Mobile record detail
https://mobbin.com/screens/f03367b0-cbbe-497c-bfc5-4479a5ed4fd1 adopts quiet record
header and optional activity disclosure, rejects staff edit/comment chrome.
Sibling Linear list-settings references fea8a7b6 and f02d53ae do not establish a
document swipe pattern and are rejected for this surface. Native paging is an
implementation choice with explicit controls as required by CP-10.

12ui installed0.2.130 and attempted a Paper-anchored review; service requires its
own sign-in and produced no candidates. Optional tooling preference asked;
continue data work meanwhile. Existing explicit Paper fidelity and continuous-work
authorization govern implementation; do not replace Paper with an unreviewed image.
