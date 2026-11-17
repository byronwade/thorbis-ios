import SwiftUI

// Paper's own glyphs for the customer, message, record and search screens (Paper 47–51, 76–77,
// 85–88), copied from each artboard's SVG.
extension PaperGlyph {
    /// A row's chevron (Paper 48N, 86A, 87): 14pt, stroke 1.6, in `subtle-foreground`.
    static let rowChevron14 = PaperGlyph(box: 14, [.stroke("M5 3l4 4-4 4", 1.6)])
    /// The handset on Paper 48N's Call circle and 49N's missed-call line.
    static let handset = PaperGlyph(box: 18, [.stroke("M5.5 2.5L7.5 6L6 7.5C6.8 9.3 8.7 11.2 10.5 12L12 10.5L15.5 12.5L14.5 15C14.2 15.6 13.6 16 12.9 15.9C7.5 15.3 2.7 10.5 2.1 5.1C2 4.4 2.4 3.8 3 3.5Z", 1.5)])
    /// Paper 47's Archive cell.
    static let archiveBox = PaperGlyph(box: 24, [.rect(3, 4, 18, 4, rx: 1, 1.8),
                                                 .stroke("M5 8v11a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8M10 12.5h4", 1.8)])
}

/// A row's trailing chevron as Paper draws it.
struct PaperRowChevron: View {
    var body: some View { PaperIcon(.rowChevron14, size: 14, color: Theme.subtleForeground) }
}

/// A record list's row (Paper 85C / 86 / 87A / 88): the name (16/22 Medium, -0.01em) over one
/// muted line (14/20), with a status word (14 Medium, in its own ink) or a number trailing the
/// name. 16 in from the card's edges, 11 above and below. At accessibility sizes the lines wrap.
struct PaperRecordRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var status: String? = nil
    var statusColor: Color = Theme.muted
    var dimmed = false
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                let top = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                  : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
                top {
                    Text(title).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                        .foregroundStyle(dimmed ? Theme.muted : Theme.foreground)
                        .lineLimit(stacked ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let status, !status.isEmpty {
                        Text(status).font(Theme.font(14, weight: .medium)).foregroundStyle(statusColor)
                            .lineLimit(stacked ? nil : 1).fixedSize(horizontal: !stacked, vertical: true)
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .lineLimit(stacked ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension PaperRecordRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, status: String? = nil, statusColor: Color = Theme.muted, dimmed: Bool = false) {
        self.init(title: title, subtitle: subtitle, status: status, statusColor: statusColor, dimmed: dimmed) { EmptyView() }
    }
}
