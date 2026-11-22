import SwiftUI

// Paper's primitives ("DS · Thorbis Mobile primitives" in the main Paper file), with Paper's own
// values. One search-and-filter field per list, segments on a card track, groups as a 13 Semibold
// label over one card of rows, one blue pill per screen, quiet 48pt circles for everything else.
// Every screen builds from these so a change here is a change everywhere.

extension Theme {
    /// Paper's quiet control fill: ink at 9% over whatever it sits on (the filter circle in the
    /// search field, the call and message circles on a card, an unchosen chip in a sheet).
    static let quietFill = foreground.opacity(0.09)
    /// Paper's chosen-chip fill: brand at 24% (a filter chip in the search field, a chosen sheet chip).
    static let brandTint = brand.opacity(0.24)
    /// Paper `border-strong`: the ring of a status that has not started (white 40% / black 18%).
    static let borderStrong = Color(uiColor: UIColor { traits in
        let dark = traits.userInterfaceStyle == .dark
        let high = traits.accessibilityContrast == .high
        return (dark ? UIColor.white : UIColor.black).withAlphaComponent(high ? 0.75 : dark ? 0.40 : 0.18)
    })
    /// Paper `subtle-foreground` (#8A8A8A in both themes): a drawer count, a drawer section label,
    /// the role under the person's name. Light is one shade deeper so it holds 4.5:1 on the sidebar.
    static let subtleForeground = Color(uiColor: UIColor { traits in
        let dark = traits.userInterfaceStyle == .dark
        let high = traits.accessibilityContrast == .high
        if high { return dark ? UIColor(white: 0.93, alpha: 1) : UIColor(white: 0.1, alpha: 1) }
        return dark ? UIColor(red: 0x8A / 255, green: 0x8A / 255, blue: 0x8A / 255, alpha: 1)
                    : UIColor(red: 0x6B / 255, green: 0x6B / 255, blue: 0x6B / 255, alpha: 1)
    })
}

// MARK: - Search and filter field

/// The typed-in twin of `PaperSearchBar`: the same card well, magnifier and 16pt "Search or ask",
/// but the words are a real field that narrows the list under it (Paper 20E Estimates, 20F
/// Invoices, 55 Team). With a `filter` it takes Paper 87A's measures (46 tall, 12 leading, the
/// 40pt circle 6 from the right); alone it is 20E's 48-tall well.
///
///     PaperSearchInput(text: $search, label: "Search estimates") {
///         Button { showFilters = true } label: { PaperFilterCircle(active: filtered) }
///     }
///     .paperCardMargin()
struct PaperSearchInput<Filter: View>: View {
    @Binding var text: String
    /// Spoken name of the field ("Search estimates").
    let label: String
    var placeholder = "Search or ask"
    @ViewBuilder var filter: Filter

    private var hasFilter: Bool { Filter.self != EmptyView.self }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if hasFilter { PaperIcon(.search, size: 18, color: Theme.muted) }
                else { PaperIcon(.searchField, size: 18, color: Theme.muted) }
            }
            .accessibilityHidden(true)
            TextField(label, text: $text, prompt: .placeholder(placeholder))
                .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    PaperIcon(.close, size: 12, color: Theme.muted)
                        .frame(width: 22, height: 22).background(Theme.quietFill, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Clear search")
            }
            // The circle's 44pt target overhangs its 40pt face by 2, so 4 + 2 is Paper's 6.
            if hasFilter { filter.padding(.leading, -2) }
        }
        .padding(.leading, hasFilter ? 12 : 14)
        .padding(.trailing, hasFilter ? 4 : (text.isEmpty ? 14 : 2))
        .frame(minHeight: hasFilter ? 46 : 48)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension PaperSearchInput where Filter == EmptyView {
    init(text: Binding<String>, label: String, placeholder: String = "Search or ask") {
        self.init(text: text, label: label, placeholder: placeholder) { EmptyView() }
    }
}

extension PaperGlyph {
    /// Paper 20E/20F's 18pt magnifier: a 5.5 circle and its handle, 1.6 strokes.
    static let searchField = PaperGlyph(box: 18, [.circle(8, 8, 5.5, 1.6), .stroke("M12.2 12.2L15.5 15.5", 1.6)])
}

/// A filter shown in the search field as a brand chip; × takes it off.
struct PaperFilterChip: Identifiable {
    let id: String
    let title: String
    let remove: () -> Void
}

/// Paper 18 / 20: the search field under the title. Card fill, radius 14, 46 tall, 12 in from the
/// leading edge and 6 from the trailing one, 8 between its parts. The 18pt glass and the words
/// ("Search or ask", 16 Regular muted) open Search; what narrows the list sits inside as brand
/// chips; the 40pt filter circle trails. Give it `.paperCardMargin()` (16 from the screen edges).
///
///     PaperSearchBar(placeholder: "Search", chips: chips) {
///         Button { showFilters = true } label: { PaperFilterCircle(active: filtered) }
///     }
///     .paperCardMargin()
struct PaperSearchBar<Filter: View>: View {
    let placeholder: String
    var chips: [PaperFilterChip] = []
    @ViewBuilder var filter: Filter
    @Environment(\.paperSearch) private var search

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        HStack(spacing: 0) {
            magnifier
            // Chips and the words when they fit; otherwise the chips scroll and the glass searches.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    chipRow
                    searchWords
                }
                ScrollView(.horizontal) { chipRow }
                    .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The circle's 44pt target overhangs its 40pt face by 2, so 4 + 2 is Paper's 6.
            filter.padding(.leading, 6)
        }
        .padding(.leading, search == nil ? 12 : 0).padding(.trailing, 4)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(Theme.card, in: shape)
        .clipShape(shape)
    }

    /// Without the shell's Search (the iPad layout), the field never pretends to search: no glass
    /// and no words, only the chips and the filter circle.
    @ViewBuilder private var magnifier: some View {
        if let search {
            Button(action: search.run) {
                PaperIcon(.search, size: 18, color: Theme.muted)
                    .padding(.leading, 12).padding(.trailing, 8)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Search")
            .accessibilityIdentifier("header-search")
        }
    }

    @ViewBuilder private var searchWords: some View {
        if let search {
            // The glass is the one VoiceOver stop for Search; the words are a bigger target for a thumb.
            Button(action: search.run) {
                Text(placeholder).font(Theme.font(16)).foregroundStyle(Theme.muted).lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityHidden(true)
        } else if chips.isEmpty {
            // iPad: the shell's bar searches, so this field only filters. Empty, it says so
            // instead of sitting blank.
            Text("No filters").font(Theme.font(16)).foregroundStyle(Theme.muted).lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        } else {
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var chipRow: some View {
        if !chips.isEmpty {
            HStack(spacing: 8) {
                ForEach(chips) { chip in PaperFilterChipButton(chip: chip) }
            }
        }
    }
}

/// One brand chip in the search field: 36 tall, brand at 24%, 14 Semibold brand text and an 11pt ×.
struct PaperFilterChipButton: View {
    let chip: PaperFilterChip

    var body: some View {
        Button(action: chip.remove) {
            HStack(spacing: 5) {
                Text(chip.title).font(Theme.font(14, weight: .semibold)).lineLimit(1)
                PaperIcon(.close, size: 11, color: Theme.brandText)
            }
            .foregroundStyle(Theme.brandText)
            .padding(.leading, 10).padding(.trailing, 8)
            .frame(minHeight: 36)
            .background(Theme.brandTint, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .fixedSize()
        .accessibilityLabel("\(chip.title) filter")
        .accessibilityHint("Removes this filter")
    }
}

/// The search field's filter circle: 40pt, ink at 9%, Paper's three shortening lines; brand-tinted
/// while a filter narrows the list. A label only: wrap it in a `Button` or a `ThorbisMenu`.
struct PaperFilterCircle: View {
    var active = false
    var body: some View {
        PaperIcon(.filter, size: 16, color: active ? Theme.brandText : Theme.foreground)
            .frame(width: 40, height: 40)
            .background(active ? Theme.brandTint : Theme.quietFill, in: Circle())
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }
}

// MARK: - Groups and cards

// MARK: - Headers and labels (consistency pass, 2026-11-18)

/// Where a page's title sits (Paper 20 / 61A / 67 / 21J): the 44pt circles 2 under the status bar,
/// then 14 to the 34/40 Bold title, so the title's box starts 60 under the status bar on every
/// page, whether the circles are the header's own row or sit in the navigation bar.
enum PaperHeaderMetrics {
    /// Status bar to the title's box.
    static let titleBelowStatusBar: CGFloat = 60
    /// The navigation bar that carries the back or menu circle: 54 tall from iOS 26, 44 before.
    static var barHeight: CGFloat { if #available(iOS 26.0, *) { 54 } else { 44 } }
    /// The space above a title that follows the navigation bar.
    static var titleTopUnderBar: CGFloat { titleBelowStatusBar - barHeight }
    /// The space above a title that follows the header's own 44pt circle row.
    static let titleTopUnderCircles: CGFloat = 14
}

/// The title block every page shares (Paper 20 "Jobs", 61A "Hours, tax and terms", 67, 39H): the
/// 34/40 Bold title (-0.025em) 20 from the screen's edge and, 2 under it, one 15/20 muted line.
/// A long title wraps; it never truncates. The block ends at its last line: a label or a card
/// follows 22 under it, a search field or tabs 14.
///
///     PaperPageTitle(title: "Time and profit", subtitle: "AC repair · 2h 10m")   // full-width column
///     PaperPageTitle(title: "Checklist", subtitle: line, columnInset: 16)         // inside a 16pt column
struct PaperPageTitle: View {
    /// Only where Paper prints a record's reference over its name (63 "Role · 2 members", 51
    /// "CALL-0142 · (916) 555-0148"): one 15/20 muted line above the title. Never the parent page's name.
    var eyebrow: String? = nil
    let title: String
    var subtitle: String? = nil
    /// The space already between the screen's edge and this block: 0 in a full-width column,
    /// `PaperCardMetrics.margin` inside a card column.
    var columnInset: CGFloat = 0
    /// False where the page draws its own 44pt circle row straight above the title.
    var underBar = true
    /// Only where a container already places the block (a list section's own inset): the space above.
    var top: CGFloat? = nil
    var titleIdentifier: String? = nil
    var subtitleIdentifier: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let eyebrow, !eyebrow.isEmpty {
                Text(eyebrow).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(title).font(Theme.font(34, weight: .bold)).tracking(-0.85)
                .foregroundStyle(Theme.foreground)
                .lineLimit(typeSize.isAccessibilitySize ? 5 : 3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .modifier(OptionalIdentifier(identifier: titleIdentifier))
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 20, alignment: .leading)
                    .modifier(OptionalIdentifier(identifier: subtitleIdentifier))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, max(0, Theme.gutter - columnInset))
        .padding(.top, top ?? (underBar ? PaperHeaderMetrics.titleTopUnderBar : PaperHeaderMetrics.titleTopUnderCircles))
    }
}

/// A section's label (Paper 18 / 20 / 61A / 21E): 13/18 Semibold muted, the count at the trailing
/// edge in 13 Regular, 4 in from the card's edge and 8 above the card. Paper leaves 22 above it:
/// the caller's stack spacing or `.padding(.top, 22)` adds that. This is the one label; a column
/// that already sits 16 from the screen uses it as is, a full-width column uses `PaperCardLabel`.
///
///     PaperSectionLabel(title: "Hours")
///     PaperSectionLabel(title: "In progress", count: 2)
///     PaperSectionLabel(title: "Contacts") { addButton }
struct PaperSectionLabel<Trailing: View>: View {
    let title: String
    var count: Int? = nil
    /// The count with its unit ("4 jobs", "4 · 7.5h"); wins over `count`.
    var countText: String? = nil
    /// Paper 79 prints today's and tomorrow's day label in the muted grey and a later day in ink.
    var titleColor: Color = Theme.muted
    /// The label's inset from its column: 4 beside a card, 0 inside a sheet (Paper 21E).
    var inset: CGFloat = 4
    /// The space to the card: Paper's 8. Pass 0 only inside a stack whose own spacing is that 8.
    var gap: CGFloat = 8
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title).font(Theme.font(13, weight: .semibold)).foregroundStyle(titleColor)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let countText {
                Text(countText).font(Theme.font(13)).foregroundStyle(Theme.muted)
            } else if let count, count > 0 {
                Text("\(count)").font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .accessibilityLabel("\(count)")
            }
            trailing
        }
        .frame(minHeight: 18)
        .padding(.horizontal, inset)
        .padding(.bottom, gap)
    }
}

extension PaperSectionLabel where Trailing == EmptyView {
    init(title: String, count: Int? = nil, countText: String? = nil, titleColor: Color = Theme.muted, inset: CGFloat = 4, gap: CGFloat = 8) {
        self.init(title: title, count: count, countText: countText, titleColor: titleColor, inset: inset, gap: gap) { EmptyView() }
    }
}

/// `PaperSectionLabel` for a full-width column: the same label, 20 from the screen's edge.
///
///     PaperCardLabel(title: "In progress", count: 2)
///     PaperCardLabel(title: "Later today", countText: "4 jobs")
struct PaperCardLabel<Trailing: View>: View {
    let title: String
    var count: Int? = nil
    /// The count with its unit ("4 jobs", "4 · 7.5h"); wins over `count`.
    var countText: String? = nil
    /// Paper 79 prints today's and tomorrow's day label in the muted grey and a later day in ink.
    var titleColor: Color = Theme.muted
    @ViewBuilder var trailing: Trailing

    var body: some View {
        PaperSectionLabel(title: title, count: count, countText: countText, titleColor: titleColor) { trailing }
            .padding(.horizontal, PaperCardMetrics.margin)
    }
}

extension PaperCardLabel where Trailing == EmptyView {
    init(title: String, count: Int? = nil, countText: String? = nil, titleColor: Color = Theme.muted) {
        self.init(title: title, count: count, countText: countText, titleColor: titleColor) { EmptyView() }
    }
}

/// One card of rows (Paper 18 / 20): the card fill, radius 20, clipped, 16 from the screen's edges.
/// Rows pad themselves (16 leading and trailing, 11 above and below) and the caller draws the
/// hairline between them with `WellDivider(leading:)`, inset to where the words start.
struct PaperRowsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: shape)
            .clipShape(shape)
            .paperCardMargin()
    }
}

extension View {
    /// One row of a `PaperRowsCard` drawn on its own, for long lists: the rows sit directly in the
    /// page's lazy stack, so only the rows on screen are built. Same fill, radius and margin as
    /// the card; the first row carries the top corners and the last the bottom ones.
    func paperRowsCardSlice(first: Bool, last: Bool) -> some View {
        let r = Theme.cardRadius
        let shape = UnevenRoundedRectangle(topLeadingRadius: first ? r : 0, bottomLeadingRadius: last ? r : 0,
                                           bottomTrailingRadius: last ? r : 0, topTrailingRadius: first ? r : 0,
                                           style: .continuous)
        return frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: shape)
            .clipShape(shape)
            .paperCardMargin()
    }
}

/// A person's initials (Paper 20's avatar chip): 11 Semibold brand text on the brand surface, 28pt.
struct PaperInitials: View {
    let name: String
    var size: CGFloat = 28

    var body: some View {
        Text(initials(name))
            .font(.custom("Inter-Regular", fixedSize: size >= 34 ? 12 : 11).weight(.semibold))
            .foregroundStyle(Theme.brandText)
            .frame(width: size, height: size)
            .background(Theme.brandSurface, in: Circle())
            .accessibilityLabel("Assigned to \(name)")
    }
}

// MARK: - Buttons

/// Paper's control ramp (the DS board: "One blue pill per screen, 48–50 tall. Everything else is a
/// quiet 44px pill or a 44px circle; chips are 40."). Every tappable pill in the app is one of
/// these sizes in one of these tones; a feature file never types its own height, radius or label
/// font. Measured in the main Paper file: brand pills 50 (75 of them), 48 on a card (13), 44
/// "Done"/"Submit" (15 Semibold), 36 row and token pills (14 Semibold); Field mode's commit is 60.
enum PaperControl {
    enum Size {
        /// Field mode's one action (Paper Field mode F1–F6 "On my way"): 60 tall, 18 Semibold. Only
        /// on the gloves-on job screen; nowhere else.
        case field
        /// A screen's or a sheet's commit ("Show 7 jobs", "Save draft" beside it): 50 tall, 16 Semibold.
        case commit
        /// The main action on a card ("Navigate"): 48 tall, 16 Semibold.
        case card
        /// Every other button ("Text instead", "Resume", "Done"): 44 tall, 15 Semibold.
        case secondary
        /// A pill inside a row or a tight strip ("Schedule", a filter token): 36 tall to the eye,
        /// 44 to the finger, 14 Semibold.
        case compact

        var height: CGFloat {
            switch self { case .field: 60; case .commit: 50; case .card: 48; case .secondary: 44; case .compact: 36 }
        }
        var type: CGFloat {
            switch self { case .field: 18; case .commit, .card: 16; case .secondary: 15; case .compact: 14 }
        }
        /// Either side of the words when the pill hugs them.
        var inset: CGFloat {
            switch self { case .field, .commit: 22; case .card: 18; case .secondary: 16; case .compact: 12 }
        }
        var glyph: CGFloat {
            switch self { case .field: 20; case .commit, .card, .secondary: 16; case .compact: 14 }
        }
    }

    enum Tone {
        /// The one blue pill: white on brand.
        case brand
        /// Its quieter twin: brand text on brand at 24% ("Resume", "Create your first job").
        case tinted
        /// Everything else: ink on ink at 9% ("Save draft", "Text instead", "Add").
        case quiet
        /// A destructive commit: white on red ("Delete my account").
        case danger
        /// A destructive action that is not the commit: red words on red at 14%.
        case dangerQuiet

        var fill: Color {
            switch self {
            case .brand: Theme.brand
            case .tinted: Theme.brandTint
            case .quiet: Theme.quietFill
            case .danger: Theme.destructiveFill
            case .dangerQuiet: Theme.destructive.opacity(0.14)
            }
        }
        var ink: Color {
            switch self {
            case .brand, .danger: .white
            case .tinted: Theme.brandText
            case .quiet: Theme.foreground
            case .dangerQuiet: Theme.destructive
            }
        }
    }

    /// A choice or filter chip (Paper 20A): 40 tall, 14 Medium, 14 Semibold when chosen.
    static let chipHeight: CGFloat = 40
    /// A small status word on a row or a card ("Low", "Invite pending"): 26 tall, 13 Semibold, 10 either side.
    static let statusHeight: CGFloat = 26
    /// A text field or a picker well: 50 tall, radius 14, 16 either side, 16 Regular.
    static let fieldHeight: CGFloat = 50
    static let fieldRadius: CGFloat = 14
}

private struct PaperButtonFace: ViewModifier {
    let size: PaperControl.Size
    let tone: PaperControl.Tone
    let fills: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.thorbisPressed) private var pressed

    func body(content: Content) -> some View {
        content
            .font(Theme.font(size.type, weight: .semibold))
            .foregroundStyle(tone.ink.opacity(isEnabled ? 1 : 0.7))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, fills ? 16 : size.inset).padding(.vertical, 8)
            .frame(maxWidth: fills ? .infinity : nil, minHeight: size.height)
            .background(tone.fill.opacity(isEnabled ? (pressed ? 0.85 : 1) : 0.4), in: Capsule())
            // 36 to the eye is still 44 to the finger.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Dresses any label (words, or a glyph and words) as one of Paper's pills. Sizes and tones are
    /// `PaperControl`'s; a button that needs a different height needs a reason next to it.
    ///
    ///     Button(action: edit) { Text("Edit").paperButton(.secondary, tone: .quiet) }.buttonStyle(PressStyle())
    func paperButton(_ size: PaperControl.Size = .secondary, tone: PaperControl.Tone = .quiet,
                     fills: Bool = false) -> some View {
        modifier(PaperButtonFace(size: size, tone: tone, fills: fills))
    }
}

/// A pill with words and an optional leading mark, in Paper's ramp. A label only: wrap it in a
/// `Button`, a `NavigationLink` or a `ThorbisMenu`.
///
///     Button(action: text) { PaperButtonLabel(title: "Text instead", symbol: "bubble.left") }.buttonStyle(PressStyle())
struct PaperButtonLabel: View {
    let title: String
    var glyph: PaperGlyph? = nil
    /// An SF Symbol, where Paper draws no glyph of its own for this action.
    var symbol: String? = nil
    var size: PaperControl.Size = .secondary
    var tone: PaperControl.Tone = .quiet
    /// True fills the row; false hugs the words.
    var fills = false
    var busy = false

    var body: some View {
        HStack(spacing: 8) {
            if busy {
                ProgressView().tint(tone.ink)
            } else if let glyph {
                PaperIcon(glyph, size: size.glyph, color: tone.ink)
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: size.glyph - 1, weight: .semibold)).accessibilityHidden(true)
            }
            Text(title)
        }
        .paperButton(size, tone: tone, fills: fills)
    }
}

/// Paper's one blue pill (the DS board's "Buttons"): brand fill, white 16 Semibold, 48 tall on a
/// card ("Navigate") and 50 as a sheet's or a screen's commit ("Show 7 jobs"). `tinted` is the
/// quieter twin (brand text on brand at 24%, Paper 19 "Create your first job"). `PaperButtonLabel`
/// in the brand tone; kept so the screens that already say `PaperPillLabel` read the same.
struct PaperPillLabel: View {
    let title: String
    var glyph: PaperGlyph? = nil
    var symbol: String? = nil
    /// 48 on a card, 50 as the commit. No other value: the ramp is `PaperControl.Size`.
    var height: CGFloat = 48
    var tinted = false
    var busy = false
    /// False hugs the words instead of filling the row.
    var fills = true

    var body: some View {
        PaperButtonLabel(title: title, glyph: glyph, symbol: symbol,
                         size: height >= 50 ? .commit : .card, tone: tinted ? .tinted : .brand,
                         fills: fills, busy: busy)
    }
}

/// A tappable row's trailing chevron (Paper 21 / 52 / 65): the 16pt drawn chevron in the muted
/// tone. Every row that opens something ends in this, never an SF Symbol at its own size.
struct PaperChevron: View {
    var body: some View {
        PaperIcon(.chevronRight, size: 16, color: Theme.muted).accessibilityHidden(true)
    }
}

/// A small status word on a row or a card (Paper 84 "Low", 62 "Invite pending"): 26 tall, 13
/// Semibold, the tone's word on the tone's surface. Not tappable.
struct PaperStatusPill: View {
    let text: String
    var ink: Color = Theme.muted
    var surface: Color = Theme.fill

    var body: some View {
        Text(text).font(Theme.font(13, weight: .semibold)).foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minHeight: PaperControl.statusHeight)
            .background(surface, in: Capsule())
    }
}

/// Paper's quiet round button: a 48pt circle of ink at 9% with a 20pt glyph (the call and message
/// circles beside Navigate). 44 in a tighter row. A label only.
struct PaperRoundLabel: View {
    var glyph: PaperGlyph? = nil
    var symbol: String? = nil
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let glyph {
                PaperIcon(glyph, size: 20)
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.foreground)
            }
        }
        .frame(width: size, height: size)
        .background(Theme.quietFill, in: Circle())
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Circle())
    }
}

/// `PaperRoundLabel` as a plain button with its spoken name.
struct PaperRoundButton: View {
    var glyph: PaperGlyph? = nil
    var symbol: String? = nil
    let label: String
    var size: CGFloat = 48
    let action: () -> Void

    var body: some View {
        Button(action: action) { PaperRoundLabel(glyph: glyph, symbol: symbol, size: size) }
            .buttonStyle(PressStyle())
            .accessibilityLabel(label)
    }
}

// MARK: - Sheet chips and segments (Paper 20A)

/// A sheet chip's face (Paper 20A): a 40-tall pill of ink at 9% in 14 Medium; chosen, 14 Semibold
/// brand text on brand at 24%. 44 tall to the touch.
struct PaperChoiceChipLabel: View {
    let title: String
    let isOn: Bool

    var body: some View {
        Text(title).font(Theme.font(14, weight: isOn ? .semibold : .medium))
            .foregroundStyle(isOn ? Theme.brandText : Theme.foreground)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: PaperControl.chipHeight)
            .background(isOn ? Theme.brandTint : Theme.quietFill, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// A sheet chip (Paper 20A) that turns one choice on or off.
struct PaperChoiceChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) { PaperChoiceChipLabel(title: title, isOn: isOn) }
            .buttonStyle(PressStyle())
            .animation(Theme.selectionSpring(reduceMotion: reduceMotion), value: isOn)
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// A sheet's segmented choice (Paper 20A "Sort by"): the same track as `PaperTabs` (radius 11, 2
/// in, a 36-tall raised segment of ink at 16%), drawn on the sheet's quiet fill.
struct PaperSheetSegments: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button { selection = option } label: {
                    Text(option).font(Theme.font(14, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? Theme.foreground : Theme.subtle)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.selectedSegment)
                                    .shadow(color: Theme.segmentShadow, radius: 2.5, y: 1)
                            }
                        }
                        .contentShape(Rectangle().inset(by: -4))
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sensoryFeedback(.selection, trigger: selection)
    }
}
