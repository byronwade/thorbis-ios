import SwiftUI

// Redesign phase 2 (2026-10-31): the rows of the Jobs and Customers lists, Customer › Jobs and
// Search, after Linear's issue rows. Each one is content only; the screen wraps it in its own link
// (`PaperSplitLink` on the lists so iPad selects into the detail column) and context menu.

/// One row of a lazily built panel: the first slice rounds the top, the last the bottom. No line
/// between rows (v2: tone and space do the pause). Like `paperCardSlot`, so a long list stays lazy
/// instead of becoming one eager `Well`.
private struct WellSlice: ViewModifier {
    let first: Bool
    let last: Bool
    let dividerInset: CGFloat

    func body(content: Content) -> some View {
        let r = Theme.cardRadius
        content
            .environment(\.paperRowInset, PaperCardMetrics.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ThorbisPanelStyle(), in: UnevenRoundedRectangle(topLeadingRadius: first ? r : 0, bottomLeadingRadius: last ? r : 0,
                                                               bottomTrailingRadius: last ? r : 0, topTrailingRadius: first ? r : 0,
                                                               style: .continuous))
    }
}

extension View {
    /// A row of a well built row by row (see `WellSlice`).
    func wellSlice(first: Bool, last: Bool, dividerInset: CGFloat = PaperCardMetrics.inset) -> some View {
        modifier(WellSlice(first: first, last: last, dividerInset: dividerInset))
    }
}

/// A grouped section: the semibold header with its count over one well of rows, built lazily.
struct WellSection<Data: RandomAccessCollection, Row: View, Trailing: View>: View where Data.Element: Identifiable {
    let title: String
    var count: Int? = nil
    let data: Data
    var dividerInset: CGFloat = PaperCardMetrics.inset
    @ViewBuilder var row: (Data.Element) -> Row
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let items = Array(data)
        if !items.isEmpty {
            SectionHeader(title: title, count: count) { trailing }
                .padding(.top, 12).padding(.bottom, 2)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item).wellSlice(first: index == 0, last: index == items.count - 1, dividerInset: dividerInset)
            }
        }
    }
}

extension WellSection where Trailing == EmptyView {
    init(title: String, count: Int? = nil, data: Data, dividerInset: CGFloat = PaperCardMetrics.inset,
         @ViewBuilder row: @escaping (Data.Element) -> Row) {
        self.init(title: title, count: count, data: data, dividerInset: dividerInset, row: row) { EmptyView() }
    }
}

/// A job in a list (Jobs tab, a customer's open jobs), v2: the street leads in Medium (or the
/// job's title when the site is unknown), then the problem, then the status as a word with its small
/// mark followed by who and when, and the tech's avatar. Colour never appears without its word.
/// VoiceOver reads the row as one button: street, problem, status, who and when.
struct JobListRowContent: View {
    let job: Job
    /// Nil on a customer's own page, where the name is the page.
    var customer: String? = nil
    var street: String? = nil
    /// Where, when the street does not lead the row (a customer's own page leads with the problem).
    var place: String? = nil
    /// "Today 4 p.m.", "No time yet"; nil for finished work.
    var when: String? = nil
    var pendingStatus: String? = nil
    /// A booked visit whose time has passed: the status reads "Late" in the error hue.
    var late = false
    /// "You" when the roster is out of reach but the job is the signed-in person's.
    var assigneeWord: String? = nil
    /// The assigned tech's name from the roster; nil shows no avatar.
    var assignee: String? = nil
    var titleLines = 2
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.paperRowInset) private var inset

    /// Kept for call sites; rows have no hairline (v2).
    static let dividerInset: CGFloat = PaperCardMetrics.inset

    private var status: String { pendingStatus ?? job.status }
    private var dimmed: Bool { ["completed", "canceled"].contains(job.status) }

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(street ?? job.title).font(Theme.font(16, weight: .medium))
                    .foregroundStyle(dimmed ? Theme.muted : Theme.foreground)
                    .lineLimit(stacked ? nil : titleLines)
                    .fixedSize(horizontal: false, vertical: true)
                if street != nil {
                    Text(job.title).font(Theme.font(14)).foregroundStyle(Theme.subtle)
                        .lineLimit(stacked ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                statusLine(stacked: stacked)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let assignee {
                InitialsAvatar(name: assignee, size: 24)
                    .accessibilityLabel("Assigned to \(assignee)")
            }
        }
        .padding(.horizontal, inset).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The status word with its mark, then who and when: "◔ En route · Danielle Marlowe · Today 4 p.m.".
    @ViewBuilder private func statusLine(stacked: Bool) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
        layout {
            label
            if let meta {
                Text(stacked ? meta : "· \(meta)").font(Theme.font(13)).monospacedDigit()
                    .foregroundStyle(Theme.muted)
                    .lineLimit(stacked ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var label: some View {
        if late {
            StatusLabel(tone: .attention, word: "Late", emphasis: .strong)
                .accessibilityLabel("Late, \(status.statusLabel)")
        } else {
            StatusLabel(jobStatus: status, hasTime: job.scheduledFor != nil, pending: pendingStatus != nil, emphasis: .quiet)
        }
    }

    private var meta: String? {
        var parts: [String] = []
        if let customer { parts.append(customer) }
        if let place { parts.append(place) }
        if let when { parts.append(when) }
        if let assigneeWord { parts.append(assigneeWord) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

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
                        Text(detail).font(Theme.font(14)).foregroundStyle(Theme.subtle)
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
