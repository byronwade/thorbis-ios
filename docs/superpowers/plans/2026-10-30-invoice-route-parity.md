# Invoice Route Parity Plan

**Goal:** Make invoice return and payment selection consistent for every way a technician reaches a job, while preserving the native navigation and all existing screens.

**Architecture:** Each actual `NavigationStack` owns its own typed path and owner; invoice return events are scoped to the job presentation, actor, organization, session and API generation. Never reuse an outer owner's environment in an independently owned stack. Keep the experiment DEBUG-only until every route is tested and reviewed.

**Evidence:** `docs/typed-tablet-invoice-experiment.md` and `docs/superpowers/plans/2026-10-30-tablet-invoice-navigation.md`. The legacy customer entry reproduces a failed invoice opening in `/private/tmp/thorbis-typed-customer-red.xcresult`; candidate `e143902` compiled but its test runner did not start.

## Entry roots and acceptance checks

- Phone Jobs and Schedule: existing typed owners and equal-balance/payment-return tests; repeat on final integrated source and cover cancelled versus completed edge swipes, VoiceOver and keyboard.
- Phone Customers: `PaperNavigation.swift` customer path and `PaperCustomerViews.swift` job links. Verify customer list, customer record deep link (including unloaded customer), saved-customer entry, both customer job links, actual invoice open, return, exact selection and scope changes. Candidate `e143902` is unverified.
- Phone More: `phoneTabs` uses `morePath`; recent items, record links and job links append it. Give this stack its own owner and typed path, adapt each programmatic append/reset, and test all More routes plus invoice return from a job. Do not alter saved records or feature availability.
- Phone custom tabs: each `customPaths[item.rawValue]` belongs to a distinct stack. Use an owner and typed path keyed by stable tab identifier; preserve path when changing tabs, discard return event only for the changed stack, and verify separate custom tabs cannot consume each other's events. Test custom-tab job links and existing section navigation.
- Search: `PaperGlobalSearch` has an independent stack and deliberately clears inherited owner. Give it its own owner, cover both embedded tab and sheet, and verify search result navigation, cancellation, job return and search text. Do not route these events into the host tab's owner.
- Saved work: `SavedWorkReviewView` has its own path and explicitly clears inherited owner. Preserve recovery, authorization and offline actions; test opening a job then its invoice and returning to the same work item.
- New job: `NewJobSheet` owns an independent stack and clears inherited owner. Test creation, opening the saved job, invoice return, sheet dismissal and authority changes without duplicating creation.
- Tablet: single owner at the visible detail stack; tested normal job deep link and Schedule job switching. Test customer, estimate and invoice record links, price book and saved drafts, map selection, job creation and other tabs on narrow and wide configurations.

For each root, write the actual-open/equal-balance regression before wiring its owner, verify the red failure, make the smallest migration, and run the same test plus navigation parity before checkpointing. An invoice detail opening by itself is insufficient: after Back, `Collect payment` must name the explicitly opened invoice, and a stale or changed invoice must fail closed with recovery guidance. A failed simulator startup is not a passing or failing app test.
