import SwiftUI

/// One payment from the Query Platform's `payments.all` view (web payments.tsx / money-data.ts).
struct CompanyPayment: Identifiable, Hashable {
    let id: String
    let invoiceID: String
    let amount: Int
    let refundedAmount: Int
    let method: String
    let status: String
    let recordedAt: String

    var refunded: Bool { status == "refunded" || refundedAmount > 0 }
    var isCard: Bool { method.contains("card") || method.contains("tap") }
    var isCash: Bool { method == "cash" }
    var methodLabel: String {
        switch method {
        case "tap_to_pay": "Tap to Pay"
        case "": "Payment"
        default: method.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private struct PaymentsQueryPage: Decodable {
    struct Item: Decodable {
        let id: String
        let fields: [String: QueryValue]
    }
    /// A query cell: money arrives as a number or, from bigint columns, as a string.
    enum QueryValue: Decodable {
        case text(String), number(Double), other
        init(from decoder: Decoder) throws {
            let box = try decoder.singleValueContainer()
            if let text = try? box.decode(String.self) { self = .text(text) }
            else if let number = try? box.decode(Double.self) { self = .number(number) }
            else { self = .other }
        }
        var text: String { if case .text(let value) = self { return value }; return "" }
        var cents: Int {
            switch self {
            case .number(let value): return Int(value)
            case .text(let value): return Int(value) ?? 0
            case .other: return 0
            }
        }
    }
    let items: [Item]
    let nextCursor: String?
}

extension APIClient {
    /// Every payment, newest first: `payments.all` drained a bounded number of pages, as the web does.
    func companyPayments(maxPages: Int = 5) async throws -> (payments: [CompanyPayment], complete: Bool) {
        var all: [CompanyPayment] = []
        var cursor: String?
        var seen = Set<String>()
        for _ in 0..<maxPages {
            let page: PaymentsQueryPage = try await send("GET", "/v1/query", queryItems: [
                URLQueryItem(name: "resourceId", value: "payments"),
                URLQueryItem(name: "viewId", value: "payments.all"),
                URLQueryItem(name: "limit", value: "100"),
            ], cursor: cursor)
            all += page.items.map { item in
                CompanyPayment(id: item.id,
                               invoiceID: item.fields["payments.invoice_id"]?.text ?? "",
                               amount: item.fields["payments.amount"]?.cents ?? 0,
                               refundedAmount: item.fields["payments.refunded_amount"]?.cents ?? 0,
                               method: item.fields["payments.method"]?.text ?? "",
                               status: item.fields["payments.status"]?.text ?? "",
                               recordedAt: item.fields["payments.recorded_at"]?.text ?? "")
            }
            guard let next = page.nextCursor, !next.isEmpty, seen.insert(next).inserted else {
                return (all.sorted { $0.recordedAt > $1.recordedAt }, true)
            }
            cursor = next
        }
        return (all.sorted { $0.recordedAt > $1.recordedAt }, false)
    }
}

/// Web parity (payments.tsx): every payment collected, with All / Card / Cash / Refunded. There is
/// no "New payment" here on purpose: money is collected on an invoice. A row opens its invoice.
struct CompanyPaymentsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var payments: [CompanyPayment] = []
    @State private var complete = true
    @State private var invoiceCustomers: [String: String] = [:]
    @State private var loaded = false
    @State private var error: String?
    @State private var tab = "All"
    @State private var search = ""
    @State private var openInvoice: String?
    /// Paper 54A's chip in the search field: the stretch of time the list and its total cover.
    @State private var period = PaymentPeriod.week

    enum PaymentPeriod: String, CaseIterable {
        case week = "This week", month = "This month", all = "All time"
        var start: Date? {
            switch self {
            case .week: Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start
            case .month: Calendar.current.dateInterval(of: .month, for: .now)?.start
            case .all: nil
            }
        }
    }
    /// The iPad page keeps its own week summary beside the full list.
    private var activePeriod: PaymentPeriod { wide ? .all : period }
    private var inPeriod: [CompanyPayment] {
        guard let start = activePeriod.start else { return payments }
        return payments.filter { (JobFiltering.date($0.recordedAt) ?? .distantPast) >= start }
    }

    /// Paper 54A's segments. "Cash and check" holds the money handed over in person.
    private static let tabs = ["All", "Card", "Cash and check", "Refunds"]

    private var shown: [CompanyPayment] {
        let scope = inPeriod
        let byTab: [CompanyPayment] = switch tab {
        case "Card": scope.filter(\.isCard)
        case "Cash and check": scope.filter { $0.isCash || $0.method == "check" }
        case "Refunds": scope.filter(\.refunded)
        default: scope
        }
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return byTab }
        return byTab.filter { payment in
            [invoiceCustomers[payment.invoiceID] ?? "", reference(payment) ?? "", payment.methodLabel]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
    private var collected: Int { payments.filter { !$0.refunded }.reduce(0) { $0 + $1.amount } }

    /// Payments by the day they were recorded, newest day first, each with what came in that day.
    private struct DayGroup: Identifiable {
        let id: String
        let label: String
        var payments: [CompanyPayment]
        var total: Int { payments.filter { !$0.refunded }.reduce(0) { $0 + $1.amount } }
    }

    private var days: [DayGroup] {
        var groups: [DayGroup] = []
        for payment in shown {
            let date = JobFiltering.date(payment.recordedAt)
            let key = date.map { Calendar.current.startOfDay(for: $0).ISO8601Format() } ?? "unknown"
            if let last = groups.indices.last, groups[last].id == key {
                groups[last].payments.append(payment)
            } else {
                groups.append(DayGroup(id: key, label: date.map { dayLabel($0) } ?? "Date not recorded", payments: [payment]))
            }
        }
        return groups
    }

    /// The iPad layout (Paper T54A): the search field beside the method chips, the days in the wide
    /// column and the week's summary beside them. A phone keeps the single column.
    private var wide: Bool { sizeClass == .regular }

    /// This calendar week, and whether the payments read reach back past its start (so the week's
    /// numbers are whole). When they don't, the summary says how many payments it covers instead.
    private var weekStart: Date? { Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start }
    private var weekCovered: Bool {
        guard let weekStart else { return false }
        return complete || payments.contains { (JobFiltering.date($0.recordedAt) ?? .distantFuture) < weekStart }
    }
    private var summaryPayments: [CompanyPayment] {
        guard weekCovered, let weekStart else { return payments }
        return payments.filter { (JobFiltering.date($0.recordedAt) ?? .distantPast) >= weekStart }
    }

    private var phoneSubtitle: String {
        guard loaded else { return "Every payment, newest first" }
        // Paper 54A: "This week · $12,480 collected". When the read stops short of the period's
        // start, the line says how many payments the figure covers.
        let start = activePeriod.start
        let whole = complete || start.map { start in
            payments.contains { (JobFiltering.date($0.recordedAt) ?? .distantFuture) < start }
        } ?? false
        let sum = inPeriod.filter { !$0.refunded }.reduce(0) { $0 + $1.amount }
        let figure = "\(money(sum, currency: "USD")) collected\(whole ? "" : " in the latest \(payments.count)")"
        return activePeriod == .all ? figure : "\(activePeriod.rawValue) \u{00B7} \(figure)"
    }

    private var periodChips: [PaperFilterChip] {
        period == .all ? [] : [PaperFilterChip(id: "period", title: period.rawValue) { period = .all }]
    }

    private var periodMenu: [ThorbisMenuItem] {
        PaymentPeriod.allCases.map { option in
            ThorbisMenuItem(option.rawValue, isSelected: period == option) { period = option }
        }
    }

    /// Paper T54A: "This week · $12,480 collected" under the title.
    private var wideSubtitle: String {
        guard loaded, weekCovered else { return phoneSubtitle }
        let week = summaryPayments.filter { !$0.refunded }.reduce(0) { $0 + $1.amount }
        return "This week \u{00B7} \(money(week, currency: "USD")) collected"
    }

    /// Paper 54A: the 34 Bold title with what's been collected, a search field, the method
    /// segments, then one card per day under its label and the day's total.
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Paper 54A and T54A: "This week · $12,480 collected" whenever the read covers the
                // week; otherwise what the latest payments add up to.
                PaperHeader(title: "Payments", subtitle: wide ? wideSubtitle : phoneSubtitle, showsCreate: true)
                    // A pushed page: the back button leads, never the drawer's menu circle.
                    .environment(\.paperMenuButton, false)
                    .environment(\.paperDrawer, nil)
                if wide {
                    wideBar
                } else {
                    // Paper 54A: the period chip in the field, the filter circle choosing the period.
                    PlaceSearchField(query: $search, placeholder: "Search or ask", chips: periodChips, identifier: "payments-search") {
                        ThorbisMenu(items: periodMenu, title: "Show", accessibilityLabel: "Choose the period") {
                            PaperFilterCircle(active: false)
                        }
                        .accessibilityIdentifier("header-filter")
                    }
                    PaperTabs(options: Self.tabs, selection: $tab)
                        .padding(.top, 16)
                }
                if let error { ErrorBanner(message: error) { await load() } }
                if wide {
                    HStack(alignment: .top, spacing: 0) {
                        LazyVStack(alignment: .leading, spacing: 0) { dayGroups }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if loaded && !payments.isEmpty {
                            weekSummary
                                .frame(width: 340, alignment: .leading)
                                .padding(.trailing, PaperCardMetrics.margin)
                        }
                    }
                } else {
                    dayGroups
                }
            }
            .environment(\.paperRowInset, ListRoom.gutter)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: session.generation) { await load() }
        .thorbisDestination(item: Binding(get: { openInvoice.map(OpenedID.init) }, set: { openInvoice = $0?.id })) {
            InvoiceDetailView(id: $0.id).thorbisBackButton()
        }
    }

    /// Loading, empty, then one card per day under its label and the day's total.
    @ViewBuilder private var dayGroups: some View {
        if !loaded && error == nil { ListRoomSkeleton(count: 5, threeLines: false) }
        if loaded && shown.isEmpty {
            ListRoomEmpty(glyph: .money, title: payments.isEmpty ? "No payments yet" : "None here",
                          message: payments.isEmpty ? "Collect a payment on an invoice and it shows here." : nil)
        }
        ForEach(days) { day in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(day.label).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(money(day.total, currency: "USD")).font(Theme.font(13)).foregroundStyle(Theme.muted)
            }
            .accessibilityElement(children: .combine)
            .padding(.horizontal, Theme.gutter).padding(.top, 20).padding(.bottom, 8)
            ForEach(Array(day.payments.enumerated()), id: \.element.id) { index, payment in
                Button { openInvoice = payment.invoiceID } label: {
                    // Paper 54A: 16 Medium name, 16 Semibold amount, the 14 muted line; money that
                    // went back in full reads "−$60.00" in the destructive text colour.
                    DocumentCardRow(title: invoiceCustomers[payment.invoiceID] ?? "Payment",
                                    amount: amountText(payment),
                                    subtitle: subtitle(payment),
                                    divider: index > 0,
                                    compact: true,
                                    amountTint: wentBack(payment) ? Theme.destructive : Theme.foreground)
                }
                .buttonStyle(RowPressStyle())
                .disabled(payment.invoiceID.isEmpty)
                .accessibilityHint("Opens the invoice")
                .documentCardSlot(first: index == 0, last: index == day.payments.count - 1, topGap: 0)
            }
        }
    }

    /// Paper T54A's top row: the search field, then All / Card / Cash and check / Refunds as chips
    /// (40 tall, the chosen one brand-tinted).
    private var wideBar: some View {
        HStack(alignment: .center, spacing: 0) {
            DocumentSearchField(text: $search, label: "Search payments")
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                ForEach(Self.tabs, id: \.self) { option in filterChip(option) }
            }
            .padding(.top, 4)
            .padding(.trailing, PaperCardMetrics.margin)
        }
    }

    private func filterChip(_ option: String) -> some View {
        let selected = tab == option
        return Button { tab = option } label: {
            PaperChoiceChipLabel(title: option, isOn: selected)
        }
        .buttonStyle(PressStyle())
        .fixedSize()
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Paper T54A's "This week" card: what came in, what went back and the average payment.
    private var weekSummary: some View {
        let scope = summaryPayments
        let kept = scope.filter { !$0.refunded }
        let collectedCents = kept.reduce(0) { $0 + $1.amount }
        let refundCents = scope.reduce(0) { $0 + refundedCents($1) }
        let refundText = refundCents > 0 ? "\u{2212}\(money(refundCents, currency: "USD"))" : money(0, currency: "USD")
        return VStack(alignment: .leading, spacing: 0) {
            Text(weekCovered ? "This week" : "Latest \(payments.count) payments")
                .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 4).padding(.top, 20).padding(.bottom, 8)
            VStack(spacing: 0) {
                summaryRow("Collected", money(collectedCents, currency: "USD"), tint: Theme.foreground, divider: false)
                summaryRow("Refunds", refundText, tint: refundCents > 0 ? Theme.destructive : Theme.foreground, divider: true)
                if !kept.isEmpty {
                    summaryRow("Average payment", money(collectedCents / kept.count, currency: "USD"),
                               tint: Theme.foreground, divider: true)
                }
            }
            .padding(.horizontal, 16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    private func summaryRow(_ title: String, _ value: String, tint: Color, divider: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value).font(Theme.monoFont(16, weight: .semibold)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(minHeight: 54)
        .overlay(alignment: .top) { if divider { WellDivider(leading: 0) } }
        .accessibilityElement(children: .combine)
    }

    /// What went back on one payment: the recorded refund, or the whole payment when it is marked
    /// refunded without an amount.
    private func refundedCents(_ payment: CompanyPayment) -> Int {
        payment.refundedAmount > 0 ? payment.refundedAmount : (payment.status == "refunded" ? payment.amount : 0)
    }

    /// The whole payment went back to the customer (a part refund keeps its amount and says so in
    /// the line under the name).
    private func wentBack(_ payment: CompanyPayment) -> Bool {
        payment.refunded && refundedCents(payment) >= payment.amount && payment.amount > 0
    }

    /// "$340.00", or "−$60.00" for a payment refunded in full (Paper 54A).
    private func amountText(_ payment: CompanyPayment) -> String {
        let text = money(payment.amount, currency: "USD")
        return wentBack(payment) ? "\u{2212}\(text)" : text
    }

    private struct OpenedID: Identifiable, Hashable { let id: String }

    private func reference(_ payment: CompanyPayment) -> String? {
        payment.invoiceID.isEmpty ? nil : "INV-\(payment.invoiceID.suffix(4).uppercased())"
    }

    /// "Today", "Yesterday", then "Mon, Jul 19".
    private func dayLabel(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date),
                                                   to: Calendar.current.startOfDay(for: .now)).day ?? 0
        return days <= 0 ? "Today" : days == 1 ? "Yesterday" : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "INV-2209 · Card", "INV-8819 · Card · refunded" (the day is the group's label).
    private func subtitle(_ payment: CompanyPayment) -> String {
        // Paper 54A: "INV-8819 · Refund to Visa ending 7302". The record carries the method, not
        // the card or who took it, so a full refund reads "Refund to card".
        if wentBack(payment) {
            let to = payment.method.isEmpty ? "Refund" : "Refund to \(payment.methodLabel.lowercased())"
            return [reference(payment), to].compactMap { $0 }.joined(separator: " \u{00B7} ")
        }
        let refund: String? = payment.refunded
            ? (payment.refundedAmount > 0 ? "\(money(payment.refundedAmount, currency: "USD")) refunded" : "refunded")
            : nil
        return [reference(payment), payment.methodLabel, refund].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    private func load() async {
        let generation = session.generation
        do {
            let page = try await api.companyPayments()
            // Payments carry no customer; names join from the invoice book, as on the web.
            let invoices = (try? await api.fieldInvoices()) ?? []
            guard session.generation == generation else { return }
            payments = page.payments
            complete = page.complete
            invoiceCustomers = Dictionary(invoices.map { ($0.id, store.customerName($0.customerId)) }, uniquingKeysWith: { first, _ in first })
            loaded = true
            error = nil
        } catch is CancellationError {
        } catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
        }
    }
}
