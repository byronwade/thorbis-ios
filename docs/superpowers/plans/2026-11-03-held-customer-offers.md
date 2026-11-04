# Held customer offer selection implementation plan

**Goal:** Let a customer review issued optional work and request an exact server quote, behind the disabled offer capability.

**Architecture:** A token-authorized server endpoint derives customer-safe available offers from the locked issued revision and verified paper. The native client uses this discovery and the existing server quote/approval contracts; it never treats catalog data or local arithmetic as acceptance authority. Changes invalidate quote and consent; scope/session/generation retirement drops results.

**Tech stack:** Existing TypeScript domain/API, SwiftUI and XCTest, PostgreSQL integration fixture.

1. Add failing route tests for authorized discovery, applicability, safe projection, invalid token and default-held behavior. Implement the locked snapshot-derived endpoint and an explicit schema. Verify no nonce consumed or quote written and pricing matches a subsequent quote.
2. Implement gated native DTO, request and selection state with strict identity, generation and quote/consent invalidation. Test unknown fields/choices, quantity boundaries, stale replies and server money. Do not expose until both feature admission and backend rollout are qualified.
3. Integrate offer browsing and exact quote review into existing customer presentation with Paper's Q6N-0/VUI-0 hierarchy, customer typography and clear back/error actions. Preserve unrelated approvals, technician features and job context. Capture simulator/large-text evidence when scheduled.
4. Independently review code and record tested source, limits and rollout prerequisites; do not merge or deploy unfinished flows.

## Candidate status

The isolated implementation is **held and incomplete**: the customer shop, choice state, server discovery/quote transport, offer-bound decision and per-estimate handoff evidence are staged behind `CustomerOfferCapability.isEnabled == false`. The server contract remains unmerged and unavailable in production. No technician offer-preparation UI, full native typecheck, simulator, VoiceOver, device, loss/retry, customer-facing screenshot or full integration qualification has been completed. This is not a TestFlight feature.

The pure Foundation cart harness ran via `swiftc` and checks valid discovery, quantity validation, quote calculation, fractional expiry parsing, changed-selection invalidation and stale quote retirement. Source syntax parsing passed. It is not an iOS app build or end-to-end approval evidence. Review all asynchronous identity, scope, consent, expiry and uncertain-decision paths before any enabling. Backend fixture evidence is recorded in its separately held branch; its SQL fences and production gate remain off.

Follow-up source changes address review findings: signature fallback now uses the quoted total; financing is hidden for this held offer path; re-opening the shop restores validated choices; the standalone signing path retains its original quote-bound token; and restoring the same handoff option does not discard its quote. Both discovery and quote require contract version 1. The standalone Foundation harness passed with matching source hashes (`/private/tmp/thorbis-held-native-cart-{before,after}.sha`, `/private/tmp/thorbis-held-native-cart-run.log`); XCTest source and UI remain unrun and untypechecked. No device, VoiceOver, full lifecycle, consent/retry, multi-estimate or release qualification is implied. The backend and native payload fixtures have not yet been cross-tested. The rollout gate remains false.

Further held source changes bind a review to token, paper hash, revision, option and API generation, invalidate the parent quote when a choice changes, gate long-description sheets on current authority, and compare customer-visible acceptance evidence to the quoted ID, identity, signer, selections and total. Standalone uncertain submissions retain the exact in-memory decision and prevent editing while pending. This is not a durable process-relaunch journal and remains held. The pure state harness exercises scope and selection invalidation only; receipt XCTest and all UI/lifecycle scenarios remain unrun, including cross-workspace loss of authorization, explicit sheet dismissal and unknown-response replay. A same-process UI callback cannot establish server authorization. Do not enable without native typecheck, UI tests, backend cross-contract and independent review.

A follow-up preserves an exact previously submitted in-memory decision for retry after quote expiry; fresh decisions still require an unexpired quote. This matches the held server's replay distinction but is only covered by the Foundation state harness so far. There is no status-check UI or process-relaunch recovery, so do not treat this as complete uncertain-outcome handling.

Paper reference inspected: Thorbis Mobile Q6N-0, token hash `2803f4aa`; the held shop adopts the existing native customer commit and secondary button, a scrollable action area for accessibility sizes, and a read-only full description sheet. This is an unrendered adaptation, not evidence of visual parity or accessible interaction.

An additional held source pass normalizes the signer consistently with server acceptance, checks sheet return against the still-current token/revision/option, and shows invalid discovery as an error rather than leaving a spinner. Stale quote responses are discarded. These paths are syntax-parsed only and remain awaiting the native lifecycle and authorization tests.
