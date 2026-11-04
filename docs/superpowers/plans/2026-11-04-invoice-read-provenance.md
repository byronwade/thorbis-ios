# Invoice response provenance implementation plan

> **For agentic workers:** Use focused tests, independent review and exact-source evidence. Keep this additive slice held until the broader denial owner is qualified.

**Goal:** Carry source and request identity with each invoice response and each payment-history page without changing existing offline, pagination or payment behavior.

**Architecture:** Add provenance to APIClient's existing data response at the point where it returns URLSession or a saved copy, including request origin, scope, generation, path and cursor. Decode through an additive API. Existing callers retain their current wrappers. Add invoice and payment-history wrappers that return response-specific metadata. URLSession provenance must report the request cache policy and must not claim server freshness unless the caller required it. Do not treat this metadata as authorization or solve cancellation-denial delivery in this slice.

**Tasks:**
1. Add request-keyed tests covering offline copy versus a concurrent URLSession result on the same path, live-only cache policy, multiple history pages and existing wrapper behavior; establish baseline where possible.
2. Implement the additive data response metadata and typed wrappers while preserving existing caching, errors, cancellation and pagination semantics.
3. Run focused iOS tests with before/after hashes, obtain independent review, document scope and remaining durable denial/cancellation limitations. No deployment or release claim.

**Scope boundary:** history pagination captures a distinct saved-copy-scope revision and rejects a changed or A→B→A scope before/after every page. This detects changes to the saved-copy namespace, not authority revalidation while that value stays unchanged; full session/resource authorization is a separate requirement. The result does not carry response bytes or error/denial attribution, and local URLSession cache bypass does not by itself prove origin-server authorization.
