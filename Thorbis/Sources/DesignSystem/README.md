# Thorbis design system — controls

One custom control system, Linear-mobile style. **No stock SwiftUI controls** in app screens:
no `Menu {}`, `Picker`, `confirmationDialog`, `.buttonStyle(.bordered*)`, or `.borderedProminent`.
Everything is built from `Theme` tokens (see `../Theme.swift`) so it looks the same everywhere,
in light and dark, and scales with Dynamic Type.

## What to reach for

| Need | Use | Where |
|------|-----|-------|
| Round icon button (36–40pt, 44pt hit) | `PaperCircleButton` | `../PaperComponents.swift` |
| Rimmed square button beside a commit | `PaperSquareButton` | `../PaperComponents.swift` |
| The screen's one primary action | `PrimaryButton` / `.inkCommit()` / `PaperActionBar` | `../Theme.swift`, `../PaperComponents.swift` |
| Pill segmented tabs | `PaperTabs` | `../PaperComponents.swift` |
| Status / value chip (display only) | `Chip` | `../Theme.swift` |
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
