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
                if loading && records.isEmpty { SkeletonRows(count: 6, leading: false) }
                if !records.isEmpty { summaryLine(estimates: records) }
                ForEach(paperDocumentGroups(visible, status: \.status, order: ["draft", "sent", "approved", "declined"]), id: \.0) { status, group in
                    PaperGroupHeader(title: status.statusLabel, count: group.count).padding(.top, 6)
                    ForEach(group) { record in
                        NavigationLink { EstimateDetailView(id: record.id) } label: {
                            PaperDocumentRow(reference: "EST-\(record.id.suffix(4).uppercased())", title: record.title,
                                             subtitle: store.customerName(record.customerId), status: record.status,
                                             amount: paperLinesTotal(record.lines).map { money($0, currency: record.lines.first?.unitPrice.currency ?? "USD") },
                                             showsStatus: false)
                        }.buttonStyle(RowPressStyle())
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
    /// The job it was opened from; in-person approval stores the signature with that job.
    var jobID: String? = nil
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var store: Store
    @State private var record: EstimateRecord?
    @State private var error: String?
    @State private var busy = false
    @State private var confirm = false
    @State private var showRevisionEditor = false
    @State private var action = ""
    @State private var showToCustomer = false
    @State private var memberPricing: MemberPricing?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error { ErrorBanner(message: error) }
                if let record {
                    commercialHeading(ref: "EST-\(record.id.suffix(4).uppercased())", context: store.customerName(record.customerId), title: record.title,
                                      status: record.status, date: record.createdAt)
                    Text("Line items")
                        .font(Theme.font(17, weight: .medium))
                        .padding(.top, 8)
                    VStack(spacing: 0) {
                        ForEach(record.lines) { line in CommercialLineView(line: line) }
                        if record.lines.isEmpty { Text("No line items yet.").foregroundStyle(Theme.muted).padding(16) }
                        if !record.lines.isEmpty, let total = paperLinesTotal(record.lines) {
                            Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 15)
                            HStack {
                                Text("Total").font(Theme.font(15, weight: .medium))
                                Spacer()
                                Text(money(total, currency: record.lines.first?.unitPrice.currency ?? "USD"))
                                    .font(Theme.monoFont(14, weight: .medium))
                            }
                            .padding(15)
                            if let memberPricing, memberPricing.isMember, memberPricing.discountPercent > 0 {
                                let memberTotal = record.lines.reduce(0) { $0 + $1.quantity * memberPricing.memberPrice($1.unitPrice.amount) }
                                HStack {
                                    Label("Member price · \(memberPricing.discountPercent)% off", systemImage: "star")
                                        .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.brandText)
                                    Spacer()
                                    Text(money(memberTotal, currency: record.lines.first?.unitPrice.currency ?? "USD"))
                                        .font(Theme.monoFont(14, weight: .medium)).foregroundStyle(Theme.brandText)
                                }
                                .padding(.horizontal, 15).padding(.bottom, 15)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
                    ForEach(record.options ?? []) { option in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(option.title).font(Theme.font(17, weight: .medium))
                            Text(option.description).font(Theme.font(13)).foregroundStyle(Theme.muted)
                            ForEach(option.lines) { line in CommercialLineView(line: line) }
                            HStack {
                                Text("Option total").foregroundStyle(Theme.muted)
                                Spacer()
                                Text(money(option.totalAmount, currency: option.currency))
                            }
                            .font(Theme.font(14, weight: .medium))
                            .padding(15)
                        }
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    }
                    Text("Actions").font(Theme.font(17, weight: .medium)).padding(.top, 8)
                    NavigationLink { CommercialDocumentView(path: "/v1/estimates/\(id)/document").toolbar(.visible, for: .navigationBar) } label: {
                        commercialAction("View PDF", icon: "doc.text")
                    }
                    if let signature = record.approvalSignature { SignatureBadge(label: "Approved by", signature: signature) }
                    if record.status == "sent", session.can("estimate.approve", feature: "estimates") {
                        Button(jobID != nil && (record.options ?? []).isEmpty ? "Approve without a signature" : "Approve estimate") { action = "Approve"; confirm = true }
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
                } else if error == nil { SkeletonRows(count: 5, leading: false, inset: 0) }
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
            } else if let record, record.status == "sent", session.can("estimate.approve", feature: "estimates"),
                      (jobID != nil && (record.options ?? []).isEmpty) || session.can("estimate.send", feature: "estimates") {
                // On site, the next step is the customer's yes: hand them the options to choose and sign.
                // Options (and estimates without a job) are signed through an issued link, which needs estimate.send.
                PaperActionBar(title: "Show to customer", symbol: "person.crop.rectangle", busy: busy) { showToCustomer = true }
            }
        }
        .confirmationDialog("\(action) this estimate?", isPresented: $confirm, titleVisibility: .visible) {
            Button(action, role: action == "Decline" ? .destructive : nil) { Task { await performAction() } }
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
        .fullScreenCover(isPresented: $showToCustomer) {
            if let record {
                CustomerModeContainer(onUnlocked: {
                    showToCustomer = false
                    Task { await load() }
                }) { handBack in
                    CustomerEstimatePresentation(estimate: record, jobID: jobID, customerName: store.customerName(record.customerId),
                                                 onApproved: { if let updated = $0 { self.record = updated } }, onDone: handBack)
                }
                .environmentObject(api)
            }
        }
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
        do {
            record = try await api.fieldEstimate(id)
            error = nil
            if let customer = record?.customerId { memberPricing = try? await api.memberPricing(customer) }
        }
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
                if loading && records.isEmpty { SkeletonRows(count: 6, leading: false) }
                if !records.isEmpty { summaryLine(invoices: records) }
                ForEach(paperDocumentGroups(records, status: \.status, order: ["draft", "issued", "paid", "void"]), id: \.0) { status, group in
                    PaperGroupHeader(title: status == "issued" ? "Awaiting payment" : status.statusLabel, count: group.count).padding(.top, 6)
                    ForEach(group) { record in
                        NavigationLink { InvoiceDetailView(id: record.id) } label: {
                            let total = paperLinesTotal(record.lines)
                            let due = total.map { max(0, $0 - record.amountPaid) }
                            PaperDocumentRow(reference: "INV-\(record.id.suffix(4).uppercased())", title: store.customerName(record.customerId),
                                             subtitle: record.status == "issued" ? (due.map { "\(money($0, currency: record.currency)) due" } ?? "Balance unavailable") : "Paid \(money(record.amountPaid, currency: record.currency))",
                                             status: record.status,
                                             amount: total.map { money($0, currency: record.currency) },
                                             showsStatus: false)
                        }.buttonStyle(RowPressStyle())
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
    @EnvironmentObject var store: Store
    @State private var record: InvoiceRecord?
    @State private var error: String?
    @State private var busy = false
    @State private var confirmIssue = false
    @State private var showEditDraft = false
    @State private var showCollectPayment = false
    @State private var paymentModel: InvoicePaymentCollectionModel?
    @State private var showSignature = false
    @State private var showToCustomer = false
    /// Set when the customer pressed Pay and the technician unlocked: collect once customer mode closes.
    @State private var collectAfterCustomer = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error { ErrorBanner(message: error) }
                if let record {
                    // Who it's for and what's owed come first; the line revision is bookkeeping, not for people.
                    commercialHeading(ref: "INV-\(record.id.suffix(4).uppercased())", title: store.customerName(record.customerId),
                                      status: record.status, date: record.issuedAt ?? record.createdAt)
                    let total = record.lines.reduce(0) { $0 + $1.quantity * $1.unitPrice.amount }
                    VStack(spacing: 0) {
                        commercialDetail("Total", money(total, currency: record.currency))
                        if record.amountPaid > 0 { commercialDetail("Paid", money(record.amountPaid, currency: record.currency)) }
                        commercialDetail("Balance due", money(max(total - record.amountPaid, 0), currency: record.currency))
                    }
                    .padding(.horizontal, 15)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    if let signed = record.customerAuthorization, signed.linesRevision == record.linesRevision {
                        SignatureBadge(label: "Authorized by", signature: signed)
                    } else if record.jobId != nil, record.status != "void", session.can("invoice.edit", feature: "invoicing") {
                        Button { showSignature = true } label: { commercialAction("Get customer signature", icon: "signature") }
                            .buttonStyle(.plain)
                    }
                    Text("Line items").font(Theme.font(17, weight: .medium)).padding(.top, 8)
                    VStack(spacing: 0) {
                        ForEach(record.lines) { line in CommercialLineView(line: line) }
                        if record.lines.isEmpty { Text("No line items yet.").foregroundStyle(Theme.muted).padding(16) }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
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
                    Text("Actions").font(Theme.font(17, weight: .medium)).padding(.top, 8)
                    if record.status != "draft", record.status != "void" {
                        Button { showToCustomer = true } label: { commercialAction("Show to customer", icon: "person.crop.rectangle") }
                            .buttonStyle(.plain)
                    }
                    NavigationLink { CommercialDocumentView(path: "/v1/invoices/\(id)/document").toolbar(.visible, for: .navigationBar) } label: {
                        commercialAction("View PDF", icon: "doc.text")
                    }
                } else if error == nil { SkeletonRows(count: 5, leading: false, inset: 0) }
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
        .sheet(isPresented: $showSignature) {
            if let record, let jobID = record.jobId {
                let total = record.lines.reduce(0) { $0 + $1.quantity * $1.unitPrice.amount }
                SignatureCaptureSheet(title: "Sign for \(money(total, currency: record.currency))",
                                      summary: "By signing, \(store.customerName(record.customerId)) authorizes the work and charges on this invoice.",
                                      jobID: jobID, suggestedName: store.customerName(record.customerId)) { signature in
                    do {
                        self.record = try await api.authorizeFieldInvoice(id, expectedLinesRevision: record.linesRevision, signature: signature)
                        return nil
                    } catch { return error.localizedDescription }
                }
            }
        }
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
        .fullScreenCover(isPresented: $showToCustomer, onDismiss: {
            if collectAfterCustomer { collectAfterCustomer = false; showCollectPayment = true }
        }) {
            if let record {
                CustomerModeContainer(onUnlocked: { showToCustomer = false }) { handBack in
                    CustomerInvoicePresentation(
                        invoice: record, customerName: store.customerName(record.customerId),
                        canSign: session.can("invoice.edit", feature: "invoicing"),
                        onPay: paymentModel?.canRecordPayment == true && session.can("invoice.payment.create", feature: "payments") ? {
                            // Taking payment is a staff screen, so the technician unlocks first.
                            Task {
                                if await StaffUnlock.unlock(reason: "Unlock to take payment") {
                                    collectAfterCustomer = true
                                    showToCustomer = false
                                }
                            }
                        } : nil,
                        onSigned: { updated in
                            self.record = updated
                            paymentModel?.acceptInvoiceMutationResponse(updated)
                        },
                        onDone: handBack)
                }
                .environmentObject(api)
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
                    .font(Theme.font(14, weight: .medium))
            }
        }
        .foregroundStyle(Theme.foreground)
        .padding(15)
    }
}

/// Same header shape as job and customer pages: eyebrow, 24/500 title, then the status as the
/// shared dot-and-word chip (approved isn't amber, draft isn't amber) and the date.
private func commercialHeading(ref: String, context: String? = nil, title: String, status: String, date: String?) -> some View {
    VStack(alignment: .leading, spacing: 9) {
        PaperEyebrow(reference: ref, text: context)
        Text(title).font(Theme.font(24, weight: .medium)).tracking(-0.36)
        HStack(spacing: 8) {
            PaperStatusChip(status: status)
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
        Text(title).font(Theme.font(15, weight: .medium))
        Spacer()
        Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
    }
    .foregroundStyle(Theme.foreground)
    .padding(15)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
}

private struct CommercialSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(14, weight: .medium))
            .foregroundStyle(Theme.foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(Theme.card.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

private extension View {
    func commercialField() -> some View {
        font(Theme.font(14))
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 13)
            .frame(minHeight: 46)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
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

/// Paper's document row, shaped like job and customer rows: the title over one muted line
/// ("customer · EST-1A2B", reference in mono), the amount on the right. Lists grouped by
/// status pass `showsStatus: false`, since the group header already says it.
struct PaperDocumentRow: View {
    let reference: String
    let title: String
    let subtitle: String
    let status: String
    let amount: String?
    var showsStatus = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                HStack(spacing: 6) {
                    Text(subtitle).font(Theme.font(13)).lineLimit(1)
                    Text("·").font(Theme.font(13))
                    Text(reference).font(Theme.monoFont(12, weight: .medium)).fixedSize()
                }
                .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if let amount { Text(amount).font(Theme.monoFont(13, weight: .medium)).foregroundStyle(Theme.foreground) }
                if showsStatus { PaperStatusChip(status: status) }
            }
        }
        .frame(minHeight: 56)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Document status as a word in a tinted chip (never colour alone).
struct PaperStatusChip: View {
    let status: String
    var body: some View {
        let tint: Color = switch status {
        case "approved", "paid", "completed": Theme.success
        case "sent", "issued", "open": Theme.warning
        case "declined", "void", "canceled": Theme.destructive
        default: Theme.muted
        }
        // MA-10: the word on the neutral well; the hue is a dot beside it, never the word itself.
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(status == "issued" ? "Unpaid" : status.statusLabel)
        }
            .font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.foreground)
            .padding(.horizontal, 10).frame(minHeight: Theme.chipHeight)
            .background(Theme.fill, in: Capsule())
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
                        PaperEyebrow(reference: jobID.map { "JOB-\($0.suffix(4).uppercased())" }, text: "New estimate")
                        TextField("Estimate title", text: $title, axis: .vertical)
                            .font(Theme.font(24, weight: .medium)).tracking(-0.36)
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
                                Text("Total").font(Theme.font(15, weight: .medium))
                                Spacer()
                                Text(total.map { money($0, currency: "USD") } ?? "—").font(Theme.monoFont(14, weight: .medium))
                            }
                            .padding(14)
                        }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
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
                    PaperPriceBookPicker(api: api, currency: "USD", customerID: customerID.isEmpty ? nil : customerID) { item in
                        guard lines.count < 500, item.sellPrice.currency == "USD", item.revision > 0 else { return }
                        lines.append(DraftLine(description: item.description, quantity: 1,
                                               price: String(format: "%.2f", Double(item.sellPrice.amount) / 100),
                                               source: .priceBookSelection(itemID: item.id, revision: item.revision)))
                    }
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
                    Text(money(cents * line.wrappedValue.quantity, currency: "USD")).font(Theme.monoFont(13, weight: .medium))
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
                        .font(Theme.monoFont(16)).multilineTextAlignment(.trailing)
                        .padding(.horizontal, 10).frame(width: 110, height: 44)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
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

/// The one line an office reads first on a document list: what's outstanding and how much.
@ViewBuilder func summaryLine(estimates: [EstimateRecord]) -> some View {
    let waiting = estimates.filter { $0.status == "sent" }
    let total = waiting.compactMap { paperLinesTotal($0.lines) }.reduce(0, +)
    Text(waiting.isEmpty ? "Nothing waiting on customers" : "\(waiting.count) waiting on customers · \(money(total, currency: "USD"))")
        .font(Theme.font(15)).foregroundStyle(Theme.muted)
        .padding(.bottom, 6)
}

@ViewBuilder func summaryLine(invoices: [InvoiceRecord]) -> some View {
    let unpaid = invoices.filter { $0.status == "issued" }
    let owed = unpaid.compactMap { invoice in paperLinesTotal(invoice.lines).map { max(0, $0 - invoice.amountPaid) } }.reduce(0, +)
    Text(unpaid.isEmpty ? "Everything is paid" : "\(money(owed, currency: "USD")) owed · \(unpaid.count) unpaid")
        .font(Theme.font(15)).foregroundStyle(Theme.muted)
        .padding(.bottom, 6)
}
