import SwiftUI

// Parts shared by the places that keep their records on this phone (Time clock, Receipts, Truck
// stock, Training, Vendors, Pipeline, Marketing), drawn with Paper's values.

extension PaperGlyph {
    /// Paper 27 "Synced": two arrows round a circle.
    static let placeSync = PaperGlyph(box: 12, [.stroke("M10.4 5.2A4.5 4.5 0 0 0 2.4 3.4M1.6 6.8a4.5 4.5 0 0 0 8 1.8M1.6 2.2v2.4h2.4M10.4 9.8V7.4H8", 1.3)])
    /// Paper 27 "Add missed punch": a light plus in a 14 box.
    static let placePlus = PaperGlyph(box: 14, [.stroke("M7 2.5V11.5M2.5 7H11.5", 1.5)])
    /// Paper 42: the small + beside a group's label.
    static let placeSmallPlus = PaperGlyph(box: 16, [.stroke("M8 3V13M3 8H13", 1.6)])
    /// Paper 46: the tick inside a chosen row's circle.
    static let placeCheck = PaperGlyph(box: 12, [.stroke("M2.5 6.2L5 8.7L9.5 3.7", 1.8)])
    /// A row's trailing chevron (Paper 28).
    static let placeChevron = PaperGlyph(box: 16, [.stroke("M6 3.5L10.5 8L6 12.5", 1.6)])
    /// Paper 84: a part's hexagon.
    static let placeHex = PaperGlyph(box: 18, [.stroke("M9 2L15.5 5.5V12.5L9 16L2.5 12.5V5.5L9 2Z", 1.5)])
    /// Paper 84's stepper minus and plus.
    static let placeMinus = PaperGlyph(box: 12, [.stroke("M3 6H9", 1.6)])
    static let placeStepPlus = PaperGlyph(box: 12, [.stroke("M6 3V9M3 6H9", 1.6)])
    /// Paper 28: a lesson's play mark in a ring.
    static let placePlay = PaperGlyph(box: 18, [.circle(9, 9, 7.25, 1.4), .fill("M7.5 6.5L11.5 9L7.5 11.5V6.5Z")])
    /// Paper 28: a manual's page.
    static let placePage = PaperGlyph(box: 18, [.stroke("M4 2.75H10.5L14 6.25V15.25H4V2.75Z", 1.4), .stroke("M10.5 2.75V6.25H14", 1.4)])
}

/// Where Paper prints "Synced 2m ago": a centred 13 Regular muted line. These places are not
/// synced, so it says the records are kept on this phone.
struct PlacePhoneLine: View {
    var text = "Kept on this phone"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "iphone").font(.system(size: 12, weight: .medium)).accessibilityHidden(true)
            Text(text).font(Theme.font(13)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.muted)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, PaperCardMetrics.margin + 4)
        .accessibilityElement(children: .combine)
    }
}

/// Paper's search field (card fill, radius 14, 46 tall, an 18pt glass, chips, a 40pt filter
/// circle) for a list whose records live on this phone: the shell's Search cannot find them, so
/// the words are typed here and narrow this list.
struct PlaceSearchField<Filter: View>: View {
    @Binding var query: String
    var placeholder = "Search or ask"
    var chips: [PaperFilterChip] = []
    var identifier: String? = nil
    @ViewBuilder var filter: Filter

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        HStack(spacing: 8) {
            PaperIcon(.search, size: 18, color: Theme.muted)
            ForEach(chips) { chip in PaperFilterChipButton(chip: chip) }
            TextField("", text: $query, prompt: .placeholder(placeholder))
                .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel(placeholder)
                .modifier(PlaceOptionalIdentifier(identifier: identifier))
            if !query.isEmpty {
                Button { query = "" } label: {
                    PaperIcon(.close, size: 12, color: Theme.muted)
                        .frame(width: 32, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Clear search")
            }
            filter.padding(.leading, -2)
        }
        .padding(.leading, 12).padding(.trailing, 4)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(Theme.card, in: shape)
        .clipShape(shape)
        .paperCardMargin()
    }
}

extension PlaceSearchField where Filter == EmptyView {
    init(query: Binding<String>, placeholder: String = "Search or ask", chips: [PaperFilterChip] = [], identifier: String? = nil) {
        self.init(query: query, placeholder: placeholder, chips: chips, identifier: identifier) { EmptyView() }
    }
}

private struct PlaceOptionalIdentifier: ViewModifier {
    let identifier: String?
    func body(content: Content) -> some View {
        if let identifier { content.accessibilityIdentifier(identifier) } else { content }
    }
}

/// Paper's list row on a rows card (46 / 84 / 28 / 42): a leading mark, 12, the name in 16 Medium
/// (-0.01em, 22 line) over a 14 / 20 muted line, then what trails. 16 in from the card's edges and
/// 11 above and below.
struct OnPhoneRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var subtitleColor: Color = Theme.muted
    var leadingWidth: CGFloat? = nil
    /// 64 where Paper sets a two-line row's height (28 / 84).
    var minHeight: CGFloat = 44
    var trailingInset: CGFloat = 16
    var titleColor: Color = Theme.foreground
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    /// Where the hairline between two rows starts: the words' leading edge.
    static func dividerInset(leading width: CGFloat?) -> CGFloat { width.map { 16 + $0 + 12 } ?? 16 }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let leadingWidth { leading.frame(width: leadingWidth) }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(Theme.font(14)).foregroundStyle(subtitleColor)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.leading, 16).padding(.trailing, trailingInset).padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension OnPhoneRow where Leading == EmptyView {
    init(title: String, subtitle: String? = nil, subtitleColor: Color = Theme.muted, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, subtitleColor: subtitleColor, leadingWidth: nil, leading: { EmptyView() }, trailing: trailing)
    }
}

/// A row's amount at the trailing edge: 16 Medium ink (Paper 46 / 42).
struct PlaceAmount: View {
    let text: String
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(text).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
            if let caption { Text(caption).font(Theme.font(14)).foregroundStyle(Theme.muted) }
        }
        .fixedSize()
    }
}

/// The 16pt chevron that ends a row which opens something (Paper 28).
struct PlaceChevron: View {
    var body: some View { PaperIcon(.placeChevron, size: 16, color: Theme.borderStrong) }
}

/// A status chip on a row (Paper 43 "Awaiting approval", 28 "Due today"): 13 Medium on its
/// surface, 22 tall (26 where Paper sets it beside a title).
struct PlaceStatusChip: View {
    let text: String
    let ink: Color
    let surface: Color
    var height: CGFloat = 22

    var body: some View {
        Text(text).font(Theme.font(13, weight: .medium)).foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(minHeight: height)
            .background(surface, in: Capsule())
    }
}

/// The two-pill commit bar at the foot of a screen (Paper 27): 50 tall pills 8 apart, 16 from the
/// edges, on a fade from clear to the canvas.
struct PlaceBottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content.paperActionBarFade()
    }
}

/// Two pills side by side with Paper's weights (27: Start break 1, Clock out 1.4), 8 apart. One
/// pill alone takes the row.
struct PlaceWeightedRow: Layout {
    var weights: [CGFloat] = [1, 1.4]
    var spacing: CGFloat = 8

    private func widths(_ total: CGFloat, count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        let used = (0..<count).map { $0 < weights.count ? weights[$0] : 1 }
        let free = max(0, total - spacing * CGFloat(count - 1))
        let sum = used.reduce(0, +)
        return used.map { free * $0 / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 320
        let each = widths(total, count: subviews.count)
        let height = zip(subviews, each).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (view, width) in zip(subviews, widths(bounds.width, count: subviews.count)) {
            view.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                       proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}

/// Paper's place header puts the screen's one action on the menu circle's row, at the trailing
/// edge. These places' menu circle rides in the navigation bar, so the action rides there too.
private struct PlaceBarCreate: ViewModifier {
    let label: String
    let shows: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            if shows {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    Button(action: action) { CreamCircleLabel(symbol: "plus", ink: true, glyph: .plus) }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel(label)
                        .accessibilityIdentifier("header-create")
                }
            }
        }
    }
}

extension View {
    /// The + circle on the menu circle's row (Paper 46 / 42 / 82A / 92A).
    func placeBarCreate(_ label: String, shows: Bool = true, action: @escaping () -> Void) -> some View {
        modifier(PlaceBarCreate(label: label, shows: shows, action: action))
    }
}
