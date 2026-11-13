# Job document shortcuts implementation plan

**Goal:** Keep a technician's path between a job's estimates and invoices visible while scrolling its Money page.

**Approach:** Keep the current two jump actions in the existing pinned section header, preserving the same scroll targets, permission gates, job scope, and payment routes. At accessibility text sizes, keep the section chooser fixed and place the jumps in the pinned header below the job header, to avoid permanently consuming additional screen height.

**Alternatives:** Separate full job tabs for estimates and invoices would change the information architecture and crowd the existing sections; leaving shortcuts at the top requires a long return scroll. Pinned shortcuts preserve existing flow and make both destinations reachable.

**Verification:** First show the current shortcuts disappear after scrolling. Then check both remain tappable at the invoice end, return to estimates, retain the selected invoice for collection, and do not cover content or actions. Check accessibility text, VoiceOver labels, phone and iPad as feasible. Review scope and existing permission conditions. Record untested cases rather than claiming them.

## Evidence and open checks

- Baseline, 2026-11-12: the focused `testMoneyShortcutsStayAvailableAfterScrollingToInvoices` reached a hittable invoice, then failed because the Estimates shortcut was not hittable. Log: `/Users/byronwade/testflight-work/job-document-shortcuts-baseline-1112.log`. Xcode was still packaging the result when this checkpoint was written.
- The code change and its normal-text, largest-text, geometry and selected-invoice tests have **not** yet been built or run. They are not qualified for release.
- Independent source review found no confirmed route, permission or selection regression, but requires green simulator evidence, long-list reachability, permission-denial coverage, iPad, and safe-area/foot geometry.
- At accessibility sizes the fixed section chooser remains above the scroll view. The shortcuts start below the job header and pin only when that header scrolls away; they are not claimed initially visible.
- The worktree's `project.yml` local Stripe override is for this machine only and must not enter the commit.
