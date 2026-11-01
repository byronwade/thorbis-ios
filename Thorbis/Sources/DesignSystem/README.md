# Thorbis design system — controls

One custom control system, Linear-mobile style.

## v2 rules (31 October 2026) — Linear grammar on design.thorbis.com tokens

**Linear grammar on design.thorbis.com tokens; the drawer is an owner-approved exception.**
Linear's mobile app sets the layout grammar; design.thorbis.com is the law for tokens, depth,
controls, forms, words, places and states ("Linear grammar. Not Linear dress"). The full rules are
at the top of `docs/design/ios-golden-rules.md`. Later passes must follow these:

- **Palette:** dark is Linear's greys (canvas `#0A0A0A`, panel `#171717`), cream type `#F7F4EE`,
  cool grey body, dimmer marker. Light is the warm cream sheet (canvas `#F7F4EE`, panel `#FDFCFA`).
  `Theme.field` is the sunk well under a field or select; `Theme.fill` is a chip or circle. One
  electric-blue accent (`Theme.brand`) for selected, focus and the one live thing. Status hues are
  the site's success/error/info/warning, tuned in lightness only. Place marks: `markOlive`,
  `markForest`, `markPumpkin`, `markBurnt`, `markAccent`. `python3 scripts/tests/contrast.py`
  reports 0 failures (4.5:1 text, 3:1 marks, both themes, Increase Contrast).
- **Type:** 400 and 500 only (`Theme.allowed()` maps semibold and heavier to 500). The staff ramp
  (`Theme.onRamp`) is compact: body/row title 15, secondary 14, chrome 13 Medium, captions 12,
  sheet titles 16–17, detail titles 24, root titles 26, money hero 30. Customer-facing views use
  `Theme.customerFont` (the older ramp) to keep their 17pt / 56pt floors.
- **Depth:** Rest (planar sheets and panels), Sink (`fieldWell()`, `ThorbisSelect`,
  `ThorbisSheetGroup`: one step darker, inset, 1px rim), Lift (`.inkCommit()` / `.dangerCommit()`:
  ink, radius 10, 1px rim, light from above, 1px drop, press sinks through `PressStyle`), Overlay
  (`ThorbisMenu` popovers only). No fifth.
- **No separators:** `WellDivider` and `ThorbisSheetDivider` draw nothing; `PaperCard` has no rim;
  no coloured side rails. A 1px rim is for fields, commits, chips and photos only.
- **Status is a word:** `StatusLabel` (a small `StatusMark` in the hue, then the word). Rows lead
  with the street; the status word sits in the subtitle (`JobListRowContent`,
  `DocumentListRowContent`) or at the trailing edge (`CustomerListRowContent`, search). Never a
  coloured glyph without its word. Status chips are neutral pills with the mark beside the word.
- **Modals:** `ThorbisModalSheet` — a clean system sheet on the panel (`thorbisSheetPresentation`,
  no Liquid Glass), `ThorbisSheetHeader` (17pt Medium title + close circle), content grouped by
  space with 20pt padding, fields as sunk wells (`ThorbisSheetField`: label, well, one slot for
  help or the error), one ink commit in the pad. Never pre-disable the commit; when it must be
  off, `commitDisabledReason` / `PaperActionBar(disabledReason:)` says why.
- **Every sheet is on the panel:** a sheet that shows a whole screen (Settings, an invoice's lines,
  a NavigationStack) wraps its `.sheet` content in `SheetSurface { … }` (or calls
  `.thorbisSheetSurface()` outside the stack); `thorbisSheetPresentation` does the same. Inside,
  `Theme.canvas` (a screen's ground: `background` on a route, `surface` in a sheet) and
  `.panelBackground(cornerRadius:)` / `ThorbisPanelStyle` (a group's ground: the panel on a route,
  the sink with its 1px rim in a sheet) follow the `thorbisSheetCanvas` environment, so one screen
  reads right as a route and in a sheet. Never paint a screen `Theme.background` directly. System
  UI (share, Safari, Quick Look, Mail, Calendar, Contacts, camera and scanner covers) and customer
  mode covers stay as they are.
- **Popovers:** `ThorbisMenu` is an anchored `.popover` with compact adaptation: overlay depth,
  ~44pt rows, a leading mark, a check on the current value, destructive rows in their own group,
  a 120ms fade. Status, the ••• overflow, selects and filters all use it.
- **Motion:** `Theme.selectionSpring` is now a 120ms ease-out (name kept); no bounce or stagger on
  routine work; haptics stay.
- **In-between states (phase 4, still current):** empty states name the one action
  (`PaperEmptyState`), loading is `SkeletonList` / `SkeletonRows`, banners are calm strips,
  toasts are `ThorbisToast` and only confirm what the screen already shows.
- **Navigation (phone):** a side drawer (`AppDrawer`, `../DrawerNavigation.swift`) after the Claude
  and ChatGPT iOS apps, reachable from every screen of a place. Roots show `DrawerMenuCircle` top
  left — `PaperHeader` draws it when the shell sets `\.paperDrawer` (roots only); roots without a
  Paper header or with a visible bar get it in the bar (`DrawerCircleInBar`). Pushed screens get it
  from `.thorbisBackButton()` / `thorbisDestination`, which reads `\.paperDrawerReach` and puts the
  circle top left with `ThorbisCompactBackButton` beside it; inside a sheet or cover
  (`PresentationProbe`) and in customer mode (`CustomerModeContainer` clears both keys) it keeps
  `ThorbisBackButton` alone. Edge swipe opens the drawer on roots; on pushed screens it is Back.
  Which places it lists comes from `DrawerSections.make` (`../CreamSheet.swift`): every place the
  role can open, grouped under Work, Money, Shop and On this phone (Fleet, Equipment, Agreements,
  saved work), with explicit Edit-menu pins leading in a Pinned section; nothing is folded away.
  Cream sheet (C-Nav.dc.html): the drawer sits on the canvas; 18pt business name + search circle;
  `PlacesList` rows (18pt mark in the place's quiet hue, filled when here, 15pt word, a tabular
  count at the trailing edge, the selected place on `Theme.fill`), 12pt section headings, Recent
  records as plain words; the list fades at its bottom edge. `DrawerDot` (brand) marks unread Inbox
  only, plus saved work needing the person on the gear. Bottom: the ink New job commit (radius 10)
  and the Settings circle (its menu: businesses, saved work, Add a business, Settings, Edit menu).
  The iPad sidebar uses the same `PlacesList` (On this iPad). New also stays in the root header's
  ink + (`CreamPlaceHeader` on Today, `PaperHeader(showsCreate: true)` elsewhere). UI tests:
  `drawer-menu`, then `drawer-<id>` rows (`openDrawer()` / `openFromDrawer(_:)`, which scrolls to
  low rows, and `openSavedWorkFromDrawer()` in `ThorbisUITests`). iPad keeps its
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
| Status as a word with its mark | `StatusLabel` (+ `StatusMark`) | `StatusGlyph.swift` |
| The status mark alone (inside a chip or menu row) | `StatusGlyph` (+ `StatusTone` mapping) | `StatusGlyph.swift` |
| Tinted property chip (status, time, tech, amount) | `PropertyChip` | `StatusGlyph.swift` |
| Property chip whose words wrap at large text (job header) | `WrappingPropertyChip` | `WrappingPropertyChip.swift` |
| Person's initials circle | `InitialsAvatar` | `StatusGlyph.swift` |
| Place mark (soft hue, outline at rest, fill when here) | `PlaceMark(filled:)` | `StatusGlyph.swift` |
| Grouped rows on a panel, no lines | `Well`, `WellList` | `StatusGlyph.swift` |
| A long list's well, row by row (stays lazy) | `WellSection`, `.wellSlice(first:last:)` | `ListRows.swift` |
| Job row (street, problem, status word · who and when, avatar) | `JobListRowContent` | `ListRows.swift` |
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
| Activity timeline row (a quiet mark, space between entries, no rail) | `JobTimelineItem`, `JobActivityGlyph` | `../JobScreenParts.swift` |
| Job status popover (moves grouped by space: forward, then pause / back) | `JobStatusMenu` | `../JobStatusMenu.swift` |
| **Anchored popover menu** (replaces `Menu {}`) | **`ThorbisMenu`** | `ThorbisMenu.swift` |
| **A menu shown as a sheet** (Create) | `ThorbisMenuCard` | `ThorbisMenu.swift` |
| Any other anchored popover (opens down from the top half, up from the bottom half; puts the keyboard away first) | `.anchoredPopover(isPresented:)`, `ThorbisKeyboard.dismiss` | `ThorbisMenu.swift` |
| A text field's placeholder (verbatim example in `Theme.muted`; the lint rejects `prompt: Text(`) | `prompt: .placeholder("…")` | `ThorbisControls.swift` |
| **Modal sheet** (one task, one ink commit) | **`ThorbisModalSheet`**, `ThorbisSheetField`, `ThorbisSheetHeader` | `ThorbisSheet.swift` |
| **Filter / display bottom sheet** | **`ThorbisSheet*`** | `ThorbisSheet.swift` |
| Sunk field well | `.fieldWell()` | `../PaperComponents.swift` |
| Danger commit (Cancel job, Void invoice) | `.dangerCommit()` | `../Theme.swift` |
| **Select row** (replaces menu/default `Picker`) | **`ThorbisSelect`** | `ThorbisControls.swift` |
| **Pill segmented** (replaces `.pickerStyle(.segmented)`) | **`ThorbisSegmented`** | `ThorbisControls.swift` |
| **Confirm sheet** (replaces `.confirmationDialog`) | **`.thorbisConfirm`** | `ThorbisControls.swift` |
| Selectable chip | `ThorbisChipToggle` / `ThorbisChipGroup` | `ThorbisSheet.swift` |
| Empty state (tinted glyph, title, sentence, action) | `PaperEmptyState(tint:)`, `EmptyGlyph` | `ThorbisStates.swift` |
| Loading list / rows | `SkeletonList`, `SkeletonRows`, `SkeletonPulse` | `ThorbisStates.swift` |
| Banner glyph (offline, sync, error strips) | `BannerGlyph` | `ThorbisStates.swift` |
| Confirmation toast (saved, undo) | `ThorbisToast` | `ThorbisToast.swift` |
| **Row swipe actions** (rows in a `ScrollView`, not a `List`; words always show) | **`RowSwipeContainer`**, `RowSwipeAction`, `.rowSwipeAccessibility` | `RowSwipeActions.swift` |

## Row swipe actions

Our list rooms are `ScrollView`s (Today mixes the Now panel, the stop-card pager and pinned
labels), so `.swipeActions` is not available. `RowSwipeContainer` gives a row cells behind it:
a sideways UIKit pan that never starts in the screen's leading 24pt (the drawer's edge swipe and
Back) and that vertical scrolling waits on only until it declines. Half a cell opens a side; past
55% of the row a full swipe runs the one action marked for it (only a forward, non-destructive
move). One row is open per screen (`RowSwipeState`; close it when the list scrolls), and a tap on
an open row closes it. Cells are Thorbis buttons with the word showing: `.ink`, `.panel`, or a
status's text on its own surface. A busy cell keeps its word while its mark turns. A swipe is
never the only path: put the same actions on the record, and on the row's own accessibility
element with `.rowSwipeAccessibility(actions)`. Job rows use `JobSwipeRow` (`../JobRowSwipes.swift`).

## ThorbisMenu

An anchored popover that grows from its trigger (overlay depth: the panel, radius 14, a real
shadow). An optional 13pt caption, ~44pt rows with a leading mark in a fixed column (`status:`
shows the status mark), a check on the current value, `.destructive` rows in their own group in the
danger tone. A chosen row's action runs after the popover has gone, so it may present a sheet.

```swift
ThorbisMenu(items: [
    ThorbisMenuItem("Dispatched", status: .dispatched, isSelected: true) {},
    ThorbisMenuItem("On my way", status: .dispatched) { start() },
    ThorbisMenuItem("Cancel", icon: "xmark.circle", role: .destructive) { cancel() },
], title: "Status") {
    statusChip   // your trigger label
}
```

## ThorbisSheet

Building blocks for a filter/display sheet: `ThorbisSheetScaffold` (grabber + optional title +
close circle), `ThorbisSheetGroup` (a rounded well) with `ThorbisSheetRow` (value + chevron-updown,
opens a `ThorbisMenu`), `ThorbisSheetToggleRow`, and `ThorbisChipGroup`. Put a
`ThorbisSheetDivider()` where rows meet (it draws nothing in v2). `DisplayOptions` is a reusable grouping/ordering
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

`.thorbisConfirm` presents a confirm modal — a clean panel sheet with the question, the
consequence, the commit (a destructive one in the danger tone) and an automatic Cancel. Use the `isPresented:` form for a Bool, or the `item:` form in
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
