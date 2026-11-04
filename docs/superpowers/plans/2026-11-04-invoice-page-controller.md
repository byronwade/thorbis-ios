# Bounded invoice page controller

**Goal:** Provide a safe on-demand controller for the existing invoice cursor endpoint without changing the current complete-search UI until the server search contract is qualified.

**Approach:** Fetch one server page per explicit request; bind every result to the initiating actor, organization, authority revision, API generation, origin and saved-copy namespace. Reject cursor loops, duplicate/foreign invoice IDs, and late results. Retain verified rows and retry on transient errors; clear rows on definitive access denial. Mark a cursor-backed collection incomplete and never claim totals for unloaded records. This is a held, unwired prerequisite; offline and search presentation are not changed.

**Offline boundary:** This held controller requires a fresh online response because current saved copies are not bound to a resource-scope grant. It does not replace the existing list. Integration requires a scope-safe offline solution, complete scoped server search, and immediate owner-context invalidation.

**Verification:** Reproduce existing eager fetch with a two-page fixture, then verify explicit next-page behavior, failed-page retry, denial retirement, cursor/identity validation, and delayed scope change. Focused simulator tests and independent source review are required before integration. Do not claim a performance measurement or complete search from the controller alone.
