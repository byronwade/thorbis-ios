import SwiftUI

struct EstimatesView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var store: Store
    @State private var records: [EstimateRecord] = []
    @State private var loading = true
    @State private var error: String?
    @State private var search = ""
    @State private var showCreate = false
    private var visible: [EstimateRecord] { records.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let error { ErrorBanner(message: error) }
                if loading && records.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40) }
                ForEach(paperDocumentGroups(visible, status: \.status, order: ["draft", "sent", "approved", "declined"]), id: \.0) { status, group in
                    PaperGroupHeader(title: status.statusLabel, count: group.count).padding(.top, 6)
                    ForEach(group) { record in
                        NavigationLink { EstimateDetailView(id: record.id) } label: {
                            PaperDocumentRow(reference: "EST-\(record.id.suffix(4).uppercased())", title: record.title,
                                             subtitle: store.customerName(record.customerId), status: record.status,
                                             amount: paperLinesTotal(record.lines).map { money($0, currency: record.lines.first?.unitPrice.currency ?? "USD") })
                        }.buttonStyle(.plain)
                    }
                }
                if !loading && records.isEmpty && error == nil {
                    PaperEmptyState(symbol: "doc.text", title: "No estimates yet", message: "Estimates you build for customers appear here.",
                                    actionTitle: session.can("estimate.create", feature: "estimates") ? "New estimate" : nil, action: { showCreate = true })
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Estimates")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search)
        .task { await load() }
        .refreshable { await load() }
        .toolbar {
            if session.can("estimate.create", feature: "estimates") { Button("New estimate", systemImage: "plus") { showCreate = true } }
        }
        .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) { NewEstimateView() }
    }
    private func load() async {
        loading = true
        defer { loading = false }
        do { records = try await api.fieldEstimates(); error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct EstimateDetailView: View {
    let id: String
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @State private var record: EstimateRecord?
    @State private var error: String?
    @State private var busy = false
    @State private var confirm = false
    @State private var showRevisionEditor = false
    @State private var action = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error { ErrorBanner(message: error) }
                if let record {
                    commercialHeading(ref: "EST-\(record.id.suffix(4).uppercased())", title: record.title,
                                      status: record.status.statusLabel, date: record.createdAt)
                    Text("Line items")
                        .font(Theme.font(16, weight: .semibold))
                        .padding(.top, 8)
                    VStack(spacing: 0) {
                        ForEach(record.lines) { line in CommercialLineView(line: line) }
                        if record.lines.isEmpty { Text("No line items yet.").foregroundStyle(Theme.muted).padding(16) }
                        if !record.lines.isEmpty, let total = paperLinesTotal(record.lines) {
                            Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 15)
                            HStack {
                                Text("Total").font(Theme.font(15, weight: .semibold))
                                Spacer()
                                Text(money(total, currency: record.lines.first?.unitPrice.currency ?? "USD"))
                                    .font(Theme.monoFont(14, weight: .semibold))
                            }
                            .padding(15)
                        }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                    ForEach(record.options ?? []) { option in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(option.title).font(Theme.font(16, weight: .semibold))
                            Text(option.description).font(Theme.font(13)).foregroundStyle(Theme.muted)
                            ForEach(option.lines) { line in CommercialLineView(line: line) }
                            HStack {
                                Text("Option total").foregroundStyle(Theme.muted)
                                Spacer()
                                Text(money(option.totalAmount, currency: option.currency))
                            }
                            .font(Theme.font(14, weight: .semibold))
                            .padding(15)
                        }
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Text("Actions").font(Theme.font(16, weight: .semibold)).padding(.top, 8)
                    NavigationLink { CommercialDocumentView(path: "/v1/estimates/\(id)/document").toolbar(.visible, for: .navigationBar) } label: {
                        commercialAction("View PDF", icon: "doc.text")
                    }
                    if record.status == "sent", session.can("estimate.approve", feature: "estimates") {
                        Button("Approve estimate") { action = "Approve"; confirm = true }
                            .buttonStyle(CommercialSecondaryButtonStyle())
                            .disabled(busy)
                        Button("Decline estimate", role: .destructive) { action = "Decline"; confirm = true }
                            .buttonStyle(CommercialSecondaryButtonStyle())
                            .disabled(busy)
                    }
                    if (record.status == "sent" || record.status == "declined"),
                       session.can("estimate.create", feature: "estimates") {
                        Button { showRevisionEditor = true } label: {
                            commercialAction("Revise estimate", icon: "square.and.pencil")
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    }
                    if let revision = record.currentRevisionNumber {
                        Text("Revision \(revision)").font(Theme.monoFont(11)).foregroundStyle(Theme.muted)
                    }
                } else if error == nil { ProgressView("Loading estimate…").frame(maxWidth: .infinity) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("Estimate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if let record, record.status == "draft", session.can("estimate.send", feature: "estimates") {
                PaperActionBar(title: "Send estimate", symbol: "paperplane", busy: busy) { action = "Send"; confirm = true }
            }
        }
        .confirmationDialog("\(action) this estimate?", isPresented: $confirm, titleVisibility: .visible) {
            Button(action) { Task { await performAction() } }
        }
        .sheet(isPresented: $showRevisionEditor) {
            if let record {
                EstimateRevisionEditorView(estimate: record) { revised in
                    self.record = revised
                    error = nil
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }
    private func performAction() async {
        guard let current = record else { return }
        busy = true
        defer { busy = false }
        do {
            switch action {
            case "Send": record = try await api.sendFieldEstimate(id, expectedRevisionNumber: current.currentRevisionNumber ?? 0)
            case "Approve":
                guard let revision = current.currentRevisionNumber else { return }
                record = try await api.approveFieldEstimate(id, revisionNumber: revision)
            case "Decline":
                guard let revision = current.currentRevisionNumber else { return }
                record = try await api.declineFieldEstimate(id, revisionNumber: revision)
            default: return
            }
            error = nil
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func load() async {
        do { record = try await api.fieldEstimate(id); error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct InvoicesView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @State private var records: [InvoiceRecord] = []
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let error { ErrorBanner(message: error) }
                if loading && records.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40) }
                ForEach(paperDocumentGroups(records, status: \.status, order: ["draft", "issued", "paid", "void"]), id: \.0) { status, group in
                    PaperGroupHeader(title: status == "issued" ? "Awaiting payment" : status.statusLabel, count: group.count).padding(.top, 6)
                    ForEach(group) { record in
                        NavigationLink { InvoiceDetailView(id: record.id) } label: {
                            let total = paperLinesTotal(record.lines)
                            let due = total.map { max(0, $0 - record.amountPaid) }
                            PaperDocumentRow(reference: "INV-\(record.id.suffix(4).uppercased())", title: store.customerName(record.customerId),
                                             subtitle: record.status == "issued" ? (due.map { "\(money($0, currency: record.currency)) due" } ?? "Balance unavailable") : "Paid \(money(record.amountPaid, currency: record.currency))",
                                             status: record.status,
                                             amount: total.map { money($0, currency: record.currency) })
                        }.buttonStyle(.plain)
                    }
                }
                if !loading && records.isEmpty && error == nil {
                    PaperEmptyState(symbol: "doc.plaintext", title: "No invoices yet", message: "Invoices created from jobs appear here.")
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Invoices")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        loading = true
        defer { loading = false }
        do { records = try await api.fieldInvoices(); error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct InvoiceDetailView: View {
    let id: String
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @State private var record: InvoiceRecord?
    @State private var error: String?
    @State private var busy = false
    @State private var confirmIssue = false
    @State private var showEditDraft = false
    @State private var showCollectPayment = false
    @State private var paymentModel: InvoicePaymentCollectionModel?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error { ErrorBanner(message: error) }
                if let record {
                    commercialHeading(ref: "INV-\(record.id.suffix(4).uppercased())", title: "Invoice",
                                      status: record.status.statusLabel, date: record.issuedAt ?? record.createdAt)
                    VStack(spacing: 0) {
                        commercialDetail("Amount paid", money(record.amountPaid, currency: record.currency))
                        commercialDetail("Line revision", "\(record.linesRevision)")
                    }
                    .padding(.horizontal, 15)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    Text("Line items").font(Theme.font(16, weight: .semibold)).padding(.top, 8)
                    VStack(spacing: 0) {
                        ForEach(record.lines) { line in CommercialLineView(line: line) }
                        if record.lines.isEmpty { Text("No line items yet.").foregroundStyle(Theme.muted).padding(16) }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    if let paymentModel {
                        InvoicePaymentsSection(
                            model: paymentModel,
                            invoice: record,
                            onCollectPayment: { showCollectPayment = true },
                            onInvoiceUpdated: { self.record = $0 }
                        )
                    }
                    if record.status == "draft", session.can("invoice.edit", feature: "invoicing") {
                        Button { showEditDraft = true } label: {
                            commercialAction("Edit line items", icon: "pencil")
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Actions").font(Theme.font(16, weight: .semibold)).padding(.top, 8)
                    NavigationLink { CommercialDocumentView(path: "/v1/invoices/\(id)/document").toolbar(.visible, for: .navigationBar) } label: {
                        commercialAction("View PDF", icon: "doc.text")
                    }
                } else if error == nil { ProgressView("Loading invoice…").frame(maxWidth: .infinity) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if let paymentModel {
                InvoiceDetailFooter(
                    model: paymentModel,
                    canCollect: session.can("invoice.payment.create", feature: "payments"),
                    canIssue: session.can("invoice.issue", feature: "invoicing"),
                    busy: busy,
                    onCollect: { showCollectPayment = true },
                    onIssue: { confirmIssue = true }
                )
            } else if let record, record.status == "draft", session.can("invoice.issue", feature: "invoicing") {
                PrimaryButton(title: "Issue invoice", busy: busy) { confirmIssue = true }
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                    .background(Theme.chrome)
            }
        }
        .confirmationDialog("Issue this invoice? Its line items will become final.", isPresented: $confirmIssue, titleVisibility: .visible) {
            Button("Issue invoice") { Task { await issue() } }
        }
        .sheet(isPresented: $showEditDraft) {
            if let record {
                NavigationStack {
                    InvoiceLineEditorView(invoice: record) { updated in
                        self.record = updated
                        paymentModel?.acceptInvoiceMutationResponse(updated)
                        error = nil
                        Task { await paymentModel?.load() }
                    }
                    .environmentObject(api)
                    .environmentObject(session)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showCollectPayment) {
            if let paymentModel, let record {
                InvoicePaymentCollectionSheet(model: paymentModel, invoice: record)
                    .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .task {
            await load()
            #if DEBUG
            if PaperPreview.enabled, PaperPreview.screen == "invoice-payment" {
                showCollectPayment = paymentModel?.canRecordPayment == true
            }
            #endif
        }
        .refreshable { await load() }
    }
    private func issue() async {
        guard let current = record else { return }
        busy = true
        defer { busy = false }
        do {
            let issued = try await api.issueFieldInvoice(id, expectedLinesRevision: current.linesRevision)
            record = issued
            paymentModel?.acceptInvoiceMutationResponse(issued)
            error = nil
            await paymentModel?.load()
            if let invoice = paymentModel?.invoice { record = invoice }
        }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func load() async {
        if paymentModel == nil {
            paymentModel = InvoicePaymentCollectionModel(api: api, invoiceID: id)
        }
        guard let paymentModel else { return }
        await paymentModel.load()
        if let invoice = paymentModel.invoice {
            record = invoice
            error = nil
        } else if let loadError = paymentModel.loadError {
            error = loadError
        }
    }
}

struct CommercialLineView: View {
    let line: FieldLine
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(line.description).font(Theme.font(14, weight: .medium))
                Text("\(line.quantity) × \(money(line.unitPrice.amount, currency: line.unitPrice.currency))")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            let total = line.quantity.multipliedReportingOverflow(by: line.unitPrice.amount)
            if !total.overflow {
                Text(money(total.partialValue, currency: line.unitPrice.currency))
                    .font(Theme.font(14, weight: .semibold))
            }
        }
        .foregroundStyle(Theme.foreground)
        .padding(15)
    }
}

private func commercialHeading(ref: String, title: String, status: String, date: String?) -> some View {
    VStack(alignment: .leading, spacing: 9) {
        Text(ref).font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.muted)
        Text(title).font(Theme.font(26, weight: .semibold)).tracking(-0.39)
        HStack(spacing: 8) {
            Text(status).font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.warning)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: 8))
            if let date = JobFiltering.date(date) {
                Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
            }
        }
    }
}

private func commercialDetail(_ label: String, _ value: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
        Text(label).foregroundStyle(Theme.muted)
        Spacer(minLength: 12)
        Text(value).foregroundStyle(Theme.foreground)
    }
    .font(Theme.font(13))
    .padding(.vertical, 13)
}

private func commercialAction(_ title: String, icon: String) -> some View {
    HStack(spacing: 10) {
        Image(systemName: icon).foregroundStyle(Theme.brandText)
        Text(title).font(Theme.font(14, weight: .medium))
        Spacer()
        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
    }
    .foregroundStyle(Theme.foreground)
    .padding(15)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
}

private struct CommercialSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(14, weight: .medium))
            .foregroundStyle(Theme.foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(Theme.card.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension View {
    func commercialField() -> some View {
        font(Theme.font(14))
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 13)
            .frame(minHeight: 46)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Sum of line amounts in cents, or nil on overflow or a negative line.
func paperLinesTotal(_ lines: [FieldLine]) -> Int? {
    var total = 0
    for line in lines {
        guard line.quantity >= 0 else { return nil }
        let (amount, o1) = line.quantity.multipliedReportingOverflow(by: line.unitPrice.amount)
        let (next, o2) = total.addingReportingOverflow(amount)
        guard !o1, !o2 else { return nil }
        total = next
    }
    return total
}

/// Groups documents by status in a fixed order, unknown statuses last.
func paperDocumentGroups<T>(_ records: [T], status: KeyPath<T, String>, order: [String]) -> [(String, [T])] {
    let grouped = Dictionary(grouping: records) { $0[keyPath: status] }
    let keys = grouped.keys.sorted { (order.firstIndex(of: $0) ?? order.count, $0) < (order.firstIndex(of: $1) ?? order.count, $1) }
    return keys.map { ($0, grouped[$0] ?? []) }
}

/// Paper's document row: mono reference, title over a muted line, status chip, mono amount.
struct PaperDocumentRow: View {
    let reference: String
    let title: String
    let subtitle: String
    let status: String
    let amount: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reference).font(Theme.monoFont(11, weight: .medium)).foregroundStyle(Theme.muted)
                Text(title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                Text(subtitle).font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if let amount { Text(amount).font(Theme.monoFont(13, weight: .semibold)).foregroundStyle(Theme.foreground) }
                PaperStatusChip(status: status)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Document status as a word in a tinted chip (never colour alone).
struct PaperStatusChip: View {
    let status: String
    var body: some View {
        let (tint, ground): (Color, Color) = switch status {
        case "approved", "paid", "completed": (Theme.success, Theme.successSurface)
        case "sent", "issued", "open": (Theme.warning, Theme.warningSurface)
        case "declined", "void", "canceled": (Theme.destructive, Theme.destructiveSurface)
        default: (Theme.muted, Theme.fill)
        }
        Text(status == "issued" ? "Unpaid" : status.statusLabel)
            .font(Theme.font(11, weight: .medium)).foregroundStyle(tint)
            .padding(.horizontal, 8).frame(minHeight: 20)
            .background(ground, in: RoundedRectangle(cornerRadius: 6))
    }
}

func money(_ cents: Int, currency: String) -> String {
    (Decimal(cents) / 100).formatted(.currency(code: currency))
}

/// Paper 35: build an estimate from the price book (typed lines still allowed),
/// optionally for a job, which it is linked to after creation.
struct NewEstimateView: View {
    struct DraftLine: Identifiable {
        let id = UUID()
        var description = ""
        var quantity = 1
        var price = "0.00"
        var source: FieldEstimateLineSourceInput = .manual
        var cents: Int? { MoneyInput.cents(price) }
        var fromPriceBook: Bool { if case .priceBookSelection = source { true } else { false } }
    }
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @Environment(\.dismiss) var dismiss
    @State private var title: String
    @State private var customerID: String
    @State private var lines: [DraftLine] = []
    @State private var busy = false
    @State private var error: String?
    @State private var showPriceBook = false
    /// Set once the server created the estimate, so a retry only links it and never creates a duplicate.
    @State private var created: EstimateRecord?
    private let jobID: String?
    private let onCreated: (EstimateRecord) -> Void

    init(customerID: String = "", jobID: String? = nil, title: String = "", onCreated: @escaping (EstimateRecord) -> Void = { _ in }) {
        _customerID = State(initialValue: customerID)
        _title = State(initialValue: title)
        self.jobID = jobID
        self.onCreated = onCreated
    }

    var valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !customerID.isEmpty &&
        !lines.isEmpty && lines.allSatisfy { !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.quantity > 0 && $0.quantity <= 100_000 && $0.cents != nil }
    }
    private var total: Int? {
        var sum = 0
        for line in lines {
            guard let cents = line.cents else { return nil }
            let (amount, o1) = cents.multipliedReportingOverflow(by: line.quantity)
            let (next, o2) = sum.addingReportingOverflow(amount)
            guard !o1, !o2 else { return nil }
            sum = next
        }
        return sum
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NEW ESTIMATE\(jobID.map { " · JOB-\($0.suffix(4).uppercased())" } ?? "")")
                            .font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.muted)
                        TextField("Estimate title", text: $title, axis: .vertical)
                            .font(Theme.font(26, weight: .semibold)).tracking(-0.39)
                            .accessibilityLabel("Estimate title")
                        HStack(spacing: 6) {
                            Chip(text: "Draft", icon: "circle.dashed")
                            Menu {
                                ForEach(store.customers.filter { $0.archived != true }) { customer in
                                    Button(customer.name) { customerID = customer.id }
                                }
                            } label: {
                                Chip(text: customerID.isEmpty ? "Choose customer" : store.customerName(customerID), icon: "person",
                                     tint: customerID.isEmpty ? Theme.brandText : Theme.muted)
                                    .padding(.vertical, 10).contentShape(Rectangle())
                            }
                            .disabled(jobID != nil && !customerID.isEmpty)
                        }
                    }
                    .padding(.bottom, 14)

                    PaperGroupHeader(title: "Line items", count: lines.count)
                    VStack(spacing: 0) {
                        ForEach($lines) { $line in
                            lineRow($line)
                            Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 14)
                        }
                        if session.can("pricebook.view", feature: "price_book") {
                            Button { showPriceBook = true } label: {
                                Label("Add from price book", systemImage: "book.closed")
                                    .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.brandText)
                                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading).padding(.horizontal, 14)
                            }
                            .buttonStyle(.plain)
                        }
                        Button { lines.append(DraftLine()) } label: {
                            Label("Add a custom line", systemImage: "plus")
                                .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading).padding(.horizontal, 14)
                        }
                        .buttonStyle(.plain)
                        .disabled(lines.count >= 500)
                        if !lines.isEmpty {
                            Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 14)
                            HStack {
                                Text("Total").font(Theme.font(15, weight: .semibold))
                                Spacer()
                                Text(total.map { money($0, currency: "USD") } ?? "—").font(Theme.monoFont(14, weight: .semibold))
                            }
                            .padding(14)
                        }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                    if lines.isEmpty {
                        Text("Start with the price book so prices match what the office set.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.top, 10)
                    }
                    if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter).padding(.top, 8) }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .foregroundStyle(Theme.foreground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
            .safeAreaInset(edge: .bottom) {
                PaperActionBar(title: created != nil ? "Retry adding to job" : jobID == nil ? "Create draft" : "Create and add to job",
                               symbol: "doc.badge.plus", busy: busy,
                               disabled: !valid || !session.can("estimate.create", feature: "estimates")) { Task { await save() } }
            }
            .sheet(isPresented: $showPriceBook) {
                NavigationStack {
                    PaperPriceBookPicker(api: api, currency: "USD") { item in
                        guard lines.count < 500, item.sellPrice.currency == "USD", item.revision > 0 else { return }
                        lines.append(DraftLine(description: item.description, quantity: 1,
                                               price: String(format: "%.2f", Double(item.sellPrice.amount) / 100),
                                               source: .priceBookSelection(itemID: item.id, revision: item.revision)))
                    }
                    .navigationTitle("Price book")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showPriceBook = false } } }
                }
                .presentationDetents([.large])
            }
            .interactiveDismissDisabled(busy)
        }
    }

    @ViewBuilder private func lineRow(_ line: Binding<DraftLine>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if line.wrappedValue.fromPriceBook {
                    Text(line.wrappedValue.description).font(Theme.font(15, weight: .medium))
                } else {
                    TextField("Description", text: line.description, axis: .vertical).font(Theme.font(16))
                }
                Spacer(minLength: 8)
                if let cents = line.wrappedValue.cents {
                    Text(money(cents * line.wrappedValue.quantity, currency: "USD")).font(Theme.monoFont(13, weight: .semibold))
                }
            }
            HStack(spacing: 10) {
                Stepper(value: line.quantity, in: 1...100_000) {
                    Text("× \(line.wrappedValue.quantity)").font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.muted)
                }
                .fixedSize()
                if line.wrappedValue.fromPriceBook {
                    Text("Price book · \(money(line.wrappedValue.cents ?? 0, currency: "USD")) each")
                        .font(Theme.font(12)).foregroundStyle(Theme.muted)
                } else {
                    TextField("0.00", text: line.price).keyboardType(.decimalPad)
                        .font(Theme.monoFont(14)).multilineTextAlignment(.trailing)
                        .padding(.horizontal, 10).frame(width: 110, height: 36)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Unit price")
                }
                Spacer()
                Button(role: .destructive) { lines.removeAll { $0.id == line.wrappedValue.id } } label: {
                    Image(systemName: "trash").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).foregroundStyle(Theme.muted)
                .accessibilityLabel("Remove line")
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
    }

    private func save() async {
        guard valid else { return }
        busy = true
        defer { busy = false }
        do {
            let estimate: EstimateRecord
            if let created {
                estimate = created
            } else {
                estimate = try await api.createFieldEstimate(.init(
                    customerId: customerID,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    lines: lines.map { .init(description: $0.description.trimmingCharacters(in: .whitespacesAndNewlines), quantity: $0.quantity,
                                             unitPrice: .init(amount: $0.cents ?? 0, currency: "USD"), source: $0.source) }))
                created = estimate
                onCreated(estimate)
            }
            if let jobID {
                do { _ = try await api.linkFieldEstimate(jobID: jobID, estimateID: estimate.id) }
                catch is CancellationError { return }
                catch {
                    self.error = "The estimate was saved but could not be added to the job. \(error.localizedDescription)"
                    return
                }
                onCreated(estimate)
            }
            dismiss()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}
