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
| **Filter / display bottom sheet** (replaces `Picker`/`confirmationDialog`) | **`ThorbisSheet*`** | `ThorbisSheet.swift` |
| Selectable chip (replaces segmented `Picker`) | `ThorbisChipToggle` / `ThorbisChipGroup` | `ThorbisSheet.swift` |

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

## CI guard

`scripts/lint-stock-controls.sh` fails CI when a stock control appears outside this folder
(allowlist shrinks as screens migrate). Add new controls here, not in screens.
