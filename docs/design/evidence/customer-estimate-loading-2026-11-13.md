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
Four targeted integrated tests are prepared for partial publication isolation,
cancellation, supersession and handoff retry; their path-keyed URLProtocol
fixture avoids assigning responses by concurrent request arrival order. These
tests have only been parsed, not compiled or run on iOS. Older queue-based
tests still need migration or confirmation before this can ship.

The 40-estimate customer fixture and selection test are prepared but unrun.
There is no iOS build, integrated URLProtocol test, real offline cache,
server paging, realistic performance timing, accessibility, multi-estimate
approval or simulator evidence for this candidate. Existing URLProtocol tests
use an ordered response queue and may require keyed responses for safe
out-of-order requests. Scope, response provenance, partial loading/failure
copy, cancellation, action eligibility and the shared consumers of
`JobDocumentCollections` require independent review. Do not release yet.

## Per-response estimate provenance (13 November)

`EstimateDetails.fetch` previously classified a returned estimate by looking at
the API client's shared saved-copy marker for its path. A separate request for
the same path can clear that marker after the original response was served from
disk. The extracted production-loader host probe reproduces this interleaving
with a deterministic stub: before the change a saved estimate could be marked
fresh and an otherwise complete page could become actionable. That probe fails
on the prior loader and passes when each record is classified using its own
`APIRead` provenance. This is a simulated race, not an observed production
incident. A URLProtocol test was added with overlapping actual API reads: one
falls back to a verified saved copy while a held network read later clears the
shared marker; it checks each response retains its own provenance. The native
test is unbuilt and unrun, and does not directly schedule the loader's return
interleaving. The host test exercises the loader with a stub, not URLSession.
No claim of server or intermediary freshness, device concurrency coverage, or
full customer approval safety follows from these tests.

A second host regression exposed that a URLSession response whose local cache was
not bypassed could still be marked fresh. It failed before the follow-up: the
loader now first requests cache-bypassing estimate details, and only on a network
error attempts the ordinary saved-copy path for display. A response is eligible
for a customer decision only when its own provenance says URLSession bypassed
the local cache. The host probe verifies a protocol-cache response remains
visible but leaves the set incomplete. Native offline and concurrent tests are
still unrun; `no-cache` does not establish intermediary or server freshness.

A separate host regression found that the shared job collection could retain a
saved estimate while still reporting `isComplete`. The loader now marks any
nonfresh detail incomplete. It also first reads all membership pages under the
existing task-local live-only scope and, only after a network failure, uses the
ordinary offline read while marking membership and all rows nonfresh. This
avoids relying on the shared path marker, which another request can clear. The
host probe simulates a cleared marker, confirms a saved membership remains
visible but incomplete, and confirms 403 does not invoke the offline fallback.
The iOS URLProtocol test seeds and verifies readable saved membership and detail
copies, then expects both to remain visible and incomplete after cache-bypassing
network attempts fail. It is prepared but has not been built or run. The host
tests exercise the production loader with a stub, not actual URLSession timing.
