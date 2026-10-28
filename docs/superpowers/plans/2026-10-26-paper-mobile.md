# Thorbis Mobile Paper Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Match the existing Thorbis Mobile Paper designs in the native Swift app.

**Architecture:** Preserve authenticated API, permission gates, session isolation, and mutation handlers. Replace system List/Form presentation with native components whose values come directly from Paper exports. Use live records, never the artboards' sample company, people, counts, or payment amounts.

**Tech Stack:** Swift 6, SwiftUI, iOS 17+, Inter and Geist Mono bundled under OFL.

**Spec:** [Thorbis Mobile](https://app.paper.design/file/01KY0S86CYXENWSH216F3ZB058/B-0), current page, not the archived mobile page. Raw reference exports are in docs/design.

## Global Constraints
- Use actual OS status bar and safe areas, not drawn status bar examples.
- Preserve capability and feature gates, URL restrictions, cookie Origin fix, and real data semantics.
- No fabricated offline sync, provider authentication, unread counts, or financial summaries.
- Use exported colors, dimensions and typography; screenshots verify appearance only.
- Keep all existing working operations reachable.

## Review Focus
- Long customer/job names and larger accessibility text must remain usable.
- Empty/loading/error states must not display Paper sample records as real workspace data.
- Restricted accounts must not gain routes or mutations through custom navigation.
- Switching workspace and signing out must retire old data and navigation.
- Pushed details and sheets need a reliable back/dismiss path under custom root navigation.

### Task 1: Shared design primitives and navigation
- [x] Bundle Inter and Geist Mono, register fonts, and define Theme.font/monoFont plus missing tokens.
- [x] Add PaperHeader, PaperTabs, PaperSearchField, custom pill dock and More overlay in PaperComponents.swift and PaperNavigation.swift; replace RootView TabView in App.swift.
- [ ] Verify iPhone safe areas, route permissions and back navigation in simulator; keep iPad adaptive.

### Task 2: Login and core work screens
- [x] Translate LoginView.swift from login export, preserving authentication and honest unsupported-provider states.
- [x] Translate ScheduleView and JobsView into PaperWorkViews.swift; keep filters/refresh/create/navigation.
- [x] Translate customers and job detail presentation from corresponding exports; preserve all existing handlers and data.
- [x] Check real empty/error states and populated debug-only visual fixtures, never enable fixtures in Release.

### Task 3: Remaining screen coverage
- [x] Inventory all current native routes against current Paper artboards, record unimplemented contracts and empty artboards explicitly.
- [x] Match the customer contact quick-add to Paper with live name, role, phone, email, and first-contact primary behavior; keep unsupported approval/SMS switches out of the active form.
- [ ] Apply exported presentation to remaining supported routes and their sheets without inventing missing backend behavior. Schedule picker `RAG-0` is now complete for the supported native contract; many other screens/forms remain.

#### Task 3 continuation: My Day first functional slice

**Scope:** Add a My Day view within the existing Jobs route. Show the signed-in user's jobs scheduled for the device-local day, including completed and canceled work, ordered by scheduled instant and ID, with explicit loading, refresh, error, and empty states. Add the web app's dispatched-to-en-route “On my way” action with optional ETA presets, `job.edit` gating, duplicate-submit protection, and visible errors. Open each job through the existing detail destination. Do not claim offline command replay; this client requires a live connection for mutations. Invoice follow-through and canceled-job actions remain later work.

**Files:** `Thorbis/Sources/JobFiltering.swift`, `Thorbis/Sources/PaperWorkViews.swift`, `Thorbis/Sources/PaperPreview.swift`, `Thorbis/Sources/PaperNavigation.swift`, `ThorbisTests/JobFilteringTests.swift`. Reuse `APIClient.progressFieldJob`, `FieldProgressRequest.enRoute`, and the existing jobs navigation path. A read-only fixture enables visual inspection without account credentials or live writes.

**Tests:** Verify local-calendar day boundaries and time ordering, actor isolation, jobs without scheduled times, and transition plus capability gating. Run the focused tests and the complete iPhone 17 Pro simulator suite.

**Design ruling:** There is no dedicated My Day artboard in the current Paper Mobile file. Place the view as a tab within Jobs, use the existing Paper work-list tokens, and avoid implying screenshot parity with a missing artboard.

**Steps:** (1) Add the failing filter and action-gate tests and watch them fail. (2) Implement the two pure helpers and watch them pass. (3) Add the Jobs/My Day UI with the existing detail route and canonical progress endpoint. (4) Run focused and full simulator tests, inspect the UI in the simulator, and record the remaining offline/artboard limitation.

**Execution evidence:** The local-day/actor/order rules and permission/transition gate are covered, including completed/canceled rows; ETA requests encode both the selected duration and no-ETA case. Failed fetches do not display an empty-day claim. The iPhone 17 Pro suite passes 126/126. A read-only populated preview was inspected at `outputs/paper/my-day.png`. Independent code review passed; the next signed archive remains pending.

### Task 3 continuation: My Day default and native hit targets

**Scope:** Open production Jobs on My Day, matching the first Paper destination, and enforce Thorbis's 44 pt minimum on app-authored controls in the affected mobile surfaces while preserving the visible Paper sizing. See [native-ui-evidence-2026-10-27.md](../../design/native-ui-evidence-2026-10-27.md) for the HIG-001–022 matrix.

**Verification:** iPhone 17 Pro read-only preview confirms My Day, local date, visit count, and existing actions. Invoice editor and iPad schedule previews were also checked. All 147 simulator tests pass; the generic iOS Release build compiles. Accessibility runtime bounds, Dynamic Type, physical-device behavior, and iPad resizing remain open.

### Task 3 continuation: Customer archive views and history timeline

**Scope:** Match the web customer list's Recent, All customers, and Archived scopes plus its independent state filter and explicit Active/Archived status. Load both states through `includeArchived=true`. In Customer Activity, show the paginated history endpoint's kind glyph, summary, and relative time; request 50 items and follow `nextCursor` through “Load earlier activity.” Preserve loaded events after a next-page failure and let the user retry. The API supports archive and restore, but the current web customer UI exposes neither action; do not add either control in this parity slice.

**Files:** `Thorbis/Sources/FieldAPI.swift`, `Thorbis/Sources/PaperCustomerViews.swift`, `ThorbisTests/FieldAPITests.swift`, and this API contract/coverage record.

**Tests:** Verify the archived-customer query, history item decoding and endpoint, 50-item request, cursor pagination, and Recent/All/Archived predicates and ordering. Run the focused Field API tests, complete iPhone 17 Pro simulator suite, and Release iOS build.

### Task 4: Verify and release
- [x] Run Swift strict-concurrency build and relevant existing full tests; add behavioral tests only for new route/filter logic.
- [ ] Compare simulator screenshots to Paper on iPhone and iPad, fix differences, record remaining gaps precisely.
- [x] Independent review of UI, permission and navigation regressions.
- [x] Increment the build, sign and verify the archive, and upload the tested implementation to TestFlight Build 10.
- [ ] Verify processing, assign Build 10 to the external tester group, and confirm Hayley's invitation after App Store Connect access and required beta-review details are available. Full parity remains unchecked.

Execution authorization: user requested exact existing Paper design and already approved implementation and TestFlight distribution. Continue without redundant design approval.

## Execution record

Build 3 delivers the supported core screen presentation, with passing 105-test suite, iPhone/iPad screenshot checks, independent review, strict signature verification, and Release preview exclusion. See docs/design/README.md for the remaining artboard/contract gaps. Full exact design parity remains unchecked and is not represented as complete.
