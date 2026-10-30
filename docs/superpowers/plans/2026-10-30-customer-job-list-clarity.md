# Customer and Job List Clarity Implementation Plan

**Goal:** Make finding and distinguishing customers and jobs easier while retaining all existing list actions.

**Architecture:** Keep the existing SwiftUI list and filtering flows; expose the job search field directly and derive a customer's upcoming scheduled visit from the cached jobs using a deterministic, customer-scoped selector. Let long names and job titles wrap rather than compressing them into one line.

**Tech Stack:** SwiftUI, XCTest, XCUITest; iOS 18+.

**Design reference:** `docs/design/paper-VNB-0.json`, `docs/design/paper-VKG-0.json`, and `docs/design/ios-golden-rules.md`.

## Constraints and review focus

- Preserve assignment, ordering, status filters, customer scopes, creation, context menus, refresh, and offline behavior.
- Do not infer that an unscheduled, invalid, past, completed, canceled, or other customer's job is the next scheduled visit.
- Handle equal times deterministically; do not rely on array order.
- Preserve accessible and long text; don't allow icons to crowd out content.
- Verify search changes the visible list and clearing it restores results; test filter access remains separate.

## Steps

1. Add focused tests for customer-specific upcoming visit selection, including wrong customer, invalid time, historical and canceled jobs.
2. Implement the selector in `JobFiltering` and use it for customer list summaries; keep the job count even when no next scheduled visit is known.
3. Place job search directly on the list while preserving Display filters; allow long row titles to wrap.
4. Verify focused selection and list interaction tests on a coordinated simulator, then capture a representative preview for review.
