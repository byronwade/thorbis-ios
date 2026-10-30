# Customer List Performance Implementation Plan

**Goal:** Reduce customer-list rendering work without hiding customers or changing search, sections, job counts, or visit selection.

**Architecture:** Group jobs by customer once per view update and calculate each visible row from its group. Make customer rows direct lazy-stack children using lazy sections. Keep existing complete customer fetch semantics until server search and pagination are designed together.

**Tech Stack:** SwiftUI, XCTest.

**Verification:** Compare grouped summaries with existing customer-scoped summary selection, including completed jobs and unrelated customers; run customer-list UI coverage and confirm behavior at large volume. Record device/runtime constraints and do not infer network pagination improvement from rendering changes.

- [ ] Add a regression for per-customer job grouping and representative selection.
- [ ] Implement the grouped snapshot and lazy section layout.
- [ ] Run focused tests and review changes for correct search, section ordering and updates.
