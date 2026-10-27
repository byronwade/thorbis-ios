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
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "doc.text").foregroundStyle(Theme.brand).frame(width: 22)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.title).font(Theme.font(14, weight: .medium))
                            Text(store.customerName(record.customerId)).font(Theme.font(12)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 8)
                        Text(record.status.statusLabel).font(Theme.font(11, weight: .medium)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 7)
                }.listRowBackground(Theme.card).listRowSeparator(.hidden)
            }
            if !loading && records.isEmpty && error == nil { ContentUnavailableView("No estimates", systemImage: "doc.text") }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
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
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
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
                PrimaryButton(title: "Send estimate", busy: busy) { action = "Send"; confirm = true }
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                    .background(Theme.chrome)
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
        List {
            if let error { ErrorBanner(message: error) }
            if loading { ProgressView("Loading invoices…") }
            ForEach(records) { record in
                NavigationLink { InvoiceDetailView(id: record.id) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "doc.plaintext").foregroundStyle(Theme.brand).frame(width: 22)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("INV-\(record.id.suffix(4).uppercased()) · \(store.customerName(record.customerId))")
                                .font(Theme.font(14, weight: .medium))
                            Text("Paid \(money(record.amountPaid, currency: record.currency))")
                                .font(Theme.font(12)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 8)
                        Text(record.status.statusLabel).font(Theme.font(11, weight: .medium)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 7)
                }.listRowBackground(Theme.card).listRowSeparator(.hidden)
            }
            if !loading && records.isEmpty && error == nil { ContentUnavailableView("No invoices", systemImage: "doc.plaintext") }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
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
        Image(systemName: icon).foregroundStyle(Theme.brand)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NEW ESTIMATE")
                            .font(Theme.monoFont(12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                        Text("New estimate")
                            .font(Theme.font(26, weight: .semibold))
                            .tracking(-0.39)
                        Text("Draft")
                            .font(Theme.font(12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.bottom, 8)
                    Text("Details").font(Theme.font(16, weight: .semibold))
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Title").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                        TextField("Describe this estimate", text: $title)
                            .commercialField()
                        Text("Customer").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                        Picker("Customer", selection: $customerID) {
                            Text("Choose a customer").tag("")
                            ForEach(store.customers.filter { $0.archived != true }) { Text($0.name).tag($0.id) }
                        }
                        .tint(Theme.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 13).frame(minHeight: 46)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(15)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    HStack {
                        Text("Line items").font(Theme.font(16, weight: .semibold))
                        Spacer()
                        Text("\(lines.count)").font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 6)
                    ForEach($lines) { $line in
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Description", text: $line.description, axis: .vertical)
                                .lineLimit(1...4)
                                .commercialField()
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Quantity").font(Theme.font(12)).foregroundStyle(Theme.muted)
                                    TextField("Quantity", value: $line.quantity, format: .number)
                                        .keyboardType(.numberPad)
                                        .commercialField()
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Unit price (USD)").font(Theme.font(12)).foregroundStyle(Theme.muted)
                                    TextField("0.00", text: $line.price)
                                        .keyboardType(.decimalPad)
                                        .commercialField()
                                }
                            }
                            if let cents = line.cents {
                                Text("Unit price · \(money(cents, currency: "USD"))")
                                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
                            }
                            if lines.count > 1 {
                                Button("Remove line", role: .destructive) { lines.removeAll { $0.id == line.id } }
                                    .font(Theme.font(13, weight: .medium))
                            }
                        }
                        .padding(15)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if lines.count < 500 {
                        Button { lines.append(DraftLine()) } label: { commercialAction("Add line", icon: "plus") }
                            .buttonStyle(.plain)
                    }
                    if let error { ErrorBanner(message: error) }
                    if busy { ProgressView().frame(maxWidth: .infinity) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
            .background(Theme.background)
            .foregroundStyle(Theme.foreground)
            .navigationTitle("New estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() }.disabled(busy) }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Create draft", busy: busy) { Task { await save() } }
                    .disabled(!valid || !session.can("estimate.create", feature: "estimates"))
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                    .background(Theme.chrome)
            }
        }
    }
    private func save() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await api.createFieldEstimate(.init(customerId: customerID, title: title.trimmingCharacters(in: .whitespacesAndNewlines), lines: lines.map { .init(description: $0.description.trimmingCharacters(in: .whitespacesAndNewlines), quantity: $0.quantity, unitPrice: .init(amount: $0.cents ?? 0, currency: "USD"), source: .manual) }))
            dismiss()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}
