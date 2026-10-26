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
    var body: some View {
        List {
            if let error { ErrorBanner(message: error) }
            if loading { ProgressView("Loading estimates…") }
            ForEach(records.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { record in
                NavigationLink { EstimateDetailView(id: record.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record.title).font(.headline)
                        Text(store.customerName(record.customerId)).foregroundStyle(.secondary)
                        Text(record.status.statusLabel).font(.caption)
                    }
                }
            }
            if !loading && records.isEmpty && error == nil { ContentUnavailableView("No estimates", systemImage: "doc.text") }
        }
        .navigationTitle("Estimates")
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
    @State private var action = ""
    var body: some View {
        List {
            if let error { ErrorBanner(message: error) }
            if let record {
                Section("Estimate") {
                    LabeledContent("Status", value: record.status.statusLabel)
                    if let revision = record.currentRevisionNumber { LabeledContent("Revision", value: "\(revision)") }
                }
                Section("Line items") { ForEach(record.lines) { CommercialLineView(line: $0) } }
                ForEach(record.options ?? []) { option in
                    Section(option.title) {
                        Text(option.description)
                        ForEach(option.lines) { CommercialLineView(line: $0) }
                        LabeledContent("Option total", value: money(option.totalAmount, currency: option.currency))
                    }
                }
                Section("Actions") {
                    NavigationLink("View PDF") { CommercialDocumentView(path: "/v1/estimates/\(id)/document") }
                    if record.status == "draft", session.can("estimate.send", feature: "estimates") {
                        Button("Send estimate") { action = "Send"; confirm = true }.disabled(busy)
                    }
                    if record.status == "sent", session.can("estimate.approve", feature: "estimates") {
                        Button("Approve estimate") { action = "Approve"; confirm = true }.disabled(busy)
                        Button("Decline estimate", role: .destructive) { action = "Decline"; confirm = true }.disabled(busy)
                    }
                    if busy { ProgressView() }
                }
                Section("Record") { Text(record.id).font(.caption.monospaced()).textSelection(.enabled) }
            } else if error == nil { ProgressView() }
        }
        .navigationTitle(record?.title ?? "Estimate")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("\(action) this estimate?", isPresented: $confirm, titleVisibility: .visible) {
            Button(action) { Task { await performAction() } }
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
        List {
            if let error { ErrorBanner(message: error) }
            if loading { ProgressView("Loading invoices…") }
            ForEach(records) { record in
                NavigationLink { InvoiceDetailView(id: record.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.customerName(record.customerId)).font(.headline)
                        Text("Invoice \(record.id.suffix(6).uppercased()) · \(record.status.statusLabel)").font(.subheadline)
                        Text("Paid: \(money(record.amountPaid, currency: record.currency))").foregroundStyle(.secondary)
                    }
                }
            }
            if !loading && records.isEmpty && error == nil { ContentUnavailableView("No invoices", systemImage: "doc.plaintext") }
        }
        .navigationTitle("Invoices")
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
    var body: some View {
        List {
            if let error { ErrorBanner(message: error) }
            if let record {
                Section("Invoice") {
                    LabeledContent("Status", value: record.status.statusLabel)
                    LabeledContent("Amount paid", value: money(record.amountPaid, currency: record.currency))
                    LabeledContent("Line revision", value: "\(record.linesRevision)")
                }
                Section("Line items") { ForEach(record.lines) { CommercialLineView(line: $0) } }
                Section("Actions") {
                    NavigationLink("View PDF") { CommercialDocumentView(path: "/v1/invoices/\(id)/document") }
                    if record.status == "draft", session.can("invoice.issue", feature: "invoicing") {
                        Button("Issue invoice") { confirmIssue = true }.disabled(busy)
                    }
                    if busy { ProgressView() }
                }
                Section("Record") { Text(record.id).font(.caption.monospaced()).textSelection(.enabled) }
            } else if error == nil { ProgressView() }
        }
        .navigationTitle("Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Issue this invoice? Its line items will become final.", isPresented: $confirmIssue, titleVisibility: .visible) {
            Button("Issue invoice") { Task { await issue() } }
        }
        .task { await load() }
        .refreshable { await load() }
    }
    private func issue() async {
        guard let current = record else { return }
        busy = true
        defer { busy = false }
        do { record = try await api.issueFieldInvoice(id, expectedLinesRevision: current.linesRevision); error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func load() async {
        do { record = try await api.fieldInvoice(id); error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct CommercialLineView: View {
    let line: FieldLine
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(line.description)
            Text("\(line.quantity) × \(money(line.unitPrice.amount, currency: line.unitPrice.currency))").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

func money(_ cents: Int, currency: String) -> String {
    (Decimal(cents) / 100).formatted(.currency(code: currency))
}

struct NewEstimateView: View {
    struct DraftLine: Identifiable {
        let id = UUID()
        var description = ""
        var quantity = 1
        var price = "0.00"
        var cents: Int? { MoneyInput.cents(price) }
    }
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var customerID = ""
    @State private var lines = [DraftLine()]
    @State private var busy = false
    @State private var error: String?
    var valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !customerID.isEmpty &&
        !lines.isEmpty && lines.allSatisfy { !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.quantity > 0 && $0.quantity <= 100_000 && $0.cents != nil }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Estimate") {
                    TextField("Title", text: $title)
                    Picker("Customer", selection: $customerID) {
                        Text("Choose a customer").tag("")
                        ForEach(store.customers.filter { $0.archived != true }) { Text($0.name).tag($0.id) }
                    }
                }
                ForEach($lines) { $line in
                    Section("Line item") {
                        TextField("Description", text: $line.description, axis: .vertical)
                        TextField("Quantity", value: $line.quantity, format: .number).keyboardType(.numberPad)
                        TextField("Unit price (USD)", text: $line.price).keyboardType(.decimalPad)
                        if let cents = line.cents { Text(money(cents, currency: "USD")).foregroundStyle(.secondary) }
                        if lines.count > 1 { Button("Remove line", role: .destructive) { lines.removeAll { $0.id == line.id } } }
                    }
                }
                if lines.count < 500 { Button("Add line", systemImage: "plus") { lines.append(DraftLine()) } }
                if let error { Text(error).foregroundStyle(Theme.destructive) }
                Button("Create draft") { Task { await save() } }.disabled(busy || !valid || !session.can("estimate.create", feature: "estimates"))
                if busy { ProgressView() }
            }
            .navigationTitle("New estimate")
            .toolbar { Button("Cancel") { dismiss() }.disabled(busy) }
        }
    }
    private func save() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await api.createFieldEstimate(.init(customerId: customerID, title: title.trimmingCharacters(in: .whitespacesAndNewlines), lines: lines.map { .init(description: $0.description.trimmingCharacters(in: .whitespacesAndNewlines), quantity: $0.quantity, unitPrice: .init(amount: $0.cents ?? 0, currency: "USD")) }))
            dismiss()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}
