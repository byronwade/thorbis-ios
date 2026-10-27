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

    var body: some View {
        let unpaid = NeedsAttention.unpaid(invoices)
        let waiting = NeedsAttention.waiting(estimates)
        let unscheduled = NeedsAttention.unscheduled(store.jobs)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Needs attention", subtitle: loaded ? summary(unpaid.count + waiting.count + unscheduled.count) : "Checking…")
                if let error { ErrorBanner(message: error) }
                if !unpaid.isEmpty {
                    PaperGroupHeader(title: "Unpaid invoices", count: unpaid.count).padding(.horizontal, Theme.gutter).padding(.top, 8)
                    ForEach(unpaid, id: \.0.id) { invoice, balance in
                        NavigationLink(value: PaperRoute.invoice(invoice.id)) {
                            row(title: store.customerName(invoice.customerId), detail: since("Issued", invoice.issuedAt),
                                trailing: money(balance, currency: invoice.currency), tint: Theme.warning)
                        }.buttonStyle(.plain)
                    }
                }
                if !waiting.isEmpty {
                    PaperGroupHeader(title: "Estimates waiting on the customer", count: waiting.count).padding(.horizontal, Theme.gutter).padding(.top, 16)
                    ForEach(waiting) { estimate in
                        NavigationLink(value: PaperRoute.estimate(estimate.id)) {
                            row(title: estimate.title, detail: "\(store.customerName(estimate.customerId)) · \(since("Sent", estimate.sentAt))",
                                trailing: paperLinesTotal(estimate.lines).map { money($0, currency: estimate.lines.first?.unitPrice.currency ?? "USD") } ?? "", tint: Theme.muted)
                        }.buttonStyle(.plain)
                    }
                }
                if !unscheduled.isEmpty {
                    PaperGroupHeader(title: "Jobs without a time", count: unscheduled.count).padding(.horizontal, Theme.gutter).padding(.top, 16)
                    ForEach(unscheduled) { job in
                        NavigationLink(value: job) {
                            row(title: job.title, detail: "\(job.shortRef) · \(store.customerName(job.customerId))", trailing: "", tint: Theme.muted)
                        }.buttonStyle(.plain)
                    }
                }
                if loaded && unpaid.isEmpty && waiting.isEmpty && unscheduled.isEmpty {
                    PaperEmptyState(symbol: "checkmark.circle", title: "Nothing needs attention",
                                    message: "Unpaid invoices, estimates waiting more than a week and jobs without a time show up here.")
                }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .task { await load() }
        .refreshable { await load() }
    }

    private func summary(_ count: Int) -> String { count == 0 ? "All caught up" : "\(count) item\(count == 1 ? "" : "s")" }

    private func since(_ verb: String, _ raw: String?) -> String {
        guard let date = JobFiltering.date(raw) else { return verb }
        let days = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        return days <= 0 ? "\(verb) today" : "\(verb) \(days) day\(days == 1 ? "" : "s") ago"
    }

    private func row(title: String, detail: String, trailing: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(15, weight: .medium)).lineLimit(1)
                Text(detail).font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            if !trailing.isEmpty { Text(trailing).font(Theme.monoFont(13, weight: .semibold)).foregroundStyle(tint) }
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.subtle)
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 10)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
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
