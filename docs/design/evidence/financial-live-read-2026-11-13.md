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

## Integrated iPhone simulator check

On 13 November, four selected `FieldAPITests` passed in
`financial-live-read-green-retry-1113.log`: invoice and estimate requests each
used `reloadIgnoringLocalCacheData` and `Cache-Control: no-cache`; ordinary
reads used the existing scoped saved copy while offline, and their respective
live reads attempted the network and rejected the offline result. The first
build did not execute tests because two new fixture references failed to compile;
commit `f60b50d7` corrected them before the passing retry. This tests the app's
URLProtocol path on an iPhone simulator; it does not prove freshness of a server
or intermediary, authorization after role changes, or safe draft recovery.
