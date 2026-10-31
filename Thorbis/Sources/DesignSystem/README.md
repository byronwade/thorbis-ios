# Thorbis design system — controls

One custom control system, Linear-mobile style.

## Redesign rules (31 October 2026) — keep these

The owner found the app "bland and hard to navigate", so the visual rules moved toward Linear's
mobile app. Later passes must not undo them:

- **Palette:** crisp neutrals. Light: white ground, `#F4F4F5` wells (`Theme.card` / `Theme.well`),
  `#63636B` secondary text, 8% black hairline. Dark: `#0E0E10` ground, `#1A1A1D` wells, `#9A9AA3`
  secondary. No warm cream. Contrast stays ≥ 4.5:1 (`python3 scripts/tests/contrast.py`).
- **Type:** 400, 500 and 600. Semibold for screen titles (34pt display step), row titles, section
  headers and amounts. `Theme.allowed()` maps bold/heavy/black to 600.
- **Status:** job rows lead with `StatusGlyph` (dashed ring unscheduled, ring scheduled, quarter
  dispatched, half in progress, check done, × cancelled, ! attention). Its label is the word.
  Status hues: `Theme.status*` (glyph), `status*Text` (words), `status*Surface` (chip grounds).
- **Grouping:** `SectionHeader` (semibold 15, secondary, count) over a `Well`; inset hairlines
  between rows are allowed. Avatars and property chips are allowed.
- **Navigation (phone):** a side drawer (`AppDrawer`, `../DrawerNavigation.swift`) after the Claude
  and ChatGPT iOS apps. Each place root shows `DrawerMenuCircle` top left — `PaperHeader` draws it
  when the shell sets `\.paperDrawer` (roots only, never pushed screens); roots without a Paper
  header or with a visible navigation bar get it in the bar (`DrawerCircleInBar`). Edge swipe opens it on roots. The drawer:
  business name + search circle, the Now row, pinned places, Places, Edit menu, Recents; rows are an
  outline icon + 17pt label, ≥50pt, no wells; section labels semibold primary; `DrawerDot` (brand)
  for unread / needs attention. Bottom: ink New job capsule left, gear circle right. New also stays
  in the root header's + (`PaperHeader(showsCreate: true)`). UI tests: `drawer-menu`, then
  `drawer-<id>` rows (`openDrawer()` / `openFromDrawer(_:)` in `ThorbisUITests`). iPad keeps its
  sidebar. **No stock SwiftUI controls** in app screens:
no `Menu {}`, `Picker`, `confirmationDialog`, `.buttonStyle(.bordered*)`, or `.borderedProminent`.
Everything is built from `Theme` tokens (see `../Theme.swift`) so it looks the same everywhere,
in light and dark, and scales with Dynamic Type.

## What to reach for

| Need | Use | Where |
|------|-----|-------|
| Round icon button (36–40pt, 44pt hit) | `PaperCircleButton` | `../PaperComponents.swift` |
| Phone drawer, its menu circle and dot | `AppDrawer`, `DrawerMenuCircle`, `DrawerDot` | `../DrawerNavigation.swift` |
| Rimmed square button beside a commit | `PaperSquareButton` | `../PaperComponents.swift` |
| The screen's one primary action | `PrimaryButton` / `.inkCommit()` / `PaperActionBar` | `../Theme.swift`, `../PaperComponents.swift` |
| Pill segmented tabs | `PaperTabs` | `../PaperComponents.swift` |
| Status / value chip (display only) | `Chip` | `../Theme.swift` |
| Job status as a Linear progress ring | `StatusGlyph` (+ `StatusTone` mapping) | `StatusGlyph.swift` |
| Tinted property chip (status, time, tech, amount) | `PropertyChip` | `StatusGlyph.swift` |
| Property chip whose words wrap at large text (job header) | `WrappingPropertyChip` | `WrappingPropertyChip.swift` |
| Person's initials circle | `InitialsAvatar` | `StatusGlyph.swift` |
| Place mark (tinted square + white glyph) | `PlaceMark` | `StatusGlyph.swift` |
| Grouped rows on a well, inset hairlines | `Well`, `WellList`, `WellDivider` | `StatusGlyph.swift` |
| A long list's well, row by row (stays lazy) | `WellSection`, `.wellSlice(first:last:)` | `ListRows.swift` |
| Job row (glyph, street, problem, who and when, avatar) | `JobListRowContent` | `ListRows.swift` |
| Customer row (initials, name, where, open job's status) | `CustomerListRowContent` | `ListRows.swift` |
| Search row's kind glyph (status, initials, place mark) | `SearchGlyph` | `ListRows.swift` |
| Estimate / invoice status as a glyph tone and word (no new `StatusTone` cases) | `DocumentStatus` | `DocumentRows.swift` |
| Estimate / invoice row (glyph, title, who · reference, semibold amount) | `DocumentListRowContent` | `DocumentRows.swift` |
| Document status chip | `WrappingPropertyChip(document:)` | `DocumentRows.swift` |
| Label and amount on a well (totals) | `WellAmountRow` | `DocumentRows.swift` |
| Semibold tabular amount (staff screens; customer mode keeps `moneyFont`) | `Theme.amountFont(_:)` | `DocumentRows.swift` |
| Document header (eyebrow, 30pt title, wrapping chips) | `DocumentHeader` | `../FinancialViews.swift` |
| Old `PaperSection`/`PaperCard` drawn as header + well | `.environment(\.paperGroupedWells, true)` | `PaperComponents.swift` |
| Section header with count | `SectionHeader` | `../Theme.swift` |
| Linear text tabs (plain words, well pill) | `PaperTabs(textTabs: true)` | `../PaperComponents.swift` |
| Activity timeline row (glyph on a thin line) | `JobTimelineItem`, `JobActivityGlyph` | `../JobScreenParts.swift` |
| **Dropdown menu** (replaces `Menu {}`) | **`ThorbisMenu`** | `ThorbisMenu.swift` |
| **Filter / display bottom sheet** | **`ThorbisSheet*`** | `ThorbisSheet.swift` |
| **Select row** (replaces menu/default `Picker`) | **`ThorbisSelect`** | `ThorbisControls.swift` |
| **Pill segmented** (replaces `.pickerStyle(.segmented)`) | **`ThorbisSegmented`** | `ThorbisControls.swift` |
| **Confirm sheet** (replaces `.confirmationDialog`) | **`.thorbisConfirm`** | `ThorbisControls.swift` |
| Selectable chip | `ThorbisChipToggle` / `ThorbisChipGroup` | `ThorbisSheet.swift` |

## ThorbisMenu

A rounded card of rows that floats up from the bottom — no system menu material or caret.
Icons left, a checkmark on the selected row, `.destructive` rows in red.

```swift
ThorbisMenu(items: [
    ThorbisMenuItem("On my way", icon: "location.fill") { start() },
    ThorbisMenuItem("ETA 15 min", icon: "clock") { start(eta: 15) },
    ThorbisMenuItem("Cancel", icon: "xmark.circle", role: .destructive) { cancel() },
], title: "On my way") {
    commitLabel("On my way", symbol: "location.fill")   // your trigger label
}
```

## ThorbisSheet

Building blocks for a filter/display sheet: `ThorbisSheetScaffold` (grabber + optional title +
close circle), `ThorbisSheetGroup` (rounded card) with `ThorbisSheetRow` (value + chevron-updown,
opens a `ThorbisMenu`), `ThorbisSheetToggleRow`, and `ThorbisChipGroup`. Put a
`ThorbisSheetDivider()` between rows in a group. `DisplayOptions` is a reusable grouping/ordering
value model.

```swift
.sheet(isPresented: $showDisplay) {
    ThorbisSheetScaffold(title: "Display", onClose: { showDisplay = false }) {
        ThorbisSheetGroup {
            ThorbisSheetRow(label: "Grouping", value: opts.grouping.label,
                            options: DisplayOptions.Grouping.allCases.map(\.label)) { opts.setGrouping($0) }
            ThorbisSheetDivider()
            ThorbisSheetToggleRow(label: "Show completed", isOn: $opts.showCompleted)
        }
    }
}
```

## ThorbisSelect / ThorbisSegmented (form Pickers)

`ThorbisSelect` is a select row that opens a `ThorbisMenu`. With a `label` it renders as a bare
form row (`label … value ⌄`); without one it's a boxed control. `ThorbisSegmented` is a pill
segmented control for a small, fixed set of choices. Both are generic over the selection value.

```swift
ThorbisSelect(options: roles.map { ($0.id, $0.label) }, selection: $role, label: "Role")
ThorbisSegmented(options: [("residential", "Residential"), ("commercial", "Commercial")],
                 selection: $accountType)
```

## ThorbisConfirm (confirmationDialog)

`.thorbisConfirm` presents a custom confirm sheet — title, optional message, a red destructive
button, and an automatic Cancel. Use the `isPresented:` form for a Bool, or the `item:` form in
place of `.confirmationDialog(presenting:)` (it clears the item on dismiss, so swipe-away = Cancel).

```swift
.thorbisConfirm("Remove this item?", isPresented: $confirm,
                actions: [ThorbisConfirmAction("Remove", role: .destructive) { remove() }])

.thorbisConfirm(item: $toRemove, title: { _ in "Remove location?" },
                message: { "Removes it from \($0.customer)." },
                actions: { loc in [ThorbisConfirmAction("Remove \(loc.label)", role: .destructive) { remove(loc) }] })
```

> **Capture the value before dismiss.** When a Bool-driven confirm's action reads the same state
> that dismissing clears (e.g. a pending choice), capture it into a `let` before the modifier so
> the action doesn't read a blanked value. The `item:` form captures for you.

## CI guard

`scripts/lint-stock-controls.sh` flags stock controls outside this folder. The allowlist is now
empty, so any stock `Menu {}`, `Picker(`, `confirmationDialog`, bordered button style or bare
`ToolbarItem` in a screen fails the guard. Add new controls here, not in screens; the keyboard's
Done bar is `ThorbisKeyboardDoneBar`.
