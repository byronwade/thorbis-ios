import SwiftUI

/// Web parity (money.tsx): what's owed, collected and billed, how old the unpaid balances are, and
/// who to chase first. Figures come from the whole invoice book and the payments tape; when either
/// read is partial the totals say so instead of printing a smaller, wrong number.
struct MoneyOverviewView: View {
    /// Inside Money's Overview tab: the screen's header, scroll and refresh belong to Money.
    var embedded = false
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
            content.padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PaperHeader(title: "Money", subtitle: "What's owed, collected and billed")
                        .environment(\.paperMenuButton, false)
                        .environment(\.paperDrawer, nil)
                        .padding(.horizontal, -Theme.gutter)
                    content
                }
                .padding(.horizontal, Theme.gutter).padding(.bottom, 24)
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await load() }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let error { ErrorBanner(message: error) { await load() }.padding(.horizontal, -Theme.gutter) }
            if !loaded && error == nil { SkeletonRows(count: 4, leading: false, inset: 0) }
            if loaded {
                figures
                aging
                chasingList
            }
        }
        .task(id: session.generation) { await load() }
        .thorbisDestination(item: $openInvoice) { InvoiceDetailView(id: $0.id).thorbisBackButton() }
    }

    /// The vital numbers, two by two (the Today strip's figure and word).
    private var figures: some View {
        let collection = billed > 0 && paymentsComplete ? "\(Int((Double(collected) / Double(billed) * 100).rounded()))%" : "\u{2014}"
        let cells = [(money(outstanding, currency: "USD"), "outstanding", outstanding > 0 ? Theme.foreground : Theme.muted),
                     (paymentsComplete ? money(collected, currency: "USD") : "\u{2014}", "collected", Theme.foreground),
                     (money(billed, currency: "USD"), "billed", Theme.foreground),
                     (collection, "of billed collected", Theme.foreground)]
        // Two by two; one column at accessibility sizes, so no word breaks mid-way ("outstandi-ng").
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(cells, id: \.1) { figure($0.0, $0.1, tint: $0.2) }
                }
            } else {
                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow { figure(cells[0].0, cells[0].1, tint: cells[0].2); figure(cells[1].0, cells[1].1) }
                    GridRow { figure(cells[2].0, cells[2].1); figure(cells[3].0, cells[3].1) }
                }
            }
        }
    }

    private func figure(_ value: String, _ word: String, tint: Color = Theme.foreground) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.font(24, weight: .medium)).monospacedDigit().foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(word).font(Theme.font(14)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var aging: some View {
        let buckets = Self.buckets(chasing)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Aging", horizontalPadding: 0) {
                if outstanding > 0 && !typeSize.isAccessibilitySize { Text("days since created").font(Theme.font(13)) }
            }
            if outstanding > 0 && typeSize.isAccessibilitySize {
                Text("Days since the invoice was created").font(Theme.font(13)).foregroundStyle(Theme.muted)
            }
            if outstanding == 0 {
                Text("Nothing outstanding. Every issued invoice is collected.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                        HStack(spacing: 8) {
                            Circle().fill(bucket.amount > 0 ? Self.tints[index] : Theme.muted.opacity(0.4)).frame(width: 8, height: 8)
                            Text(bucket.label).font(Theme.font(15)).foregroundStyle(Theme.subtle)
                            if bucket.count > 0 {
                                Text("\(bucket.count)").font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 8)
                            Text(money(bucket.amount, currency: "USD")).font(Theme.rowAmountFont(15))
                                .foregroundStyle(bucket.amount > 0 ? Theme.foreground : Theme.muted)
                        }
                        .frame(minHeight: 36)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var chasingList: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Chasing", count: chasing.isEmpty ? nil : chasing.count, horizontalPadding: 0) {
                if chasing.count > 6 { Text("top 6").font(Theme.font(13)) }
            }
            if chasing.isEmpty {
                Text("No one owes you right now.").font(Theme.font(15)).foregroundStyle(Theme.muted)
            }
            ForEach(chasing.prefix(6), id: \.0.id) { invoice, due in
                Button { openInvoice = OpenedInvoice(id: invoice.id) } label: {
                    MoneyListRow(title: store.customerName(invoice.customerId),
                                 subtitle: "INV-\(invoice.id.suffix(4).uppercased()) \u{00B7} balance due",
                                 status: DocumentStatus(invoice: invoice),
                                 amount: money(due, currency: invoice.currency))
                }
                .buttonStyle(RowPressStyle())
                .accessibilityHint("Opens the invoice")
            }
            .environment(\.paperRowInset, 0)
        }
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
