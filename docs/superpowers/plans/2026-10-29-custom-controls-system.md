# Custom Linear-style Controls System Implementation Plan

> **For agentic workers:** Implement task-by-task. Steps use checkbox (`- [ ]`) syntax. Small PRs, rebase on origin/main often, squash-merge on green.

**Goal:** Build one custom Linear-style control system (menus + filter/display sheets) and migrate every screen off stock SwiftUI `Menu`/`Picker`/`confirmationDialog`, starting with the jobs homepage, with a CI guard that prevents regressions.

**Architecture:** The repo already has a strong custom system — `Theme` tokens + `Paper*` components (`PaperCircleButton` round icon buttons, `PaperTabs` pill segmented, `Chip`, `PressStyle`). We **keep `Paper*` as the canonical control set** (renaming to `Thorbis*` is pure churn and collides with Codex/Grok in-flight work). We add only the genuinely-missing pieces as new `Thorbis*` components in a dedicated `Thorbis/Sources/DesignSystem/` folder: `ThorbisMenu` (custom popover/sheet replacing stock dropdown `Menu {}`) and `ThorbisSheet` (the filter/display bottom sheet from the reference image). Then we sweep the app replacing stock `Menu`/`Picker`/`confirmationDialog`, deferring files Codex/Grok are editing. A CI lint lands last (or as a shrinking allowlist) so it never blocks migration PRs.

**Tech Stack:** SwiftUI (iOS 18), Swift 6 strict concurrency, XcodeGen (`Thorbis/Sources` is globbed — new files auto-included), `#Preview` macros (DEBUG).

**Scope decision (note in PR #1 body so Byron can veto):** Adopt existing `Paper*` as the system; build only `ThorbisMenu` + `ThorbisSheet`; no mass rename.

**Out of scope / defer (collision with other lanes):**
- `contextMenu {` long-press menus (different affordance, not a stock dropdown — directive doesn't target these).
- Files Codex owns: `EstimateBuilder.swift`, `NewEstimateView.swift`, `InvoiceLineEditorView.swift`, `PaperComponents.swift`'s `LineItemMenuItems`/`LineItemActions` (estimate/invoice lines), payment-handoff files.
- Files Grok owns right now: `PaperCustomerViews.swift` (PR #86 customer-from-jobs). Revisit after #86 merges.

---

## File Structure

- Create: `Thorbis/Sources/DesignSystem/ThorbisMenu.swift` — custom dropdown menu (adaptive sheet/popover of rounded card rows).
- Create: `Thorbis/Sources/DesignSystem/ThorbisSheet.swift` — filter/display bottom-sheet scaffold + row/toggle/chip building blocks.
- Create: `Thorbis/Sources/DesignSystem/README.md` — what lives here, the "no stock controls" rule, how to use each component.
- Create: `ThorbisTests/ThorbisControlsTests.swift` — logic/state tests for menu selection + sheet view-model.
- Create: `scripts/lint-stock-controls.sh` — grep guard (lands in later PR; allowlist-based).
- Modify (PR #1 homepage): `Thorbis/Sources/PaperWorkViews.swift` (ScheduleView `Menu` at ~239; wire Jobs/Schedule filter button to `ThorbisSheet`), `Thorbis/Sources/PaperComponents.swift` only if a shared header hook is needed (avoid — Codex touches this file).
- Modify (later sweep): `Screens.swift`, `TeamViews.swift`, `MediaView.swift`, `PaperJobDetailView.swift`, `EquipmentMembershipViews.swift`, plus `Picker`/`confirmationDialog` files not owned by other lanes.

---

## Task 1: `ThorbisMenu` component (PR #1 foundation)

**Files:**
- Create: `Thorbis/Sources/DesignSystem/ThorbisMenu.swift`
- Create: `Thorbis/Sources/DesignSystem/README.md`
- Test: `ThorbisTests/ThorbisControlsTests.swift`

Design: a trigger (any label) that presents a rounded 14pt card of rows. Compact width → bottom sheet with small detent; regular width → `.popover`. Rows: icon left (optional, place-mark tint), title, trailing checkmark when selected; `.destructive` role tints the row `Theme.destructive`. Dismiss on tap. Fully custom visuals — hide the system sheet background (`.presentationBackground`) and draw the `Theme.card` card so there is no system chrome. Reuse `Theme`, `PressStyle`, `RowPressStyle`.

Public API:
```swift
struct ThorbisMenuItem: Identifiable {
    let id = UUID()
    var title: String
    var icon: String? = nil
    var isSelected: Bool = false
    var role: ButtonRole? = nil          // .destructive supported
    var action: () -> Void
}

struct ThorbisMenu<Label: View>: View {
    var items: [ThorbisMenuItem]
    var width: CGFloat = 260
    @ViewBuilder var label: () -> Label
}
```
State to test lives in a tiny view model so it is testable without UI:
```swift
struct ThorbisMenuModel {
    var isPresented = false
    mutating func select(_ item: ThorbisMenuItem) { item.action(); isPresented = false }
}
```

- [ ] **Step 1: Write failing test** in `ThorbisTests/ThorbisControlsTests.swift`:
```swift
import XCTest
@testable import Thorbis

final class ThorbisControlsTests: XCTestCase {
    func testMenuSelectFiresActionAndDismisses() {
        var fired = false
        var model = ThorbisMenuModel()
        model.isPresented = true
        let item = ThorbisMenuItem(title: "Delete", role: .destructive) { fired = true }
        model.select(item)
        XCTAssertTrue(fired)
        XCTAssertFalse(model.isPresented)
    }
}
```
- [ ] **Step 2: Run, verify it fails** (type not defined). `xcodegen generate` then build-for-testing.
- [ ] **Step 3: Implement `ThorbisMenu.swift`** (model + view + `#Preview` showing a trigger with 4 rows incl. selected + destructive, light & dark).
- [ ] **Step 4: Write `DesignSystem/README.md`** (rule: no stock `Menu`/`Picker`/`confirmationDialog`/`.borderedProminent` outside this folder; how to use `ThorbisMenu`/`ThorbisSheet`/`PaperCircleButton`/`PaperTabs`/`Chip`).
- [ ] **Step 5: Run test, verify pass.**
- [ ] **Step 6: Commit** `feat: ThorbisMenu custom dropdown (design system)`.

## Task 2: `ThorbisSheet` filter/display bottom sheet (PR #1 foundation)

**Files:**
- Create: `Thorbis/Sources/DesignSystem/ThorbisSheet.swift`
- Test: `ThorbisTests/ThorbisControlsTests.swift` (add cases)

Design (reference image `~/grok-work/linear-ref/display-sheet.webp`): bottom sheet, drag indicator, title row with a close circle (`PaperCircleButton` "xmark"), grouped rounded card of rows. Building blocks:
- `ThorbisSheetScaffold<Content>` — title + close + `Theme.background`, `.presentationDetents`, custom drag affordance.
- `ThorbisSheetRow` — label (left) + value (right, muted) + `chevron.up.chevron.down`; tap opens a nested `ThorbisMenu` of options.
- `ThorbisSheetToggleRow` — label + a custom pill toggle (reuse `Theme`, not stock `Toggle` look; wrap `Toggle` with `.tint` + `.labelsHidden` is acceptable since it is a switch, OR draw custom).
- `ThorbisChipToggle` — selectable capsule chip (filled when on) in a `FlowRow`.

- [ ] **Step 1: Write failing tests** for a `DisplayOptions` value type driving the sheet:
```swift
func testDisplayOptionsCycleGrouping() {
    var opts = DisplayOptions()
    XCTAssertEqual(opts.grouping, .status)
    opts.grouping = .priority
    XCTAssertEqual(opts.grouping.label, "Priority")
}
```
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** scaffold + rows + `DisplayOptions`/`enum Grouping/Ordering` with `.label`, plus `#Preview` reproducing the reference sheet (Grouping, Ordering, a toggle, chip row).
- [ ] **Step 4: Run tests, verify pass.**
- [ ] **Step 5: Commit** `feat: ThorbisSheet filter/display bottom sheet (design system)`.

## Task 3: Wire jobs homepage to the new controls (PR #1)

**Files:**
- Modify: `Thorbis/Sources/PaperWorkViews.swift`

- [ ] **Step 1:** In `ScheduleView.commit(for:)` (~line 239) replace stock `Menu {}` (On-my-way ETA) with `ThorbisMenu` presenting the ETA options; keep `commitLabel` as the trigger. Build.
- [ ] **Step 2:** Give `JobsView` + `ScheduleView` a real Display/filter entry: the `PaperHeader` filter circle button opens a `ThorbisSheet` (search field + grouping/ordering + show-completed toggle + status chips) instead of only toggling the plain search field. Wire sheet state to the existing filtering (`tab`, `search`, add `showCompleted`/grouping where cheap). Build.
- [ ] **Step 3:** `xcodebuild` build+test on sim `A53349E1-5BFA-4B0E-86C5-D4DD81732611`; capture before/after screenshots to `~/claude-work/shots/custom-controls/`.
- [ ] **Step 4: Commit** `feat: jobs homepage uses ThorbisMenu + ThorbisSheet`.
- [ ] **Step 5:** Open PR `claude/custom-controls` → main with scope-decision note + screenshots. Squash-merge on green.

## Task 4+: Migration sweep (one small PR per cluster)

For each cluster, branch `claude/controls-<area>` off fresh origin/main, replace stock controls with `ThorbisMenu`/`ThorbisSheet`/`PaperTabs`/`Chip`, build+test+screenshot, PR, squash-merge on green. Skip any file with an open Codex/Grok PR (check `gh pr list` first).

- [ ] **4a** `Screens.swift` (Menu ~190; Picker), `TeamViews.swift` (Menu 195), `MediaView.swift` (Menu 200; Picker).
- [ ] **4b** `PaperJobDetailView.swift` (Menus 277/427/673) — confirm not in Codex's active diff first.
- [ ] **4c** `EquipmentMembershipViews.swift` (Menu 243; Picker; confirmationDialog).
- [ ] **4d** `Picker` sweep: `RoleEditor`, `SettingsView`, `MemberAccess`, `TeamInvites`, `InboxLocalDrafts`, `LocalWorkspaceViews`, `NewCustomerSheet`, `WorkspaceViews`, `JobOperationsViews` (skip Codex/Grok-owned).
- [ ] **4e** `confirmationDialog` sweep: `FinancialViews`, `SettingsView`, `CustomerPresentation`, `PublicEstimateActionView`, `BillingViews`, `Onboarding`, `WorkspaceViews`, `JobOperationsViews` (skip Codex/Grok-owned).
- [ ] **4f** Deferred (after Codex/Grok PRs merge): `EstimateBuilder`, `NewEstimateView`, `InvoiceLineEditorView`, `PaperComponents` line-item menus, `PaperCustomerViews`.

## Task 5: CI lint guard (PR, after the bulk of the sweep)

**Files:**
- Create: `scripts/lint-stock-controls.sh`
- Modify: `.github/workflows/ios.yml` (add a fast `lint` job before/alongside build).

Guard greps `Thorbis/Sources` for ` Menu {` (excluding `contextMenu`), `Picker(`, `.confirmationDialog(`, `.buttonStyle(.bordered`, `.borderedProminent` — **allowlisting** `Thorbis/Sources/DesignSystem/` and any not-yet-migrated files listed in `scripts/.stock-controls-allowlist`. Shrink the allowlist each sweep PR; when empty, the guard is absolute.

- [ ] **Step 1:** Write `lint-stock-controls.sh` (reads allowlist, exits non-zero on new offenders, prints file:line).
- [ ] **Step 2:** Seed allowlist with current remaining offenders so CI is green on landing.
- [ ] **Step 3:** Add `lint` job to `ios.yml`.
- [ ] **Step 4:** Commit + PR `ci: guard against stock SwiftUI controls`.

## Task 6: Finish & merge `claude/selectable-activity-feeds` (after controls land)

- [ ] Rebase/merge origin/main (which now has the controls system + possibly Grok's PR #87 `grok/activity-destinations`). Check `gh pr list` — if #87 already makes activity rows open their records, reconcile/avoid duplication. Build+test, PR, squash-merge on green.

---

## Self-review notes
- Spec coverage: round icon buttons (`PaperCircleButton`, already there — unify usage), pill segmented (`PaperTabs`), chips (`Chip`), custom menus (`ThorbisMenu` ✓), filter bottom sheets (`ThorbisSheet` ✓), CI lint (Task 5 ✓), migrate every screen (Task 4 ✓), jobs homepage first (Task 3 ✓), coordinate with Grok/defer Codex (scope ✓), finish activity-feeds branch (Task 6 ✓).
- No `Toggle`/stock-switch purity claim: a `Toggle` styled as a switch is acceptable per reference (the reference sheet shows an iOS-style switch). Do not replace switches.
