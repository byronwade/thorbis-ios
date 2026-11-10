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
    @State private var payments: [CompanyPayment] = []
    @State private var complete = true
    @State private var invoiceCustomers: [String: String] = [:]
    @State private var loaded = false
    @State private var error: String?
    @State private var tab = "All"
    @State private var openInvoice: String?

    private var shown: [CompanyPayment] {
        switch tab {
        case "Card": payments.filter(\.isCard)
        case "Cash": payments.filter(\.isCash)
        case "Refunded": payments.filter(\.refunded)
        default: payments
        }
    }
    private var collected: Int { payments.filter { !$0.refunded }.reduce(0) { $0 + $1.amount } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Payments",
                            subtitle: loaded ? "\(money(collected, currency: "USD")) collected\(complete ? "" : " in the latest \(payments.count)")"
                                             : "Every payment, newest first")
                    // A pushed page: the back button leads, never the drawer's menu circle.
                    .environment(\.paperMenuButton, false)
                    .environment(\.paperDrawer, nil)
                PaperTabs(options: ["All", "Card", "Cash", "Refunded"], selection: $tab, wrapOverflow: true, textTabs: true)
                    .padding(.horizontal, ListRoom.gutter - 4).padding(.bottom, 4)
                if let error { ErrorBanner(message: error) { await load() } }
                if !loaded && error == nil { ListRoomSkeleton(count: 5, threeLines: false) }
                if loaded && shown.isEmpty {
                    ListRoomEmpty(title: payments.isEmpty ? "No payments yet." : "None here.",
                                  message: payments.isEmpty ? "Collect a payment on an invoice and it shows here." : nil)
                }
                ForEach(shown) { payment in
                    Button { openInvoice = payment.invoiceID } label: {
                        MoneyListRow(title: invoiceCustomers[payment.invoiceID] ?? "Payment",
                                     subtitle: subtitle(payment),
                                     status: payment.refunded ? DocumentStatus(tone: .cancelled, word: "Refunded")
                                                              : DocumentStatus(tone: .done, word: "Paid"),
                                     amount: money(payment.amount, currency: "USD"))
                    }
                    .buttonStyle(RowPressStyle())
                    .disabled(payment.invoiceID.isEmpty)
                    .accessibilityHint("Opens the invoice")
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

    private struct OpenedID: Identifiable, Hashable { let id: String }

    private func subtitle(_ payment: CompanyPayment) -> String {
        let invoice = payment.invoiceID.isEmpty ? nil : "INV-\(payment.invoiceID.suffix(4).uppercased())"
        let when = JobFiltering.date(payment.recordedAt).map { date -> String in
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date),
                                                       to: Calendar.current.startOfDay(for: .now)).day ?? 0
            return days <= 0 ? "Today" : days == 1 ? "Yesterday" : date.formatted(.dateTime.month(.abbreviated).day())
        }
        return [invoice, payment.methodLabel, when].compactMap { $0 }.joined(separator: " \u{00B7} ")
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
