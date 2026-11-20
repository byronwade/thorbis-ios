import SwiftUI

/// Paper 48D–48G: the parts of a customer's tabbed page. The header (number and since, the name,
/// the five segments) and the Jobs and Billing bodies; Media is `CustomerRecordsView(mediaTab:)`
/// and Activity is the customer's own timeline.

/// A row whose children share its width by weight (Paper gives "Overview" 1.25 and the rest 1).
private struct WeightedRow: Layout {
    let weights: [CGFloat]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let total = max(weights.prefix(subviews.count).reduce(0, +), 1)
        var x = bounds.minX
        for (index, view) in subviews.enumerated() {
            let width = bounds.width * (index < weights.count ? weights[index] : 1) / total
            view.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width
        }
    }
}

/// Paper 48D's header under the back and more circles: "CUS-0412 · Customer since Mar 2022" (14
/// muted), the name (30 Bold, -0.025em), then the segments (card track radius 11, 2 in; 36-tall
/// segments radius 9, the chosen one ink at 16%).
struct CustomerTabsHeader: View {
    let eyebrow: String?
    let name: String
    let tabs: [String]
    let selection: String
    let select: (String) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Text(eyebrow).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(name).font(Theme.font(30, weight: .bold)).tracking(-0.75).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4).padding(.top, 12)
            track.padding(.top, 16)
        }
    }

    @ViewBuilder private var track: some View {
        if typeSize.isAccessibilitySize {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) { ForEach(tabs, id: \.self) { segment($0).padding(.horizontal, 12) } }
                    .padding(2)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        } else {
            WeightedRow(weights: tabs.map { $0 == "Overview" ? 1.25 : 1 }) {
                ForEach(tabs, id: \.self) { segment($0) }
            }
            .padding(2)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    private func segment(_ tab: String) -> some View {
        let on = tab == selection
        return Button { select(tab) } label: {
            Text(tab).font(Theme.font(14, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? Theme.foreground : Theme.subtle)
                .lineLimit(1).minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.85)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(on ? Theme.foreground.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                // A 36-tall segment with a 44-point target.
                .padding(.vertical, 4).contentShape(Rectangle()).padding(.vertical, -4)
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("customer-tab-\(tab.lowercased())")
    }
}

/// A section label on a customer tab (13 Semibold muted; 22 above, 8 below, 4 in), with an
/// optional trailing fact or action.
struct CustomerTabLabel<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 4).padding(.top, 22).padding(.bottom, 8)
    }
}

extension CustomerTabLabel where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

/// One open job on the Jobs tab (Paper 48D "Today"): the problem (17 Semibold) over
/// "JOB-2214 · 10:30 AM · Ramon M." with the status pill, then a hairline and the job's unpaid
/// invoice beside "Open job".
struct CustomerOpenJobCard: View {
    let job: Job
    let line: String
    let invoiceLine: String?
    let open: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let tone = StatusTone(jobStatus: job.status, hasTime: job.scheduledFor != nil)
        let pill = HStack(spacing: 6) {
            StatusGlyph(tone: tone, label: job.status.statusLabel, size: 12)
            Text(tone == .inProgress && job.status != "paused" ? "Working" : job.status.statusLabel)
                .font(Theme.font(13, weight: .semibold)).foregroundStyle(tone.text)
        }
        .padding(.horizontal, 10).frame(minHeight: PaperControl.statusHeight)
        .background(tone.surface, in: Capsule())
        let words = VStack(alignment: .leading, spacing: 0) {
            // Two lines beside the pill at most; the job opens with its whole title.
            Text(job.title).font(Theme.font(17, weight: .semibold)).tracking(-0.17).foregroundStyle(Theme.foreground)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
            Text(line).font(Theme.font(14)).foregroundStyle(Theme.muted)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        return Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) { words; pill }
                } else {
                    HStack(alignment: .center, spacing: 12) { words; pill.fixedSize() }
                }
                Rectangle().fill(Theme.border).frame(height: 1)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(invoiceLine ?? "").font(Theme.font(14)).foregroundStyle(Theme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Open job").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.brandText)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(RowPressStyle())
        .accessibilityHint("Opens the job")
        .accessibilityIdentifier("customer-open-job-\(job.id)")
    }
}

/// A two-line row with a figure trailing (Paper 48D past jobs, 48E invoices): 16 Medium over 14,
/// the figure 16 in a fixed column, 11 above and below, 16 in.
struct CustomerFigureRow: View {
    let title: String
    let line: String
    var lineColor: Color = Theme.muted
    let figure: String?
    var figureColor: Color = Theme.foreground
    var figureWeight: Font.Weight = .medium
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(line).font(Theme.font(14)).foregroundStyle(lineColor)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let figure {
                Text(figure).font(Theme.font(16, weight: figureWeight)).foregroundStyle(figureColor)
                    .lineLimit(1).fixedSize()
                    .frame(minWidth: typeSize.isAccessibilitySize ? 0 : 76, alignment: .trailing)
            }
        }
        .padding(.leading, 16).padding(.trailing, 16).padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A plain card of rows on a customer tab (radius 20, hairlines 16 in).
struct CustomerRowsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: shape)
            .clipShape(shape)
    }
}

/// What the Billing tab knows about one invoice.
struct CustomerBillingInvoice: Identifiable {
    let id: String
    let reference: String
    let title: String?
    let status: String
    let total: Int?
    let due: Int?
    /// What has been paid toward it, in cents.
    var paid = 0
    let currency: String
    let issuedAt: Date?
    let paidAt: Date?

    var isOpen: Bool { ["issued", "sent", "open", "overdue"].contains(status) }
    var isVoid: Bool { status == "void" || status == "voided" }
    var heading: String { [reference, title].compactMap { $0 }.joined(separator: " · ") }

    /// "Unpaid · sent Jul 21", "Part paid $100 · sent Jul 21", "Paid Mar 12", "Paid Nov 4, 2025",
    /// "Draft", "Void".
    func line(now: Date = .now) -> String {
        if isVoid { return "Void" }
        if status == "paid" { return paidAt.map { "Paid \(CustomerTabDates.short($0, now: now))" } ?? "Paid" }
        if isOpen {
            let word = paid > 0 ? "Part paid \(summaryMoney(paid, currency: currency))" : "Unpaid"
            return issuedAt.map { "\(word) · sent \(CustomerTabDates.sent($0, now: now))" } ?? word
        }
        return status.statusLabel
    }
}

enum CustomerTabDates {
    /// "Mar 12" this year, "Nov 4, 2025" before it.
    static func short(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// Today's time ("9:39 AM"), else the short date.
    static func sent(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        calendar.isDate(date, inSameDayAs: now) ? date.tradeTime : short(date, now: now, calendar: calendar)
    }

    /// A past job's day, always with its year (Paper 48D "Mar 12, 2026").
    static func full(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).day().year()) }
}

/// Paper 48E's balance card: "Balance" (13 Semibold muted), the figure (34 Bold, -0.02em), what it
/// is for, then Collect in the brand beside a quiet second action.
struct CustomerBalanceCard: View {
    let balance: String
    let line: String
    let collectTitle: String?
    let collect: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Balance").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                Text(balance).font(Theme.font(34, weight: .bold)).tracking(-0.68).foregroundStyle(Theme.foreground)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(line).font(Theme.font(14)).foregroundStyle(Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if let collectTitle {
                Button(action: collect) {
                    Text(collectTitle).paperButton(.card, tone: .brand, fills: true)
                }
                .buttonStyle(PressStyle())
                .accessibilityHint("Opens the invoice to take payment")
                .accessibilityIdentifier("customer-billing-collect")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}
