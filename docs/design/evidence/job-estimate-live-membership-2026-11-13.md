# Live job-estimate membership reads — 13 November 2026

The customer approval path rechecks all job-estimate membership pages via `liveFieldJobEstimateLinks`. Previously the wrapper called its paged reader without the `SavedCopies.liveOnly` task-local scope, so `URLSession` could apply protocol caching; a path-level saved-copy marker alone did not guarantee an uncached read. This is a code-path finding, not a demonstrated incorrect production approval.

The wrapper now scopes the entire paginated read to `liveOnly`. Ordinary membership browsing is unchanged and can still use its saved copies. The existing generation, cancellation and job-scope checks remain unchanged.

`python3 scripts/tests/test_job_membership_live_host.py` exercises the actual wrapper against a two-page stub: baseline reported `[false, false]` and failed; the corrected wrapper reports `[true, true]` and unwinds after an error. `python3 scripts/tests/test_financial_live_read_host.py` also passed. This host test does not run URLSession or the iOS app.

Two URLProtocol integration tests are prepared but **not run**: one checks every real request in a two-page read uses `.reloadIgnoringLocalCacheData` and `Cache-Control: no-cache`; the other checks that a live read refuses an offline saved copy while ordinary browsing can use it. iOS build, real server/proxy freshness, concurrent same-path provenance and actual signing remain unverified. No release/deployment claim.

The path-level saved-copy marker is shared with ordinary concurrent reads and is not provenance for a particular live request. A deterministic host stub simulating a same-path ordinary saved read caused the original `requireLive(path)` check to reject a successful live read; the wrapper now relies on the scoped live-only read, which prevents saved copies on each page, instead of that shared marker. The host regression passed after removing the marker check. This is a stubbed interleaving; actual URLSession / actor scheduling and concurrent offline copies remain unverified on iOS.
