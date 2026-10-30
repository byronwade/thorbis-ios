# Activity fallback — work in progress

## Change

Activity rows with a verified subject continue to use their existing record route. Rows without one now open a read-only sheet containing only feed-provided title, optional body and date. No related invoice, customer or job is inferred. The detail checks actor, organization, session generation, authority revision and the relevant view capability before showing its captured content. Call sites include the job, invoice, customer activity and customer compiled records. Pending job notes preserve their waiting/failed state and body.

## Evidence

- Existing customer payment fixture loads but has no selectable button before the change. `/private/tmp/activity-fallback-red2.xcresult` and log record this behavioral failure. The preceding red run did not first establish row loading and is not relied on.
- `/private/tmp/activity-fallback-final-check.xcresult` and log: 16 focused unit tests (existing activity mapping, release notes and a new same-session customer capability revoke/regrant scope test) and one UI test passed. The UI test opens the unlinked payment without navigating to an invented invoice.
- The first scope test failed to compile because the new scope type did not yet exist; that was not a behavioral red. The passing test exercises real SessionController revalidation and verifies old scope remains invalid after regrant.
- The build and tests ran on dedicated simulator `F82BCAFD-63EE-429A-A6CC-2AC9BE5DB850`. No production release has been made.

## Open checks

Independent review is required, especially for permissions across all five call sites, scope changes, sheet lifecycle and data retention. Large Dynamic Type, long multi-paragraph body, VoiceOver, iPad, live on-screen authority revocation, job pending-note interaction, and customer compiled-record/invoice navigation need focused verification. The existing mapping's missing-ID behavior remains intact and its tests passed; this run does not establish every activity feed or all app routes. The user-facing release note is included but is not evidence of release.
