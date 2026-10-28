# Job Overview Simplification Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan inline. Steps use checkbox syntax for tracking.

**Goal:** Give technicians one clear next action and a shorter Job Overview while preserving every existing action and its authority checks.

**Architecture:** A small pure presentation policy selects a primary action from the effective job status, server-allowed transitions, and existing permissions. Schedule and Job Detail reuse it. Existing mutation, queue, pause/resume, and closeout handlers remain the authority for carrying out an action.

**Tech Stack:** SwiftUI, Swift 6, iOS/iPadOS 18+, XcodeGen, XCTest.

**Spec:** `docs/design/continuous-ux-goal.md` and `docs/design/ux-audit-2026-10-28.md`.

## Global Constraints

- Preserve all features, permissions, feature gates, queued work, pause evidence, and server authority.
- Keep Call, Text, Directions, the editable time chip, and pinned record tabs immediately accessible.
- Keep lifecycle transitions in the status menu. Put Schedule and Assign technician in the existing More menu; retain Wrap up, Follow-ups, Show to customer, Copy ID, and Share.
- Use existing Thorbis tokens, `PaperActionBar`, native `Menu`, `NavigationStack`, and existing destinations. Wrap up opens the checklist and never completes a job directly.
- Preserve Job Detail's direct Resume work when the server permits it; Schedule does not gain a resume handler in this batch.
- Use a single primary action and remove the duplicate On this job action list and Details/Edit time control.
- Follow D-025 and Native HIG-001–HIG-010, HIG-013, HIG-015–HIG-017, HIG-020–HIG-022. Existing components retain their typography, motion, and touch behavior.

## Source receipts

Consulted 28 October 2026 for the technician's guided record view on iPhone/iPad:

- [Thorbis Native](https://design.thorbis.com/skills/native): platform controls, action reachability, state continuity, and verification.
- [Apple Menus](https://developer.apple.com/design/human-interface-guidelines/menus): concise labels and related action groups, with limited nesting.
- [Apple Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons): give the likely action clear prominence and maintain comfortable hit regions.
- [Apple Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars): keep frequent commands close and put additional actions in More.

The older `/mobile-app` URL in the audit currently returns 404. Use the live Native contract for platform rules and the audit for implementation history.

## Review Focus

- In-progress work offers Wrap up even if Pause or a reverse step appears first in server order.
- Paused work retains its existing audited Resume path on Job Detail.
- Missing permissions, unknown statuses, or absent allowed transitions never invent a mutation.
- Queued status takes priority over fetched status; Schedule uses the freshest loaded record before its list summary.
- Unscheduled jobs, read-only roles, and large text retain access to the appropriate secondary destinations.

---

### Task 1: Simplify and align job actions

**Files:**
- Create: `Thorbis/Sources/JobPrimaryAction.swift`
- Create: `ThorbisTests/JobPrimaryActionTests.swift`
- Create: `ThorbisUITests/JobOverviewUITests.swift`
- Modify: `project.yml` (native UI test target only)
- Modify: `Thorbis/Sources/PaperJobDetailView.swift`
- Modify: `Thorbis/Sources/PaperWorkViews.swift`
- Modify: `docs/design/ux-audit-2026-10-28.md`

**Interfaces:**
- Produce `JobPrimaryAction.progress(String)` and `.wrapUp` with `resolve(status:allowedTransitions:canEdit:canAssign:canResume:) -> JobPrimaryAction?`.
- Consume only server-provided or previously learned transitions; `canAssign` and `canResume` default to false for Schedule.
- Strictly forward field order is en_route, arrived, in_progress. Assignment-capable Job Detail can first Dispatch a scheduled job. Reverse steps and Pause remain secondary.

- [x] Write meaningful policy tests: in-progress → Wrap up; forward order independent of server array order; no backwards primary step; no invented transition; edit/assignment gates; resume needs server allowance and a resume-capable surface; completed/canceled/unknown statuses → no primary action.
- [x] Run `xcodebuild test -quiet -project Thorbis.xcodeproj -scheme Thorbis -destination 'platform=iOS Simulator,id=BFB124FA-3F9E-449A-B15B-9178F0E46525' -only-testing:ThorbisTests/JobPrimaryActionTests`. Expected: failure because the new policy is missing.
- [x] Implement the policy and wire it into Schedule and Job Detail, including the fresher Schedule hero status. Consolidate secondary actions and keep existing handlers and capability checks.
- [x] Run the policy tests plus `JobFilteringTests`, `FieldOutboxTests`, `FieldAPITests`, and `JobActionAPITests`. Expected: all pass.
- [x] Run the native interaction checks for secondary-menu reachability, scheduling presentation, and in-progress Wrap up navigation. Visually check dispatched/in-progress Job Overview and the More/status menus on iPhone, plus the adaptive iPad record view. Check light/dark and accessibility text size; record native checks separately from unit tests.
- [x] Run the full iOS test target and `git diff --check`, record the evidence and feature-access map in the UX audit, then commit the batch. Expected: zero test failures and no whitespace errors. Record existing warnings and untested physical-device/assistive-input checks honestly.

### Task 2: Let controls grow with accessible text

The Task 1 largest-text visual check exposed existing fixed-height clipping. Fix the shared controls before the final whole-branch verification; HIG-008 takes priority over fixed baseline dimensions.

**Files:** `Thorbis/Sources/Theme.swift`, `Thorbis/Sources/PaperComponents.swift`, `Thorbis/Sources/PaperJobDetailView.swift`, `ThorbisTests/DynamicTypeLayoutTests.swift`, `ThorbisUITests/JobOverviewUITests.swift`.

**Interfaces:** Keep the existing component APIs. Treat 28/32/50 pt pill/tab/commit dimensions as minimums; content determines the enlarged height. FlowRow constrains an oversized child to its available width, and accessibility-sized contact shortcuts become full-width vertical rows.

- [x] Add hosted layout tests comparing standard/enlarged primary-button and tab heights, and wide/narrow long-label wrapping in Chip and FlowRow. Add a native check that the largest text size stacks contact actions and grows the primary action.
- [x] Run these new checks before changing the controls. Expected: assertions fail for fixed heights and unbounded horizontal content.
- [x] Replace fixed text-control heights with padded minimums, permit multiline chip labels, constrain oversized FlowRow measurements, and use the existing accessibility-size stacking convention for the whole quick-action group. Keep decorative avatar/glyph dimensions and all actions.
- [x] Re-run layout, appearance, and native interaction checks. Expected: all pass; inspect the enlarged dark preview and the wide iPad record layout.
- [x] Run the full app scheme once after both tasks, record the HIG matrix and remaining manual-device gaps, then commit and request the whole-branch review.

### Task 3: Reconcile with the current release before TestFlight

**New binding baseline:** origin/main `663c622`, which contains build 69 (`0c83429`) and newer job hours, booking-call and price search work. The initial checkout predates 104 main commits.

**Files:** retain main's complete application; keep only the narrow adaptive-layout changes, layout/native tests, goal guidance and release notes.

- [x] Stop the initial archive before upload; compare the latest uploaded source and main.
- [x] Preserve main's TechJobFlow, JobMenu, onboarding, estimate builder, money hierarchy, record sections, fitted tabs and Reduce Motion. Remove the superseded JobPrimaryAction and its tests; restore main Schedule unchanged.
- [x] Carry forward adaptive shared controls and local metadata heights. Adapt native tests to the current guided payment step and menu labels. Add the required What's new entry, including missing booking-call release coverage.
- [ ] Generate and run the integrated full scheme. Inspect current screenshots. Expected: all tests pass, the payment step remains primary, all secondary actions remain reachable, text grows without clipping.
- [ ] Archive and upload a new sequential TestFlight build using existing Xcode signing, verify processing and tester-group availability in App Store Connect, and record actual status.
