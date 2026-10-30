# Job media paging implementation plan

**Goal:** Show a bounded first page of a job's photos and documents promptly, with an explicit way to load the rest and honest partial counts.

**Architecture:** Add a single-page job-media API while retaining the existing full-list API for other consumers. The job media view owns its cursor, request identity and loaded records; each request is bound to the current actor, workspace, job, permission, policy, session, API origin and request generation. Invalidation synchronously hides stale content. Filters apply to loaded items and explicitly say more may be available; loading more traverses the unfiltered feed, including documents and untagged photos. Existing thumbnails and local pending uploads remain unchanged.

**Tech Stack:** SwiftUI, XCTest, cursor-paged Thorbis API.

**Review focus:** later pages with matching filters; duplicate/cursor loops; concurrent refresh and pagination; authorization and workspace loss/regrant; failed pages and existing local pending media.

1. Prove current all-page behavior with a failing first-page request test. Add an API that makes a single bounded page request and checks returned cursor and job/tenant scope.
2. Implement a paging state machine which rejects duplicate/stale responses, loops and scope changes; test first page, load-more, refresh, late result, error/retry and authorization loss.
3. Integrate state into job media; distinguish partial counts and empty filter results from complete data; retain add, retag, pending, photo, document and refresh actions.
4. Verify focused API and state tests, simulator journeys, accessibility and privacy review. Record that customer-wide photo aggregation and server-sized image thumbnails are separate follow-up work.
