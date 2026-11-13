# Job estimate membership paging prototype — 13 November 2026

This is an isolated, **unwired** coordinator, not user-facing paging. It permits one job-link page per explicit request, rejects foreign job links, duplicate link IDs, repeated/empty cursors and retired authority, and deduplicates estimate IDs. Network failure leaves the current cursor retryable. `scanUsedOnlyFreshResponses` requires the caller to provide an independently verified provenance for each page. An exhausted cursor is not a frozen server snapshot; approval must separately revalidate each selected estimate's job association and issued revision.

Host command:

```sh
swiftc -swift-version 6 -parse-as-library Thorbis/Sources/JobEstimateMembershipPager.swift scripts/tests/job_estimate_membership_pager_host.swift -o /private/tmp/job-estimate-membership-probe && /private/tmp/job-estimate-membership-probe
```

The synthetic host probe passes single-demand paging, scope retirement after await, foreign job rejection, unverified saved-page gating, cursor-loop rejection, failed-page retry, duplicate estimate IDs and concurrent invocation. The initial test-first compilation failed because the type/file was not yet present; it was a compile failure, not a demonstrated production behavior failure.

A real one-page API adapter and two URLProtocol tests are prepared, but not built or run. The adapter records response provenance and checks origin, request generation and saved-copy scope revision around the request. Its default non-fresh mode retains the existing saved-copy path; callers must explicitly require a fresh read for a current-response claim. UUID-like identity and cursor comparisons normalize letter case.

Not established: real API adapter / URLSession response provenance, iOS compilation or UI, saved-copy behavior, mutation across pages, exact approval membership/revision revalidation, accessibility, a Load more action, or actual memory/network measurements. This does not address invoice paging. The existing production handoff continues to load all link pages and estimate details. No feature or performance claim is made from this probe. Do not expose this coordinator or use it to enable approval without those integration checks.

Independent review found that a completed scan cannot establish current authority or a stable membership snapshot. The API now names its properties as historical scan facts, and a host check shows subsequent operations reject retired authority even though those historical facts remain true. Identity comparison for links, estimate IDs and cursors is case-insensitive; a host regression failed before this change and passed afterward. The page adapter requires an explicit current-authority closure instead of defaulting to true.

Additional URLProtocol test source covers cursor-scoped saved pages, denying fresh use of offline copies, 403 propagation, and authority retirement while a request is in flight. These tests have only been parsed and have not been run in iOS/Xcode. They do not replace a real server snapshot, selected-membership revalidation or a user-facing page flow.
