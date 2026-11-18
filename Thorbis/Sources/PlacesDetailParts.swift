import SwiftUI

// Pieces for the detail, editor and sheet screens of the places that keep their records on this
// phone, at Paper's sizes.

extension PaperGlyph {
    /// Paper 41's status mark on a meta pill: a ring, half filled.
    static let placeHalfRing = PaperGlyph(box: 14, [.circle(7, 7, 6, 1.4), .fill("M7 3.2 A3.8 3.8 0 0 1 7 10.8 Z")])
    /// Paper 41's clock on a meta pill.
    static let placeClock = PaperGlyph(box: 14, [.circle(7, 7, 6, 1.4), .stroke("M7 3.8V7L9 8.5", 1.4)])
    /// Paper 27A's caution mark on the warning strip.
    static let placeCaution = PaperGlyph(box: 16, [.circle(8, 8, 6.2, 1.5), .stroke("M8 4.8V8.6M8 11V11.1", 1.6)])
    /// Paper 27B's spark on the suggestion card.
    static let placeSpark = PaperGlyph(box: 18, [.stroke("M9 2L10.4 6.6L15 8L10.4 9.4L9 14L7.6 9.4L3 8L7.6 6.6L9 2Z", 1.5)])
}

/// Paper 41's meta pill under a detail's title: 40 tall on the card, 14 Medium, an optional 14pt
/// mark (10 in from the edge, 6 before the words) or a 22pt initials circle (6 in).
struct PlaceMetaPill: View {
    let text: String
    var glyph: PaperGlyph? = nil
    var initials: String? = nil
    var ink: Color = Theme.subtle

    var body: some View {
        HStack(spacing: 6) {
            if let initials {
                Text(initials).font(.custom("Inter-Regular", fixedSize: 11).weight(.semibold))
                    .foregroundStyle(Theme.brandText)
                    .frame(width: 22, height: 22)
                    .background(Theme.brandSurface, in: Circle())
                    .accessibilityHidden(true)
            } else if let glyph {
                PaperIcon(glyph, size: 14, color: Theme.muted).accessibilityHidden(true)
            }
            Text(text).font(Theme.font(14, weight: .medium)).foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, initials != nil ? 6 : (glyph != nil ? 10 : 12)).padding(.trailing, 12)
        .padding(.vertical, 4)
        .frame(minHeight: 40)
        .background(Theme.card, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Paper 56C / 42A's summary tile: a 13 label over a 22 Bold figure on a radius-16 card; the
/// warning surface and ink when it asks for attention.
struct PlaceSummaryTile: View {
    let label: String
    let value: String
    var warn = false
    var valueInk: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(Theme.font(13)).foregroundStyle(warn ? Theme.warning : Theme.muted)
            Text(value).font(Theme.font(22, weight: .bold))
                .foregroundStyle(valueInk ?? (warn ? Theme.warning : Theme.foreground))
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(warn ? Theme.warningSurface : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Paper 27A's kind picker: three words on the card (radius 14, 3 in), the chosen one on a
/// radius-11 plate 38 tall in 14 Semibold, the others 14 Medium muted.
struct PlaceSegments<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    /// Paper 92D rounds the track and the plate all the way and tints the plate with 12% ink.
    var pill = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let on = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.label).font(Theme.font(14, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? Theme.foreground : Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: pill ? 19 : 11, style: .continuous)
                                    .fill(pill ? Theme.foreground.opacity(0.12) : Theme.sidebarAccent)
                            }
                        }
                        .contentShape(Rectangle().inset(by: -3))
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: pill ? 22 : 14, style: .continuous))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Paper 27B's editable time on a row: 16 Semibold in a 36-tall box with a 1.5pt brand rim
/// (radius 10). It opens the date picker.
struct PlaceTimeBox: View {
    let text: String
    let label: String
    var identifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text).font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .frame(minHeight: 36)
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.brand, lineWidth: 1.5) }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(label), \(text)")
        .accessibilityHint("Changes the time")
        .accessibilityIdentifier(identifier ?? "place-time-box")
    }
}

/// A sheet row's label and its value, 56 tall (Paper 27B): 16 Regular ink and a 16 Regular muted
/// value, or both 16 Semibold ink for the total.
struct PlaceSheetValueRow: View {
    let label: String
    let value: String
    var strong = false
    var minHeight: CGFloat = 56
    /// The value in 16 Semibold ink beside a regular label (Paper 27C's Today rows).
    var emphasis = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { labelText; Spacer(minLength: 12); valueText }
            VStack(alignment: .leading, spacing: 2) { labelText; valueText }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View {
        Text(label).font(Theme.font(16, weight: strong ? .semibold : .regular)).foregroundStyle(Theme.foreground)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value).font(Theme.font(16, weight: strong || emphasis ? .semibold : .regular))
            .foregroundStyle(strong || emphasis ? Theme.foreground : Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Paper 56C's three tiles side by side, 8 apart, the first a little wider (1.3 to 1 to 1).
struct PlaceTileRow: Layout {
    var spacing: CGFloat = 8
    var firstWeight: CGFloat = 1.3

    private func widths(_ count: Int, in width: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        let weights = (0..<count).map { $0 == 0 && count > 1 ? firstWeight : 1 }
        let free = max(0, width - spacing * CGFloat(count - 1))
        let sum = weights.reduce(0, +)
        return weights.map { free * $0 / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Asked for its ideal width, it reports the tiles' own so ViewThatFits can tell when they don't fit.
        guard let width = proposal.width, width.isFinite else {
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            return CGSize(width: sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, subviews.count - 1)),
                          height: sizes.map(\.height).max() ?? 0)
        }
        let columns = widths(subviews.count, in: width)
        let height = zip(subviews, columns).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = widths(subviews.count, in: bounds.width)
        var x = bounds.minX
        for (subview, width) in zip(subviews, columns) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}

extension PaperGlyph {
    /// Paper 44's bolt on the "read from the photo" note.
    static let placeBolt = PaperGlyph(box: 16, [.fill("M8.8 1.5L3.5 9h3.2l-.5 5.5L11.5 7H8.3l.5-5.5z")])
    /// Paper 44's up-and-down mark after an answer that can be changed.
    static let placeUpDown = PaperGlyph(box: 12, [.stroke("M3.5 4.5L6 2L8.5 4.5M3.5 7.5L6 10L8.5 7.5", 1.4)])
}
