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

## Provenance follow-up — incomplete, do not release

Independent review found the original candidate captured authority at tap rather than at feed publication. Customer history now associates entries and cursors with the actor, organization, customer, generation and authority revision that authorized the response, and checks this scope after the history await. The compiled customer-record fallback uses its original `CustomerRecordsScope`. Unlinked job and invoice rows are intentionally held without the new fallback until their source provenance is established. This does not satisfy the full selectable-activity request.

A focused build and prior customer fallback UI and scope tests passed after the first customer scope change (`/private/tmp/activity-source-scope-test.xcresult`); the later source changes have not been fully retested. A debug-only authority fixture was added. The first UI attempt ended in an infrastructure SIGTERM before bootstrapping. The second failed because the test expected a Customers tab after regrant, while its recorded hierarchy showed the restored activity view and refreshed row; it had observed the old row disappear. The test was corrected but has not yet been rerun. Its runner remained live collecting simulator diagnostics at this writing (`/private/tmp/activity-customer-cycle.log`). These observations do not prove the transition window, late-response rejection or overall scope safety.

Outstanding blockers: independent review of the customer change and original `CustomerRecordsScope` conversion; behavioral tests for revoke/regrant before tapping, delayed history and pagination, actor/workspace/customer switch, and on-screen revocation; job notes' post-await check and cache-write provenance; offline note cache keyed only by job ID with no actor/workspace envelope; pending notes; invoice history provenance; and correct behavior when authorization changes while a sheet is open. Large text, VoiceOver, iPad, and all remaining activity feeds remain unverified. Preview fixture controls must be excluded from any release archive. No merge or release is authorized by this record.

The corrected single UI scenario passed in `/private/tmp/activity-customer-cycle-corrected.xcresult`: after same-session customer permission revoke/regrant, the old payment row disappeared and a different, delayed fresh history row appeared. This checks that scenario, not a delayed old response arriving after regrant or tenant/actor changes; the other blockers above remain open. The Xcode process exited successfully. The branch remains held from release.
