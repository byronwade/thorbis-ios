# Customer estimate loading experiment — held

The current job estimate loader first reads every membership page, then requests
each estimate detail serially and publishes only after the full set completes.
This candidate uses at most four in-flight detail requests, publishes a first
partial result after four finishes and later updates, preserves membership order,
and marks every partial `isComplete = false`. It also uses a lazy stack for the
customer overview. All link pages and all details are still fetched eventually:
this is **not demand paging** and does not complete the large-list requirement.

The host probe extracts the actual production loader into a standalone Swift
program with a deterministic API stub. It passed bounded concurrency, stable
ordering despite out-of-order responses, partial publication, retryable stale
retention, denied and mismatched records, and invalidation before/after a
partial. A scheduler probe passed bounded operation count and cancellation.
The original serial loader was checked retrospectively against an earlier
concurrency assertion and failed as expected; this was not strict test-first.

Review found global partial publication falsely made other consumers report a
load failure and could leave a stranded partial. Partial reads now go only to
the requesting handoff, with an explicit loading marker; the shared collection
publishes only completed or failed final reads. If the handoff's load returns
without publishing while authority remains current, it shows a retryable error
and keeps the previous selection. This revision is source-reviewed only and
requires integrated cancellation, supersession and shared-consumer tests.

The 40-estimate customer fixture and selection test are prepared but unrun.
There is no iOS build, integrated URLProtocol test, real offline cache,
server paging, realistic performance timing, accessibility, multi-estimate
approval or simulator evidence for this candidate. Existing URLProtocol tests
use an ordered response queue and may require keyed responses for safe
out-of-order requests. Scope, response provenance, partial loading/failure
copy, cancellation, action eligibility and the shared consumers of
`JobDocumentCollections` require independent review. Do not release yet.
