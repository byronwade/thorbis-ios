# Job invoice navigation identity implementation plan

> **For agentic workers:** Execute and review each task separately. The integration and release gate is the last task; do not ship intermediate work.

**Goal:** Opening any fresh invoice for a job must navigate promptly, and returning to that job must make the same eligible invoice the target of collection after a fresh, scope-checked read.

**Architecture:** Replace opaque `NavigationPath` storage at each stack that can host a job with an inspectable typed path. A native value-based `NavigationLink` carries the job and invoice identity; the owning stack detects the pushed and popped route from its path binding and records the actual route transition. A job-scoped return coordinator clears the old payment model immediately, blocks collection while it refreshes, and enables it only if the refreshed invoice and payment model match the captured identity and current authority. Never derive selection from a gesture, view-builder evaluation, lifecycle callback on the invoice destination, or amount.

**Tech stack:** Swift 6, SwiftUI NavigationStack/NavigationLink, XCTest and XCUITest, iOS 18+.

**Spec:** `docs/design/ios-golden-rules.md`, `docs/design/ios-implementation-process.md`, and `docs/design/evidence/invoice-navigation/2026-10-30-semantic-link.md`.

## Global constraints

- Keep every existing route, native Back/swipe, document action, job scope and payment method; do not add an invoice choice to the ordinary last-opened flow.
- Use the active actor, organization, session generation, authority revision, job ID and invoice ID to reject stale navigation and asynchronous responses.
- Never expose a previous invoice's collection action during a transition or refresh. Failed or stale refresh must not silently select a different invoice.
- Keep the existing `JobDocumentsSafetyUITests.testEqualBalanceCardSelectsTheInvoiceCollectedAfterReturning` assertions intact; equal balances cannot identify an invoice.
- `NavigationPath` is opaque. Do not infer a path element by decoding an undocumented serialization format.
- Scope this work to the existing app/API contracts; do not invent server fields or persistence.

## Review focus

1. Open invoice A while invoice B has the same balance: collect must resolve A, including a fast tap immediately on return.
2. Open a paid invoice or an invoice removed/voided while open: no fallback to another invoice; show a recoverable unavailable state.
3. Change organization, actor, authority or job while a detail/refresh is active: stale route and responses never enable collection.
4. Navigate by VoiceOver, hardware keyboard, back button and interactive swipe-back: all use the same semantic route transition; cancellation must not count as a completed pop.
5. Cover phone, iPad schedule detail, job created in a sheet, custom tabs, customer-to-job links and deep links. Each stack must own its own path and not disturb unrelated navigation.

## File map

- `Thorbis/Sources/PaperNavigation.swift`: typed phone/tablet/custom paths, shared destination registrations, deep-link path construction and return coordinator injection.
- `Thorbis/Sources/PaperTabletSchedule.swift`: typed schedule-detail stack and per-stack coordinator.
- `Thorbis/Sources/Screens.swift`: typed job-creation sheet stack and coordinator; inspect all other local `NavigationStack` sites reachable from a job.
- `Thorbis/Sources/PaperJobDetailView.swift`: job-scoped value link, identity-bound return refresh and collection guard.
- `Thorbis/Sources/JobCommercialDocuments.swift`: existing scope and freshness checks; only extend identity types if needed, preserving API checks.
- `ThorbisTests/`: typed route transition and job-return policy tests; `ThorbisUITests/JobDocumentsUITests.swift`: existing end-to-end regressions plus the new tests below.

### Task 1: Prove typed route transitions without changing app navigation

**Interfaces:** Add a `PaperStackRoute: Hashable` with cases for existing `Job`, `Customer`, `PaperRoute`, and `jobInvoice` carrying a `JobInvoiceRoute` value. `JobInvoiceRoute` carries job ID, invoice ID, organization ID, customer ID, actor ID, session generation and authority revision. Add a pure `JobInvoiceRouteTransition` function that compares old and new `[PaperStackRoute]` and returns a completed invoice pop only if the exact top route was removed; a same-path update or interactive cancellation returns none.

- [ ] Add unit tests for push, actual pop, cancelled pop, unrelated pop, multiple sequential invoices, and same amount/different IDs. Include session/actor/workspace/job mismatches.
- [ ] Run the tests and verify they fail before implementation. Implement only the types and pure transition policy; rerun and verify they pass.
- [ ] Confirm the route is `Hashable` without encoding secrets and that the type does not assume server-side job membership; existing `JobDocumentScope` checks remain authoritative.

### Task 2: Migrate stack ownership with route parity

**Interfaces:** Each root owning a typed path provides a coordinator scoped to that stack, and maps each existing value route to `PaperStackRoute`; one shared destination switch reconstructs existing destinations. Paths in separate tabs and custom tabs remain separate. The `jobInvoice` case opens `InvoiceDetailView` with the existing expected job scope.

- [ ] Inventory and convert the value-based links, path appends, deep links and destination registrations reachable from `PaperNavigation`, `PaperTabletSchedule`, and `Screens`. Existing base has approximately 36 value-link sites and 35 app-root path appends; verify the inventory rather than assuming those counts are exhaustive.
- [ ] Add parity tests for schedule/jobs/custom tab paths, job/customer/document deep links, iPad selected job, and the job-created sheet. Verify switching tabs retains each path and external request reset still lands on the correct entity.
- [ ] Run the focused navigation test suite and simulator smoke journeys. Verify native Back and swipe-back, no nested duplicate navigation bar, and no loss of existing estimate, photo, activity or settings routes.

### Task 3: Restore the exact invoice safely

**Interfaces:** On a completed pop of `jobInvoice`, pass the captured route to the matching visible `JobDetailView`. Before any async call, mark invoice return pending, remove/disable the old collect and issue actions, and clear the old invoice payment model. Refresh job documents, require a complete fresh membership read and `JobDocumentScope.contains` for the captured ID, then load payments for that exact ID. Enable collection only after the returned model's invoice ID, scope, current session/authority, eligibility and verified balance all match. If any check fails, show a refresh/unavailable state and do not choose a different invoice automatically. Cancel or discard out-of-order completions when a newer route, job, session or authority supersedes them.

- [ ] Keep the existing equal-balance regression unchanged and add a fast-return/fast-tap test that can never open the previous invoice. Add a second job with the same customer to verify membership isolation.
- [ ] Add meaningful tests for removal, paid/void status, changed balance, incomplete read, payment load failure, workspace/actor/authority change, and rapid successive route transitions; assert that collection stays unavailable rather than targeting a different ID.
- [ ] Run the existing two invoice UI regressions, scope/payment model unit tests, and new tests. Both invoices must open without a prolonged idle wait; opening the first equal-balance invoice and returning must collect against that first invoice.

### Task 4: Accessibility and release evidence

- [ ] Exercise actual VoiceOver activation, hardware keyboard focus/activation, native Back, completed swipe-back and cancelled swipe-back against two equal-balance invoices. Record device/runtime and outcome; a tap-only XCUITest is not evidence for these modes.
- [ ] Exercise narrow screen, largest accessibility text, iPad schedule, separate tabs, stale/denied states and the new-job sheet. Confirm invoice label, current status and amount remain understandable and the collection target is explicit.
- [ ] Run a clean Release build and the relevant Swift tests on the exact candidate. Record logs, result bundles, source commit and known gaps. Independently review route parity and payment identity before merging or uploading.
- [ ] Upload a new TestFlight build only after the exact integrated source passes; verify App Store Connect processing and intended tester availability.

No implementation in this plan is certified yet. The documented migration is intentionally broader than the release candidate because opaque paths cannot supply the actual popped invoice identity. If the new route transition itself reproduces the SwiftUI stall, stop and diagnose before attempting another architecture; do not weaken the tests or use a touch-only workaround.
