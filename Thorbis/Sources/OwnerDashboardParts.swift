import SwiftUI

// Paper 52 (Office dashboard) and 58 (Owner dashboard): the glyphs, the period arithmetic and the
// small pieces both dashboards, Money and Reports draw. Every figure here is computed from lists
// and reports the app really loads; a comparison with nothing to compare against is left out.

extension PaperGlyph {
    /// Paper 52/58: the 12pt trend arrows before a delta.
    static let trendUp = PaperGlyph(box: 12, [.stroke("M6 10V2.5M2.8 5.5L6 2.3L9.2 5.5", 1.6)])
    static let trendDown = PaperGlyph(box: 12, [.stroke("M6 2V9.5M2.8 6.5L6 9.7L9.2 6.5", 1.6)])
    /// Paper 52/58 Needs attention marks (20 box, drawn at 22).
    static let alertTriangle = PaperGlyph(box: 20, [.stroke("M10 3.5L17.5 16H2.5L10 3.5Z", 1.6), .stroke("M10 8.5V11.5", 1.6),
                                                    .circle(10, 13.8, 0.9)])
    static let alertClock = PaperGlyph(box: 20, [.circle(10, 10, 7, 1.6), .stroke("M10 6V10L12.5 11.5", 1.6)])
    static let alertDocument = PaperGlyph(box: 20, [.stroke("M5 3H12L15.5 6.5V17H5V3Z", 1.6),
                                                    .stroke("M12 3V6.5H15.5M7.5 10.5H12.5M7.5 13.5H12.5", 1.6)])
    static let alertSlipping = PaperGlyph(box: 20, [.stroke("M3 6L8 11L11 8L17 14M17 14V10M17 14H13", 1.6)])
    static let alertCalendar = PaperGlyph(box: 20, [.rect(3, 4.5, 14, 12.5, rx: 2, 1.6), .stroke("M3 8.5H17M7 3V6M13 3V6", 1.6)])
    static let alertSync = PaperGlyph(box: 20, [.stroke("M4 10a6 6 0 0 1 10.2-4.2L16 7.5M16 4v3.5h-3.5M16 10a6 6 0 0 1-10.2 4.2L4 12.5M4 16v-3.5h3.5", 1.6)])
    /// Paper's 16pt row chevron.
    static let rowChevron = PaperGlyph(box: 16, [.stroke("M6 3.5L10.5 8L6 12.5", 1.6)])
    /// Paper 59/60: the bars before "Full P&L and trends" / "View full report".
    static let bars = PaperGlyph(box: 20, [.stroke("M5 16V9M10 16V4.5M15 16V11.5", 1.8)])
}

/// "↑ 12% vs Jun": Paper's delta line. Green up, red down; the comparison word in muted.
struct DashboardDelta: Equatable {
    let up: Bool
    let text: String
    var versus: String? = nil

    /// A percent change; nil when there is nothing to compare against or nothing changed.
    static func percent(now: Int, before: Int?, versus: String? = nil) -> DashboardDelta? {
        guard let before, before > 0, now != before else { return nil }
        let change = Int((Double(now - before) / Double(before) * 100).rounded())
        guard change != 0 else { return nil }
        return DashboardDelta(up: change > 0, text: "\(abs(change))%", versus: versus)
    }

    /// A plain difference ("↑ 9"), or in points ("↓ 2 pts").
    static func difference(now: Int, before: Int?, unit: String = "", versus: String? = nil) -> DashboardDelta? {
        guard let before, now != before else { return nil }
        return DashboardDelta(up: now > before, text: "\(abs(now - before))\(unit)", versus: versus)
    }
}

struct DashboardDeltaLine: View {
    let delta: DashboardDelta
    /// Paper 58: the lead card's delta is Semibold with 5 after the arrow; a tile's is Medium with 4.
    var lead = false

    var body: some View {
        HStack(alignment: .center, spacing: lead ? 5 : 4) {
            PaperIcon(delta.up ? .trendUp : .trendDown, size: 12, color: delta.up ? Theme.success : Theme.destructive)
            Text(delta.text).font(Theme.font(14, weight: lead ? .semibold : .medium))
                .foregroundStyle(delta.up ? Theme.success : Theme.destructive)
            if let versus = delta.versus {
                Text(versus).font(Theme.font(14)).foregroundStyle(Theme.muted)
            }
        }
        .frame(minHeight: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(delta.up ? "Up" : "Down") \(delta.text)\(delta.versus.map { " \($0)" } ?? "")")
    }
}

/// Paper 58's figure tile: 13 Semibold label, the figure in 26 Bold, then a delta or one muted
/// line. 14 above and under, 16 at the sides, radius 20.
struct DashboardTile: View {
    let label: String
    let value: String
    var delta: DashboardDelta? = nil
    var detail: String? = nil
    /// Paper 52 draws the office tiles' figure in 28 Bold; 58 in 26.
    var figureSize: CGFloat = 26
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            Text(value).font(Theme.font(figureSize, weight: .bold)).tracking(-0.02 * figureSize)
                .foregroundStyle(Theme.foreground)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let delta {
                DashboardDeltaLine(delta: delta)
            } else if let detail {
                Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Paper 58/59's trailing bars: one 5-wide bar per month, radius 2, 4 apart, the latest in brand
/// blue and the rest in the strong border grey. Decorative; the card's words carry the figure.
struct DashboardMonthBars: View {
    let values: [Int]

    var body: some View {
        let peak = max(values.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index == values.count - 1 ? Theme.brand : Theme.borderStrong)
                    .frame(width: 5, height: max(5, 38 * CGFloat(value) / CGFloat(peak)))
            }
        }
        .frame(height: 40, alignment: .bottom)
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }
}

/// Paper 52/58's attention row: a 22pt mark in a 34-wide lane, the title in 16 Medium over one
/// muted 14 line, a 16pt chevron; the hairline between rows starts at the words.
struct DashboardMarkRow: View {
    let glyph: PaperGlyph
    let tint: Color
    let title: String
    let subtitle: String?
    var divider = false
    var chevron = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            PaperIcon(glyph, size: 22, color: tint).frame(width: 34, alignment: .leading)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(Theme.font(16, weight: .medium)).tracking(-0.16).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle).font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if chevron { PaperIcon(.rowChevron, size: 16, color: Theme.muted) }
            }
            .padding(.trailing, 14).padding(.vertical, 11)
            .frame(minHeight: 64)
            .overlay(alignment: .top) { if divider { WellDivider(leading: 0) } }
        }
        .padding(.leading, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Paper 52/59's money row: the label in 16 Medium, a quiet word and the amount in 16 Semibold on
/// the right; 56 tall, the hairline inset to the words.
struct DashboardAmountRow: View {
    let title: String
    let amount: String
    var note: String? = nil
    var divider = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let note { Text(note).font(Theme.font(13)).foregroundStyle(Theme.muted) }
                Text(amount).font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(.trailing, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .overlay(alignment: .top) { if divider { WellDivider(leading: 0) } }
        .padding(.leading, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The owner's periods (Paper 58: This month / Quarter / YTD) over a report kept in whole months
/// ("yyyy-MM" keys, oldest first, the last one the month in progress).
enum DashboardPeriod: String, CaseIterable {
    case month = "This month", quarter = "Quarter", year = "YTD"

    private static func parts(_ key: String) -> (year: Int, month: Int)? {
        let pieces = key.split(separator: "-")
        guard pieces.count == 2, let year = Int(pieces[0]), let month = Int(pieces[1]), (1...12).contains(month) else { return nil }
        return (year, month)
    }

    /// The month keys this period covers and the keys it is compared with, given the newest key.
    /// The comparison is nil unless every month of it is in `known` (never a short sum).
    func keys(latest: String, known: Set<String>) -> (current: [String], before: [String]?, versus: String?) {
        guard let (year, month) = Self.parts(latest) else { return ([latest], nil, nil) }
        func key(_ y: Int, _ m: Int) -> String { String(format: "%04d-%02d", y, m) }
        func complete(_ keys: [String]) -> [String]? { keys.allSatisfy(known.contains) ? keys : nil }
        switch self {
        case .month:
            let prior = month == 1 ? key(year - 1, 12) : key(year, month - 1)
            let name = Calendar.current.shortStandaloneMonthSymbols[(month + 10) % 12]
            return ([latest], complete([prior]), "vs \(name)")
        case .quarter:
            let first = (month - 1) / 3 * 3 + 1
            let current = (first...month).map { key(year, $0) }
            let priorFirst = first == 1 ? 10 : first - 3
            let priorYear = first == 1 ? year - 1 : year
            let prior = (priorFirst...(priorFirst + 2)).map { key(priorYear, $0) }
            return (current, complete(prior), "vs Q\((priorFirst - 1) / 3 + 1)")
        case .year:
            let current = (1...month).map { key(year, $0) }
            let prior = (1...month).map { key(year - 1, $0) }
            return (current, complete(prior), "vs \(year - 1)")
        }
    }

    /// Sum of `values` over the period, and over what it is compared with.
    func totals(_ values: [(key: String, value: Int)]) -> (now: Int, before: Int?, versus: String?)? {
        guard let latest = values.last?.key else { return nil }
        let table = Dictionary(values.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        let keys = keys(latest: latest, known: Set(table.keys))
        let now = keys.current.reduce(0) { $0 + (table[$1] ?? 0) }
        return (now, keys.before.map { $0.reduce(0) { $0 + (table[$1] ?? 0) } }, keys.versus)
    }

    /// [start, now) in local time, and the whole period before it.
    func range(now: Date = .now, calendar: Calendar = .current) -> (current: DateInterval, before: DateInterval?) {
        let component: Calendar.Component = self == .month ? .month : self == .quarter ? .quarter : .year
        let start: Date
        if self == .quarter {
            // Calendar's .quarter interval is unreliable; build it from the month.
            let month = calendar.component(.month, from: now)
            let first = (month - 1) / 3 * 3 + 1
            start = calendar.date(from: DateComponents(year: calendar.component(.year, from: now), month: first, day: 1)) ?? now
        } else {
            start = calendar.dateInterval(of: component, for: now)?.start ?? now
        }
        let current = DateInterval(start: start, end: max(now, start))
        let priorStart: Date? = switch self {
        case .month: calendar.date(byAdding: .month, value: -1, to: start)
        case .quarter: calendar.date(byAdding: .month, value: -3, to: start)
        case .year: nil
        }
        return (current, priorStart.map { DateInterval(start: $0, end: start) })
    }
}

/// The office's periods (Paper 52: Today / Week / Month), in local time; weeks start Monday.
enum OfficePeriod: String, CaseIterable {
    case today = "Today", week = "Week", month = "Month"

    func range(now: Date = .now, calendar base: Calendar = .current) -> (current: DateInterval, before: DateInterval?, versus: String) {
        var calendar = base
        calendar.firstWeekday = 2
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            let prior = calendar.date(byAdding: .day, value: -7, to: start) ?? start
            let end = calendar.date(byAdding: .day, value: 1, to: prior) ?? prior
            return (DateInterval(start: start, end: max(now, start)), DateInterval(start: prior, end: end),
                    "vs last \(now.formatted(.dateTime.weekday(.abbreviated)))")
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
            let prior = calendar.date(byAdding: .day, value: -7, to: start) ?? start
            return (DateInterval(start: start, end: max(now, start)), DateInterval(start: prior, end: start), "vs last week")
        case .month:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
            let prior = calendar.date(byAdding: .month, value: -1, to: start) ?? start
            return (DateInterval(start: start, end: max(now, start)), DateInterval(start: prior, end: start),
                    "vs \(prior.formatted(.dateTime.month(.abbreviated)))")
        }
    }

    /// "Revenue today", "Completed this week".
    var suffix: String {
        switch self {
        case .today: "today"
        case .week: "this week"
        case .month: "this month"
        }
    }
}

/// Figures read from the invoice and estimate lists the dashboard already loads.
enum DashboardBooks {
    static func total(_ invoice: InvoiceRecord) -> Int { invoice.lines.reduce(0) { $0 + $1.quantity * $1.unitPrice.amount } }

    /// Invoices sent in the interval (issued or paid; drafts and voids are not revenue).
    static func issued(_ invoices: [InvoiceRecord], in interval: DateInterval) -> [InvoiceRecord] {
        invoices.filter { invoice in
            guard ["issued", "paid"].contains(invoice.status), let date = JobFiltering.date(invoice.issuedAt) else { return false }
            return date >= interval.start && date < interval.end || (date == interval.start && interval.duration == 0)
        }
    }

    /// The average invoice sent in the interval, when every one is in `currency`; nil with none.
    static func averageTicket(_ invoices: [InvoiceRecord], in interval: DateInterval, currency: String = "USD") -> Int? {
        let sent = issued(invoices, in: interval)
        guard !sent.isEmpty, sent.allSatisfy({ $0.currency == currency }) else { return nil }
        return sent.reduce(0) { $0 + total($1) } / sent.count
    }

    /// Of the estimates sent in the interval, the share approved, in whole percent; nil with none sent.
    static func closeRate(_ estimates: [EstimateRecord], in interval: DateInterval) -> Int? {
        let sent = estimates.filter { estimate in
            guard estimate.status != "draft", let date = JobFiltering.date(estimate.sentAt) else { return false }
            return date >= interval.start && date < interval.end
        }
        guard !sent.isEmpty else { return nil }
        return Int((Double(sent.filter { $0.status == "approved" }.count) / Double(sent.count) * 100).rounded())
    }
}

/// Paper 52/58: a dashboard's header carries Search as its right-hand circle (no create button).
/// The circle opens the shell's Search; where the shell offers none (iPad column, pushed) it is absent.
struct DashboardHeader: View {
    let title: String
    let subtitle: String
    @Environment(\.paperSearch) private var search
    @Environment(\.paperDrawer) private var drawer
    @Environment(\.paperMenuButton) private var menuButton

    /// True when the header itself carries the menu circle (a tab root); otherwise the circles
    /// sit in the navigation bar and Search joins them there.
    private var inHeader: Bool { drawer != nil || menuButton }

    var body: some View {
        PaperHeader(title: title, subtitle: subtitle)
            .overlay(alignment: .topTrailing) {
                if inHeader { circle.padding(.top, 2).padding(.trailing, PaperCardMetrics.margin) }
            }
            .toolbar {
                if search != nil, !inHeader {
                    ThorbisToolbarItem(placement: .topBarTrailing) { circle }
                }
            }
    }

    @ViewBuilder private var circle: some View {
        if let search {
            Button(action: search.run) { CreamCircleLabel(symbol: "magnifyingglass", glyph: .search) }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Search")
                .accessibilityIdentifier("header-search")
        }
    }
}
