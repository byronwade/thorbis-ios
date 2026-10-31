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
                if !records.isEmpty { summaryLine(estimates: records).padding(.horizontal, Theme.gutter - PaperCardMetrics.margin) }
                ForEach(paperDocumentGroups(visible, status: \.status, order: ["draft", "sent", "approved", "declined"]), id: \.0) { status, group in
                    PaperGroupHeader(title: status.statusLabel, count: group.count).padding(.top, 14)
                        .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                    PaperCardList(data: group) { record in
                        NavigationLink { EstimateDetailView(id: record.id).thorbisBackButton() } label: {
                            // The status is a word on every row; the tile's colour only reinforces it.
                            PaperDocumentRow(kind: .estimate, reference: "EST-\(record.id.suffix(4).uppercased())", title: record.title,
                                             subtitle: store.customerName(record.customerId), status: record.status,
                                             amount: paperLinesTotal(record.lines).map { money($0, currency: record.lines.first?.unitPrice.currency ?? "USD") },
                                             // The group's label already names the status.
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
            .paperCardMargin().padding(.bottom, 24)
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
    @EnvironmentObject private var customerView: JobEstimateHandoffPresenter
    @State private var memberPricing: MemberPricing?
    @State private var showPDF = false
    @State private var openCustomer: Customer?
    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let error { ErrorBanner(message: error, retry: record == nil ? { await load() } : nil) }
                if let record {
                    let currency = record.lines.first?.unitPrice.currency ?? record.options?.first?.currency ?? "USD"
                    DocumentHeading(eyebrow: "Estimate EST-\(record.id.suffix(4).uppercased()) · \(store.customerName(record.customerId))",
                                    title: record.title, status: record.status, statusWord: record.status.statusLabel,
                                    date: estimateStatusDate(record))
                    if let signature = record.approvalSignature { SignatureBadge(label: "Approved by", signature: signature) }
                    // The estimate's own lines. With options they are listed apart and honestly labelled;
                    // the customer approves an option's lines, not these.
                    if !record.lines.isEmpty || (record.options ?? []).isEmpty {
                        DocumentLinesSection(label: (record.options ?? []).isEmpty ? "Line items" : "Estimate line items",
                                             lines: record.lines, totalLabel: "Total",
                                             total: paperLinesTotal(record.lines), currency: currency,
                                             memberLine: memberLine(record.lines, currency: currency))
                    }
                    ForEach(Array((record.options ?? []).enumerated()), id: \.element.id) { index, option in
                        DocumentLinesSection(label: "Option \(index + 1) · \(option.title)", note: option.description,
                                             lines: option.lines, totalLabel: "Option total",
                                             total: option.totalAmount, currency: option.currency,
                                             memberLine: memberLine(option.lines, currency: option.currency))
                    }
                    if let revision = record.currentRevisionNumber {
                        Text("Revision \(revision)").font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                            .padding(.horizontal, 4)
                    }
                } else if error == nil { SkeletonRows(count: 5, leading: false, inset: 0) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }

    /// The date that goes with the status word: when it was sent, approved or declined.
    private func estimateStatusDate(_ record: EstimateRecord) -> String? {
        switch record.status {
        case "sent": record.sentAt ?? record.createdAt
        case "approved": record.approvedAt ?? record.createdAt
        case "declined": record.declinedAt ?? record.createdAt
        default: record.createdAt
        }
    }

    /// MF-05: a member's price is the supporting line under a total, never a second total.
    private func memberLine(_ lines: [FieldLine], currency: String) -> String? {
        guard let memberPricing, memberPricing.isMember, memberPricing.discountPercent > 0, !lines.isEmpty else { return nil }
        let memberTotal = lines.reduce(0) { $0 + $1.quantity * memberPricing.memberPrice($1.unitPrice.amount) }
        return "Member price \(money(memberTotal, currency: currency)) · \(memberPricing.discountPercent)% off"
    }

    /// Everything that isn't the next step: approve, decline, edit, the PDF and the customer.
    private var menuItems: [ThorbisMenuItem] {
        guard let record else { return [] }
        var items: [ThorbisMenuItem] = []
        let canCreate = session.can("estimate.create", feature: "estimates")
        if record.status == "draft", canCreate {
            items.append(ThorbisMenuItem("Edit lines", icon: "square.and.pencil") { showRevisionEditor = true })
        }
        if record.status == "sent" || record.status == "declined", canCreate {
            items.append(ThorbisMenuItem("Revise estimate", icon: "square.and.pencil") { showRevisionEditor = true })
        }
        if record.status == "draft", jobID != nil, TechJobFlow.canShow(record, can: estimateAbilities),
           session.can("estimate.send", feature: "estimates") {
            // The commit shows (and so sends) it; sending without showing stays one tap away.
            items.append(ThorbisMenuItem("Send estimate", icon: "paperplane") { action = "Send"; confirm = true })
        }
        if record.status == "sent", session.can("estimate.approve", feature: "estimates") {
            items.append(ThorbisMenuItem(jobID != nil && (record.options ?? []).isEmpty ? "Approve without a signature" : "Approve estimate",
                                         icon: "checkmark.circle") { action = "Approve"; confirm = true })
            items.append(ThorbisMenuItem("Decline estimate", icon: "xmark.circle", role: .destructive) { action = "Decline"; confirm = true })
        }
        items.append(ThorbisMenuItem("View PDF", icon: "doc.text") { showPDF = true })
        if session.can("customer.view", feature: "core_crm"), let customer = store.customers.first(where: { $0.id == record.customerId }) {
            items.append(ThorbisMenuItem(customer.name, icon: "person", subtitle: "Customer") { openCustomer = customer })
        }
        return items
    }

    var body: some View {
        scrollContent
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if record != nil {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    ThorbisMenu(items: menuItems, title: "Estimate", accessibilityLabel: "Edit, approve or open the PDF") {
                        PaperCircleLabel(symbol: "ellipsis", fill: Theme.card, bordered: true)
                    }
                }
            }
        }
        .thorbisDestination(isPresented: $showPDF) {
            CommercialDocumentView(path: "/v1/estimates/\(id)/document").toolbar(.visible, for: .navigationBar)
        }
        .thorbisDestination(item: $openCustomer) { CustomerDetailView(customer: $0) }
        .safeAreaInset(edge: .bottom) { estimateBar }
        .sensoryFeedback(.success, trigger: succeeded)
        .thorbisConfirm("\(action) this estimate?", isPresented: $confirm,
                        actions: [ThorbisConfirmAction(action, role: action == "Decline" ? .destructive : nil) { Task { await performAction() } }])
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
            PaperActionBar(title: "Show customer", symbol: "iphone", busy: busy) { Task { await handToCustomer() } }
        } else if let record, record.status == "draft", session.can("estimate.send", feature: "estimates") {
            PaperActionBar(title: "Send estimate", symbol: "paperplane", busy: busy) { action = "Send"; confirm = true }
        } else if let record, record.status == "sent", canShowSent(record) {
            // On site, the next step is the customer's yes: hand them the options to choose and sign.
            // Options (and estimates without a job) are signed through an issued link, which needs estimate.send.
            PaperActionBar(title: "Show customer", symbol: "iphone", busy: busy) { Task { await presentToCustomer() } }
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
        await presentToCustomer()
    }

    /// On a job, the estimate opens in that job's Customer view, so the customer can also see the
    /// job's other estimates, invoices and their own details. Without a job it stays a single document.
    private func presentToCustomer() async {
        guard let record else { return }
        if let jobID {
            busy = true
            let opened = await customerView.openCustomerView(jobID: jobID, customerID: record.customerId,
                customerName: store.customerName(record.customerId), start: .estimate(record.id), api: api, session: session) { _ in
                customerModeClosed()
            }
            busy = false
            if opened { return }
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
                if !records.isEmpty { summaryLine(invoices: records).padding(.horizontal, Theme.gutter - PaperCardMetrics.margin) }
                ForEach(paperDocumentGroups(visible, status: \.status, order: ["draft", "issued", "paid", "void"]), id: \.0) { status, group in
                    PaperGroupHeader(title: status == "issued" ? "Awaiting payment" : status.statusLabel, count: group.count).padding(.top, 14)
                        .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                    // The subtitle carries the status as a word ("Balance due", "Paid").
                    PaperCardList(data: group) { record in
                        NavigationLink { InvoiceDetailView(id: record.id).thorbisBackButton() } label: {
                            let total = paperLinesTotal(record.lines)
                            let due = total.map { max(0, $0 - record.amountPaid) }
                            PaperDocumentRow(kind: .invoice, reference: "INV-\(record.id.suffix(4).uppercased())", title: store.customerName(record.customerId),
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
            .paperCardMargin().padding(.bottom, 24)
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
    var expectedJobScope: JobDocumentScope? = nil
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var store: Store
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
    @EnvironmentObject private var customerView: JobEstimateHandoffPresenter
    /// Set when the customer pressed Pay and the technician unlocked: collect once customer mode closes.
    @State private var collectAfterCustomer = false
    @State private var showPDF = false
    @State private var openCustomer: Customer?

    /// The commit at the bottom is the next step (Issue or Collect); the rest lives here.
    private var menuItems: [ThorbisMenuItem] {
        guard let record else { return [] }
        var items: [ThorbisMenuItem] = []
        if record.status != "draft", record.status != "void" {
            items.append(ThorbisMenuItem("Customer view", icon: "iphone", isDisabled: busy) { Task { await presentToCustomer() } })
        }
        if record.status == "draft", session.can("invoice.edit", feature: "invoicing") {
            items.append(ThorbisMenuItem("Edit line items", icon: "pencil") { showEditDraft = true })
        }
        items.append(ThorbisMenuItem("View PDF", icon: "doc.text") { showPDF = true })
        if session.can("customer.view", feature: "core_crm"), let customer = store.customers.first(where: { $0.id == record.customerId }) {
            items.append(ThorbisMenuItem(customer.name, icon: "person", subtitle: "Customer") { openCustomer = customer })
        }
        return items
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error { ErrorBanner(message: error, retry: record == nil ? { await load() } : nil) }
                if let record {
                    // Who it's for and what's owed come first; the line revision is bookkeeping, not for people.
                    DocumentHeading(eyebrow: "Invoice INV-\(record.id.suffix(4).uppercased())", title: store.customerName(record.customerId),
                                    status: record.status, statusWord: record.status == "issued" ? "Unpaid" : record.status.statusLabel,
                                    date: record.paidAt ?? record.issuedAt ?? record.createdAt)
                    let total = record.lines.reduce(0) { $0 + $1.quantity * $1.unitPrice.amount }
                    let due = max(total - record.amountPaid, 0)
                    // MF-04: what's owed now is the largest thing on the invoice; Total and Paid sit in the lines.
                    MoneyFigure(label: record.status == "draft" ? "Total" : due == 0 && record.amountPaid > 0 ? "Paid in full" : "Balance due",
                                cents: due == 0 && record.amountPaid > 0 ? record.amountPaid : due, currency: record.currency)
                    if let signed = record.customerAuthorization, signed.linesRevision == record.linesRevision {
                        SignatureBadge(label: "Authorized by", signature: signed)
                    } else if record.jobId != nil, record.status != "void", session.can("invoice.edit", feature: "invoicing") {
                        Button { showSignature = true } label: {
                            Label("Get customer signature", systemImage: "signature")
                                .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding(.horizontal, 4).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                    }
                    DocumentLinesSection(label: "Line items", lines: record.lines, totalLabel: "Total", total: total, currency: record.currency,
                                         extraRows: record.amountPaid > 0 && record.status != "draft"
                                            ? [("Paid", money(record.amountPaid, currency: record.currency)), ("Balance due", money(due, currency: record.currency))]
                                            : [])
                    if let paymentModel {
                        InvoicePaymentsSection(
                            model: paymentModel,
                            invoice: record,
                            onCollectPayment: { showCollectPayment = true },
                            onInvoiceUpdated: { _ = accept($0) }
                        )
                    }
                } else if error == nil { SkeletonRows(count: 5, leading: false, inset: 0) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if record != nil {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    ThorbisMenu(items: menuItems, title: "Invoice", accessibilityLabel: "Customer view, edit or open the PDF") {
                        PaperCircleLabel(symbol: "ellipsis", fill: Theme.card, bordered: true)
                    }
                }
            }
        }
        .thorbisDestination(isPresented: $showPDF) {
            CommercialDocumentView(path: "/v1/invoices/\(id)/document").toolbar(.visible, for: .navigationBar)
        }
        .thorbisDestination(item: $openCustomer) { CustomerDetailView(customer: $0) }
        .sheet(isPresented: $showSignature) {
            if let record, let jobID = record.jobId {
                let total = record.lines.reduce(0) { $0 + $1.quantity * $1.unitPrice.amount }
                SignatureCaptureSheet(title: "Sign for \(money(total, currency: record.currency))",
                                      summary: "By signing, \(store.customerName(record.customerId)) authorizes the work and charges on this invoice.",
                                      jobID: jobID, suggestedName: store.customerName(record.customerId)) { signature in
                    do {
                        let updated = try await api.authorizeFieldInvoice(id, expectedLinesRevision: record.linesRevision, signature: signature)
                        return accept(updated) ? nil : paymentModel?.loadError
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
        .thorbisConfirm("Issue this invoice? Its line items will become final.", isPresented: $confirmIssue,
                        actions: [ThorbisConfirmAction(issueCollects ? "Issue and collect" : "Issue invoice") { Task { await issueThenCollect() } }])
        .sheet(isPresented: $showEditDraft) {
            if let record {
                NavigationStack {
                    InvoiceLineEditorView(invoice: record) { updated in
                        guard accept(updated) else { return }
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
                            _ = accept(updated)
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
        .task(id: session.generation) {
            paymentModel = nil
            record = nil
            await load()
            #if DEBUG
            if PaperPreview.enabled, PaperPreview.screen == "invoice-payment" {
                showCollectPayment = paymentModel?.canRecordPayment == true
            }
            #endif
        }
        .refreshable { await load() }
    }
    /// On a job, the invoice opens in that job's Customer view, with its payments and balance beside
    /// the job's other documents. Without a verified job it stays a single document.
    private func presentToCustomer() async {
        guard let record else { return }
        if let jobID = record.jobId, expectedJobScope.map({ $0.contains(record) }) != false {
            busy = true
            let opened = await customerView.openCustomerView(jobID: jobID, customerID: record.customerId,
                customerName: store.customerName(record.customerId), start: .invoice(record.id), api: api, session: session) { exit in
                await load()
                guard case .collect(let invoiceID) = exit, invoiceID == id, paymentModel?.canRecordPayment == true,
                      session.can("invoice.payment.create", feature: "payments") else { return }
                showCollectPayment = true
            }
            busy = false
            if opened { return }
        }
        showToCustomer = true
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
            guard accept(issued) else { return false }
            error = nil
            self.issued += 1
            await paymentModel?.load()
            record = paymentModel?.invoice
            return true
        }
        catch is CancellationError { return false } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult private func accept(_ invoice: InvoiceRecord) -> Bool {
        guard let paymentModel, paymentModel.acceptInvoiceMutationResponse(invoice) else {
            record = nil
            error = paymentModel?.loadError
            return false
        }
        record = invoice
        return true
    }

    private func load() async {
        let generation = session.generation
        guard expectedJobScope.map({ $0.organizationID == session.activeOrganization?.id }) != false else {
            record = nil
            paymentModel = nil
            return
        }
        if paymentModel == nil {
            paymentModel = InvoicePaymentCollectionModel(api: api, invoiceID: id, expectedJobScope: expectedJobScope)
        }
        guard let paymentModel else { return }
        await paymentModel.load()
        guard session.generation == generation else { return }
        record = paymentModel.invoice
        if paymentModel.invoice != nil {
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
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        // At accessibility sizes the amount reads under the line, so the description keeps the full width.
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(line.description).font(Theme.font(15, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(line.quantity) × \(money(line.unitPrice.amount, currency: line.unitPrice.currency))")
                    .font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            if !stacked { Spacer(minLength: 8) }
            let total = line.quantity.multipliedReportingOverflow(by: line.unitPrice.amount)
            if !total.overflow {
                Text(money(total.partialValue, currency: line.unitPrice.currency))
                    .moneyStyle(.line)
            }
        }
        .foregroundStyle(Theme.foreground)
        .padding(15)
        .frame(maxWidth: stacked ? .infinity : nil, minHeight: 56, alignment: .leading)
        .overlay(alignment: .top) {
            if divider { Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 15) }
        }
        .accessibilityElement(children: .combine)
    }
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

// MARK: - Document pieces (estimate and invoice detail)

/// The record line, the title and the status as a dot and a word with its date.
struct DocumentHeading: View {
    let eyebrow: String
    let title: String
    let status: String
    let statusWord: String
    let date: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(title).font(Theme.font(26, weight: .medium)).tracking(-0.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                Circle().fill(documentStatusTint(status)).frame(width: 7, height: 7).padding(.trailing, 6).accessibilityHidden(true)
                Text(statusWord).font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.foreground)
                if let date = JobFiltering.date(date) {
                    Text(" · " + documentDate(date)).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                }
            }
            .padding(.top, 8)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Jul 18", with the year only when it isn't this year.
func documentDate(_ date: Date) -> String {
    Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        ? date.formatted(.dateTime.month(.abbreviated).day())
        : date.formatted(.dateTime.month(.abbreviated).day().year())
}

/// A status's colour, used only for the dot beside its word.
func documentStatusTint(_ status: String) -> Color {
    switch status {
    case "approved", "paid", "completed": Theme.success
    case "sent", "issued", "open": Theme.warning
    case "declined", "void", "canceled": Theme.destructive
    default: Theme.muted
    }
}

extension View {
    /// The white sheet a section's rows sit on: radius 14 and a faint rim, on the cream ground.
    func documentPanel() -> some View {
        clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

/// A section label, the lines on one sheet with every description in full, then the total row
/// and an optional supporting line (a member's price) under the sheet.
struct DocumentLinesSection: View {
    let label: String
    var note: String = ""
    let lines: [FieldLine]
    let totalLabel: String
    let total: Int?
    let currency: String
    var extraRows: [(String, String)] = []
    var memberLine: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                if !note.isEmpty {
                    Text(note).font(Theme.font(15)).foregroundStyle(Theme.subtle)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
                }
                ForEach(lines) { DocumentLineRow(line: $0) }
                if lines.isEmpty {
                    Text("No line items yet.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
                if let total, !lines.isEmpty {
                    VStack(spacing: 0) {
                        totalRow(totalLabel, money(total, currency: currency), strong: extraRows.isEmpty)
                        ForEach(Array(extraRows.enumerated()), id: \.offset) { index, row in
                            totalRow(row.0, row.1, strong: index == extraRows.count - 1)
                        }
                    }
                    .background(Theme.background.opacity(0.6))
                }
            }
            .documentPanel()
            if let memberLine {
                Text(memberLine).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func totalRow(_ label: String, _ amount: String, strong: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Theme.font(16, weight: strong ? .medium : .regular))
                .foregroundStyle(strong ? Theme.foreground : Theme.subtle)
            Spacer(minLength: 12)
            Text(amount).font(Theme.font(16, weight: strong ? .medium : .regular)).monospacedDigit()
                .foregroundStyle(strong ? Theme.foreground : Theme.subtle)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

/// One priced line: the description in full (it wraps, never truncates), the line total, then
/// "2 × $60.00". The data has one text per line, so the whole of it is shown.
struct DocumentLineRow: View {
    let line: FieldLine
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // At accessibility sizes the amount goes under the description; beside it, the
            // description is squeezed into a column and breaks mid-word.
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            layout {
                Text(line.description).font(Theme.font(15, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let total = paperLinesTotal([line]) {
                    Text(money(total, currency: line.unitPrice.currency))
                        .font(Theme.font(15, weight: .medium)).monospacedDigit()
                        .lineLimit(1).fixedSize()
                }
            }
            Text("\(line.quantity) × \(money(line.unitPrice.amount, currency: line.unitPrice.currency))")
                .font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
        }
        .foregroundStyle(Theme.foreground)
        .padding(.horizontal, 16).padding(.vertical, 13)
        .accessibilityElement(children: .combine)
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
    enum Kind {
        case estimate, invoice, billingSchedule

        var symbol: String {
            switch self {
            case .estimate: "doc.text"
            case .invoice: "doc.plaintext"
            case .billingSchedule: "list.bullet.rectangle"
            }
        }
    }

    let kind: Kind
    let reference: String
    let title: String
    let subtitle: String
    let status: String
    let amount: String?
    var showsStatus = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.paperRowInset) private var inset

    /// design 2026-10-30: the list row, no tile. Title, then who and the reference; on the right
    /// the amount over the status word (or only the amount when the subtitle already says it).
    var body: some View {
        PaperListRow(title: title, subtitle: "\(subtitle) · \(reference)") {
            VStack(alignment: .trailing, spacing: 4) {
                if let amount { Text(amount).font(Theme.moneyFont(.line)).foregroundStyle(Theme.foreground) }
                if showsStatus { StatusWord(documentStatus: status) }
            }
            .fixedSize()
        }
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
    // One line, said once: the rows carry each amount, so no hero figure repeats them.
    Text(waiting.isEmpty ? "Nothing waiting on customers"
         : "\(waiting.count) waiting on customers · \(money(total, currency: "USD"))")
        .font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted).padding(.bottom, 6)
}

@MainActor @ViewBuilder func summaryLine(invoices: [InvoiceRecord]) -> some View {
    let unpaid = invoices.filter { $0.status == "issued" }
    let owed = unpaid.compactMap { invoice in paperLinesTotal(invoice.lines).map { max(0, $0 - invoice.amountPaid) } }.reduce(0, +)
    Text(unpaid.isEmpty ? "Everything is paid"
         : "\(money(owed, currency: "USD")) owed on \(unpaid.count) unpaid invoice\(unpaid.count == 1 ? "" : "s")")
        .font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted).padding(.bottom, 6)
}
