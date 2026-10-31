import SwiftUI
import UIKit

struct ThorbisLogoLockup: View {
    var markSize: CGFloat = 30
    var wordmarkSize: CGFloat = 16

    var body: some View {
        HStack(spacing: markSize * 0.3) {
            Image("ThorbisMark")
                .resizable()
                .scaledToFit()
                .frame(width: markSize, height: markSize)
                .accessibilityHidden(true)
            Text("Thorbis")
                .font(Theme.font(wordmarkSize, weight: .medium))
                .foregroundStyle(Theme.foreground)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Thorbis")
    }
}

/// The tab-root header (redesign 2026-10-31, after Linear): a 34pt semibold title with round circles
/// at top right (filter, then + on tab roots that opt in), then one muted subtitle line. On iPad a
/// 44-tall top row holds the menu button. The title scrolls with its content; the tab bar stays put.
struct PaperHeader: View {
    let title: String
    var icon: String = ""
    let subtitle: String
    /// Opens this list's real filters (status, ordering). Never a search: that is the bar's Search.
    var filter: (() -> Void)? = nil
    /// Secondary filters as a menu behind the same circle (one selector row per screen).
    var filterMenu: [ThorbisMenuItem]? = nil
    /// Shows the circle as on while a filter narrows the screen.
    var filterActive = false
    /// Tab roots show the shell's + (New job / estimate / customer) beside the filter.
    var showsCreate = false
    @Environment(\.paperCreate) private var create
    @EnvironmentObject private var session: SessionController
    @Environment(\.paperShowMenu) private var openAccount
    @Environment(\.paperMenuButton) private var showsMenuButton

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The menu button sits top-left on iPad. On iPhone the bottom bar opens the menu, so the
            // filter joins the title's line and no near-empty row sits above it.
            if showsMenuButton {
                HStack(alignment: .center, spacing: 8) {
                    PaperCircleButton(symbol: "line.3.horizontal", label: "Open menu", action: openAccount)
                    Spacer(minLength: 0)
                    filterButton
                    createButton
                }
                .frame(minHeight: 44)
            }
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(Theme.font(34, weight: .semibold)).tracking(-0.8)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if !showsMenuButton {
                    filterButton
                    createButton
                }
            }
            Text(subtitle)
                .font(Theme.font(15)).foregroundStyle(Theme.muted)
                .lineLimit(2)
                .frame(minHeight: 20, alignment: .leading)
        }
        .foregroundStyle(Theme.foreground)
        .padding(.horizontal, Theme.gutter).padding(.top, showsMenuButton ? 2 : 12).padding(.bottom, 12)
    }

    /// The tab root's +. Several creates open the create menu; a long press lists them directly.
    @ViewBuilder private var createButton: some View {
        if showsCreate, let create {
            PaperCircleButton(symbol: "plus", label: create.label, size: 40, fill: Theme.fill, action: create.run)
                .contextMenu {
                    ForEach(create.choices) { choice in
                        Button(action: choice.run) { Label(choice.title, systemImage: choice.symbol) }
                    }
                }
                .accessibilityIdentifier("header-create")
        }
    }

    /// Filters this list; the bar's Search finds anything. Different glyphs, different jobs.
    @ViewBuilder private var filterButton: some View {
        let symbol = "line.3.horizontal.decrease"
        if let filterMenu, !filterMenu.isEmpty {
            ThorbisMenu(items: filterMenu, title: "Show", accessibilityLabel: "Filter \(title.lowercased())") {
                PaperCircleLabel(symbol: symbol, size: 40, fill: filterActive ? Theme.brandSurface : Theme.fill)
            }
            .accessibilityValue(filterActive ? "Filtered" : "")
            .accessibilityIdentifier("header-filter")
        } else if let filter {
            PaperCircleButton(symbol: symbol, label: "Filter \(title.lowercased())", size: 40,
                              fill: filterActive ? Theme.brandSurface : Theme.fill, action: filter)
                .accessibilityValue(filterActive ? "Filtered" : "")
        }
    }
}

/// A 36pt filled circle with a 44pt hit area (HIG-004).
struct PaperCircleButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 36
    /// Canvas fill; use `Theme.card` with `bordered` on a cream ground so the circle reads as a button.
    var fill: Color = Theme.fill
    var bordered = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PaperCircleLabel(symbol: symbol, size: size, fill: fill, bordered: bordered)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

/// The look of `PaperCircleButton` on its own, for controls that are not a plain `Button`
/// (a `ShareLink`, a `ThorbisMenu`): a filled circle inside a 44pt hit area.
struct PaperCircleLabel: View {
    let symbol: String
    var size: CGFloat = 36
    var fill: Color = Theme.fill
    var bordered = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.foreground)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .overlay { if bordered { Circle().strokeBorder(Theme.border.opacity(0.6), lineWidth: 1) } }
            .frame(width: max(44, size), height: max(44, size)).contentShape(Rectangle())
    }
}

/// Paper's segment tabs: quiet words, the selected one sits in a fill pill.
struct PaperTabs: View {
    let options: [String]
    @Binding var selection: String
    /// Keep every destination visible when a compact screen cannot fit one row.
    var wrapOverflow = false
    /// Offer a button as well as a swipe when a row has hidden sections.
    var explicitScrollControl = false
    /// Linear text tabs (redesign 2026-10-31): plain words on the ground, the chosen one on a light
    /// well pill, left-aligned under the large title. Used by Today; other screens keep the segments.
    var textTabs = false
    /// True while tabs remain past the trailing edge; the fade shows only then, so the
    /// last tab is never left dimmed once you've scrolled to it.
    @State private var moreTrailing = true
    /// The width offered to the tabs, and each label's natural width, measured on the main actor.
    @State private var available: CGFloat = 0
    @State private var labelWidths: [String: CGFloat] = [:]
    @Environment(\.dynamicTypeSize) private var typeSize

    /// One-row spacings, loosest first, each with its outer inset. The job's five tabs need the
    /// tighter ones on a 402pt phone; a cut-off "Acti" reads as a bug. The tightest is only for
    /// callers that would otherwise wrap; each tab keeps its 44-point minimum and full label.
    private var candidates: [(padding: CGFloat, inset: CGFloat)] {
        var all: [(padding: CGFloat, inset: CGFloat)] = [(12, Theme.gutter), (8, Theme.gutter), (6, Theme.gutter - 6)]
        if wrapOverflow { all.append((3, Theme.gutter - 6)) }
        return all
    }

    /// The loosest one-row spacing that fits, or nil when none does. Chosen here rather than with
    /// `ViewThatFits`: that builds candidate rows lazily during layout, which SwiftUI can run on its
    /// async render thread, and the main-actor tab content then traps (crash in `row(padding:)`).
    private var fittingCandidate: (padding: CGFloat, inset: CGFloat)? {
        // Until measured, start from the loosest row; the measurement settles it before the next frame.
        guard available > 0, options.allSatisfy({ labelWidths[$0] != nil }) else { return candidates.first }
        return candidates.first { candidate in
            let tabs = options.reduce(CGFloat(0)) { $0 + max(44, (labelWidths[$1] ?? 0) + candidate.padding * 2) }
            // The segmented track adds 3 on each side.
            return tabs + CGFloat(max(0, options.count - 1)) * 2 + 6 + candidate.inset * 2 <= available + 0.5
        }
    }

    var body: some View {
        // Fit one row where possible. Compact layouts can wrap; other callers keep
        // the scrolling fallback and its trailing fade.
        Group {
            if typeSize.isAccessibilitySize {
                // Accessibility sizes: the job screen's chooser. Three words at XXXL never fit one
                // row, and a row of fixed-width words would widen the whole screen past its edges.
                accessibleChooser
            } else if textTabs {
                HStack(spacing: 4) {
                    ForEach(options, id: \.self) { option in tab(option, padding: 12) }
                }
                .padding(.horizontal, Theme.gutter - 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let fit = fittingCandidate {
                // design 2026-10-30: one selector style everywhere, the segmented pill. A field
                // track, the chosen segment raised as a white pill, every segment the same width.
                // Segments are 44 tall (golden rule 13); the white pill is inset 3 inside them.
                row(padding: fit.padding, tracked: true)
                    .padding(.horizontal, 3)
                    .background(Theme.fill, in: Capsule())
                    .padding(.horizontal, fit.inset)
            } else if wrapOverflow {
                FlowRow(spacing: 2, lineSpacing: 0) {
                    ForEach(options, id: \.self) { option in
                        tab(option, padding: 8)
                    }
                }
                .padding(.horizontal, Theme.gutter - 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    HStack(spacing: 0) {
                        ScrollView(.horizontal) {
                            row(padding: explicitScrollControl ? 6 : 12).padding(.horizontal, Theme.gutter - 4)
                        }
                        .scrollIndicators(.hidden)
                        .onScrollGeometryChange(for: Bool.self) { geometry in
                            geometry.contentOffset.x + geometry.containerSize.width < geometry.contentSize.width - 1
                        } action: { _, value in
                            moreTrailing = value
                        }
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0.88),
                                                     .init(color: moreTrailing ? .clear : .black, location: 1)],
                                             startPoint: .leading, endPoint: .trailing))
                        .onChange(of: selection) { _, value in
                            withMotion(.easeOut(duration: 0.2)) { proxy.scrollTo(value, anchor: .center) }
                        }
                        if explicitScrollControl, let first = options.first, let last = options.last {
                            Button {
                                withMotion(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(moreTrailing ? last : first, anchor: moreTrailing ? .trailing : .leading)
                                }
                            } label: {
                                Image(systemName: moreTrailing ? "chevron.right" : "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(moreTrailing ? "Show more job sections" : "Show first job sections")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
        .background(alignment: .topLeading) { labelMeasurement }
        .padding(.bottom, 4)
        .sensoryFeedback(.selection, trigger: selection)
    }

    /// One full-width row naming the chosen section; it opens a menu of every section.
    private var accessibleChooser: some View {
        ThorbisMenu(items: options.map { option in
            ThorbisMenuItem(option, isSelected: option == selection) { selection = option }
        }, title: "Show", accessibilityLabel: "Showing \(selection)") {
            HStack(spacing: 12) {
                Text(selection).font(Theme.font(15, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .accessibilityHint("Choose what to show")
        .padding(.horizontal, Theme.gutter)
    }

    /// Each label at its natural width, unseen. Weight does not change with selection, so
    /// selecting a tab never re-measures.
    private var labelMeasurement: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Text(option).font(Theme.font(15, weight: .medium)).lineLimit(1).fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidths[option] = $0 }
            }
        }
        .fixedSize()
        .hidden()
        .accessibilityHidden(true)
    }

    private func row(padding: CGFloat, tracked: Bool = false) -> some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                tab(option, padding: padding, tracked: tracked)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tab(_ option: String, padding: CGFloat, tracked: Bool = false) -> some View {
        let on = selection == option
        return Button { selection = option } label: {
            if tracked {
                // Fixed width so a long word ("All customers") may use its neighbours' padding rather
                // than truncate; accessibility sizes, where a row of these widened the whole screen,
                // never get here (they use `accessibleChooser`).
                Text(option).font(Theme.font(15, weight: .medium)).lineLimit(1).fixedSize()
                    .foregroundStyle(on ? Theme.foreground : Theme.muted)
                    .padding(.horizontal, padding)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        if on {
                            Capsule().fill(Theme.selectedSegment).shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
                                .padding(.vertical, 3)
                        }
                    }
                    .contentShape(Capsule())
            } else {
                Text(option).font(Theme.font(15, weight: .medium)).lineLimit(1).fixedSize()
                    .foregroundStyle(on ? Theme.foreground : Theme.muted)
                    .padding(.horizontal, padding).padding(.vertical, 6)
                    .frame(minHeight: Theme.chipHeight + 4)
                    .background(on ? Theme.fill : .clear, in: Capsule())
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
        }
        .buttonStyle(PressStyle())
        .id(option)
        .accessibilityAddTraits(selection == option ? .isSelected : [])
    }
}

/// The muted line above a page title. Only the reference ("JOB-2214") is mono so its digits
/// line up; names and words read in the 13pt body face.
struct PaperEyebrow: View {
    var reference: String? = nil
    var text: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the name goes under the reference instead of being cut to "Danielle…".
        let stacked = typeSize.isAccessibilitySize && reference != nil && text != nil
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 6))
        layout {
            if let reference { Text(reference).font(Theme.monoFont(12, weight: .medium)).fixedSize() }
            if reference != nil, text != nil, !stacked { Text("·").font(Theme.font(13)) }
            if let text { Text(text).font(Theme.font(13)).lineLimit(typeSize.isAccessibilitySize ? 2 : 1) }
        }
        .foregroundStyle(Theme.muted)
        .accessibilityElement(children: .combine)
    }
}

/// Sentence-case group header: 13/500 muted title, mono count (left out at zero, where the
/// empty state below already says so), optional trailing action.
struct PaperGroupHeader<Trailing: View>: View {
    let title: String
    var count: Int? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            // "Later today · 3": one label, the count in the same voice.
            Text(count.flatMap { $0 > 0 ? "\(title) · \($0)" : nil } ?? title)
                .font(Theme.font(13, weight: .medium)).monospacedDigit()
            Spacer(minLength: 0)
            trailing
        }
        .foregroundStyle(Theme.muted)
        .frame(minHeight: 32)
        .accessibilityElement(children: .contain)
    }
}

extension PaperGroupHeader where Trailing == EmptyView {
    init(title: String, count: Int? = nil) {
        self.init(title: title, count: count) { EmptyView() }
    }
}

/// Job status as a mark whose shape (not only colour) carries meaning, plus a spoken word.
struct StatusRing: View {
    let status: String
    var size: CGFloat = 16

    var body: some View {
        let (symbol, color) = statusIcon(status)
        Image(systemName: symbol)
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(color)
            .frame(width: size + 6, height: size + 6)
            .accessibilityLabel(status.statusLabel)
    }
}

/// Paper's quick-edit value row: muted label left, value right.
struct PaperDetailRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        // A short value sits on the label's line; a long one (gate codes, notes) goes under it,
        // left-aligned, instead of a ragged right-aligned paragraph.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label).font(Theme.font(15)).foregroundStyle(Theme.muted).fixedSize()
                Spacer(minLength: 8)
                value.font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(Theme.font(15)).foregroundStyle(Theme.muted)
                value.font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

extension PaperDetailRow where Value == Text {
    init(_ label: String, value: String) {
        self.init(label: label) { Text(value) }
    }
    /// MF-02: an amount in a detail row reads at the line size in tabular mono.
    init(_ label: String, money: String) {
        self.init(label: label) { Text(money).font(Theme.moneyFont(.line)).monospacedDigit() }
    }
}

/// A row in a grouped list of destinations or settings (Paper 29 / 65).
struct PaperMenuRow<Trailing: View>: View {
    let title: String
    let symbol: String
    var subtitle: String? = nil
    var tint: Color = Theme.foreground
    /// A softly tinted mark, so a long menu scans by color after the word.
    var tile: Color? = nil
    /// Inside a card the mark sits in an `IconTile` well, like every other card row.
    var filled = false
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: filled ? 12 : 14) {
            if filled {
                // design 2026-10-30: a neutral glyph, never a coloured tile.
                Image(systemName: symbol).font(.system(size: 17))
                    .foregroundStyle(tint == Theme.foreground ? Theme.muted : tint)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            } else if let tile {
                // D-020 outline mark at rest; quiet hue on the mark only, never a filled tile.
                Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(tile)
                    .frame(width: 22)
            } else {
                Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(tint == Theme.foreground ? Theme.muted : tint)
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.font(15, weight: .medium)).foregroundStyle(tint)
                if let subtitle {
                    Text(subtitle).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .lineLimit(filled && !typeSize.isAccessibilitySize ? 2 : nil)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, filled ? PaperCardMetrics.inset : 0).padding(.vertical, filled ? 10 : 0)
        .frame(minHeight: filled ? 52 : 48).contentShape(Rectangle())
    }
}

extension PaperMenuRow where Trailing == AnyView {
    /// A navigable row. design 2026-10-30: no chevron on every row; the row itself is the target.
    init(_ title: String, symbol: String, subtitle: String? = nil, value: String? = nil, tile: Color? = nil, filled: Bool = false) {
        self.init(title: title, symbol: symbol, subtitle: subtitle, tile: tile, filled: filled) {
            AnyView(HStack(spacing: 6) {
                if let value { Text(value).font(Theme.font(15)).foregroundStyle(Theme.muted).monospacedDigit() }
            })
        }
    }
}

/// The sticky bottom bar: one ink commit (MA-08), at most one quiet square beside it.
struct PaperActionBar<Secondary: View>: View {
    let title: String
    var symbol: String? = nil
    var busy = false
    var disabled = false
    let action: () -> Void
    @ViewBuilder var secondary: Secondary

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 7) {
                    if busy { ProgressView().tint(Theme.onInk) } else if let symbol { Image(systemName: symbol).font(.subheadline.weight(.medium)).accessibilityHidden(true) }
                    Text(title)
                }
                .inkCommit(enabled: !disabled)
            }
            .buttonStyle(PressStyle())
            .disabled(busy || disabled)
            secondary
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 10).padding(.bottom, 8)
        .background(Theme.background)
    }
}

extension PaperActionBar where Secondary == EmptyView {
    init(title: String, symbol: String? = nil, busy: Bool = false, disabled: Bool = false, action: @escaping () -> Void) {
        self.init(title: title, symbol: symbol, busy: busy, disabled: disabled, action: action) { EmptyView() }
    }
}

/// The rimmed square that sits beside a commit, as tall as the commit.
struct PaperSquareButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(Theme.foreground)
                .frame(width: Theme.commitHeight, height: Theme.commitHeight)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).stroke(Theme.border))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

struct PaperSearchField: View {
    @Binding var text: String
    var prompt: String = "Search"
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField(prompt, text: $text).textInputAutocapitalization(.never).autocorrectionDisabled()
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted).frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Clear search") }
        }.font(Theme.font(16)).padding(.leading, 12).frame(minHeight: 44).background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).stroke(Theme.border)).padding(.horizontal, Theme.gutter).padding(.bottom, 12)
    }
}

enum PaperChrome {
    /// Inter titles on the native navigation bar, so pushed screens keep system
    /// back, swipe-back and VoiceOver escape while matching Paper's type.
    @MainActor static func configureNavigationBar() {
        func inter(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let descriptor = UIFontDescriptor(fontAttributes: [
                .family: "Inter",
                .traits: [UIFontDescriptor.TraitKey.weight: weight]
            ])
            return UIFontMetrics.default.scaledFont(for: UIFont(descriptor: descriptor, size: size))
        }
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.font: inter(17, .medium)]
        appearance.largeTitleTextAttributes = [.font: inter(30, .medium)]
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.titleTextAttributes = appearance.titleTextAttributes
        scrolled.largeTitleTextAttributes = appearance.largeTitleTextAttributes
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}

private struct PaperMenuButtonKey: EnvironmentKey {
    static let defaultValue = true
}
extension EnvironmentValues {
    /// Whether tab-root headers show the top-left menu button. iPhone turns it off for the bottom bar.
    var paperMenuButton: Bool {
        get { self[PaperMenuButtonKey.self] }
        set { self[PaperMenuButtonKey.self] = newValue }
    }
}

private struct PaperShowMenuKey: EnvironmentKey {
    static let defaultValue: @Sendable () -> Void = {}
}
extension EnvironmentValues {
    /// Opens account and settings (the More tab on iPhone, the settings sheet on iPad).
    var paperShowMenu: @Sendable () -> Void {
        get { self[PaperShowMenuKey.self] }
        set { self[PaperShowMenuKey.self] = newValue }
    }
}

/// The header + (redesign 2026-10-31: New moved from the bar into the tab roots' headers).
/// One choice starts it directly; several open the create menu, and a long press lists them.
struct PaperCreateAction: @unchecked Sendable {
    let label: String
    let run: () -> Void
    var choices: [AppBottomBar.QuickAction] = []
}

private struct PaperCreateKey: EnvironmentKey {
    static let defaultValue: PaperCreateAction? = nil
}
private struct PaperOpenPlaceKey: EnvironmentKey {
    static let defaultValue: (@Sendable (MenuItem) -> Void)? = nil
}
private struct PaperManageBusinessesKey: EnvironmentKey {
    static let defaultValue: (@Sendable () -> Void)? = nil
}
extension EnvironmentValues {
    /// What a tab root's + starts. Nil (iPad, or nothing this person may create) hides the circle.
    var paperCreate: PaperCreateAction? {
        get { self[PaperCreateKey.self] }
        set { self[PaperCreateKey.self] = newValue }
    }
    /// Opens a place the way the bar would (More lists every place). Nil where the shell has its own
    /// list of places (the iPad sidebar), so More leaves out places it could not open.
    var paperOpenPlace: (@Sendable (MenuItem) -> Void)? {
        get { self[PaperOpenPlaceKey.self] }
        set { self[PaperOpenPlaceKey.self] = newValue }
    }
    /// Opens the business list to add or manage businesses, when the shell offers it.
    var paperManageBusinesses: (@Sendable () -> Void)? {
        get { self[PaperManageBusinessesKey.self] }
        set { self[PaperManageBusinessesKey.self] = newValue }
    }
}

/// Paper 73 / 74: offline, syncing and needs-review states. Queued is never shown as done.
struct OfflineBanner: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var outbox: FieldOutbox
    @EnvironmentObject private var media: PendingMediaStore
    @Environment(\.savedWorkReviewReturnToRoot) private var returnToReview
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var reviewScope: SavedWorkScope?

    private var scope: SavedWorkScope? { .capture(session: session, api: api, media: media, outbox: outbox) }
    private var reviewIsCurrent: Bool { reviewScope?.isCurrent(session: session, api: api, media: media, outbox: outbox) ?? true }
    private var snapshot: SavedWorkSnapshot? {
        guard let scope else { return nil }
        return .make(scope: scope, entries: outbox.entries, media: media.items, mediaErrors: media.errors,
                     unverifiedMediaIDs: media.unverifiedIDs, uploadingMediaID: media.uploadingID,
                     commandsSyncing: outbox.syncing, jobs: store.jobs, listingWarning: media.storageWarning)
    }
    var body: some View {
        Group {
            if let state = snapshot, state.hasPendingWork {
                Button {
                    if let returnToReview { returnToReview() }
                    else { reviewScope = scope }
                } label: {
                    banner(symbol: state.attentionCount > 0 || state.hasListingWarning ? "exclamationmark.triangle" : (session.isOffline ? "wifi.slash" : "arrow.triangle.2.circlepath"),
                           tint: state.attentionCount > 0 || state.hasListingWarning ? Theme.warning : Theme.muted,
                           text: summary(state), trailing: state.totalCount == 0 ? String(localized: "Review") : (state.totalCount == 1 ? String(localized: "1 item") : String(localized: "\(state.totalCount) items")))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Review saved work")
                .accessibilityValue(summary(state) + ", " + String(localized: "\(state.totalCount) items listed"))
                .accessibilityIdentifier("saved-work-summary")
            } else if session.isOffline {
                banner(symbol: "wifi.slash", tint: Theme.warning,
                       text: "Offline · showing \(store.cachedAt.map { "work saved " + $0.formatted(.relative(presentation: .named)) } ?? "your last copy")", trailing: nil)
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.bottom, 10)
        .sheet(item: $reviewScope) { SavedWorkReviewView(scope: $0) }
        .onChange(of: reviewIsCurrent) { _, valid in if !valid { reviewScope = nil } }
        #if DEBUG
        .task { await PaperPreview.activateSavedWorkScenario(session: session) }
        #endif
    }
    private func summary(_ state: SavedWorkSnapshot) -> String {
        if state.hasListingWarning { return String(localized: "Saved work needs checking") }
        if state.attentionCount > 0 { return String(localized: "Saved work needs attention") }
        if session.isOffline { return String(localized: "Offline · saved on this phone") }
        return state.isSending ? String(localized: "Syncing saved work") : String(localized: "Saved on this phone")
    }
    private func banner(symbol: String, tint: Color, text: String, trailing: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(tint).accessibilityHidden(true)
            // At accessibility sizes the count reads under the words, which then keep the width.
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                                      : AnyLayout(HStackLayout(spacing: 10))
            layout {
                Text(text).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground).fixedSize(horizontal: false, vertical: true)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                if let trailing { Text(trailing).font(Theme.monoFont(13, weight: .medium)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// One row of the actions people reach for on a person or a place: call, text, email, drive.
/// Used on the job and customer headers so the pattern is the same everywhere.
struct PaperQuickActions: View {
    var phone: String?
    var email: String?
    var directions: URL?
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var dialable: String? {
        phone.map { $0.filter { $0.isNumber || $0 == "+" } }.flatMap { $0.count >= 7 ? $0 : nil }
    }

    var body: some View {
        let dialable = dialable
        let mail = email.flatMap { $0.contains("@") ? URL(string: "mailto:\($0)") : nil }
        if dialable != nil || mail != nil || directions != nil {
            if dynamicTypeSize.isAccessibilitySize {
                row(dialable: dialable, mail: mail, stacked: false, vertical: true)
            } else {
                // At standard sizes, use the compact row while every label fits.
                ViewThatFits(in: .horizontal) {
                    row(dialable: dialable, mail: mail, stacked: false)
                    row(dialable: dialable, mail: mail, stacked: true)
                }
            }
        }
    }

    private func row(dialable: String?, mail: URL?, stacked: Bool, vertical: Bool = false) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            if let dialable, let call = URL(string: "tel:\(dialable)"), let text = URL(string: "sms:\(dialable)") {
                action("Call", symbol: "phone", label: "Call", stacked: stacked) { openURL(call) }
                action("Text", symbol: "message", label: "Text", stacked: stacked) { openURL(text) }
            }
            if let mail { action("Email", symbol: "envelope", label: "Email", stacked: stacked) { openURL(mail) } }
            if let directions { action("Directions", symbol: "arrow.triangle.turn.up.right.diamond", label: "Directions in Maps", stacked: stacked) { openURL(directions) } }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func action(_ title: String, symbol: String, label: String, stacked: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            // Glyph then word: the same reach as a tile, in less height.
            let layout = stacked ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 6))
            layout {
                // A fixed glyph box keeps every word on one baseline, whatever the symbol's height.
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.brandText)
                    .frame(width: 22, height: 20)
                Text(title).font(Theme.font(stacked ? 13 : 15, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
            }
            .padding(.horizontal, stacked ? 4 : 10)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : (stacked ? 6 : 0))
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: dynamicTypeSize.isAccessibilitySize ? nil : .infinity)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

/// Lays chips out left to right and wraps to a new line when they run out of room.
struct FlowRow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = measuredSize(of: view, width: width)
            if x > 0 && x + size.width > width { x = 0; y += lineHeight + lineSpacing; lineHeight = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Break into lines first, then center each chip on its line so mixed hit areas align.
        var lines: [[(Subviews.Element, CGSize)]] = [[]]
        var x: CGFloat = 0
        for view in subviews {
            let size = measuredSize(of: view, width: bounds.width)
            if x > 0 && x + size.width > bounds.width { lines.append([]); x = 0 }
            lines[lines.count - 1].append((view, size))
            x += size.width + spacing
        }
        var y = bounds.minY
        for line in lines where !line.isEmpty {
            let height = line.map(\.1.height).max() ?? 0
            var x = bounds.minX
            for (view, size) in line {
                view.place(at: CGPoint(x: x, y: y + (height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += height + lineSpacing
        }
    }

    private func measuredSize(of view: Subviews.Element, width: CGFloat) -> CGSize {
        let natural = view.sizeThatFits(.unspecified)
        guard natural.width > width else { return natural }
        return view.sizeThatFits(ProposedViewSize(width: max(0, width), height: nil))
    }
}


/// One "more" control for an editable line (MA-12): keeps the description wide instead of
/// three icon buttons beside it.
struct LineItemActions: View {
    let name: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        var items: [ThorbisMenuItem] = []
        if canMoveUp { items.append(ThorbisMenuItem("Move up", icon: "arrow.up") { moveUp() }) }
        if canMoveDown { items.append(ThorbisMenuItem("Move down", icon: "arrow.down") { moveDown() }) }
        items.append(ThorbisMenuItem("Remove line", icon: "trash", role: .destructive) { remove() })
        return ThorbisMenu(items: items,
                           accessibilityLabel: "Actions for \(name.isEmpty ? "line item" : name)") {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
}

/// A number field on a line: a 44-tall well so the thumb can hit it, readable mono type.
struct LineNumberField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var prefix: String?
    var decimal = false
    var width: CGFloat = 64

    var body: some View {
        HStack(spacing: 4) {
            if let prefix { Text(prefix).font(Theme.monoFont(15)).foregroundStyle(Theme.muted) }
            TextField(placeholder, text: $text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .font(Theme.monoFont(15, weight: .medium))
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(label)
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: 44)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}

/// The keyboard's Done bar floats over the screen above the keyboard, outside the keyboard safe
/// area, so a focused field or row could sit under it and swallow taps. While the keyboard is up,
/// the content's safe area also clears the bar.
private struct KeyboardDoneButton: ViewModifier {
    @State private var keyboardShown = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: keyboardShown ? 52 : 0).allowsHitTesting(false)
            }
            .toolbar {
                ThorbisKeyboardDoneBar {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardShown = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardShown = false }
    }
}

extension View {
    /// Number pads have no return key: one Done above the keyboard (MA-16).
    func keyboardDoneButton() -> some View {
        modifier(KeyboardDoneButton())
    }

    /// Cancel and swipe never throw away edits silently (MA-16, MA-17).
    func discardChangesGuard(hasChanges: Bool, busy: Bool, isPresented: Binding<Bool>, discard: @escaping () -> Void) -> some View {
        interactiveDismissDisabled(busy || hasChanges)
            .thorbisConfirm("Discard your changes?", isPresented: isPresented,
                            actions: [ThorbisConfirmAction("Discard changes", role: .destructive, action: discard)])
    }
}

/// The list's create action, in the thumb zone above the tab bar (MA-02): the same pill on
/// Jobs and Customers instead of a plus on one screen and a pill on the other.
struct FloatingCreateButton: View {
    let title: String
    var disabled = false
    let action: () -> Void
    /// On iPhone the bottom bar's + holds every create, so this pill steps aside.
    @Environment(\.paperMenuButton) private var visible

    var body: some View {
        if visible { pill }
    }

    private var pill: some View {
        HStack {
            Spacer()
            Button(action: action) {
                Label(title, systemImage: "plus").font(Theme.font(15, weight: .medium))
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Theme.card, in: Capsule()).overlay(Capsule().stroke(Theme.border))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle()).disabled(disabled)
        }
        .padding(.horizontal, Theme.gutter).padding(.bottom, 8)
    }
}

/// Row disclosure chevron: one size, weight and colour for every tappable row.
struct PaperDisclosure: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.muted)
            .accessibilityHidden(true)
    }
}

extension PaperEmptyState {
    /// No-results state for a search, in Paper type instead of the system's SF Pro view.
    static func search(_ text: String) -> PaperEmptyState {
        PaperEmptyState(symbol: "magnifyingglass", title: "No results for \u{201C}\(text)\u{201D}",
                        message: "Check the spelling or try a different word.")
    }
}

// MARK: - Planar card groups (approved visual design, 2026-10-30)
//
// Groups of rows sit on one planar panel: `Theme.card`, radius 14, a 1px `Theme.border` rim that
// follows the radius, no shadow and no hairlines between rows (design.thorbis.com: "a border is a
// use case, never a separator"; golden rule 9). Rows are separated by spacing and lead with an icon
// tile; a status is always a word, the tile's colour only reinforces it.

enum PaperCardMetrics {
    /// design.thorbis.com sheet radius.
    static let radius: CGFloat = Theme.cardRadius
    /// Rows inside a card pad by this, so their text lines up with the card's edge.
    static let inset: CGFloat = 14
    /// The card's distance from the screen edge; group headers add 4 so they align with the gutter.
    static let margin: CGFloat = 16
    /// Breathing room above the first and below the last row, instead of a rule between rows.
    static let edge: CGFloat = 4
}

/// Rows pad horizontally by this. Outside a card it is the screen gutter, so a row used on the
/// bare background is unchanged; inside a card it is the card's inset.
private struct PaperRowInsetKey: EnvironmentKey { static let defaultValue: CGFloat = Theme.gutter }
extension EnvironmentValues {
    var paperRowInset: CGFloat {
        get { self[PaperRowInsetKey.self] }
        set { self[PaperRowInsetKey.self] = newValue }
    }
}

/// Redesign phase 2: screens that opt in (`.environment(\.paperGroupedWells, true)`) draw
/// `PaperSection` as a semibold `SectionHeader` with its count over a borderless well, and
/// `PaperCard` as that well. Off by default, so screens not yet redesigned keep their panels.
private struct PaperGroupedWellsKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var paperGroupedWells: Bool {
        get { self[PaperGroupedWellsKey.self] }
        set { self[PaperGroupedWellsKey.self] = newValue }
    }
}

/// A planar panel holding a group of rows or one block of content.
struct PaperCard<Content: View>: View {
    /// Inner padding for free-form content; rows pass 0 and pad themselves by `paperRowInset`.
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    @Environment(\.paperGroupedWells) private var wells

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PaperCardMetrics.radius, style: wells ? .continuous : .circular)
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(wells ? .clear : Theme.border, lineWidth: 1))
            .environment(\.paperRowInset, PaperCardMetrics.inset)
    }
}

extension View {
    /// A label-and-value row inside a `PaperCard`: padded to the card's edge, 48 tall.
    func cardRow() -> some View {
        padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 48)
    }

    /// One row of a card that is built row by row, so long lists stay lazy. The first row draws
    /// the card's top, the last its bottom; rows between carry only the side rims, never a line.
    func paperCardSlot(first: Bool, last: Bool) -> some View {
        modifier(PaperCardSlot(first: first, last: last))
    }

    /// Cards sit 16 from the screen edge.
    func paperCardMargin() -> some View { padding(.horizontal, PaperCardMetrics.margin) }
}

private struct PaperCardSlot: ViewModifier {
    let first: Bool
    let last: Bool

    func body(content: Content) -> some View {
        let r = PaperCardMetrics.radius
        content
            .environment(\.paperRowInset, PaperCardMetrics.inset)
            .padding(.top, first ? PaperCardMetrics.edge : 0)
            .padding(.bottom, last ? PaperCardMetrics.edge : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: UnevenRoundedRectangle(topLeadingRadius: first ? r : 0, bottomLeadingRadius: last ? r : 0,
                                                               bottomTrailingRadius: last ? r : 0, topTrailingRadius: first ? r : 0,
                                                               style: .circular))
            .overlay(PaperCardSliceRim(first: first, last: last, radius: r).stroke(Theme.border, lineWidth: 1))
    }
}

/// The card's 1px rim for one slice: sides always, the top arc on the first slice and the bottom
/// arc on the last, so a stack of slices reads as one panel with no rule between rows.
private struct PaperCardSliceRim: Shape {
    let first: Bool
    let last: Bool
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: 0.5, dy: 0.5)
        let r = min(radius, box.width / 2, box.height / 2)
        var path = Path()
        // Leading side, bottom to top (through the bottom arc when last).
        if last {
            path.move(to: CGPoint(x: box.midX, y: box.maxY))
            path.addArc(tangent1End: CGPoint(x: box.minX, y: box.maxY), tangent2End: CGPoint(x: box.minX, y: box.minY), radius: r)
        } else {
            path.move(to: CGPoint(x: box.minX, y: rect.maxY))
        }
        if first {
            path.addArc(tangent1End: CGPoint(x: box.minX, y: box.minY), tangent2End: CGPoint(x: box.maxX, y: box.minY), radius: r)
            path.addArc(tangent1End: CGPoint(x: box.maxX, y: box.minY), tangent2End: CGPoint(x: box.maxX, y: box.maxY), radius: r)
        } else {
            path.addLine(to: CGPoint(x: box.minX, y: rect.minY))
            path.move(to: CGPoint(x: box.maxX, y: rect.minY))
        }
        if last {
            path.addArc(tangent1End: CGPoint(x: box.maxX, y: box.maxY), tangent2End: CGPoint(x: box.minX, y: box.maxY), radius: r)
            path.addLine(to: CGPoint(x: box.midX, y: box.maxY))
        } else {
            path.addLine(to: CGPoint(x: box.maxX, y: rect.maxY))
        }
        return path
    }
}

/// A group of rows on one card, built lazily row by row.
struct PaperCardList<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    @ViewBuilder var row: (Data.Element) -> Row

    var body: some View {
        let items = Array(data)
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            row(item).paperCardSlot(first: index == 0, last: index == items.count - 1)
        }
    }
}

/// A rounded square holding a symbol: the leading mark on a row, so rows scan by shape and colour.
/// Decorative; the row's words carry the meaning.
struct IconTile: View {
    let symbol: String
    var tint: Color = Theme.foreground
    var fill: Color = Theme.fill
    static let size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: Self.size, height: Self.size)
            .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A job's status as a tinted tile. The status word is always in the row beside it.
struct StatusTile: View {
    let status: String
    /// A step saved on the phone and waiting to sync.
    var pending = false

    var body: some View {
        let (symbol, color) = statusIcon(status)
        IconTile(symbol: pending ? "clock.arrow.circlepath" : symbol,
                 tint: pending ? Theme.warning : color == Theme.muted ? Theme.foreground : color,
                 fill: Self.surface(status, pending: pending))
    }

    static func surface(_ status: String, pending: Bool = false) -> Color {
        if pending { return Theme.warningSurface }
        switch status {
        case "completed": return Theme.successSurface
        case "in_progress", "arrived", "paused": return Theme.warningSurface
        case "en_route", "dispatched": return Theme.brandSurface
        default: return Theme.fill
        }
    }
}

/// A document's kind as a tile tinted by its status (approved green, waiting amber, void red).
struct DocumentTile: View {
    let symbol: String
    let status: String

    var body: some View {
        let (tint, fill): (Color, Color) = switch status {
        case "approved", "paid", "completed": (Theme.success, Theme.successSurface)
        case "sent", "issued", "open": (Theme.warning, Theme.warningSurface)
        case "declined", "void", "canceled": (Theme.destructive, Theme.destructiveSurface)
        default: (Theme.foreground, Theme.fill)
        }
        IconTile(symbol: symbol, tint: tint, fill: fill)
    }
}

/// A plain fact beside a status pill: a small icon and words, no pill. Only what you can tap or
/// what carries state is a pill.
struct Fact: View {
    let text: String
    var icon: String? = nil
    var tint: Color = Theme.muted

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(tint).accessibilityHidden(true) }
            Text(text).font(Theme.font(13, weight: .medium)).foregroundStyle(tint).lineLimit(1).fixedSize()
        }
        .frame(minHeight: Theme.chipHeight)
    }
}

/// Headline numbers at the top of a screen: two to four figures on one card, label over value,
/// separated by space rather than rules. Stacks at accessibility sizes instead of shrinking.
struct PaperStatRow: View {
    struct Stat: Identifiable {
        let label: String
        let value: String
        var detail: String? = nil
        var tint: Color = Theme.foreground
        var detailTint: Color = Theme.muted
        var id: String { label }
    }
    let stats: [Stat]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        PaperCard { Content(stats: stats) }
    }

    /// The figures without their panel, for a `PaperSection` that already draws one.
    struct Content: View {
        let stats: [Stat]
        @Environment(\.dynamicTypeSize) private var typeSize

        var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                             : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            layout {
                ForEach(stats) { stat in
                    VStack(alignment: .leading, spacing: 3) {
                        // design 2026-10-30: colour only next to a word — a tinted stat puts a dot
                        // beside its label and keeps the figure in ink.
                        HStack(spacing: 6) {
                            if stat.tint != Theme.foreground {
                                Circle().fill(stat.tint).frame(width: 7, height: 7).accessibilityHidden(true)
                            }
                            Text(stat.label).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                                .lineLimit(stacked ? nil : 1)
                        }
                        Text(stat.value).font(Theme.font(22, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(stacked ? nil : 1).minimumScaleFactor(stacked ? 1 : 0.8)
                        if let detail = stat.detail {
                            if stat.detailTint == Theme.muted {
                                Text(detail).font(Theme.font(13)).foregroundStyle(Theme.muted)
                                    .lineLimit(stacked ? nil : 2)
                            } else {
                                StatusWord(text: detail, tint: stat.detailTint)
                            }
                        }
                    }
                    .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Redesign 2026-10-30: one row, one panel, one status word
//
// The list system (Main.dc.html, Customer.dc.html): rows on one white panel per section, the
// section's label above it, no tiles, no rings, no chevrons, no rules. A row is an optional
// leading time or date column (or a neutral glyph), a 16/500 title and one supporting line, and
// on the right either a status word with a small dot or an amount.

/// A status as a word. The dot carries the hue; the word stays body so it reads the same in
/// light, dark and for colour-blind people. Neutral states ("Scheduled", "Draft") have no dot.
struct StatusWord: View {
    let text: String
    /// Nil leaves the word alone with no dot.
    var tint: Color? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 6) {
            if let tint {
                Circle().fill(tint).frame(width: 7, height: 7).accessibilityHidden(true)
            }
            Text(text).font(Theme.font(13, weight: .medium))
                .foregroundStyle(tint == nil ? Theme.muted : Theme.foreground)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
        }
        // One line at standard sizes. At accessibility sizes rows stack the word under the title, and
        // a long word ("In progress · waiting to sync") wraps rather than widening the screen.
        .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
    }
}

extension StatusWord {
    /// A job's status. `pending` is a step saved on this phone and waiting to sync.
    init(jobStatus status: String, pending: Bool = false) {
        self.init(text: pending ? "\(status.statusLabel) · waiting to sync" : status.statusLabel,
                  tint: pending ? Theme.warning : StatusWord.jobTint(status))
    }

    /// An estimate's or invoice's status ("Unpaid" for an issued invoice).
    init(documentStatus status: String) {
        self.init(text: status == "issued" ? "Unpaid" : status.statusLabel, tint: StatusWord.documentTint(status))
    }

    static func jobTint(_ status: String) -> Color? {
        switch status {
        case "completed": Theme.success
        case "in_progress", "arrived", "paused": Theme.warning
        case "en_route", "dispatched": Theme.brandText
        default: nil
        }
    }

    static func documentTint(_ status: String) -> Color? {
        switch status {
        case "approved", "paid", "completed": Theme.success
        case "sent", "issued", "open": Theme.warning
        case "declined", "void", "canceled": Theme.destructive
        default: nil
        }
    }
}

/// What leads a list row: a time ("10:30 AM"), a date ("Apr 14"), a neutral glyph, or nothing.
enum PaperRowLeading {
    case none
    case text(String, accessibility: String? = nil)
    case icon(String)
}

/// The one list row. Title 16/500, one supporting line, an optional third meta line, and a
/// trailing view (a `StatusWord`, an amount, or a small action). Pads to `paperRowInset`.
struct PaperListRow<Trailing: View>: View {
    var leading: PaperRowLeading = .none
    let title: String
    var subtitle: String? = nil
    /// A quieter third line (tech · photos · paid).
    var meta: String? = nil
    var subtitleLines = 1
    /// A note-like supporting line (a past job's notes): folds at `subtitleLines` with "More"
    /// instead of cutting the rest off.
    var expandsSubtitle = false
    /// Finished work reads quieter.
    var dimmed = false
    /// Search: the typed words, marked where they appear in the title and supporting line.
    var highlight: [String] = []
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.paperRowInset) private var inset
    /// Wide enough for "12:15 p.m." on one line at 14pt (trade-style times are longer than "12:15 PM").
    @ScaledMetric(relativeTo: .subheadline) private var column: CGFloat = 80

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 14))
        layout {
            leadingView
            VStack(alignment: .leading, spacing: 2) {
                PaperHighlight.text(title, words: highlight).font(Theme.font(16, weight: .medium))
                    .foregroundStyle(dimmed ? Theme.muted : Theme.foreground)
                    .lineLimit(stacked ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    if expandsSubtitle {
                        ExpandableNoteText(text: subtitle, lines: subtitleLines, size: 14)
                    } else {
                        PaperHighlight.text(subtitle, words: highlight).font(Theme.font(14)).foregroundStyle(Theme.subtle)
                            .lineLimit(stacked ? nil : subtitleLines)
                    }
                }
                if let meta, !meta.isEmpty {
                    Text(meta).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                        .lineLimit(stacked ? nil : 2)
                        .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, inset).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var leadingView: some View {
        switch leading {
        case .none: EmptyView()
        case .text(let text, let spoken):
            Text(text).font(Theme.font(14, weight: .medium)).monospacedDigit()
                .foregroundStyle(dimmed ? Theme.muted : Theme.foreground)
                .lineLimit(2)
                .frame(width: typeSize.isAccessibilitySize ? nil : column, alignment: .leading)
                .accessibilityLabel(spoken ?? text)
        case .icon(let symbol):
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(Theme.muted)
                .frame(width: 24).accessibilityHidden(true)
        }
    }
}

/// The matched part of a search row: a quiet fill behind it and full ink, never a second accent.
/// Inter carries only 400 and 500 here, so weight cannot mark it.
enum PaperHighlight {
    static func text(_ string: String, words: [String]) -> Text {
        guard !words.isEmpty else { return Text(verbatim: string) }
        var attributed = AttributedString(string)
        for word in words where !word.isEmpty {
            var start = attributed.startIndex
            while start < attributed.endIndex,
                  let range = attributed[start...].range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) {
                // Short words are only marked where they start a word, like the match itself.
                let startsWord = range.lowerBound == attributed.startIndex
                    || !(attributed.characters[attributed.characters.index(before: range.lowerBound)].isLetter)
                guard word.count > 2 || startsWord else { start = range.upperBound; continue }
                attributed[range].backgroundColor = Theme.muted.opacity(0.22)
                attributed[range].foregroundColor = Theme.foreground
                start = range.upperBound
            }
        }
        return Text(attributed)
    }
}

extension PaperListRow where Trailing == EmptyView {
    init(leading: PaperRowLeading = .none, title: String, subtitle: String? = nil, meta: String? = nil,
         subtitleLines: Int = 1, dimmed: Bool = false) {
        self.init(leading: leading, title: title, subtitle: subtitle, meta: meta, subtitleLines: subtitleLines,
                  dimmed: dimmed) { EmptyView() }
    }
}

extension PaperListRow where Trailing == StatusWord {
    init(leading: PaperRowLeading = .none, title: String, subtitle: String? = nil, meta: String? = nil,
         subtitleLines: Int = 1, dimmed: Bool = false, status: StatusWord) {
        self.init(leading: leading, title: title, subtitle: subtitle, meta: meta, subtitleLines: subtitleLines,
                  dimmed: dimmed) { status }
    }
}

extension PaperListRow where Trailing == Text {
    /// A row ending in an amount (MF-02 row size, tabular).
    init(leading: PaperRowLeading = .none, title: String, subtitle: String? = nil, meta: String? = nil,
         dimmed: Bool = false, amount: String) {
        self.init(leading: leading, title: title, subtitle: subtitle, meta: meta, dimmed: dimmed) {
            Text(amount).font(Theme.moneyFont(.line, regular: false)).foregroundStyle(Theme.foreground)
        }
    }
}

/// One section: a 13/500 label (with " · count") above one white panel of rows.
struct PaperSection<Content: View, Accessory: View>: View {
    let title: String?
    var count: Int? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory

    @Environment(\.paperGroupedWells) private var wells

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title, wells {
                SectionHeader(title: title, count: count) { accessory }.padding(.bottom, 2)
            } else if let title {
                HStack(spacing: 8) {
                    Text(count.map { "\(title) · \($0)" } ?? title)
                        .font(Theme.font(13, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Theme.muted)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    accessory
                }
                .frame(minHeight: 28)
                .padding(.horizontal, 4).padding(.bottom, 4)
            }
            PaperCard { content }
        }
    }
}

extension PaperSection where Accessory == EmptyView {
    init(_ title: String?, count: Int? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, count: count, content: content) { EmptyView() }
    }
}

/// A labelled quiet circle (Call, Text, Email, Directions): the 44pt field circle with its word under it.
struct PaperLabeledCircle: View {
    let symbol: String
    let title: String
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 44, height: 44)
                    .background(Theme.fill, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.border.opacity(0.6), lineWidth: 1))
                Text(title).font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

// MARK: - Forms (design 2026-10-30): one column, the label above, the answer in a field well

/// The field well: a quiet field-coloured surface per answer, 48 tall, no rim.
struct FieldWell: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}

extension View {
    /// Puts a text field or a choice in the shared field well.
    func fieldWell() -> some View { modifier(FieldWell()) }
}

/// A persistent 13pt label above its field, with an optional quiet note ("Optional") beside it.
struct PaperFormField<Content: View>: View {
    let label: String
    var note: String? = nil
    @ViewBuilder var content: Content

    init(_ label: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                if let note { Text("· \(note)").font(Theme.font(13)).foregroundStyle(Theme.muted.opacity(0.8)) }
            }
            .accessibilityHidden(true)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A tappable choice in a field well: a neutral glyph, the value (muted while unset).
struct PaperChoiceWell: View {
    let text: String
    var symbol: String? = nil
    var isSet = true

    var body: some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                    .frame(width: 20).accessibilityHidden(true)
            }
            Text(text).font(Theme.font(16, weight: isSet ? .medium : .regular))
                .foregroundStyle(isSet ? Theme.foreground : Theme.muted)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .fieldWell()
        .contentShape(Rectangle())
    }
}

extension Date {
    /// Trade-style clock time (design 2026-10-30 copy): "7 a.m.", "10:30 a.m.", "1 p.m.".
    /// Uses the person's 24-hour setting when they have one.
    var tradeTime: String {
        let uses24 = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") == false
        if uses24 { return formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()) }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: self)
        let hour24 = parts.hour ?? 0, minute = parts.minute ?? 0
        let hour = hour24 % 12 == 0 ? 12 : hour24 % 12
        let suffix = hour24 < 12 ? "a.m." : "p.m."
        return minute == 0 ? "\(hour) \(suffix)" : String(format: "%d:%02d %@", hour, minute, suffix)
    }
}

/// A note that may run long: the first few lines, then a quiet "More" that opens the rest in place
/// (and "Less" to fold it again). Short notes show whole with no control. VoiceOver reads the full
/// text either way, so the toggle stays out of the spoken row.
struct ExpandableNoteText: View {
    let text: String
    var lines = 4
    var size: CGFloat = 15
    var color: Color = Theme.subtle
    @State private var expanded = false
    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    /// Only measured while folded, so "Less" stays once the note is open.
    private var isLong: Bool { fullHeight > shownHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text).font(Theme.font(size)).foregroundStyle(color).lineSpacing(2)
                .multilineTextAlignment(.leading)
                .lineLimit(expanded ? nil : lines)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { if !expanded { shownHeight = $0 } }
                .background(alignment: .topLeading) {
                    Text(text).font(Theme.font(size)).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { fullHeight = $0 }
                        .accessibilityHidden(true)
                }
                .accessibilityLabel(text)
            if isLong || expanded {
                Button { withMotion(.snappy) { expanded.toggle() } } label: {
                    HStack(spacing: 4) {
                        Text(expanded ? "Less" : "More")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold))
                    }
                    .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.foreground)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .padding(.vertical, -6)
                .accessibilityHidden(true)
                .accessibilityIdentifier("note-more")
            }
        }
    }
}
