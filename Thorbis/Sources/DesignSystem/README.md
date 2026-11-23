# Thorbis design system — controls

One custom control system, Linear-mobile style.

## v2 rules (31 October 2026) — Linear grammar on design.thorbis.com tokens

**Linear grammar on design.thorbis.com tokens; iPhone navigates with the Paper 18A bottom bar.**
Linear's mobile app sets the layout grammar; design.thorbis.com is the law for tokens, depth,
controls, forms, words, places and states ("Linear grammar. Not Linear dress"). The full rules are
at the top of `docs/design/ios-golden-rules.md`. Later passes must follow these:

- **Palette (Paper v2, 16 November 2026):** Paper's tokens. Dark: canvas `#1F1F1F`, card
  `#232323`, sidebar `#141414`, type `#EDEDED`. Light: canvas `#FAF9F6`, card `#FFFFFF`, sidebar
  `#F3F2EE`, type `#1A1A1A`. `Theme.field` is the sunk well under a field or select; `Theme.fill`
  is a chip or circle; `Theme.sidebar` / `sidebarAccent` are the drawer and its chosen place. One
  electric blue, `#2F6AFF` (`Theme.brand`; Paper's `#2F6BFF`, one shade off so white type on it
  holds 4.5:1), for selected, focus, switches and the one live thing. The web keeps its own accent.
  `Theme.ai*` is Paper's purple, for AI help only. Place marks: `markOlive`, `markForest`,
  `markPumpkin`, `markBurnt`, `markAccent`. `python3 scripts/tests/contrast.py` reports 0
  failures (4.5:1 text, 3:1 marks, both themes, Increase Contrast).
- **Type:** Inter 400 to 700 (`Theme.allowed()` maps heavy and black to bold). Paper's sizes
  (`Theme.onRamp`): captions 12, labels 13 (section labels Semibold), subtitles 14, body 15, rows
  16, a centred sheet title 17 Semibold, sub-heads 20, a leading sheet title 22 Bold
  (`PaperSheetTitle`), totals 24, record titles 28 / 30, and every screen title 34 Bold. Asked for
  by name: `Theme.heading()` 28 Bold, `Theme.display()` 44 Bold (the one figure a screen is
  about), `Theme.paymentAmountFont()` 52 Bold; the money hero (`Theme.moneyFont(.hero)`) is 30 on a
  phone and 34 on iPad. Customer-facing views use `Theme.customerFont` (the older ramp) to keep
  their 17pt / 56pt floors.
- **Depth:** Rest (planar sheets and panels), Sink (`fieldWell()`, `ThorbisSelect`,
  `ThorbisSheetGroup`: one step darker, inset, 1px rim), the commit (`.inkCommit()` /
  `.dangerCommit()`: a brand-blue pill, or the same pill in `destructiveFill`, 50 tall, white 16
  Semibold; pressed, the fill dims; disabled, it fades), Overlay (`ThorbisMenu` popovers and
  sheet menus). No fifth.
- **Separators (Paper v2):** `WellDivider` and `ThorbisSheetDivider` draw a hairline between rows
  inside one grouped card, inset to the row text. Never between cards or under a heading;
  `PaperCard` has no rim; no coloured side rails.
- **Status is a word:** `StatusLabel` (a small `StatusMark` in the hue, then the word). Rows lead
  with the street; the status word sits at the trailing edge (`JobRoomRow`, `MoneyListRow`,
  `CustomerListRowContent`, search) or in the subtitle (`DocumentListRowContent`). Never a
  coloured glyph without its word. A record's header carries one `RecordStatusBadge`: the word in
  the status's text colour on its surface.
- **Modals:** `ThorbisModalSheet` — a clean system sheet on the panel (`thorbisSheetPresentation`,
  no Liquid Glass), `ThorbisSheetHeader` (by default a 22 Bold title on the left with one 15pt
  muted line and a 44pt close circle on the right; with a header pill or a header commit, the close
  moves left and the title is centred at 17 Semibold; `ThorbisSheetCloseStyle` picks Cancel under
  the commit, the circle or the pill), content grouped by space with 20pt padding, fields as sunk
  wells (`ThorbisSheetField`: label, well, one slot for help or the error), one blue commit in the
  pad. Never pre-disable the commit; when it must be
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
- **Popovers and sheet menus:** `ThorbisMenu` is an anchored `.popover` with compact adaptation:
  the card tone, 56pt rows (a leading mark, the word at 16 Medium, a hairline between rows from the
  word), a check on the current value, destructive rows last, a 120ms fade. Row menus, status,
  selects and filters use it. A page's own ••• menu is a bottom sheet (`presentation: .sheet`,
  `ThorbisMenuCard`, Paper 21K / F8): its choices in 20-radius cards on `Theme.fill`.
- **Motion:** `Theme.selectionSpring` is now a 120ms ease-out (name kept); no bounce or stagger on
  routine work; haptics stay.
- **In-between states (phase 4, still current):** empty states name the one action
  (`PaperEmptyState`), loading is `SkeletonList` / `SkeletonRows`, banners are calm strips,
  toasts are `ThorbisToast` and only confirm what the screen already shows.
- **Navigation (phone):** iPhone defaults to the Paper 18A bottom bar (`PhoneTabBar`,
  `../PhoneTabBar.swift`, since 18 November 2026): a Search circle, a pill of four icon-only places
  for the role (`PhoneTabs`), then Menu (three lines), which opens the drawer, and the account circle. Settings ›
  Menu and start screen › Navigation offers the side drawer alone (`AppDrawer`,
  `../DrawerNavigation.swift`, after the Claude and ChatGPT iOS apps); iPad keeps its sidebar.
  Roots keep `DrawerMenuCircle` top left only in sidebar mode — `PaperHeader` draws it when the shell sets `\.paperDrawer` (roots only); roots without a
  Paper header or with a visible bar get it in the bar (`DrawerCircleInBar`). Pushed screens keep
  `ThorbisBackButton` alone (`.thorbisBackButton()` / `thorbisDestination`), as C-Job shows. Edge swipe opens the drawer on roots; on pushed screens it is Back.
  Which places it lists comes from `DrawerSections.make` (`../CreamSheet.swift`): exactly Paper's
  rows for the role (Navigation 29N / 57N / 58N) — the main places, then one headed group. Every
  other place opens from the screen Paper's Map gives it (`PlaceDoors`, `../PlaceDoors.swift`:
  Estimates and Invoices from Money, My scorecard from Reports, Team additions from Team, the
  rest under Settings › Other places) and from Search, which lists every place. The gear opens
  Settings; the workspace name opens Switch workspace; the menu's order is set in Settings ›
  Menu and start screen.
  Cream sheet (C-Nav.dc.html): the drawer sits on the canvas; 18pt business name + search circle;
  `PlacesList` rows (18pt mark in the place's quiet hue, filled when here, 15pt word, a tabular
  count at the trailing edge, the selected place on `Theme.fill`), 12pt section headings, Recent
  records as plain words; the list fades at its bottom edge. `DrawerDot` (brand) marks unread Inbox
  only, plus saved work needing the person on the gear. Bottom: the ink New job commit (radius 10)
  and the Settings circle (its menu: businesses, saved work, Add a business, Settings, Edit menu).
  The iPad sidebar uses the same `PlacesList` (On this iPad). New also stays in the root header's
  blue + (`PaperHeader(showsCreate: true)`). UI tests:
  `drawer-menu`, then `drawer-<id>` rows (`openDrawer()` / `openFromDrawer(_:)`, which scrolls to
  low rows, and `openSavedWorkFromDrawer()` in `ThorbisUITests`). DEBUG previews and UI tests run
  the drawer unless launched with `--paper-preview-nav bottom`; `TabBarUITests` covers the bar.
  **No stock SwiftUI controls** in app screens:
no `Menu {}`, `Picker`, `confirmationDialog`, `.buttonStyle(.bordered*)`, or `.borderedProminent`.
Everything is built from `Theme` tokens (see `../Theme.swift`) so it looks the same everywhere,
in light and dark, and scales with Dynamic Type.

## Paper primitives (fidelity pass, 17 November 2026)

Paper ("Thorbis Mobile", board "DS · Thorbis Mobile primitives") is the source of truth. These
carry Paper's own values; build screens from them before writing a one-off.

| Paper element | Use | Where |
|---------------|-----|-------|
| Any Paper icon, from its SVG path data | `PaperIcon(.menu, size: 20, color:)`, `PaperGlyph` (add new glyphs as `static let`) | `PaperIcon.swift` |
| Place header: menu circle with dot, blue +, 34 Bold title, muted subtitle | `PaperHeader(title:subtitle:showsCreate:)` | `../PaperComponents.swift` |
| Search field with filter chips and the filter circle | `PaperSearchBar(placeholder:chips:) { PaperFilterCircle(active:) }` + `PaperFilterChip` | `PaperPrimitives.swift` |
| Segments (Today / Week / Map) | `PaperTabs(options:selection:)`, `labelSize: 13` on a record | `../PaperComponents.swift` |
| Group label with count | `PaperCardLabel(title:count:)` or `countText: "4 jobs"` | `PaperPrimitives.swift` |
| One card of rows | `PaperRowsCard { rows }` with `WellDivider(leading:)` between rows | `PaperPrimitives.swift` |
| The blue pill / its tinted twin | `PaperPillLabel(title:glyph:height:tinted:)` | `PaperPrimitives.swift` |
| Any other pill button (ramp: field 60 / commit 50 / card 48 / secondary 44 / compact 36; tones brand, tinted, quiet, danger, dangerQuiet) | `PaperButtonLabel(title:glyph:symbol:size:tone:fills:busy:)` or `.paperButton(_:tone:fills:)` on a custom label | `PaperPrimitives.swift` |
| A row's chevron | `PaperChevron()` | `PaperPrimitives.swift` |
| Quiet 48pt round button (call, message) | `PaperRoundButton(glyph:label:action:)`, `PaperRoundLabel` | `PaperPrimitives.swift` |
| Avatar chip (initials) | `PaperInitials(name:size:)` / `InitialsAvatar` | `PaperPrimitives.swift`, `StatusGlyph.swift` |
| Status glyph (ring, half, check) | `StatusGlyph(tone:label:pending:size:)` | `StatusGlyph.swift` |
| Sheet chips and sort segments | `PaperChoiceChip`, `PaperSheetSegments` | `PaperPrimitives.swift` |
| Fills | `Theme.quietFill` (ink 9%), `Theme.brandTint` (brand 24%), `Theme.borderStrong`, `Theme.subtleForeground` | `PaperPrimitives.swift` |
| Times | `date.clockTime` "10:30 AM", `date.visitLabel()` "Today, 2:30 PM" | `../PaperWorkViews.swift`, `../Theme.swift` |

## What to reach for

| Need | Use | Where |
|------|-----|-------|
| Round icon button (44pt in headers and sheets, 36 in a tight row; always a 44pt hit) | `PaperCircleButton` | `../PaperComponents.swift` |
| Phone drawer, its menu circle and dot | `AppDrawer`, `DrawerMenuCircle`, `DrawerDot` | `../DrawerNavigation.swift` |
| Rimmed square button beside a commit | `PaperSquareButton` | `../PaperComponents.swift` |
| The screen's one primary action | `PrimaryButton` / `.inkCommit()` / `PaperActionBar` | `../Theme.swift`, `../PaperComponents.swift` |
| Pill segmented tabs | `PaperTabs` | `../PaperComponents.swift` |
| Status / value chip (display only) | `Chip` | `../Theme.swift` |
| Status as a word with its mark | `StatusLabel` (+ `StatusMark`) | `StatusGlyph.swift` |
| The status mark alone (inside a chip or menu row) | `StatusGlyph` (+ `StatusTone` mapping) | `StatusGlyph.swift` |
| A record's one status badge (job, customer, estimate, invoice header) | `RecordStatusBadge` | `RecordPage.swift` |
| A record page's header (reference, badge, title, one muted line) | `RecordHeader` | `RecordPage.swift` |
| Person's initials circle | `InitialsAvatar` | `StatusGlyph.swift` |
| Place mark (soft hue, outline at rest, fill when here) | `PlaceMark(filled:)` | `StatusGlyph.swift` |
| One grouped card of rows, a hairline between them | `Well` + `WellDivider` | `StatusGlyph.swift` |
| Job row on a list (street, problem · customer, when · who, status word) | `JobRoomRow` | `ListRoomRows.swift` |
| A list's group label, loading rows, empty room | `ListGroupLabel`, `ListRoomSkeleton`, `ListRoomEmpty` | `ListRoomRows.swift` |
| Customer row (initials, name, where, open job's status) | `CustomerListRowContent` | `ListRows.swift` |
| Search row's kind glyph (status, initials, place mark) | `SearchGlyph` | `ListRows.swift` |
| Estimate / invoice status as a glyph tone and word (no new `StatusTone` cases) | `DocumentStatus` | `DocumentRows.swift` |
| Estimate / invoice row (glyph, title, who · reference, semibold amount) | `DocumentListRowContent` | `DocumentRows.swift` |
| Estimate / invoice row on a v2 list (name, one line, amount over the status word) | `MoneyListRow` | `MoneyRoom.swift` |
| A line item, and the totals under the lines | `EvidenceLineRow`, `EvidenceTotalRow` | `MoneyRoom.swift` |
| Semibold tabular amount (staff screens; customer mode keeps `moneyFont`) | `Theme.amountFont(_:)` | `DocumentRows.swift` |
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
| **Confirm card** (replaces `.confirmationDialog` and `.alert`; Paper P4, centred over a scrim) | **`.thorbisConfirm`** | `ThorbisControls.swift` |
| Banner (offline, failed read, permission; Paper 73 / 74 strip) | `ErrorBanner`, `OfflineBanner`, `PermissionNotice`, `ListErrorRow` (all draw `PaperBannerStrip`) | `ThorbisStates.swift` |
| Inline "nothing here" line, spinner with words | `PaperInlineEmpty`, `ThorbisLoadingLine` | `ThorbisStates.swift` |
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

An anchored popover that grows from its trigger, on the card tone (our panel replaces Liquid
Glass). An optional 13pt caption, 56pt rows with a leading mark in a fixed column (`status:` shows the status mark), the word at 16 Medium, a hairline between rows
from the word, a check on the current value, `.destructive` rows last in the danger tone. A page's
own ••• menu passes `presentation: .sheet` and is a bottom sheet (`ThorbisMenuCard`). A chosen
row's action runs after the menu has gone, so it may present a sheet.

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
`ThorbisSheetDivider()` where rows meet (a hairline inset to the row text, as `WellDivider`
draws). `DisplayOptions` is a reusable grouping/ordering value model.

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

`.thorbisConfirm` presents the one confirm card (Paper P4): 342pt wide, centred over a 45% scrim,
radius 28, the question as a 20 Bold title that names the thing, one 15pt muted line that says
what happens, then 50pt pills: Cancel on the left, the action on the right (red when
`.destructive`, brand otherwise). The red pill repeats the verb alone ("Delete", "Remove",
"Discard", "Archive"). Several actions stack with Cancel last. `actions: []` is a notice with one
"OK"; `reason:` adds one required or optional field; `fields:` edits bound values; `cancelTitle:`
renames Cancel where the action is itself a cancel ("Keep job"). Never use `.alert`.

```swift
.thorbisConfirm("Remove this item?", isPresented: $confirm,
                actions: [ThorbisConfirmAction("Remove", role: .destructive) { remove() }])

.thorbisConfirm(item: $toRemove, title: { _ in "Remove location?" },
                message: { "Removes it from \($0.customer)." },
                actions: { loc in [ThorbisConfirmAction("Remove", role: .destructive) { remove(loc) }] })
```

> **Capture the value before dismiss.** When a Bool-driven confirm's action reads the same state
> that dismissing clears (e.g. a pending choice), capture it into a `let` before the modifier so
> the action doesn't read a blanked value. The `item:` form captures for you.

## CI guard

`scripts/lint-stock-controls.sh` flags stock controls outside this folder. The allowlist is now
empty, so any stock `Menu {}`, `Picker(`, `confirmationDialog`, bordered button style or bare
`ToolbarItem` in a screen fails the guard. Add new controls here, not in screens; the keyboard's
Done bar is `ThorbisKeyboardDoneBar`.
