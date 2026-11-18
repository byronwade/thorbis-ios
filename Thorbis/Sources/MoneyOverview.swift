import SwiftUI

/// Web parity (money.tsx): what's owed, collected and billed, how old the unpaid balances are, and
/// who to chase first. Figures come from the whole invoice book and the payments tape; when either
/// read is partial the totals say so instead of printing a smaller, wrong number.
struct MoneyOverviewView: View {
    /// Inside Money's Overview tab: the screen's header, scroll and refresh belong to Money.
    var embedded = false
    /// Paper 54's Money shows only who to get paid by; the figures and aging live in the full report.
    var chasingOnly = false
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @State private var invoices: [InvoiceRecord] = []
    @State private var payments: [CompanyPayment] = []
    @State private var paymentsComplete = false
    @State private var loaded = false
    @State private var error: String?
    @State private var openInvoice: OpenedInvoice?
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Set in the iPad's detail column; nil on iPhone.
    @Environment(\.paperReadableWidth) private var tabletWidth
    /// iPad (Paper T12E): the figures sit beside each other. Accessibility sizes keep the phone's column.
    private var tablet: Bool { tabletWidth != nil && measuredWidth >= 900 && !typeSize.isAccessibilitySize }
    /// The room this view really has: the iPad column is narrower in portrait and Split View.
    @State private var measuredWidth: CGFloat = 0
    /// Paper 54: a section's label folds its card away (the chevron before the label).
    @State private var agingCollapsed = false
    @State private var chasingCollapsed = false

    private struct OpenedInvoice: Identifiable, Hashable { let id: String }

    struct Bucket: Identifiable {
        let id: String
        let label: String
        let range: ClosedRange<Int>
        var amount = 0
        var count = 0
    }

    private static func total(_ invoice: InvoiceRecord) -> Int {
        invoice.lines.reduce(0) { $0 + $1.quantity * $1.unitPrice.amount }
    }
    /// Biggest balance first, as on the web.
    private var chasing: [(InvoiceRecord, Int)] { NeedsAttention.unpaid(invoices).sorted { $0.1 > $1.1 } }
    private var outstanding: Int { chasing.reduce(0) { $0 + $1.1 } }
    private var billed: Int {
        invoices.filter { ["issued", "paid"].contains($0.status) }.reduce(0) { $0 + Self.total($1) }
    }
    private var collected: Int { payments.filter { !$0.refunded }.reduce(0) { $0 + $1.amount } }

    /// AR aging by days since the invoice was created (there is no due date on an invoice yet).
    static func buckets(_ unpaid: [(InvoiceRecord, Int)], now: Date = .now) -> [Bucket] {
        var buckets = [Bucket(id: "current", label: "0\u{2013}30 days", range: 0...30),
                       Bucket(id: "b31", label: "31\u{2013}60 days", range: 31...60),
                       Bucket(id: "b61", label: "61\u{2013}90 days", range: 61...90),
                       Bucket(id: "b90", label: "90+ days", range: 91...Int.max)]
        for (invoice, due) in unpaid {
            let created = JobFiltering.date(invoice.createdAt) ?? now
            let age = max(0, Calendar.current.dateComponents([.day], from: created, to: now).day ?? 0)
            let index = buckets.firstIndex { $0.range.contains(age) } ?? buckets.count - 1
            buckets[index].amount += due
            buckets[index].count += 1
        }
        return buckets
    }

    private static let tints: [Color] = [Theme.success, Theme.warning, Theme.markPumpkin, Theme.destructive]

    var body: some View {
        if embedded {
            // Money's own scroll already sets the cards 16 from the edge.
            content
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Paper T12E: the iPad column's title is 28 Bold; the phone keeps the 34.
                    PaperHeader(title: "Money", subtitle: headerSubtitle, compact: tablet)
                        .environment(\.paperMenuButton, false)
                        .environment(\.paperDrawer, nil)
                        .padding(.horizontal, -PaperCardMetrics.margin)
                    content
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 40)
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await load() }
        }
    }

    /// Paper 54: "$7,330 open" leads the line under the title, then how many invoices carry it.
    private var headerSubtitle: String {
        guard loaded else { return "What's owed, collected and billed" }
        let count = chasing.count
        if count == 0 { return "Nothing open" }
        return "\(money(outstanding, currency: "USD")) open \u{00B7} \(count) unpaid invoice\(count == 1 ? "" : "s")"
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let error { ErrorBanner(message: error) { await load() }.padding(.horizontal, -PaperCardMetrics.margin) }
            if !loaded && error == nil { SkeletonRows(count: 4, leading: false, inset: 0) }
            if loaded {
                if chasingOnly {
                    chasingList
                } else if tablet {
                    tabletOverview
                } else {
                    figures
                    aging
                    chasingList
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measuredWidth = $0 }
        .task(id: session.generation) { await load() }
        .thorbisDestination(item: $openInvoice) { InvoiceDetailView(id: $0.id).thorbisBackButton() }
    }

    /// Paper 54/59: the lead figure large on its own card (what is owed, the number this screen is
    /// about), then the rest as cards two by two: label, the figure in bold tabular, the word.
    private var figures: some View {
        let collection = billed > 0 && paymentsComplete ? "\(Int((Double(collected) / Double(billed) * 100).rounded()))%" : "\u{2014}"
        let unpaidCount = chasing.count
        // One column at accessibility sizes, so no figure is squeezed.
        let pair = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Outstanding AR").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                // 44 Bold; one line, shrinking before it would clip on a small phone.
                Text(money(outstanding, currency: "USD"))
                    .font(Theme.display()).tracking(Theme.displayTracking())
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(unpaidCount == 0 ? "Nothing owed" : "\(unpaidCount) unpaid invoice\(unpaidCount == 1 ? "" : "s")")
                    .font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityElement(children: .combine)
            pair {
                figure("Collected", paymentsComplete ? money(collected, currency: "USD") : "\u{2014}",
                       detail: paymentsComplete ? "Every payment recorded" : "Too many payments to total here")
                figure("Billed", money(billed, currency: "USD"), detail: "Sent and paid invoices")
            }
            .fixedSize(horizontal: false, vertical: true)
            figure("Collection rate", collection, detail: "Of billed, collected")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func figure(_ label: String, _ value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
            Text(value).font(Theme.monoFont(24, weight: .bold)).foregroundStyle(Theme.foreground)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
        // Paper 59: 14 above and under, 16 at the sides.
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// AR aging on one card: the split bar, then each bucket as a 16 Medium row with its amount.
    private var aging: some View {
        let buckets = Self.buckets(chasing)
        return PaperSection(title: "Aging", collapsed: tablet ? nil : $agingCollapsed) {
            VStack(alignment: .leading, spacing: 0) {
                if outstanding == 0 {
                    Text("Nothing outstanding. Every issued invoice is collected.")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                } else {
                    GeometryReader { geometry in
                        HStack(spacing: 2) {
                            ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                                if bucket.amount > 0 {
                                    Self.tints[index]
                                        .frame(width: max(4, geometry.size.width * CGFloat(bucket.amount) / CGFloat(outstanding)))
                                }
                            }
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 8)
                    .accessibilityHidden(true)
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 6)
                    ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                        HStack(spacing: 8) {
                            Circle().fill(bucket.amount > 0 ? Self.tints[index] : Theme.muted.opacity(0.4)).frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            Text(bucket.label).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                            if bucket.count > 0 {
                                Text("\(bucket.count)").font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 8)
                            Text(money(bucket.amount, currency: "USD")).font(Theme.monoFont(16, weight: .semibold))
                                .foregroundStyle(bucket.amount > 0 ? Theme.foreground : Theme.muted)
                        }
                        .padding(.trailing, 16)
                        .frame(minHeight: 48)
                        .overlay(alignment: .top) { if index > 0 { WellDivider(leading: 0) } }
                        .padding(.leading, 16)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        } accessory: {
            if outstanding > 0 && !typeSize.isAccessibilitySize { Text("days since created").font(Theme.font(13)) }
        }
    }

    /// "balance due", or the status word when part of it is paid.
    private static func balanceWord(_ invoice: InvoiceRecord) -> String {
        let word = DocumentStatus(invoice: invoice).word
        return word == "Unpaid" ? "balance due" : word.lowercased()
    }

    /// Paper 54's "Get paid" card: who owes, biggest balance first. Each row is the customer over
    /// "INV-8704 · sent Jun 15", with the balance over its word on the right; the word takes the
    /// aging colour once the invoice is more than 30 days old. The open total sits beside the label.
    private var chasingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaperSection(title: chasing.isEmpty ? "Get paid" : "Get paid \u{00B7} \(chasing.count)", collapsed: $chasingCollapsed) {
                VStack(alignment: .leading, spacing: 0) {
                    if chasing.isEmpty {
                        Text("No one owes you right now.").font(Theme.font(15)).foregroundStyle(Theme.muted).padding(16)
                    }
                    ForEach(Array(chasing.prefix(6).enumerated()), id: \.element.0.id) { index, item in
                        Button { openInvoice = OpenedInvoice(id: item.0.id) } label: {
                            DocumentCardRow(title: store.customerName(item.0.customerId),
                                            amount: money(item.1, currency: item.0.currency),
                                            subtitle: Self.chaseLine(item.0),
                                            divider: index > 0,
                                            compact: true,
                                            amountNote: Self.chaseWord(item.0),
                                            amountNoteTint: Self.chaseTint(item.0))
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityHint("Opens the invoice")
                    }
                }
            } accessory: {
                if outstanding > 0 {
                    Text("\(money(outstanding, currency: "USD")) open").font(Theme.font(13)).monospacedDigit()
                        .foregroundStyle(Theme.muted)
                }
            }
            if chasing.count > 6 && !chasingCollapsed {
                Text("The 6 biggest balances. Invoices lists the rest.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    /// "INV-8704 · sent Jun 15"; the reference alone when the invoice carries no issue date.
    private static func chaseLine(_ invoice: InvoiceRecord) -> String {
        let reference = "INV-\(invoice.id.suffix(4).uppercased())"
        guard let issued = JobFiltering.date(invoice.issuedAt) else { return reference }
        return "\(reference) \u{00B7} sent \(documentDate(issued))"
    }

    /// "Balance due", or the status word when part of it is paid.
    private static func chaseWord(_ invoice: InvoiceRecord) -> String {
        let word = DocumentStatus(invoice: invoice).word
        return word == "Unpaid" ? "Balance due" : word
    }

    /// Muted up to 30 days, then the aging colours (invoices carry no due date, so no "Overdue").
    private static func chaseTint(_ invoice: InvoiceRecord) -> Color {
        let bucket = ageIndex(invoice)
        return bucket == 0 ? Theme.muted : tints[bucket]
    }

    // MARK: iPad (Paper T12E)

    /// Paper T12E: "Outstanding" beside three figure tiles, then who to chase beside the aging.
    private var tabletOverview: some View {
        let collection = billed > 0 && paymentsComplete ? "\(Int((Double(collected) / Double(billed) * 100).rounded()))%" : "\u{2014}"
        let unpaidCount = chasing.count
        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Outstanding").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.muted)
                    // Paper T12E: 60 Bold in a 300-wide lane; one line, shrinking before it clips.
                    Text(money(outstanding, currency: "USD"))
                        .font(Theme.display(wide: true)).tracking(Theme.displayTracking(wide: true))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.4)
                    Text(unpaidCount == 0 ? "Nothing owed" : "\(unpaidCount) open invoice\(unpaidCount == 1 ? "" : "s")")
                        .font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.subtle)
                        .padding(.horizontal, 12).frame(minHeight: 30)
                        .background(Theme.fill, in: Capsule())
                }
                .padding(.leading, 4)
                // Paper: the figure's lane is 300 wide and the three tiles share the rest.
                .frame(width: 300, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .center)
                .accessibilityElement(children: .combine)
                tabletTile("Collected", paymentsComplete ? money(collected, currency: "USD") : "\u{2014}",
                           detail: paymentsComplete ? "Every payment recorded" : "Too many payments to total here")
                tabletTile("Billed", money(billed, currency: "USD"), detail: "Sent and paid invoices")
                tabletTile("Collection rate", collection, detail: "Of billed, collected")
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                tabletChasing.frame(maxWidth: .infinity, alignment: .leading)
                aging.frame(maxWidth: 340)
            }
        }
    }

    /// Paper T12E's figure tile: the label, the figure in bold tabular, what it counts.
    private func tabletTile(_ label: String, _ value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.muted)
                .padding(.bottom, 14)
            // Paper T12E draws 32 Bold; 34 is the ramp's step, on one line.
            Text(value).font(Theme.monoFont(34, weight: .bold)).tracking(-0.64).foregroundStyle(Theme.foreground)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(detail).font(Theme.font(14)).foregroundStyle(Theme.subtle).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Which aging bucket an unpaid invoice is in (0: up to 30 days since it was created).
    private static func ageIndex(_ invoice: InvoiceRecord, now: Date = .now) -> Int {
        let created = JobFiltering.date(invoice.createdAt) ?? now
        let age = max(0, Calendar.current.dateComponents([.day], from: created, to: now).day ?? 0)
        if age <= 30 { return 0 }
        if age <= 60 { return 1 }
        return age <= 90 ? 2 : 3
    }

    /// Paper T12E's "Needs attention": who to chase, biggest balance first, each with its age mark.
    private var tabletChasing: some View {
        PaperSection(title: "Needs attention", count: chasing.isEmpty ? nil : chasing.count) {
            VStack(alignment: .leading, spacing: 0) {
                if chasing.isEmpty {
                    Text("No one owes you right now.").font(Theme.font(15)).foregroundStyle(Theme.muted).padding(16)
                }
                ForEach(Array(chasing.prefix(6).enumerated()), id: \.element.0.id) { index, item in
                    Button { openInvoice = OpenedInvoice(id: item.0.id) } label: {
                        tabletChaseRow(item.0, due: item.1, divider: index > 0)
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityHint("Opens the invoice")
                }
            }
        } accessory: {
            if chasing.count > 6 { Text("top 6").font(Theme.font(13)) }
        }
    }

    /// "INV-8704 · Danielle Marlowe" over "$2,480.00 · balance due", the age mark before it.
    private func tabletChaseRow(_ invoice: InvoiceRecord, due: Int, divider: Bool) -> some View {
        let bucket = Self.ageIndex(invoice)
        let tint = Self.tints[bucket]
        return HStack(spacing: 12) {
            Circle().fill(tint.opacity(0.18)).frame(width: 36, height: 36)
                .overlay { Circle().fill(tint).frame(width: 8, height: 8) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("INV-\(invoice.id.suffix(4).uppercased()) \u{00B7} \(store.customerName(invoice.customerId))")
                    .font(Theme.font(16, weight: .medium)).tracking(-0.16).foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                Text("\(money(due, currency: invoice.currency)) \u{00B7} \(Self.balanceWord(invoice))")
                    .font(Theme.monoFont(14)).foregroundStyle(bucket > 0 ? tint : Theme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PaperChevron()
                .foregroundStyle(Theme.muted).accessibilityHidden(true)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .frame(minHeight: 68)
        .overlay(alignment: .top) { if divider { WellDivider(leading: 60) } }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        let generation = session.generation
        do {
            async let invoiceBook = api.fieldInvoices()
            let tape = try? await api.companyPayments()
            let book = try await invoiceBook
            guard session.generation == generation else { return }
            invoices = book
            payments = tape?.payments ?? []
            paymentsComplete = tape?.complete ?? false
            loaded = true
            error = nil
        } catch is CancellationError {
        } catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
        }
    }
}
