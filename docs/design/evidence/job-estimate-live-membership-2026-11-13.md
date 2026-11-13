# Live job-estimate membership reads — 13 November 2026

The customer approval path rechecks all job-estimate membership pages via `liveFieldJobEstimateLinks`. Previously the wrapper called its paged reader without the `SavedCopies.liveOnly` task-local scope, so `URLSession` could apply protocol caching; a path-level saved-copy marker alone did not guarantee an uncached read. This is a code-path finding, not a demonstrated incorrect production approval.

The wrapper now scopes the entire paginated read to `liveOnly`. Ordinary membership browsing is unchanged and can still use its saved copies. The existing generation, cancellation and job-scope checks remain unchanged.

`python3 scripts/tests/test_job_membership_live_host.py` exercises the actual wrapper against a two-page stub: baseline reported `[false, false]` and failed; the corrected wrapper reports `[true, true]` and unwinds after an error. `python3 scripts/tests/test_financial_live_read_host.py` also passed. This host test does not run URLSession or the iOS app.

Two URLProtocol integration tests were prepared: one checks every real request in a two-page read uses `.reloadIgnoringLocalCacheData` and `Cache-Control: no-cache`; the other checks that a live read refuses an offline saved copy while ordinary browsing can use it. Their later hosted iPhone results are recorded below. Real server/proxy freshness, concurrent same-path provenance and actual signing remain unverified. No release/deployment claim.

The path-level saved-copy marker is shared with ordinary concurrent reads and is not provenance for a particular live request. A deterministic host stub simulating a same-path ordinary saved read caused the original `requireLive(path)` check to reject a successful live read; the wrapper now relies on the scoped live-only read, which prevents saved copies on each page, instead of that shared marker. The host regression passed after removing the marker check. This is a stubbed interleaving; actual URLSession / actor scheduling and concurrent offline copies remain unverified on iOS.

## Focused hosted iPhone verification

The full-scheme PR #478 run [43366455386](https://github.com/byronwade/thorbis-ios/actions/runs/43366455386) was cancelled in its simulator step after approximately 41 minutes and does not establish a test pass. To obtain the important native evidence without changing the release workflow, temporary draft PR #481 used product source from exact #478 head `7f2cd2db6d7719c6f53c22203844408bc6408dc0` and added only two `-only-testing` workflow selectors. Its first hosted run [43371539180](https://github.com/byronwade/thorbis-ios/actions/runs/43371539180) passed both selected tests.

The follow-up strengthened the offline test to seed and verify an actual nonempty saved page, prove ordinary offline browsing returned it, and assert the exact network error, path, cache policy and no-cache header. Hosted run [43372686163](https://github.com/byronwade/thorbis-ios/actions/runs/43372686163), temporary head `7d362b5c45cf7177a1c8e5146b02abf6f3635005`, explicitly ran and passed both selected tests (2 tests, 0 failures; `TEST SUCCEEDED`). That temporary branch differs from this branch only in its workflow selectors; its tested product and strengthened test source match this branch. The temporary workflow change is not part of this PR and must not be merged.

These focused tests do not establish a full-scheme pass, real server or intermediary freshness, an atomic membership snapshot during mutation, concurrent URLSession scheduling or end-to-end signing. Ordinary saved-copy browsing and per-page cache policy are covered only in the selected fixture scenarios.
