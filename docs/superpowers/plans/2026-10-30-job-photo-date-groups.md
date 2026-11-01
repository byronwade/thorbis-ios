# Job photo date groups implementation plan

**Goal:** Make a job's real photos easier to scan by captured day, consistent with Paper 21A.

**Architecture:** Derive display-only groups from already filtered, authorized media records using the recorded capture timestamp and the device calendar. Keep missing or invalid dates in a named group; retain server order within each day and the existing tiles, actions, filters, pending uploads and documents.

**Tech stack:** SwiftUI, Foundation, XCTest.

**Steps:**
- Add and run a failing UI test for the existing undated job photo and its existing filter and action.
- Add focused date grouping tests covering fractional/plain timestamps, timezone day boundaries, absent/malformed dates, ordering and preservation of every input.
- Implement the grouping and headers with local date formatting; leave data authority, selection and upload paths unchanged.
- Run focused tests and inspect the rendered screen; run applicable release-note checks and request independent review.

**Risks:** Parser compatibility, time zone changes, duplicate IDs, filter group updates and preserving large text and tile actions. Never infer a date from creation/upload time.
