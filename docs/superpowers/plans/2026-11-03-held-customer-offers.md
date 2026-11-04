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
