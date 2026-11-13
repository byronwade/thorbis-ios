# Financial live reads: local verification

The estimate and invoice methods used for signatures, customer handoff and editing
called their ordinary read outside the `SavedCopies.liveOnly` task-local scope.
Their ordinary endpoints bypass the app's recent-response reuse, but their
URLRequests used the default protocol cache policy. A previous saved-copy result
was also allowed to flow through the ordinary path before `requireLive` rejected it.

The methods now use the same scoped live-only read as `liveFieldJob`. Normal
`fieldEstimate` and `fieldInvoice` reads continue to support saved copies.

On the unchanged wrappers the host probe failed with observed live-only values
`[true, false, false]` for job, invoice and estimate. After the correction,
`python3 scripts/tests/test_financial_live_read_host.py` passed. It inserts the
actual wrapper bodies and request-policy fragment into a stub host client and
checks the scoped state, constructed cache policy and header, and unwind on error.

This is not an integrated URLSession test, iOS build, server freshness proof,
permission check, or draft-recovery proof. The two URLProtocol fixture tests in
`FieldAPITests.swift` remain unrun. Live financial reads intentionally fail when
offline; ordinary read-only field views retain their existing offline behavior.
