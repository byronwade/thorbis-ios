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
- [ ] Apply exported presentation to remaining supported routes and their sheets without inventing missing backend behavior.

### Task 4: Verify and release
- [x] Run Swift strict-concurrency build and relevant existing full tests; add behavioral tests only for new route/filter logic.
- [ ] Compare simulator screenshots to Paper on iPhone and iPad, fix differences, record remaining gaps precisely.
- [x] Independent review of UI, permission and navigation regressions.
- [ ] Only claim full match when verified; increment build and upload the verified implementation to TestFlight.

Execution authorization: user requested exact existing Paper design and already approved implementation and TestFlight distribution. Continue without redundant design approval.

## Execution record

Build 3 delivers the supported core screen presentation, with passing 105-test suite, iPhone/iPad screenshot checks, independent review, strict signature verification, and Release preview exclusion. See docs/design/README.md for the remaining artboard/contract gaps. Full exact design parity remains unchecked and is not represented as complete.
