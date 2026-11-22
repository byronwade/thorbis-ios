import SwiftUI

extension DynamicTypeSize {
    /// A rough multiplier for fitted-height sheets so they grow (and don't clip) at large text.
    /// Biased to over-estimate — extra height is harmless dim space; too little clips rows.
    var sheetHeightScale: CGFloat {
        switch self {
        case .xSmall, .small, .medium, .large: 1.0
        case .xLarge: 1.1
        case .xxLarge: 1.2
        case .xxxLarge: 1.35
        case .accessibility1: 1.6
        case .accessibility2: 1.9
        case .accessibility3: 2.2
        case .accessibility4: 2.5
        case .accessibility5: 2.8
        @unknown default: 1.35
        }
    }
}

// MARK: - Model

/// One row in a `ThorbisMenu`.
///
/// `role: .destructive` tints the row `Theme.destructive`. `isSelected` shows a trailing
/// checkmark. `tint` colours the leading mark only (a soft place-mark hue), never the word.
/// `status` leads the row with that status's `StatusGlyph` instead of an icon (the status picker);
/// the glyph is decorative there, the title already says where the job goes.
///
/// Sheet-era additions (all defaulted, so older call sites are unchanged):
/// - `tintsTitle`: the word takes `tint` too, not only the mark (Paper F8's amber
///   "Can't finish — pause this job": `tint: Theme.warning, tintsTitle: true`).
/// - `startsGroup`: in a sheet (`ThorbisMenuCard`) this row opens a new card (Paper 21K puts
///   "Pause job" and "Cancel job" in a second card). When no row sets it, destructive rows get
///   their own card as before. An anchored popover ignores it: it is one list.
/// - `detail`: a short trailing value in the muted tone (a step's time, "Next", "$340 due").
struct ThorbisMenuItem: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var tint: Color? = nil
    var status: StatusTone? = nil
    var isSelected: Bool = false
    var isDisabled: Bool = false
    var role: ButtonRole? = nil
    var tintsTitle: Bool = false
    var startsGroup: Bool = false
    var detail: String? = nil
    /// Paper's own glyph for the row's mark, drawn in place of `icon` (an SF symbol) when set.
    /// Set after init (`item.glyph = .x`), so no call site changes.
    var glyph: PaperGlyph? = nil
    var action: () -> Void

    init(_ title: String, icon: String? = nil, subtitle: String? = nil, tint: Color? = nil, status: StatusTone? = nil,
         isSelected: Bool = false, isDisabled: Bool = false, role: ButtonRole? = nil,
         tintsTitle: Bool = false, startsGroup: Bool = false, detail: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.status = status
        self.subtitle = subtitle
        self.tint = tint
        self.isSelected = isSelected
        self.isDisabled = isDisabled
        self.role = role
        self.tintsTitle = tintsTitle
        self.startsGroup = startsGroup
        self.detail = detail
        self.action = action
    }
}

/// How a `ThorbisMenu` shows its rows.
///
/// Paper draws two things. Pattern P-04 "Row actions" (a row's trailing more button, and the
/// selects that grow from a field) is a small anchored popover. A page's own menu (21K "More" on a
/// job, F8 the field job menu) is a bottom sheet: grabber, a title with an optional second line,
/// the choices in 20-radius cards, and a Close pill or a close circle. On iPad Paper centres that
/// same panel as a card, which is what a sheet becomes at regular width.
enum ThorbisMenuPresentation {
    /// A sheet when the caller gives sheet content (`subtitle`, `lead`, `sheetHeader` or
    /// `closeCircle`); otherwise the anchored popover.
    case automatic
    /// Always the anchored popover (Paper P-04).
    case popover
    /// Always the sheet (Paper 21K / F8).
    case sheet
}

/// Splits a sheet menu's rows into its cards (see `ThorbisMenuItem.startsGroup`).
enum ThorbisMenuGrouping {
    static func groups(_ items: [ThorbisMenuItem]) -> [[ThorbisMenuItem]] {
        if items.contains(where: { $0.startsGroup }) {
            var groups: [[ThorbisMenuItem]] = []
            for item in items {
                if item.startsGroup || groups.isEmpty {
                    groups.append([item])
                } else {
                    groups[groups.count - 1].append(item)
                }
            }
            return groups
        }
        let regular = items.filter { $0.role != .destructive }
        let destructive = items.filter { $0.role == .destructive }
        var groups: [[ThorbisMenuItem]] = []
        if !regular.isEmpty { groups.append(regular) }
        if !destructive.isEmpty { groups.append(destructive) }
        return groups
    }
}

/// Presentation state kept apart from the view so selection logic is unit-tested without UI.
struct ThorbisMenuModel {
    var isPresented = false
    /// The row chosen in an open popover; its action runs once the popover has gone, so an action
    /// that presents a sheet never collides with the closing menu.
    var pending: ThorbisMenuItem? = nil

    /// Runs the row's action and dismisses. A menu is a one-shot choice.
    mutating func select(_ item: ThorbisMenuItem) {
        item.action()
        isPresented = false
    }

    /// Popover path: close first, keep the choice for `finish()`.
    mutating func choose(_ item: ThorbisMenuItem) {
        pending = item
        isPresented = false
    }

    /// The popover has gone: run the kept choice, once.
    mutating func finish() {
        let item = pending
        pending = nil
        item?.action()
    }
}

// MARK: - Menu

/// Paper v2 (pattern P-04 "Row actions", the trailing more menu): an anchored popover that grows
/// from the control that opened it, on the card tone. Rows are 56pt: a line icon in a fixed slot
/// (a status's mark for the status picker), the word at 16 Medium, a hairline between rows that
/// starts at the word, and a check on the current value. Destructive rows come last, icon and word
/// in the danger tone. It replaces stock `Menu {}` everywhere.
///
/// It is a real `.popover` with compact adaptation, so tap-outside, VoiceOver's escape gesture and
/// focus come from the system; our panel replaces Liquid Glass (`presentationBackground`).
///
/// A page's own menu is a bottom sheet instead (Paper 21K "More", F8): pass `presentation: .sheet`,
/// or any of `subtitle`, `lead`, `sheetHeader`, `closeCircle`, which only a sheet can draw. The
/// sheet is `ThorbisMenuCard`; it fits its rows, scrolls when it cannot, opens full height at
/// accessibility sizes, and on iPad is the centred card Paper's tablet file draws. Either way the
/// chosen row's action runs after the menu has gone.
///
///     // Paper 21K, the job's More sheet
///     ThorbisMenu(items: items, title: "More", accessibilityLabel: "Job actions",
///                 presentation: .sheet, subtitle: "AC not cooling · JOB-2214") { label }
///
///     // Paper F8, the field job menu
///     ThorbisMenu(items: items, title: job.title, accessibilityLabel: "Job actions",
///                 subtitle: "JOB-2214 · Danielle Marlowe",
///                 lead: ThorbisMenuItem("Full job details", icon: "doc.text",
///                                       subtitle: "Overview, money and activity") { openDetails() },
///                 closeCircle: true, fieldMode: true) { label }
struct ThorbisMenu<Label: View>: View {
    let items: [ThorbisMenuItem]
    /// A quiet caption above the rows (e.g. the thing being changed).
    var title: String? = nil
    var accessibilityLabel: String? = nil
    /// CustomerPresentation's stronger floor (rule 13): 17pt words, 56pt rows.
    var customerFacing = false
    /// Screenshot-only: open on appear (preview flags).
    var opensOnAppear = false
    /// Where the popover's arrow sits. `.top` grows the menu down from its control, `.bottom` grows it
    /// up. Left nil (the default) it follows the control: down from the top half of the window, up
    /// from the bottom half, so a select low in a sheet (a long location list) opens where it has
    /// room instead of squeezing into the strip below it.
    var arrowEdge: Edge? = nil
    /// Popover or sheet (see `ThorbisMenuPresentation`). `.automatic` is a sheet only when one of
    /// the sheet-only parameters below is given.
    var presentation: ThorbisMenuPresentation = .automatic
    /// Sheet only: a muted second line under the title (Paper 21K "AC not cooling · JOB-2214").
    var subtitle: String? = nil
    /// Sheet only: one featured choice drawn as a brand card above the groups (Paper F8 "Full job
    /// details"): its `icon` in the brand tone, `title` at 17 Semibold, `subtitle` under it, a
    /// chevron. It is chosen like any row: the sheet closes, then its action runs.
    var lead: ThorbisMenuItem? = nil
    /// Sheet only: any view placed between the title and the choices (a summary card). It is not a
    /// choice; give it its own buttons if it needs them. Wrap it: `AnyView(MyCard())`.
    var sheetHeader: AnyView? = nil
    /// Sheet only: a 48pt close circle beside the title replaces the Close pill under the rows
    /// (Paper F8).
    var closeCircle = false
    /// Sheet only: field mode's larger rows (Paper F8: 60pt, 17 Medium, a 28pt icon slot).
    var fieldMode = false
    @ViewBuilder var label: () -> Label

    @State private var model = ThorbisMenuModel()
    /// Fixed when the menu opens, so a size-class change mid-presentation cannot swap its kind.
    @State private var opensAsSheet = false
    @State private var regularWidth = false

    private var wantsSheet: Bool {
        switch presentation {
        case .sheet: return true
        case .popover: return false
        case .automatic: return subtitle != nil || lead != nil || sheetHeader != nil || closeCircle
        }
    }

    private var popoverShown: Binding<Bool> {
        Binding(get: { model.isPresented && !opensAsSheet },
                set: { shown in if !shown { model.isPresented = false } })
    }

    private var sheetShown: Binding<Bool> {
        Binding(get: { model.isPresented && opensAsSheet },
                set: { shown in if !shown { model.isPresented = false } })
    }

    private func open() {
        opensAsSheet = wantsSheet
        regularWidth = ThorbisMenuWindow.isRegularWidth
        model.isPresented = true
    }

    var body: some View {
        Group {
            if let accessibilityLabel {
                button.accessibilityLabel(accessibilityLabel)
            } else {
                button
            }
        }
        .anchoredPopover(isPresented: popoverShown, arrowEdge: arrowEdge) {
            ThorbisMenuPanel(items: items, title: title, customerFacing: customerFacing,
                             onSelect: { model.choose($0) }, onClose: { model.isPresented = false })
                .onDisappear { model.finish() }
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Theme.surface)
        }
        // Paper 21K / F8: the page's own menu is a sheet. The row's action waits for the sheet to
        // go (`onDismiss`), so an action that presents another sheet never collides with it.
        .sheet(isPresented: sheetShown, onDismiss: { model.finish() }) {
            ThorbisMenuCard(items: items, title: title, customerFacing: customerFacing, subtitle: subtitle,
                            lead: lead, sheetHeader: sheetHeader, closeCircle: closeCircle, fieldMode: fieldMode,
                            regularWidth: regularWidth, onSelect: { model.choose($0) })
        }
        .task {
            guard opensOnAppear else { return }
            try? await Task.sleep(for: .milliseconds(900))
            open()
        }
    }

    private var button: some View {
        Button { ThorbisKeyboard.dismiss { open() } } label: { label() }
            .buttonStyle(PressStyle())
            .sensoryFeedback(.selection, trigger: model.isPresented) { _, open in open }
    }
}

/// Every anchored popover's direction (ThorbisMenu, JobStatusMenu, a list room's filter): it grows
/// down from a control in the top half of the window and up from one in the bottom half, so a
/// control low on the screen opens where there is room instead of squeezing into the strip below
/// it. An explicit `arrowEdge` wins (`.top` grows down, `.bottom` grows up).
struct AnchoredPopover<PopoverContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var arrowEdge: Edge?
    var popoverContent: () -> PopoverContent
    @State private var inLowerHalf = false

    private nonisolated static func globalMidY(_ proxy: GeometryProxy) -> CGFloat {
        proxy.frame(in: .global).midY
    }

    func body(content: Content) -> some View {
        content
            // The transform can run on SwiftUI's async render thread (mid push, say), so it only
            // reads the proxy; the main-actor window is asked in the action. Reading it in the
            // transform trapped the main-actor check and closed the app on opening a thread.
            .onGeometryChange(for: CGFloat.self, of: Self.globalMidY) { midY in
                let height = ThorbisMenuWindow.height
                inLowerHalf = height > 0 && midY > height / 2
            }
            .onAppear { ThorbisKeyboard.watch() }
            .popover(isPresented: $isPresented, arrowEdge: arrowEdge ?? (inLowerHalf ? .bottom : .top)) { popoverContent() }
    }
}

/// Opening a popover is a move away from typing. With the keyboard up, a menu growing down from a
/// select under a focused field (the invite's Role) ended behind the keyboard, and putting the
/// keyboard away at the same moment let the sheet drop and cut the menu off at the screen's foot.
/// So the keyboard goes first, and the popover opens once the layout has settled, from where its
/// control now sits.
@MainActor enum ThorbisKeyboard {
    private static var visible = false
    private static var observers: [NSObjectProtocol] = []

    /// Starts listening (idempotent); called at launch (`ThorbisApp.init`) and by every popover.
    static func watch() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { visible = true }
            },
            center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { visible = false }
            },
        ]
    }

    /// Runs `open` now, or after putting the keyboard away and letting the screen settle.
    static func dismiss(then open: @escaping @MainActor () -> Void) {
        watch()
        guard visible else { open(); return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            open()
        }
    }
}

extension View {
    /// A `.popover` that opens toward the room it has (see `AnchoredPopover`).
    func anchoredPopover<PopoverContent: View>(isPresented: Binding<Bool>, arrowEdge: Edge? = nil,
                                               @ViewBuilder content: @escaping () -> PopoverContent) -> some View {
        modifier(AnchoredPopover(isPresented: isPresented, arrowEdge: arrowEdge, popoverContent: content))
    }
}

/// The key window's height, in the global coordinate space SwiftUI reports frames in.
@MainActor enum ThorbisMenuWindow {
    private static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
    }

    static var height: CGFloat {
        keyWindow?.bounds.height ?? 0
    }

    /// The window is regular width (iPad full screen or a wide split): a menu sheet is then the
    /// centred card of Paper's tablet file, sized to its rows. Asked of the window, not the view,
    /// because a control in a sidebar column reports compact.
    static var isRegularWidth: Bool {
        keyWindow?.traitCollection.horizontalSizeClass == .regular
    }

    /// Returns once nothing in the key window is being presented or dismissed (at most about a
    /// second), so a sheet asked for right after a menu closes is not dropped mid-transition.
    static func presentationSettled() async {
        // Let a dismissal that was just requested begin before looking.
        try? await Task.sleep(for: .milliseconds(16))
        for _ in 0..<20 {
            var top = keyWindow?.rootViewController
            while let next = top?.presentedViewController { top = next }
            guard let top, top.isBeingPresented || top.isBeingDismissed else { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

/// How tall a fitted popover may be. Portrait keeps the previous 460pt cap; a compact-height
/// window (landscape phone) has to leave room for the arrow, safe area and the control the menu
/// grows from, or the first rows sit off-screen. Compact also ignores a stale portrait window
/// height after rotation, which would otherwise let the panel size itself to 460pt.
enum ThorbisMenuMetrics {
    static let portraitCap: CGFloat = 460
    static let chrome: CGFloat = 140
    static let compactChrome: CGFloat = 190
    static let compactWindowCap: CGFloat = 430
    static let minimum: CGFloat = 160

    static func maxHeight(window: CGFloat, compactHeight: Bool = false) -> CGFloat {
        if compactHeight {
            let short = window > 0 ? min(window, compactWindowCap) : 390
            return min(portraitCap, max(minimum, short - compactChrome))
        }
        if window <= 0 { return portraitCap }
        return min(portraitCap, max(minimum, window - chrome))
    }

    static func fittedHeight(estimated: CGFloat, window: CGFloat, compactHeight: Bool = false) -> CGFloat {
        min(max(estimated, 0), maxHeight(window: window, compactHeight: compactHeight))
    }
}

/// The popover's content: an optional caption, the rows, and destructive rows in their own group.
/// Sized to its rows (about 260pt wide, wider at accessibility sizes) and scrolls only when it
/// would outgrow the screen.
struct ThorbisMenuPanel: View {
    let items: [ThorbisMenuItem]
    var title: String? = nil
    var customerFacing = false
    let onSelect: (ThorbisMenuItem) -> Void
    var onClose: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var width: CGFloat {
        if customerFacing || typeSize.isAccessibilitySize { return 340 }
        return typeSize >= .xxLarge ? 300 : 264
    }

    private var rows: some View {
        ThorbisMenuRows(items: items, title: title, customerFacing: customerFacing, onSelect: onSelect)
    }

    /// A touch over the real height on purpose (Paper's 56pt rows, 58 customer-facing, plus the
    /// panel's own padding): a short estimate would make a menu that fits scroll.
    private var estimatedHeight: CGFloat {
        let row: CGFloat = customerFacing ? 59 : 57
        let rows = items.reduce(CGFloat(0)) { $0 + ($1.subtitle == nil ? row : row + 20) }
        return (rows + (title == nil ? 10 : 46)) * typeSize.sheetHeightScale
    }

    var body: some View {
        let cap = ThorbisMenuMetrics.maxHeight(window: ThorbisMenuWindow.height,
                                               compactHeight: verticalSizeClass == .compact)
        let height = min(max(estimatedHeight, 1), cap)
        // A popover sizes to its child's *ideal* height. ViewThatFits + maxHeight does not change
        // that ideal, so the gear menu still grew past a ~402pt landscape window. An explicit
        // height on a ScrollView does, and the first rows (Saved work) stay on screen.
        ScrollView {
            rows
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: width, height: height)
        // design.thorbis.com Motion: a menu fades in at 120ms ease-out; it does not fly.
        .opacity(shown || reduceMotion ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.12)) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title ?? "Menu")
        .accessibilityAction(.escape) { onClose() }
    }
}

/// The rows themselves, shared by the popover and by `ThorbisMenuCard` (a menu shown in a sheet).
///
/// Paper v2: 56pt rows, a line icon in a fixed 24pt slot, the word at 16 Medium, a hairline between
/// rows that starts at the word, destructive rows last in the danger tone. `carded` (Paper 21K, a
/// menu in a sheet) draws each group as its own 20-radius card on the field fill; left false
/// (Paper P-04, the anchored popover) the rows sit straight on the panel. `fieldMode` (Paper F8)
/// is the field job menu's larger row: 60pt, 17 Medium, a 28pt icon slot, the hairline under the
/// icon too.
struct ThorbisMenuRows: View {
    let items: [ThorbisMenuItem]
    var title: String? = nil
    var customerFacing = false
    var carded = false
    var fieldMode = false
    /// A row's press beginning and ending (see `MenuPressTravel`); nil where nothing scrolls under it.
    var pressChanged: ((Bool) -> Void)? = nil
    let onSelect: (ThorbisMenuItem) -> Void
    @ScaledMetric(relativeTo: .body) private var glyphColumn: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var fieldGlyphColumn: CGFloat = 28

    private var regular: [ThorbisMenuItem] { items.filter { $0.role != .destructive } }
    private var destructive: [ThorbisMenuItem] { items.filter { $0.role == .destructive } }
    private var cardGroups: [[ThorbisMenuItem]] { ThorbisMenuGrouping.groups(items) }
    private var rowHeight: CGFloat { fieldMode ? 60 : (customerFacing ? 58 : 56) }
    private var rule: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1).accessibilityHidden(true)
    }
    /// One row with a mark gives every row the slot, so the words share a lane.
    private var hasMarks: Bool { items.contains { $0.icon != nil || $0.glyph != nil || $0.status != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(customerFacing ? Theme.customerFont(17, weight: .medium) : Theme.font(13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, carded ? 4 : 16).padding(.top, carded ? 0 : 10).padding(.bottom, carded ? 8 : 4)
                    .accessibilityAddTraits(.isHeader)
            }
            if carded {
                // Paper 21K: each group is its own card, 16 apart. Destructive choices get their
                // own card unless the caller marks where the groups start (`startsGroup`).
                VStack(spacing: 16) {
                    ForEach(cardGroups.indices, id: \.self) { index in
                        card(cardGroups[index])
                    }
                }
            } else {
                // Paper P-04: one list, the destructive rows last behind the same hairline.
                group(regular + destructive)
            }
        }
        .padding(.vertical, carded ? 0 : 4)
    }

    private func card(_ rows: [ThorbisMenuItem]) -> some View {
        group(rows)
            .background(Theme.fill)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func group(_ rows: [ThorbisMenuItem]) -> some View {
        let firstID = rows.first?.id
        return VStack(spacing: 0) {
            ForEach(rows) { item in
                Button { onSelect(item) } label: { row(item, divided: item.id != firstID) }
                    .buttonStyle(MenuRowPressStyle(pressChanged: pressChanged))
                    .disabled(item.isDisabled)
                    .opacity(item.isDisabled ? 0.4 : 1)
            }
        }
    }

    private func row(_ item: ThorbisMenuItem, divided: Bool) -> some View {
        let isDestructive = item.role == .destructive
        let tinted: Color = item.tintsTitle ? (item.tint ?? Theme.foreground) : Theme.foreground
        let titleColor: Color = isDestructive ? Theme.destructive : tinted
        return HStack(spacing: fieldMode ? 14 : 12) {
            if hasMarks {
                mark(item, isDestructive: isDestructive).frame(width: fieldMode ? fieldGlyphColumn : glyphColumn)
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(customerFacing ? Theme.customerFont(17, weight: .medium) : Theme.font(fieldMode ? 17 : 16, weight: .medium))
                        .foregroundStyle(titleColor)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = item.subtitle {
                        Text(subtitle).font(customerFacing ? Theme.customerFont(17) : Theme.font(14)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let detail = item.detail {
                    Text(detail).font(customerFacing ? Theme.customerFont(17) : Theme.font(14)).foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                if item.isSelected {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.brandText)
                        .accessibilityHidden(true)
                }
            }
            .padding(.trailing, 16).padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
            // Paper: the hairline belongs to the words, so it starts after the icon slot.
            .overlay(alignment: .top) {
                if divided && !fieldMode { rule }
            }
        }
        // Paper F8: in field mode the hairline runs under the icon too, from the card's inset.
        .overlay(alignment: .top) {
            if divided && fieldMode { rule }
        }
        .padding(.leading, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(item.isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The row's leading mark: a status's glyph, a line icon, or the empty slot.
    @ViewBuilder
    private func mark(_ item: ThorbisMenuItem, isDestructive: Bool) -> some View {
        if let status = item.status {
            StatusGlyph(tone: status, label: item.title, size: 18)
                .accessibilityHidden(true)
        } else if let glyph = item.glyph {
            // Paper 21K: its own 22pt line glyphs in a 24pt slot, in the row's tone.
            PaperIcon(glyph, size: 22, color: isDestructive ? Theme.destructive : (item.tint ?? Theme.foreground), scales: true)
                .accessibilityHidden(true)
        } else if let icon = item.icon {
            Image(systemName: icon).font(.system(size: fieldMode ? 20 : 18, weight: .regular))
                .foregroundStyle(isDestructive ? Theme.destructive : (item.tint ?? Theme.foreground))
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(height: 1).accessibilityHidden(true)
        }
    }
}

/// A menu as a bottom sheet: what `ThorbisMenu` presents for `presentation: .sheet`, and what
/// callers that own their presentation show (Create, the dispatch board's job menu).
///
/// Paper v2 (21K "More"): the card-tone sheet under the system grabber, the title at 22 Bold with
/// an optional muted second line, the choices in 20-radius cards on the field fill (56pt rows), and
/// a Close pill under them. Paper F8 (the field job menu) swaps the pill for a 48pt close circle
/// beside the title (`closeCircle`), leads with a brand card (`lead`), and uses the larger field
/// rows (`fieldMode`). `sheetHeader` is any view between the title and the choices.
///
/// It fits its rows, scrolls when they outgrow the screen, and opens full height in a landscape
/// phone and at accessibility sizes. `regularWidth` (set by `ThorbisMenu` on iPad) draws Paper's
/// tablet version: the same panel as a centred card sized to its rows, with no grabber.
struct ThorbisMenuCard: View {
    let items: [ThorbisMenuItem]
    var title: String? = nil
    var customerFacing = false
    var subtitle: String? = nil
    var lead: ThorbisMenuItem? = nil
    var sheetHeader: AnyView? = nil
    var closeCircle = false
    var fieldMode = false
    var regularWidth = false
    let onSelect: (ThorbisMenuItem) -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @State private var travel = MenuPressTravel()

    private var hasHeaderRow: Bool { title != nil || subtitle != nil || closeCircle }

    /// A row's tap, unless the menu was scrolled under the finger (see `MenuPressTravel`).
    private func choose(_ item: ThorbisMenuItem) {
        guard !travel.scrolled else { return }
        onSelect(item)
    }

    /// A touch over the real height on purpose: a short estimate would make a menu that fits scroll.
    private var estimatedHeight: CGFloat {
        let row: CGFloat = (fieldMode ? 61 : 57) + (customerFacing ? 2 : 0)
        let rows = items.reduce(CGFloat(0)) { $0 + ($1.subtitle == nil ? row : row + 20) }
        let groups = ThorbisMenuGrouping.groups(items).count
        let gaps = CGFloat(max(groups - 1, 0)) * 16
        var header: CGFloat = 0
        if hasHeaderRow {
            let words: CGFloat = (title == nil ? 0 : 28) + (subtitle == nil ? 0 : 22)
            header = max(words, closeCircle ? 48 : 0) + 16
        }
        let leadHeight: CGFloat = lead == nil ? 0 : 88
        // The Close pill (28 above it, 50 tall).
        let close: CGFloat = closeCircle ? 0 : 78
        // 24 above the title, then the sheet's foot (12 and the home indicator).
        let total: CGFloat = 24 + header + leadHeight + rows + gaps + close + 46
        return total * dynamicTypeSize.sheetHeightScale
    }

    private var detents: Set<PresentationDetent> {
        if verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize { return [.large] }
        // A caller's own header has a height this cannot guess.
        if sheetHeader != nil { return [.medium, .large] }
        return estimatedHeight <= 600 ? [.height(estimatedHeight)] : [.medium, .large]
    }

    /// iPad: the card is as tall as its rows, never taller than the window allows.
    private var regularHeight: CGFloat {
        let window = ThorbisMenuWindow.height
        let cap: CGFloat = window > 0 ? max(240, window - 120) : 600
        if sheetHeader != nil { return min(600, cap) }
        return min(max(estimatedHeight - 24, 120), cap)
    }

    var body: some View {
        if regularWidth {
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: 460, height: regularHeight)
                .background(Theme.surface)
                .presentationSizing(.fitted)
                .presentationBackground(Theme.surface)
                .presentationCornerRadius(Theme.cardRadius + 8)
                .presentationDragIndicator(.hidden)
        } else {
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
                .background(Theme.surface)
                .presentationDetents(detents)
                .presentationBackground(Theme.surface)
                .presentationCornerRadius(Theme.cardRadius + 8)
                .presentationDragIndicator(.visible)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if hasHeaderRow { headerRow }
            if let sheetHeader { sheetHeader }
            if let lead { leadCard(lead) }
            ThorbisMenuRows(items: items, customerFacing: customerFacing, carded: true, fieldMode: fieldMode,
                            pressChanged: { travel.pressChanged($0) }, onSelect: choose)
            if !closeCircle {
                Button { dismiss() } label: {
                    Text("Close").font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.fill, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .padding(.top, 12)
            }
        }
        // Paper: 20 from the edges under a title and a Close pill (21K), 16 with the close circle (F8).
        .padding(.horizontal, closeCircle ? PaperCardMetrics.margin : Theme.gutter)
        .padding(.top, regularWidth ? 20 : 24).padding(.bottom, 12)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { travel.position = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title ?? "Menu")
        .accessibilityAction(.escape) { dismiss() }
    }

    /// Paper 21K / F8: the title at 22 Bold, a muted line under it, and (F8) the close circle.
    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            PaperSheetTitle(title: title, subtitle: subtitle)
            if closeCircle {
                PaperCircleButton(symbol: "xmark", label: "Close", size: 48, fill: Theme.fill, action: { dismiss() })
            }
        }
        .padding(.leading, closeCircle ? 4 : 0)
    }

    /// Paper F8 "Full job details": the one featured choice, a brand card with a chevron.
    private func leadCard(_ item: ThorbisMenuItem) -> some View {
        Button { onSelect(item) } label: {
            HStack(spacing: 14) {
                Image(systemName: item.icon ?? "doc.text").font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.brandText)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title).font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = item.subtitle {
                        Text(subtitle).font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PaperIcon(.chevronRight, size: 16, color: Theme.muted)
                    .frame(width: 24)
            }
            .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(Theme.brandSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(PressStyle())
        .disabled(item.isDisabled)
        .opacity(item.isDisabled ? 0.4 : 1)
    }
}

/// A menu row's press: a quiet wash over the row (square in a list or card, which clips it; rounded
/// where the row floats inside a padded card).
struct MenuRowPressStyle: ButtonStyle {
    var radius: CGFloat = 0
    var pressChanged: ((Bool) -> Void)? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.foreground.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onChange(of: configuration.isPressed) { _, pressed in pressChanged?(pressed) }
    }
}

/// How far a sheet menu's rows have moved since a press began. A press that rests on a row and
/// then scrolls the menu (or drags the sheet taller) is not cancelled: the row stays pressed, moves
/// with the finger, and would be chosen when the finger lifts. The sheet compares where its rows
/// were when the press began with where they are when the row reports its tap, and lets a tap
/// through only when they have not moved. A plain class: it changes on every scrolled point and
/// nothing draws from it.
@MainActor final class MenuPressTravel {
    /// The rows' top edge on screen, now.
    var position: CGFloat = 0
    /// The same edge when the current press began; nil with no press (a VoiceOver activation).
    private var pressedAt: CGFloat?

    func pressChanged(_ pressed: Bool) {
        if pressed {
            pressedAt = position
        } else {
            // The tap, when there is one, is reported in this same turn; forget the press after it.
            Task { @MainActor [weak self] in self?.pressedAt = nil }
        }
    }

    /// The rows moved under the finger: this was a scroll, not a choice.
    var scrolled: Bool {
        guard let pressedAt else { return false }
        return abs(position - pressedAt) > 10
    }
}

#if DEBUG
#Preview("ThorbisMenu panel") {
    ThorbisMenuPanel(items: [
        ThorbisMenuItem("Dispatched", status: .dispatched, isSelected: true) {},
        ThorbisMenuItem("On my way", status: .dispatched) {},
        ThorbisMenuItem("Start work", status: .inProgress) {},
        ThorbisMenuItem("Cancel trip", icon: "xmark.circle", role: .destructive) {},
    ], title: "Status") { _ in }
    .background(Theme.surface)
}
#endif
