import SwiftUI

// The customer row (Book a job's customer picker) and the search row's leading glyph. Each is
// content only; the screen wraps it in its own button or link. Job, customer and inbox rows on
// the list rooms are `JobRoomRow` and its neighbours in `ListRoomRows.swift`.

/// A customer in the book: their initials on a tinted circle, the name in semibold, where and how
/// to reach them, and the open job's status (glyph and word) or "Archived" on the right.
struct CustomerListRowContent: View {
    let name: String
    /// Street · phone.
    var detail: String? = nil
    /// Jobs and when the open visit is.
    var meta: String? = nil
    var status: (tone: StatusTone, word: String)? = nil
    var archived = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.paperRowInset) private var inset

    /// Kept for call sites; rows have no hairline (v2).
    static let dividerInset: CGFloat = PaperCardMetrics.inset + 32 + 12

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        HStack(alignment: stacked ? .top : .center, spacing: 12) {
            InitialsAvatar(name: name, size: 32)
                .opacity(archived ? 0.55 : 1)
                .accessibilityHidden(true)
            let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                 : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(Theme.font(16, weight: .medium))
                        .foregroundStyle(archived ? Theme.muted : Theme.foreground)
                        .lineLimit(stacked ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .lineLimit(stacked ? nil : 1)
                    }
                    if let meta, !meta.isEmpty {
                        Text(meta).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                            .lineLimit(stacked ? nil : 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
        }
        .padding(.horizontal, inset).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var trailing: some View {
        if archived {
            StatusWord(text: "Archived")
        } else if let status {
            StatusLabel(tone: status.tone, word: status.word, emphasis: .quiet)
                .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
        }
    }
}

/// What leads a search row, by the kind of record (Linear's search): a job's place mark (its status
/// is a word at the row's end), a customer's initials, a document's place mark, or a symbol for an
/// action or recent search.
enum SearchGlyph {
    case none
    case job(status: String, hasTime: Bool)
    case customer(String)
    case place(symbol: String, tint: Color)
    case icon(String)

    /// An estimate, invoice or other record's place mark, in the More screen's hues.
    static func document(_ type: String) -> SearchGlyph {
        switch type {
        case "estimate": .place(symbol: MenuItem.estimates.symbol, tint: MenuItem.estimates.tint)
        case "invoice": .place(symbol: MenuItem.invoices.symbol, tint: MenuItem.invoices.tint)
        case "billing_schedule": .place(symbol: MenuItem.billing.symbol, tint: MenuItem.billing.tint)
        case "payment": .place(symbol: "dollarsign", tint: Theme.markForest)
        case "location": .place(symbol: "mappin", tint: Theme.markPumpkin)
        default: .place(symbol: "doc", tint: Theme.markGrey)
        }
    }

    @ViewBuilder var view: some View {
        switch self {
        case .none: EmptyView()
        // v2: a job leads with the Jobs mark; the row ends in its status word (see SearchViews).
        case .job: PlaceMark(symbol: MenuItem.jobs.symbol, tint: MenuItem.jobs.tint)
        case .customer(let name): InitialsAvatar(name: name, size: 24).accessibilityHidden(true)
        case .place(let symbol, let tint): PlaceMark(symbol: symbol, tint: tint)
        case .icon(let symbol):
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                .frame(width: 24).accessibilityHidden(true)
        }
    }
}
