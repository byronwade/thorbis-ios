# Onsite payment receipt confirmation

The collection audit found a false-success path: any new receipt or zero balance
could confirm a Tap to Pay attempt. Controller refresh now receives the created
intent and checks its canonical receipt against complete validated history: exact
invoice, organization, server attempt key, card tender, amount/currency, recorded
status and no refunds. Failed refreshes cannot reuse formerly verified receipts.
This changes no payment method UI or distribution qualification gate.

The deployed prepare response omits an opaque receipt key. Native temporarily uses
the inspected server convention `tap:invoiceId:attemptId`; canonical verified-webhook
settlement copies it unchanged. If that convention changes, confirmation stays
pending. Prefer an additive opaque key response in subsequent backend work.

Initial test build failed because the new matcher did not exist; it executed no
tests. First GREEN passed27/27. A behavioral mutation restored the original
count/balance predicate inside the matcher: the unrelated-full-payment regression
then failed1/1. Exact source was restored and checked byte-for-byte. Initial focused
qualification passed46/46 with zero failures/skips on the owned iPhone17Pro iOS26
simulator. Coverage includes collection/history, readiness, remembered options,
payment links and refunds. [Results](../../design/evidence/onsite-payments/focused-tests.json)
and [four Swift fingerprints](../../design/evidence/onsite-payments/swift-sha256.json).
No actual card charge, banking action or physical-reader qualification was performed.

One fresh independent review approved the scoped implementation, with0Critical,
0Important and1Minor: the unrelated receipt had a different amount, leaving exact
attempt-key comparison independently unprotected. Root regraded this Important
because identity is the central financial guarantee. A same-amount/different-attempt
test failed when only the key comparison was removed. A further workspace-change
test exposed that previously published history could survive API invalidation.
Verified history now carries its request-generation UUID; stale context cannot
confirm success, even before a replacement load begins. Both checks failed first.
After restoration and the generation fix, final qualification passed48/48, zero
failures/skips, on the final source. No deferred minor remains. Manual card/check,
new tenders, physical-provider qualification and existing retry/relaunch/expiry
remain explicit subsequent work; the distribution gate continues to prevent exposure.

User authorization permits continued inline implementation without repeated menus;
reviewable changes can be revised if that judgment is wrong. Focused important
checks follow the user's explicit preference over repetitive full CI.

The [spec](../specs/2026-10-29-onsite-payments.md) records secure keyed card entry,
check capture, cash, ACH and other truthful construction tender requirements.
BYR-436 now includes those requirements and the separate distribution hold.
Native keyed card public configuration/account routing is not yet an established
contract; current continuation explicitly supports browser use. Check capture needs
private payment evidence storage. Capture-only versus electronic deposit remains a
pending user choice. No check capture/deposit or new charging method is claimed.

Build76 remains the already verified TestFlight release. This next batch has not
been uploaded and does not retroactively change that archive.
