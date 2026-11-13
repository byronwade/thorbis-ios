# Job estimate membership paging prototype — 13 November 2026

This is an isolated, **unwired** coordinator, not user-facing paging. It permits one job-link page per explicit request, rejects foreign job links, duplicate link IDs, repeated/empty cursors and retired authority, and deduplicates estimate IDs. Network failure leaves the current cursor retryable. `allPagesAuthoritative` requires the caller to provide an independently verified provenance for each page. An exhausted cursor is not a frozen server snapshot; approval must separately revalidate each selected estimate's job association and issued revision.

Host command:

```sh
swiftc -swift-version 6 -parse-as-library Thorbis/Sources/JobEstimateMembershipPager.swift scripts/tests/job_estimate_membership_pager_host.swift -o /private/tmp/job-estimate-membership-probe && /private/tmp/job-estimate-membership-probe
```

The synthetic host probe passes single-demand paging, scope retirement after await, foreign job rejection, unverified saved-page gating, cursor-loop rejection, failed-page retry, duplicate estimate IDs and concurrent invocation. The initial test-first compilation failed because the type/file was not yet present; it was a compile failure, not a demonstrated production behavior failure.

Not established: real API adapter / URLSession response provenance, iOS compilation or UI, saved-copy behavior, mutation across pages, exact approval membership/revision revalidation, accessibility, a Load more action, or actual memory/network measurements. This does not address invoice paging. The existing production handoff continues to load all link pages and estimate details. No feature or performance claim is made from this probe. Do not expose this coordinator or use it to enable approval without those integration checks.
