# Tablet Invoice Navigation Implementation Plan

**Goal:** Keep the tablet Schedule list visible while opening and returning from the correct job invoice using one native navigation owner.

**Architecture:** In the DEBUG preview experiment, the existing tablet path and owner move to the Schedule detail stack when Schedule is selected; there is no outer stack around that detail. Other tablet sections retain their root stack using the same path and owner. Schedule selection clears the shared path and pending return before changing the selected job. Existing deep links continue to set the tablet section and append to the shared path; destinations and environment use the same owner. Production remains on its existing path until all roots and tests are verified.

**Tech Stack:** SwiftUI NavigationStack, XCTest UI and unit tests.

**Spec:** `docs/typed-tablet-invoice-experiment.md`; existing tablet Schedule behavior and job/invoice identity requirements.

## Review Focus

- Selecting a different job must discard pending invoice return state and show only the newly selected job.
- Job and record deep links must still open their requested target on tablet, including an unloaded customer.
- Invoice A and invoice B with identical balances must retain the explicitly opened invoice after Back; payment must not default to B.
- An invalidated user, workspace, API session, permission, or changed invoice must not permit stale collection.
- A cancelled interactive Back swipe must not update selection; a completed Back must, for accessibility and ordinary touch.

## Task 1: Establish tablet Schedule ownership

**Files:** `Thorbis/Sources/PaperNavigation.swift`, `Thorbis/Sources/PaperTabletSchedule.swift`, `Thorbis/Sources/PaperTypedJobsNavigation.swift`, `ThorbisUITests/JobDocumentsUITests.swift`.

- [x] Keep the failing `testTypedTabletScheduleRetainsSelectedInvoice` assertion that the Invoice navigation bar actually opens and Back returns before collecting the same invoice. Baseline failure: `/private/tmp/thorbis-typed-tablet-detailassert.xcresult`.
- [x] Pass the tablet root's `[PaperTypedJobsRoute]` binding and `PaperTypedJobsOwner` to Schedule in the experiment. Build the Schedule list outside the single detail NavigationStack, with its existing typed destination and menu destinations registered on that stack. Other tablet tabs retain their stack. Remove the distinct nested route wrapper.
- [x] Run the existing explicit-open Schedule and outer Jobs tests on iPad, together with equal-balance selection and same-invoice collection assertions. Both passed without changing the tests to accept underlying row text: `/private/tmp/thorbis-tablet-single-owner.xcresult`.
- [x] Add a second-job selection regression proving that changing the Schedule selection after an invoice return clears the pending return and cannot collect the prior job's invoice. Passed in `/private/tmp/thorbis-tablet-single-owner-parity.xcresult`.

## Task 2: Deep links and navigation parity

**Files:** `Thorbis/Sources/PaperNavigation.swift`, `Thorbis/Sources/PaperTabletSchedule.swift`, `ThorbisUITests/JobDocumentsUITests.swift`.

- [ ] Add tablet job, customer, invoice and estimate deep-link UI tests asserting actual destination navigation and Back. Test an unloaded customer and a different selected Schedule job. The different-job link passed in `/private/tmp/thorbis-tablet-single-owner-parity.xcresult`; the other record links remain unverified.
- [ ] Preserve price book, saved drafts, job creation, settings, and Schedule map; test each entry point and its return path. Fix only identified route regressions.
- [ ] Verify successful and cancelled edge swipes and native VoiceOver/keyboard activation, as well as revoked authority and stale-record recovery. Keep unverified cases explicitly documented.

## Task 3: Release qualification

- [ ] Run all relevant iPhone and iPad route, payment-identity, permissions and refresh regressions on the exact candidate; obtain independent code review.
- [ ] Remove diagnostic-only probes. Migrate remaining job entry roots and prove parity before enabling the typed experiment in production. Do not include this work in a TestFlight build until those checks pass.
