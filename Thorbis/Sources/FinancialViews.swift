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
    /// Title, customer or reference, so "EST-4F2A" or a customer's name finds it too.
    private var visible: [EstimateRecord] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return records }
        return records.filter { record in
            [record.title, store.customerName(record.customerId), "EST-\(record.id.suffix(4).uppercased())"]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let error { ErrorBanner(message: error) { await load() } }
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
                if !records.isEmpty && visible.isEmpty {
                    PaperEmptyState.search(search.trimmingCharacters(in: .whitespaces))
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
        .searchable(text: $search, prompt: "Title, customer or EST number")
        .task { await load() }
        .refreshable { await load() }
        .toolbar {
            // Neutral like the back button beside it; blue stays for links and selection.
            if session.can("estimate.create", feature: "estimates") { Button("New estimate", systemImage: "plus") { showCreate = true }.tint(Theme.foreground) }
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
    /// Opened from the job's next step: hand it to the customer as soon as it loads (TF-05), and
    /// go back to the job once they approve, where the invoice is the next step (TF-06).
    var presentsOnOpen = false
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var autoPresented = false
    @State private var record: EstimateRecord?
    @State private var error: String?
    @State private var busy = false
    @State private var confirm = false
    @State private var succeeded = 0
    @State private var showRevisionEditor = false
    @State private var action = ""
    @State private var showToCustomer = false
    @State private var memberPricing: MemberPricing?
    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error { ErrorBanner(message: error, retry: record == nil ? { await load() } : nil) }
                if let record {
                    commercialHeading(ref: "EST-\(record.id.suffix(4).uppercased())", context: store.customerName(record.customerId), title: record.title,
                                      status: record.status, date: record.createdAt)
                    // MF-04: an estimate leads with its total.
                    if let total = paperLinesTotal(record.lines), !record.lines.isEmpty {
                        MoneyFigure(label: "Total", cents: total, currency: record.lines.first?.unitPrice.currency ?? "USD")
                    }
                    PaperGroupHeader(title: "Line items", count: record.lines.count).padding(.top, 4)
                    VStack(spacing: 0) {
                        ForEach(record.lines) { line in CommercialLineView(line: line, divider: line.id != record.lines.first?.id) }
                        if record.lines.isEmpty { Text("No line items yet.").foregroundStyle(Theme.muted).padding(16) }
                        if !record.lines.isEmpty, let total = paperLinesTotal(record.lines) {
                            Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 15)
                            HStack {
                                Text("Total").font(Theme.font(15, weight: .medium))
                                Spacer()
                                Text(money(total, currency: record.lines.first?.unitPrice.currency ?? "USD"))
                                    .moneyStyle(.total)
                            }
                            .padding(15)
                            if let memberPricing, memberPricing.isMember, memberPricing.discountPercent > 0 {
                                let memberTotal = record.lines.reduce(0) { $0 + $1.quantity * memberPricing.memberPrice($1.unitPrice.amount) }
                                HStack {
                                    Label("Member price · \(memberPricing.discountPercent)% off", systemImage: "star")
                                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.brandText)
                                    Spacer()
                                    // MF-05: money stays ink; only the label carries the member mark.
                                    Text(money(memberTotal, currency: record.lines.first?.unitPrice.currency ?? "USD"))
                                        .moneyStyle(.total).foregroundStyle(Theme.foreground)
                                }
                                .padding(.horizontal, 15).padding(.bottom, 15)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border))
                    ForEach(record.options ?? []) { option in
                        VStack(alignment: .leading, spacing: 0) {
                            // The title and note sit inside the card's 15pt inset, like the lines under them.
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.title).font(Theme.font(17, weight: .medium))
                                if !option.description.isEmpty {
                                    Text(option.description).font(Theme.font(13)).foregroundStyle(Theme.muted)
                                }
                            }
                            .padding([.horizontal, .top], 15).padding(.bottom, 5)
                            ForEach(option.lines) { line in CommercialLineView(line: line, divider: line.id != option.lines.first?.id) }
                            HStack {
                                Text("Option total").font(Theme.font(15, weight: .medium))
                                Spacer()
                                Text(money(option.totalAmount, currency: option.currency)).moneyStyle(.total)
                            }
                            .padding(15)
                        }
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border))
                    }
                    PaperGroupHeader(title: "Actions").padding(.top, 4)
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
                        Text("Revision \(revision)").font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                    }
                } else if error == nil { SkeletonRows(count: 5, leading: false, inset: 0) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
    }

    var body: some View {
        scrollContent
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("Estimate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { estimateBar }
        .sensoryFeedback(.success, trigger: succeeded)
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
        .task { await loadAndMaybePresent() }
        .refreshable { await load() }
        .fullScreenCover(isPresented: $showToCustomer) {
            if let record { customerMode(record) }
        }
    }

    private func customerMode(_ record: EstimateRecord) -> some View {
        CustomerModeContainer(onUnlocked: { customerModeClosed() }) { handBack in
            CustomerEstimatePresentation(estimate: record, jobID: jobID, customerName: store.customerName(record.customerId),
                                         onApproved: { if let updated = $0 { self.record = updated } }, onDone: handBack)
        }
        .environmentObject(api)
    }

    private func customerModeClosed() {
        showToCustomer = false
        Task {
            await load()
            // TF-06: approved from the job's next step, the job (and its invoice step) comes back.
            if presentsOnOpen, record?.status == "approved" { dismiss() }
        }
    }
    @ViewBuilder private var estimateBar: some View {
        if let record, record.status == "draft", jobID != nil, TechJobFlow.canShow(record, can: estimateAbilities) {
            // TF-05: on site, showing is sending. The draft is issued as it's handed over, no second step.
            PaperActionBar(title: "Show to customer", symbol: "person.crop.rectangle", busy: busy) { Task { await handToCustomer() } }
        } else if let record, record.status == "draft", session.can("estimate.send", feature: "estimates") {
            PaperActionBar(title: "Send estimate", symbol: "paperplane", busy: busy) { action = "Send"; confirm = true }
        } else if let record, record.status == "sent", canShowSent(record) {
            // On site, the next step is the customer's yes: hand them the options to choose and sign.
            // Options (and estimates without a job) are signed through an issued link, which needs estimate.send.
            PaperActionBar(title: "Show to customer", symbol: "person.crop.rectangle", busy: busy) { showToCustomer = true }
        }
    }

    private func canShowSent(_ record: EstimateRecord) -> Bool {
        guard session.can("estimate.approve", feature: "estimates") else { return false }
        let singleScopeOnJob = jobID != nil && (record.options ?? []).isEmpty
        return singleScopeOnJob || session.can("estimate.send", feature: "estimates")
    }

    private func loadAndMaybePresent() async {
        await load()
        guard presentsOnOpen, !autoPresented, let record, TechJobFlow.canShow(record, can: estimateAbilities) else { return }
        autoPresented = true
        await handToCustomer()
    }

    private var estimateAbilities: TechJobAbilities {
        TechJobAbilities(sendEstimate: session.can("estimate.send", feature: "estimates"),
                         approveEstimate: session.can("estimate.approve", feature: "estimates"))
    }

    /// Issues a draft (the revision the customer signs is frozen first), then opens customer mode.
    private func handToCustomer() async {
        guard let current = record else { return }
        if current.status == "draft" {
            busy = true
            defer { busy = false }
            do { record = try await api.sendFieldEstimate(id, expectedRevisionNumber: current.currentRevisionNumber ?? 0) }
            catch is CancellationError { return } catch { self.error = error.localizedDescription; return }
        }
        showToCustomer = true
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
            if action != "Decline" { succeeded += 1 }
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
    @State private var search = ""
    /// Customer or reference, the two things a tech has in hand when a customer calls about a bill.
    private var visible: [InvoiceRecord] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return records }
        return records.filter { record in
            [store.customerName(record.customerId), "INV-\(record.id.suffix(4).uppercased())"]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let error { ErrorBanner(message: error) { await load() } }
                if loading && records.isEmpty { SkeletonRows(count: 6, leading: false) }
                if !records.isEmpty { summaryLine(invoices: records) }
                ForEach(paperDocumentGroups(visible, status: \.status, order: ["draft", "issued", "paid", "void"]), id: \.0) { status, group in
                    PaperGroupHeader(title: status == "issued" ? "Awaiting payment" : status.statusLabel, count: group.count).padding(.top, 6)
                    ForEach(group) { record in
                        NavigationLink { InvoiceDetailView(id: record.id) } label: {
                            let total = paperLinesTotal(record.lines)
                            let due = total.map { max(0, $0 - record.amountPaid) }
                            PaperDocumentRow(reference: "INV-\(record.id.suffix(4).uppercased())", title: store.customerName(record.customerId),
                                             subtitle: record.status == "issued" ? (record.amountPaid > 0 ? "Balance due · part paid" : "Balance due") : record.status == "paid" ? "Paid" : record.status.statusLabel,
                                             status: record.status,
                                             // MF-04: an unpaid invoice's row shows what's owed now.
                                             amount: (record.status == "issued" ? due : total).map { money($0, currency: record.currency) },
                                             showsStatus: false)
                        }.buttonStyle(RowPressStyle())
                    }
                }
                if !records.isEmpty && visible.isEmpty {
                    PaperEmptyState.search(search.trimmingCharacters(in: .whitespaces))
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
        .searchable(text: $search, prompt: "Customer or INV number")
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
    /// Opened from the job's next step: once it's paid, go back to the job for wrap up (TF-09).
    var returnsWhenPaid = false
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var store: Store
    @EnvironmentObject private var outbox: FieldOutbox
    @Environment(\.dismiss) private var dismiss
    @State private var record: InvoiceRecord?
    @State private var error: String?
    @State private var busy = false
    @State private var confirmIssue = false
    @State private var issued = 0
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
                if let error { ErrorBanner(message: error, retry: record == nil ? { await load() } : nil) }
                if let record {
                    // Who it's for and what's owed come first; the line revision is bookkeeping, not for people.
                    commercialHeading(ref: "INV-\(record.id.suffix(4).uppercased())", title: store.customerName(record.customerId),
                                      status: record.status, date: record.issuedAt ?? record.createdAt)
                    let total = record.lines.reduce(0) { $0 + $1.quantity * $1.unitPrice.amount }
                    let due = max(total - record.amountPaid, 0)
                    // MF-04: what's owed now is the largest thing on the invoice; Total and Paid sit under it.
                    MoneyFigure(label: record.status == "draft" ? "Total" : due == 0 && record.amountPaid > 0 ? "Paid in full" : "Balance due",
                                cents: due == 0 && record.amountPaid > 0 ? record.amountPaid : due, currency: record.currency)
                    if record.amountPaid > 0 {
                        VStack(spacing: 0) {
                            commercialDetail("Total", money(total, currency: record.currency))
                            Rectangle().fill(Theme.border).frame(height: 1)
                            commercialDetail("Paid", money(record.amountPaid, currency: record.currency))
                        }
                        .padding(.horizontal, 15)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    }
                    if let signed = record.customerAuthorization, signed.linesRevision == record.linesRevision {
                        SignatureBadge(label: "Authorized by", signature: signed)
                    } else if let waiting = outbox.waitingSignature(invoiceID: record.id), waiting.expectedLinesRevision == record.linesRevision {
                        // OF-02: signed on this phone, not yet on the server.
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Signed by \(waiting.signerName)").font(Theme.font(15, weight: .medium))
                            WaitingToSyncLabel()
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    } else if record.jobId != nil, record.status != "void", session.can("invoice.edit", feature: "invoicing") {
                        Button { showSignature = true } label: { commercialAction("Get customer signature", icon: "signature") }
                            .buttonStyle(.plain)
                    }
                    PaperGroupHeader(title: "Line items", count: record.lines.count).padding(.top, 4)
                    VStack(spacing: 0) {
                        ForEach(record.lines) { line in CommercialLineView(line: line, divider: line.id != record.lines.first?.id) }
                        if record.lines.isEmpty { Text("No line items yet.").foregroundStyle(Theme.muted).padding(16) }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border))
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
                    PaperGroupHeader(title: "Actions").padding(.top, 4)
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
                                      jobID: jobID, suggestedName: store.customerName(record.customerId),
                                      queueOffline: { png, assetID, signer, signedAt in
                                          // OF-01: the ink stays on the phone and authorizes this exact revision once online.
                                          outbox.enqueueSignature(png, payload: .init(jobId: jobID, invoiceId: record.id,
                                                                                      expectedLinesRevision: record.linesRevision,
                                                                                      signerName: signer, signedAt: signedAt,
                                                                                      clientAssetId: assetID),
                                                                  policyVersion: session.policyVersion ?? 0) != nil
                                      }) { signature in
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
                    issueTitle: issueCollects ? "Issue and collect payment" : "Issue invoice",
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
        .sensoryFeedback(.success, trigger: issued)
        .confirmationDialog("Issue this invoice? Its line items will become final.", isPresented: $confirmIssue, titleVisibility: .visible) {
            Button(issueCollects ? "Issue and collect" : "Issue invoice") { Task { await issueThenCollect() } }
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
        .sheet(isPresented: $showCollectPayment, onDismiss: returnIfPaid) {
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
    /// TF-08: issuing and collecting are one step for the tech; payment opens right after.
    private func issueThenCollect() async {
        guard await issue(), issueCollects, paymentModel?.canRecordPayment == true else { return }
        showCollectPayment = true
    }

    private func returnIfPaid() {
        if returnsWhenPaid, paymentModel?.invoice?.status == "paid" { dismiss() }
    }

    private var issueCollects: Bool {
        session.can("invoice.issue", feature: "invoicing") && session.can("invoice.payment.create", feature: "payments")
    }
    @discardableResult private func issue() async -> Bool {
        guard let current = record else { return false }
        busy = true
        defer { busy = false }
        do {
            let issued = try await api.issueFieldInvoice(id, expectedLinesRevision: current.linesRevision)
            record = issued
            paymentModel?.acceptInvoiceMutationResponse(issued)
            error = nil
            self.issued += 1
            await paymentModel?.load()
            if let invoice = paymentModel?.invoice { record = invoice }
            return true
        }
        catch is CancellationError { return false } catch { self.error = error.localizedDescription; return false }
    }
    private func load() async {
        if paymentModel == nil {
            paymentModel = InvoicePaymentCollectionModel(api: api, invoiceID: id)
            paymentModel?.outbox = outbox
            paymentModel?.policyVersion = session.policyVersion ?? 0
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

/// One priced line, same type as the job's Invoice tab: 15/500 description over a 13pt
/// "2 × $60.00", the line total in mono, and a hairline between lines.
struct CommercialLineView: View {
    let line: FieldLine
    var divider = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(line.description).font(Theme.font(15, weight: .medium))
                Text("\(line.quantity) × \(money(line.unitPrice.amount, currency: line.unitPrice.currency))")
                    .font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            let total = line.quantity.multipliedReportingOverflow(by: line.unitPrice.amount)
            if !total.overflow {
                Text(money(total.partialValue, currency: line.unitPrice.currency))
                    .moneyStyle(.line)
            }
        }
        .foregroundStyle(Theme.foreground)
        .padding(15)
        .frame(minHeight: 56)
        .overlay(alignment: .top) {
            if divider { Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 15) }
        }
        .accessibilityElement(children: .combine)
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

/// MF-02: a labelled amount in a card, at the total size.
@MainActor
private func commercialDetail(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(label).font(Theme.font(15)).foregroundStyle(Theme.muted)
        Spacer(minLength: 12)
        Text(value).moneyStyle(.total).foregroundStyle(Theme.foreground)
    }
    .padding(.vertical, 12)
    .accessibilityElement(children: .combine)
}

/// MF-01/MF-03/MF-04: the amount a screen is about, labelled, at the hero size. Zero reads muted.
struct MoneyFigure: View {
    let label: String
    let cents: Int
    let currency: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(15)).foregroundStyle(Theme.muted)
            // MF-06: a recorded payment rolls the balance down instead of swapping it.
            Text(money(cents, currency: currency)).moneyStyle(.hero).tracking(-0.5)
                .foregroundStyle(cents == 0 ? Theme.muted : Theme.foreground)
                .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: cents)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private func commercialAction(_ title: String, icon: String) -> some View {
    HStack(spacing: 10) {
        Image(systemName: icon).foregroundStyle(Theme.brandText)
        Text(title).font(Theme.font(15, weight: .medium))
        Spacer()
        PaperDisclosure()
    }
    .foregroundStyle(Theme.foreground)
    .padding(15)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
}

private struct CommercialSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(15, weight: .medium))
            .foregroundStyle(Theme.foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(Theme.card.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

private extension View {
    func commercialField() -> some View {
        font(Theme.font(15))
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 13)
            .frame(minHeight: 46)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                HStack(spacing: 6) {
                    Text(subtitle).font(Theme.font(13)).lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    Text("·").font(Theme.font(13))
                    Text(reference).font(Theme.monoFont(12, weight: .medium)).fixedSize()
                }
                .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if let amount { Text(amount).moneyStyle(.row).foregroundStyle(Theme.foreground) }
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

/// The one line an office reads first on a document list: what's outstanding and how much.
@MainActor @ViewBuilder func summaryLine(estimates: [EstimateRecord]) -> some View {
    let waiting = estimates.filter { $0.status == "sent" }
    let total = waiting.compactMap { paperLinesTotal($0.lines) }.reduce(0, +)
    // MF-03: the amount is a figure, the words label it.
    if waiting.isEmpty {
        Text("Nothing waiting on customers").font(Theme.font(15)).foregroundStyle(Theme.muted).padding(.bottom, 6)
    } else {
        MoneyFigure(label: "\(waiting.count) waiting on customers", cents: total, currency: "USD").padding(.bottom, 6)
    }
}

@MainActor @ViewBuilder func summaryLine(invoices: [InvoiceRecord]) -> some View {
    let unpaid = invoices.filter { $0.status == "issued" }
    let owed = unpaid.compactMap { invoice in paperLinesTotal(invoice.lines).map { max(0, $0 - invoice.amountPaid) } }.reduce(0, +)
    if unpaid.isEmpty {
        Text("Everything is paid").font(Theme.font(15)).foregroundStyle(Theme.muted).padding(.bottom, 6)
    } else {
        MoneyFigure(label: "Owed on \(unpaid.count) unpaid invoice\(unpaid.count == 1 ? "" : "s")", cents: owed, currency: "USD").padding(.bottom, 6)
    }
}
