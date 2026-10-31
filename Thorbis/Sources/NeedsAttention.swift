import SwiftUI

/// What the office would otherwise go hunting for: invoices still owed, estimates the customer
/// hasn't answered, and jobs with no time yet. Read-only; each row opens the record.
enum NeedsAttention {
    static let staleEstimateDays = 7

    static func unpaid(_ invoices: [InvoiceRecord]) -> [(InvoiceRecord, Int)] {
        invoices.compactMap { invoice in
            guard invoice.status == "issued" else { return nil }
            let total = invoice.lines.reduce(0) { $0 + $1.quantity * $1.unitPrice.amount }
            let balance = total - invoice.amountPaid
            return balance > 0 ? (invoice, balance) : nil
        }
        .sorted { (JobFiltering.date($0.0.issuedAt) ?? .distantFuture) < (JobFiltering.date($1.0.issuedAt) ?? .distantFuture) }
    }

    static func waiting(_ estimates: [EstimateRecord], now: Date = Date()) -> [EstimateRecord] {
        estimates.filter { estimate in
            guard estimate.status == "sent", let sent = JobFiltering.date(estimate.sentAt) else { return false }
            return now.timeIntervalSince(sent) >= Double(staleEstimateDays) * 86_400
        }
        .sorted { (JobFiltering.date($0.sentAt) ?? .now) < (JobFiltering.date($1.sentAt) ?? .now) }
    }

    static func unscheduled(_ jobs: [Job]) -> [Job] {
        jobs.filter { $0.scheduledFor == nil && !["completed", "canceled"].contains($0.status) }
    }
}

struct NeedsAttentionView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @State private var invoices: [InvoiceRecord] = []
    @State private var estimates: [EstimateRecord] = []
    @State private var loaded = false
    @State private var error: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let unpaid = NeedsAttention.unpaid(invoices)
        let waiting = NeedsAttention.waiting(estimates)
        let unscheduled = NeedsAttention.unscheduled(store.jobs)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Pushed screen: system Back only, so no second menu button under it (MA-05).
                // Redesign phase 3: the 30pt semibold title, then one grouped well per kind with its
                // count; rows lead with their status glyph and amounts are semibold tabular.
                // v2: the detail title on the ramp (24), one quiet line, then a group per kind.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Needs attention").font(Theme.font(30, weight: .medium)).tracking(-0.4)
                        .accessibilityAddTraits(.isHeader)
                    Text(loaded ? summary(unpaid.count + waiting.count + unscheduled.count) : "Checking…")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, Theme.gutter).padding(.bottom, 8)
                if let error { ErrorBanner(message: error) }
                // v2 List room, like Jobs and Customers: rows on the canvas under a 13 Medium label
                // with its count. Each row names its state as a word ("Unpaid", "Waiting", "No time").
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !loaded { ListRoomSkeleton(count: 5, threeLines: false) }
                    let rows = unpaid.map { AttentionInvoice(invoice: $0.0, balance: $0.1) }
                    if !rows.isEmpty {
                        ListGroupLabel(title: "Unpaid invoices", count: rows.count, first: true)
                        ForEach(rows) { item in
                            NavigationLink(value: PaperRoute.invoice(item.invoice.id)) {
                                MoneyListRow(title: store.customerName(item.invoice.customerId),
                                             subtitle: "INV-\(item.invoice.id.suffix(4).uppercased()) · \(since("Issued", item.invoice.issuedAt))",
                                             status: DocumentStatus(invoice: item.invoice),
                                             amount: money(item.balance, currency: item.invoice.currency))
                            }.buttonStyle(RowPressStyle())
                        }
                    }
                    if !waiting.isEmpty {
                        ListGroupLabel(title: "Estimates waiting on the customer", count: waiting.count, first: rows.isEmpty)
                        ForEach(waiting) { estimate in
                            NavigationLink(value: PaperRoute.estimate(estimate.id)) {
                                MoneyListRow(title: store.customerName(estimate.customerId),
                                             subtitle: "\(estimate.title) · \(since("Sent", estimate.sentAt))",
                                             status: DocumentStatus(estimateStatus: estimate.status),
                                             statusWord: "Waiting",
                                             amount: paperLinesTotal(estimate.lines).map { money($0, currency: estimate.lines.first?.unitPrice.currency ?? "USD") })
                            }.buttonStyle(RowPressStyle())
                        }
                    }
                    if !unscheduled.isEmpty {
                        ListGroupLabel(title: "Jobs without a time", count: unscheduled.count, first: rows.isEmpty && waiting.isEmpty)
                        ForEach(unscheduled) { job in
                            NavigationLink(value: job) {
                                JobRoomRow(job: job, customer: store.customerName(job.customerId), when: "No time yet")
                            }.buttonStyle(RowPressStyle())
                        }
                    }
                    if loaded && unpaid.isEmpty && waiting.isEmpty && unscheduled.isEmpty {
                        ListRoomEmpty(title: "Nothing needs attention.",
                                      message: "Unpaid invoices, estimates waiting over a week and jobs with no time land here. Pull down to check again.")
                    }
                }
                .environment(\.paperRowInset, ListRoom.gutter)
            }
            .padding(.bottom, 24)
        }
        .modifier(PaperPreviewScrollAnchor())
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .task { await load() }
        .refreshable { await load() }
    }

    private func summary(_ count: Int) -> String { count == 0 ? "All caught up" : "\(count) item\(count == 1 ? "" : "s")" }

    private func since(_ verb: String, _ raw: String?) -> String {
        guard let date = JobFiltering.date(raw) else { return verb }
        let days = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        // "99 days ago" makes you count; past two weeks speak in weeks, then months.
        func ago(_ n: Int, _ unit: String) -> String { "\(verb) \(n) \(unit)\(n == 1 ? "" : "s") ago" }
        switch days {
        case ...0: return "\(verb) today"
        case 1..<14: return ago(days, "day")
        case 14..<60: return ago(days / 7, "week")
        default: return ago(days / 30, "month")
        }
    }

    private func load() async {
        async let invoiceList: [InvoiceRecord] = session.can("invoice.view", feature: "invoicing") ? api.fieldInvoices() : []
        async let estimateList: [EstimateRecord] = session.can("estimate.view", feature: "estimates") ? api.fieldEstimates() : []
        do {
            invoices = try await invoiceList
            estimates = try await estimateList
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }
}

/// An unpaid invoice and what is still owed, keyed for a card list.
private struct AttentionInvoice: Identifiable {
    let invoice: InvoiceRecord
    let balance: Int
    var id: String { invoice.id }
}
