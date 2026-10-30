# Onsite payment collection

The user requires Tap to Pay, secure keyed card entry, check capture, cash and
bank payments for construction work. Preserve partial receipts, invoice-specific
history, discounts and safe retries. Charging and recording an already received
payment must remain distinct actions. Scanning a check never establishes deposit
or clearance. Whether electronic deposit is required remains a pending user choice.

## First deliverable: exact Tap receipt confirmation

The current native closure considers either a larger payment count or zero invoice
balance sufficient to confirm a Tap payment. An unrelated receipt can satisfy both.
Only a complete validated history containing this attempt's card receipt may confirm
it. Require exact invoice, organization, amount, currency, recorded status and no
refund, plus the server-generated attempt key. Missing/invalid data stays pending.
History must also belong to the current API request generation; switching workspace
or signing out invalidates a previously verified receipt before another load starts.

Current server contract: `prepareInvoiceCardPresentIntent` constructs
`tap:${invoiceId}:${attemptId}`; `recordSucceededAttempt` carries that key unchanged
into the canonical payment; verified webhook processing owns settlement. Native uses
this inspected convention for compatibility with the deployed response, which omits
the key. A future additive response should expose the opaque key instead. A changed
server convention must fail closed; never fall back to count or balance.

Retain the disabled distribution build gate and pinned Terminal SDK. No actual charge
is needed to test receipt reconciliation. Do not persist client secrets or add raw
card fields. The current card endpoint explicitly calls its continuation browser-only;
native keyed entry requires a qualified SDK configuration/account-routing contract.
Check image capture requires private payment evidence storage, not generic job media.

## Next deliverables

Secure manual card entry with provider-owned UI, exact-attempt confirmation, recovery
after interruption and no technician-wallet shortcut. Check number/front/back capture
with human amount review and explicit received/deposited/cleared states as supported by
the actual banking contract. Keep cash, received ACH, external-card receipts and secure
customer payment links accessible. No new method is advertised as operational before
its backend/provider path is verified.

## Construction tender coverage

| Method | Required behavior | Current audit |
| --- | --- | --- |
| Contactless card/customer wallet | Tap on the technician's iPhone; verified settlement | Terminal exists; distribution qualification remains gated |
| Keyed card | Secure provider-owned entry and confirmation | Native configuration/continuation contract still required |
| Cash | Record amount received; partial or remaining balance | Existing receipt path |
| Paper check | Check number and private front/back capture, review amount; explicit banking state | Receipt path exists; capture/reference contract still required |
| ACH | Distinguish authorized/pending debit from transfer already received | Existing path records received ACH only |
| Wire/approved external apps | Record truthful tender/reference and received state | Requires canonical tender/subtype support; never label these ACH by assumption |
| Card charged elsewhere | Record existing receipt without initiating a new charge | Existing separate external-card receipt path |
| Customer remote payment | Secure QR/share link; webhook-confirmed receipt | Existing hosted Checkout path |

Apply each receipt to the exact invoice for the job. Split tenders remain distinct
receipts; deposits/progress/final invoices retain their own balances. Financing,
credits, discounts and write-offs must use their actual domain contracts rather
than masquerading as a received cash/card/check payment.
