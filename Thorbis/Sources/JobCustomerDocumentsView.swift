import SwiftUI

enum CustomerJobPaper: Hashable {
    case estimate(EstimateRecord)
    case invoice(InvoiceRecord, signing: Bool)
}

/// Stable navigation owner for async rechecks and destination callbacks.
@MainActor final class CustomerJobPaperNavigation: ObservableObject {
    @Published var paper: CustomerJobPaper?
    @Published var generation = UUID()
    @Published var book: CustomerJobDocumentID?
    @Published var openingID: String?
    var selectionRevision = UUID()
    private(set) var requestRevision = UUID()

    func beginOpen(_ id: String) -> UUID? {
        guard openingID == nil else { return nil }
        let request = UUID()
        requestRevision = request
        openingID = id
        return request
    }
    func finishOpen(_ request: UUID) {
        if requestRevision == request { openingID = nil }
    }
    func invalidatePendingOpen() {
        requestRevision = UUID()
        openingID = nil
    }
}

/// Customer view's home. Lives inside one CustomerModeContainer: the job's estimates (select and
/// approve one or several), its invoices with their payments, and the customer's own details.
/// Browsing never exposes technician controls.
struct JobCustomerDocumentsView: View {
    let scope: JobDocumentScope
    @ObservedObject var documents: JobDocumentCollections
    /// Generation under which the shared job-document collection was loaded.
    let sourceGeneration: UUID?
    let jobTitle: String
    let customerName: String
    let handBack: () -> Void
    let onUnlocked: () -> Void
    /// Called only after device-owner authentication, before the cover closes.
    let requestPayment: (String) -> Void
    let invoiceUpdated: (InvoiceRecord) -> Void
    var authenticateOwner: @MainActor (String) async -> Bool = { await StaffUnlock.unlock(reason: $0) }
    /// The job's multi-estimate selection and approval, opened from Estimates.
    var handoff: JobEstimateHandoffModel? = nil
    /// The customer's own details, when this person may edit customers.
    var details: CustomerSelfEditModel? = nil
    var start: CustomerViewStart = .home

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dynamicTypeSize) private var typeSize
    private var estimates: JobDocumentRead<EstimateRecord>? { documents.estimates }
    private var invoices: JobDocumentRead<InvoiceRecord>? { documents.invoices }
    @StateObject private var paperNavigation = CustomerJobPaperNavigation()
    private var paper: CustomerJobPaper? {
        get { paperNavigation.paper }
        nonmutating set { paperNavigation.paper = newValue }
    }
    private var paperGeneration: UUID {
        get { paperNavigation.generation }
        nonmutating set { paperNavigation.generation = newValue }
    }
    private var book: CustomerJobDocumentID? {
        get { paperNavigation.book }
        nonmutating set {
            if paperNavigation.book != newValue { paperNavigation.invalidatePendingOpen() }
            paperNavigation.book = newValue
        }
    }
    private var openingID: String? {
        get { paperNavigation.openingID }
        nonmutating set { paperNavigation.openingID = newValue }
    }
    private var documentSelectionRevision: UUID {
        get { paperNavigation.selectionRevision }
        nonmutating set {
            paperNavigation.invalidatePendingOpen()
            paperNavigation.selectionRevision = newValue
        }
    }
    @State private var paymentModel: InvoicePaymentCollectionModel?
    @State private var error: String?
    @State private var unlocking = false
    @State private var approving = false
    @State private var editingDetails = false
    @State private var started = false

    private var currentWorkspace: Bool { sourceGeneration == session.generation && session.user != nil && session.activeOrganization?.id == scope.organizationID }
    private var canViewEstimates: Bool { session.can("estimate.view", feature: "estimates") }
    private var canViewInvoices: Bool { session.can("invoice.view", feature: "invoicing") }
    private var canEditDetails: Bool { details != nil && session.can("customer.edit", feature: "core_crm") }

    var body: some View {
        Group {
            if currentWorkspace {
                ScrollView {
                    // Paper "Customer view": the greeting, then Estimates, Invoices and Your details as
                    // grouped cards 16 from the edge, 22 apart, with the commit after the last card.
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(eyebrow).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(greeting).font(Theme.font(34)).tracking(-0.85)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 6)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("customer-view-title")
                            Text("Here is everything for your visit today")
                                .font(Theme.font(15)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 4)
                        if let error { CustomerProblemBanner(message: error, actionTitle: "Try again") { await refresh() } }
                        else if estimates?.isComplete == false || invoices?.isComplete == false {
                            CustomerProblemBanner(message: "Some documents couldn't be refreshed. Try again to see everything.",
                                                  actionTitle: "Try again") { await refresh() }
                        }
                        if canViewEstimates { estimateRows }
                        if canViewInvoices { invoiceRows }
                        if canEditDetails { detailsRow }
                        if canViewEstimates { approveEstimates }
                    }
                    .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 16)
                    // Paper 38B: the commit sits 10 above the hand-back pill, which is pinned below.
                    .frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("customer-job-documents-list")
                .refreshable { await refresh() }
            } else {
                customerHandBackState(withAction: false)
            }
        }
        .navigationTitle("Customer view")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                CustomerHandBackPill(busy: openingID != nil, action: beginHandBack)
                // At accessibility sizes the pinned foot is the pill alone, so the list keeps its room.
                if !typeSize.isAccessibilitySize {
                    Text("Your technician's screens stay locked.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 10).padding(.bottom, 12).background(Theme.canvas)
        }
        // Paper 38B draws no bar over the customer's home: the greeting starts the page and handing
        // back is the pill at its foot. Pushed pages keep their bar, back circle and owner exit.
        .toolbar(.hidden, for: .navigationBar)
        .thorbisDestination(item: Binding(get: { book }, set: { book = $0 })) { initial in
            if currentWorkspace {
                CustomerJobDocumentBook(scope: scope, sourceGeneration: sourceGeneration,
                    estimates: canViewEstimates && estimates?.scope == scope ? estimates?.records ?? [] : [],
                    invoices: canViewInvoices && invoices?.scope == scope ? invoices?.records ?? [] : [],
                    freshEstimates: estimates?.scope == scope ? estimates?.freshIDs ?? [] : [],
                    freshInvoices: invoices?.scope == scope ? invoices?.freshIDs ?? [] : [],
                    unavailableEstimates: canViewEstimates && estimates?.scope == scope ? estimates?.unavailableIDs ?? [] : [],
                    initial: initial, actionError: error, refresh: refresh,
                    reviewEstimate: { id in Task { await openEstimate(id, decision: true) } },
                    signInvoice: { id in Task { await openInvoice(id, decision: true, sign: true) } },
                    payInvoice: { id in
                        #if DEBUG
                        if PaperPreview.isJobDocumentsPreview, ProcessInfo.processInfo.arguments.contains("--paper-preview-payment-recheck-fails") {
                            PaperPreviewProtocol.failDocumentPaymentRecheck()
                        }
                        #endif
                        Task { await openInvoice(id, payment: true) }
                    },
                    canSignInvoice: session.can("invoice.edit", feature: "invoicing"),
                    canPayInvoice: session.can("invoice.payment.create", feature: "payments"),
                    onSelectionChanged: { documentSelectionRevision = UUID(); error = nil })
                    .disabled(unlocking || openingID != nil)
                    .onDisappear { paperNavigation.invalidatePendingOpen() }
                    .thorbisDestination(item: Binding(get: { paper }, set: { next in
                        if paper != next { paperGeneration = UUID() }
                        paper = next
                    })) { destination in
                        VStack(spacing: 0) {
                            if case .invoice = destination, let error {
                                CustomerProblemBanner(message: error)
                                    .padding(.horizontal, Theme.gutter).padding(.bottom, 12)
                            }
                            destinationView(destination)
                        }
                            .disabled(unlocking)
                            .navigationTitle(reference(destination))
                            .toolbar {
                                ThorbisToolbarItem(placement: .topBarTrailing) {
                                    Button { Task { await unlock() } } label: {
                                        Image(systemName: "lock").font(.system(size: 20))
                                            .frame(width: CustomerModeStyle.target, height: CustomerModeStyle.target)
                                            .contentShape(Rectangle())
                                    }
                                    .accessibilityLabel("Technician: unlock to leave customer mode")
                                    .disabled(unlocking)
                                }
                            }
                    }
                    .toolbar {
                        ThorbisToolbarItem(placement: .topBarTrailing) {
                            Button { Task { await unlock() } } label: {
                                Image(systemName: "lock").font(.system(size: 20))
                                    .frame(width: CustomerModeStyle.target, height: CustomerModeStyle.target)
                            }.accessibilityLabel("Technician: unlock to leave customer mode")
                        }
                    }
            } else {
                customerHandBackState(withAction: true)
            }
        }
        .thorbisDestination(isPresented: $approving) {
            // The handoff guards itself: a changed session or access shows its own hand-back screen.
            if let handoff {
                JobEstimateHandoffView(model: handoff, handBack: beginHandBack)
                    .toolbar { ThorbisToolbarItem(placement: .topBarTrailing, customerFacing: true) { CustomerModeOwnerUnlockButton() } }
            } else {
                customerHandBackState(withAction: true)
            }
        }
        .thorbisDestination(isPresented: $editingDetails) {
            if currentWorkspace, canEditDetails, let details {
                CustomerSelfEditForm(model: details, currentAuthority: {
                    currentWorkspace && handoff?.isCurrentJob == true && session.can("customer.edit", feature: "core_crm")
                }) { editingDetails = false }
                    .navigationTitle("My details")
                    .toolbar { ThorbisToolbarItem(placement: .topBarTrailing, customerFacing: true) { CustomerModeOwnerUnlockButton() } }
            } else {
                customerHandBackState(withAction: true)
            }
        }
        .task(id: session.generation) {
            paperGeneration = UUID(); paper = nil
            book = nil
            editingDetails = false
            paymentModel = nil
            await refresh()
            if !started {
                started = true
                await open(start)
            }
        }
    }

    /// Opens Customer view on the section or document the technician started from.
    private func open(_ start: CustomerViewStart) async {
        guard currentWorkspace else { return }
        var instant = Transaction()
        instant.disablesAnimations = true
        switch start {
        case .home: break
        case .estimates:
            if canViewEstimates, handoff != nil { withTransaction(instant) { approving = true } }
        case .estimate(let id):
            // Opens on this estimate in the job's book; "Review and sign" is one tap away.
            await openEstimate(id)
        case .invoice(let id):
            await openInvoice(id)
        case .details:
            if canEditDetails { withTransaction(instant) { editingDetails = true } }
        }
    }

    /// Paper: "Wade's Plumbing · Customer view" above the greeting.
    private var eyebrow: String {
        guard let workspace = session.activeOrganization?.name, !workspace.isEmpty else { return "Customer view" }
        return "\(workspace) \u{00B7} Customer view"
    }

    /// Paper: "Hi Danielle", the customer's first name.
    private var greeting: String {
        guard let first = customerName.split(separator: " ").first else { return "Hi" }
        return "Hi \(first)"
    }

    private var estimateRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            customerSectionLabel("Estimates")
            VStack(spacing: 0) {
                if let estimates {
                    if estimates.records.isEmpty && estimates.unavailableIDs.isEmpty && estimates.isComplete {
                        empty("No estimates for this job yet.")
                    }
                    ForEach(Array(estimates.records.enumerated()), id: \.element.id) { index, estimate in
                        if index > 0 { WellDivider() }
                        Button { Task { await openEstimate(estimate.id) } } label: {
                            estimateRow(estimate, fresh: estimates.freshIDs.contains(estimate.id))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("customer-estimate-\(estimate.id)")
                        .disabled(openingID != nil || !estimates.freshIDs.contains(estimate.id))
                    }
                    ForEach(Array(estimates.unavailableIDs.enumerated()), id: \.element) { index, id in
                        if index > 0 || !estimates.records.isEmpty { WellDivider() }
                        CustomerHomeDocumentRow(title: "Estimate unavailable", reference: "EST-\(id.suffix(4).uppercased())",
                                                word: "Needs refresh", chevron: false)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("customer-estimate-unavailable-\(id)")
                    }
                } else { SkeletonRows(count: 2, leading: false, inset: PaperCardMetrics.inset) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelBackground()
        }
    }

    /// Paper's estimate row: the name over "EST-1042 · Waiting for you", the amount, a chevron.
    private func estimateRow(_ estimate: EstimateRecord, fresh: Bool) -> CustomerHomeDocumentRow {
        let facts = JobDocumentRow(estimate: estimate, fresh: fresh, customerFacing: true)
        let word = estimate.status == "sent" ? "Waiting for you" : estimate.status.statusLabel
        return CustomerHomeDocumentRow(title: facts.title, reference: facts.reference,
                                       word: fresh ? word : "Needs refresh",
                                       tint: fresh ? StatusWord.documentTint(estimate.status) : nil,
                                       detail: facts.detail, amount: facts.amount)
    }

    /// Paper's invoice row: the job's name over "INV-2209 · $340.00 due", the total, a chevron.
    private func invoiceRow(_ invoice: InvoiceRecord, fresh: Bool) -> CustomerHomeDocumentRow {
        let facts = JobDocumentRow(invoice: invoice, fresh: fresh, customerFacing: true)
        let word = invoice.status == "issued" ? (facts.detail ?? "Unpaid") : invoice.status.statusLabel
        return CustomerHomeDocumentRow(title: invoice.origin == "estimate_deposit" || jobTitle.isEmpty ? facts.title : jobTitle,
                                       reference: facts.reference,
                                       word: fresh ? word : "Needs refresh",
                                       tint: fresh ? StatusWord.documentTint(invoice.status) : nil,
                                       amount: facts.amount)
    }

    /// Approving goes through the job's one multi-estimate review: select one or several, review,
    /// then sign each. Already approved estimates stay listed without approving again.
    /// Paper: the brand commit "Review estimates" under the last card.
    @ViewBuilder private var approveEstimates: some View {
        if handoff != nil, let estimates, estimates.records.contains(where: { $0.status == "sent" }) {
            CustomerPresentationCommit(title: "Review estimates", enabled: openingID == nil, busy: false,
                                       type: CustomerType(nil)) { approving = true }
                .accessibilityIdentifier("customer-view-approve-estimates")
        }
    }

    private var detailsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            customerSectionLabel("Your details")
            Button { editingDetails = true } label: {
                if let details { CustomerHomeDetailsCard(model: details) }
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Your details")
            .accessibilityHint("Check and fix your name, phone, email and addresses")
            .accessibilityIdentifier("customer-view-details")
            .disabled(openingID != nil)
        }
    }

    private var invoiceRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            customerSectionLabel("Invoices")
            VStack(spacing: 0) {
                if let invoices {
                    if invoices.records.isEmpty && invoices.isComplete { empty("No invoices for this job yet.") }
                    ForEach(Array(invoices.records.enumerated()), id: \.element.id) { index, invoice in
                        if index > 0 { WellDivider() }
                        Button { Task { await openInvoice(invoice.id) } } label: {
                            invoiceRow(invoice, fresh: invoices.freshIDs.contains(invoice.id))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("customer-invoice-\(invoice.id)")
                        .disabled(openingID != nil || !invoices.freshIDs.contains(invoice.id))
                    }
                } else { SkeletonRows(count: 2, leading: false, inset: PaperCardMetrics.inset) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelBackground()
        }
    }

    @ViewBuilder private func destinationView(_ destination: CustomerJobPaper) -> some View {
        let presentation = paperGeneration
        switch destination {
        case .estimate(let estimate):
            if estimate.status == "sent", TechJobFlow.canShow(estimate, can: .init(
                sendEstimate: session.can("estimate.send", feature: "estimates"),
                approveEstimate: session.can("estimate.approve", feature: "estimates"))) {
                CustomerEstimatePresentation(estimate: estimate, jobID: scope.jobID, customerName: customerName,
                    returnToDocuments: {
                        returnToJobDocuments()
                    },
                    currentAuthority: { paperGeneration == presentation && currentWorkspace && handoff?.isCurrentJob == true && canViewEstimates && session.can("estimate.approve", feature: "estimates") },
                    onApproved: { approved in
                        guard paperGeneration == presentation, currentWorkspace, handoff?.isCurrentJob == true, canViewEstimates else { return }
                        documents.markEstimatesStale(scope: scope, updated: approved, requestedID: estimate.id)
                        refreshEstimatesInBackground()
                    }, onDone: beginHandBack)
            } else {
                CustomerJobReadOnlyPaper(estimate: estimate, handBack: beginHandBack)
            }
        case .invoice(let invoice, let signing):
            if ["issued", "paid"].contains(invoice.status) {
                CustomerInvoicePresentation(invoice: invoice, customerName: customerName,
                    canSign: session.can("invoice.edit", feature: "invoicing"),
                    onPay: paymentModel?.canRecordPayment == true && session.can("invoice.payment.create", feature: "payments")
                        ? { Task { await pay(invoice.id) } } : nil, initiallySigning: signing,
                    currentAuthority: { paperGeneration == presentation && currentWorkspace && handoff?.isCurrentJob == true && canViewInvoices && (!signing || session.can("invoice.edit", feature: "invoicing")) && scope.contains(invoice) },
                    onSigned: { updated in
                        guard paperGeneration == presentation, currentWorkspace, handoff?.isCurrentJob == true,
                              canViewInvoices, session.can("invoice.edit", feature: "invoicing"),
                              scope.contains(updated), updated.id == invoice.id else { return }
                        documents.replaceInvoice(updated)
                        paymentModel?.acceptInvoiceMutationResponse(updated)
                        paperGeneration = UUID(); paper = .invoice(updated, signing: false)
                        invoiceUpdated(updated)
                    }, onDone: beginHandBack)
            } else {
                CustomerJobReadOnlyPaper(invoice: invoice, handBack: beginHandBack)
            }
        }
    }

    private func reference(_ destination: CustomerJobPaper) -> String {
        switch destination {
        case .estimate(let estimate): "EST-\(estimate.id.suffix(4).uppercased())"
        case .invoice(let invoice, _): "INV-\(invoice.id.suffix(4).uppercased())"
        }
    }

    private func beginHandBack() {
        paperNavigation.invalidatePendingOpen()
        paperGeneration = UUID(); paper = nil
        book = nil
        approving = false
        editingDetails = false
        handBack()
    }

    /// The session or workspace changed under the customer: only the technician can reopen it.
    /// On the home the pinned "Hand back to technician" is the one action, so the state is
    /// words only; pushed pages have no pinned bar and carry it themselves.
    private func customerHandBackState(withAction: Bool) -> some View {
        let handBack: (() -> Void)? = withAction ? { beginHandBack() } : nil
        return CustomerStateMessage(symbol: "hand.raised", title: "Please hand the device back",
                             message: "Your technician needs to reload this job.",
                             actionTitle: withAction ? "Hand back to technician" : nil,
                             action: handBack)
            .padding(.horizontal, Theme.gutter)
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(Theme.font(15)).foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: CustomerModeStyle.target, alignment: .leading)
    }

    private func refresh() async {
        error = nil
        let generation = session.generation
        if currentWorkspace && canViewEstimates {
            await documents.loadEstimates(scope: scope, api: api) {
                session.generation == generation && currentWorkspace && canViewEstimates
            }
        }
        guard session.generation == generation, currentWorkspace else { return }
        if canViewInvoices {
            await documents.loadInvoices(scope: scope, api: api) {
                session.generation == generation && currentWorkspace && canViewInvoices
            }
        }
    }

    private func returnToJobDocuments() {
        guard currentWorkspace, canViewEstimates,
              let presented = paper, case .estimate = presented else { return }
        documents.markEstimatesStale(scope: scope)
        paperGeneration = UUID(); paper = nil
        refreshEstimatesInBackground()
    }

    private func refreshEstimatesInBackground() {
        let generation = session.generation
        Task {
            await documents.loadEstimates(scope: scope, api: api) {
                session.generation == generation && currentWorkspace && canViewEstimates
            }
        }
    }

    private func openEstimate(_ id: String, decision: Bool = false) async {
        guard currentWorkspace, canViewEstimates, let request = paperNavigation.beginOpen(id) else { return }
        defer { paperNavigation.finishOpen(request) }
        let generation = session.generation
        let published = await documents.loadEstimates(scope: scope, api: api) {
            paperNavigation.requestRevision == request && session.generation == generation && currentWorkspace && canViewEstimates
        }
        guard paperNavigation.requestRevision == request, session.generation == generation,
              currentWorkspace, published, let read = estimates else { return }
        guard read.freshIDs.contains(id), let estimate = read.records.first(where: { $0.id == id }) else {
            error = "This estimate couldn't be refreshed. Try again in a moment."
            return
        }
        if decision { paperGeneration = UUID(); paper = .estimate(estimate) }
        else { book = .estimate(id) }
    }

    private func openInvoice(_ id: String, decision: Bool = false, sign: Bool = false, payment: Bool = false) async {
        guard currentWorkspace, canViewInvoices,
              !sign || session.can("invoice.edit", feature: "invoicing"),
              !decision || book != nil,
              let request = paperNavigation.beginOpen(id) else { return }
        error = nil
        defer { paperNavigation.finishOpen(request) }
        let generation = session.generation
        let authority = session.authorityRevision
        let apiGeneration = api.requestGeneration
        let originatingBook = book
        let selection = documentSelectionRevision
        let presentation = paperGeneration
        let originalPaper = paper
        func isCurrentOpen() -> Bool {
            !Task.isCancelled && paperNavigation.requestRevision == request &&
            session.generation == generation && session.authorityRevision == authority &&
            api.requestGeneration == apiGeneration && currentWorkspace && canViewInvoices &&
            (!sign || session.can("invoice.edit", feature: "invoicing")) &&
            (!(decision || payment) || handoff?.isCurrentJob == true) &&
            book == originatingBook && documentSelectionRevision == selection &&
            paperGeneration == presentation && paper == originalPaper
        }
        do {
            #if DEBUG
            if sign && PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-revoke-invoice-edit-on-sign") {
                PaperPreviewProtocol.revokeInvoiceEditForSigning()
                await session.revalidate()
            }
            if sign && PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-delay-invoice-signing") {
                try await Task.sleep(for: .seconds(15))
            }
            #endif
            guard isCurrentOpen() else { return }
            let invoice = try await api.liveFieldInvoice(id)
            guard isCurrentOpen() else { return }
            guard invoice.id == id, scope.contains(invoice) else {
                throw Problem(title: "This invoice couldn't be verified for this job", status: nil, detail: nil)
            }
            let model = InvoicePaymentCollectionModel(api: api, invoiceID: id, expectedJobScope: scope)
            await model.load()
            guard isCurrentOpen() else { return }
            if let latest = model.invoice {
                guard latest.id == id, scope.contains(latest) else {
                    throw Problem(title: "This invoice couldn't be verified for this job", status: nil, detail: nil)
                }
                documents.replaceInvoice(latest)
                paymentModel = model
                if payment { await pay(id) }
                else if decision {
                    guard CustomerDocumentAmounts(lines: latest.lines, currency: latest.currency, amountPaid: latest.amountPaid) != nil else {
                        throw Problem(title: "These invoice amounts couldn't be verified. Refresh before continuing.", status: nil, detail: nil)
                    }
                    paperGeneration = UUID(); paper = .invoice(latest, signing: sign)
                } else { book = .invoice(id) }
            } else {
                paymentModel = nil
                throw Problem(title: model.loadError ?? "This invoice couldn't be refreshed", status: nil, detail: nil)
            }
        } catch is CancellationError {
        } catch {
            guard isCurrentOpen() else { return }
            self.error = error.customerSentence(.openInvoice)
        }
    }

    private func pay(_ invoiceID: String) async {
        guard !unlocking, currentWorkspace else { return }
        guard paymentModel?.invoice?.id == invoiceID, paymentModel?.canRecordPayment == true,
              canViewInvoices, handoff?.isCurrentJob == true,
              session.can("invoice.payment.create", feature: "payments"),
              let authority = CustomerHandoffExitAuthority.capture(api: api, session: session) else {
            error = "Payment isn't ready. Ask your technician to check this invoice."
            return
        }
        error = nil
        let selectionRevision = documentSelectionRevision
        let presentationRevision = paperGeneration
        let originalPaper = paper
        let originalBook = book
        unlocking = true
        defer { unlocking = false }
        let unlocked = await authenticateOwner("Unlock to take payment")
        #if DEBUG
        if PaperPreview.isJobDocumentsPreview, ProcessInfo.processInfo.arguments.contains("--paper-preview-payment-retire-on-unlock") {
            api.invalidateRequests()
        }
        #endif
        let current = currentWorkspace && handoff?.isCurrentJob == true && canViewInvoices &&
            session.can("invoice.payment.create", feature: "payments") && authority.isCurrent(api: api, session: session) &&
            documentSelectionRevision == selectionRevision && paperGeneration == presentationRevision &&
            paper == originalPaper && book == originalBook && paymentModel?.invoice?.id == invoiceID &&
            paymentModel?.canRecordPayment == true
        guard current else { return }
        if unlocked {
            requestPayment(invoiceID)
        } else {
            error = "Your technician needs to unlock before taking payment."
        }
    }

    private func unlock() async {
        guard !unlocking else { return }
        paperNavigation.invalidatePendingOpen()
        unlocking = true
        defer { unlocking = false }
        if await authenticateOwner("Unlock to leave customer mode") { onUnlocked() }
    }
}

/// Drafts, declined estimates and void invoices can be browsed without issuing or changing them.
private struct CustomerJobReadOnlyPaper: View {
    var estimate: EstimateRecord? = nil
    var invoice: InvoiceRecord? = nil
    let handBack: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let type = CustomerType(sizeClass)
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let estimate {
                        Text(estimate.title).font(Theme.customerFont(type.heading, weight: .medium))
                        CustomerStatusWord(status: estimate.status, type: type)
                        if let options = estimate.options, !options.isEmpty, estimate.status != "approved" {
                            ForEach(options) { option in
                                Text(option.title).font(Theme.customerFont(type.heading, weight: .medium))
                                if !option.description.isEmpty { Text(option.description).font(Theme.customerFont(type.body)) }
                                estimateLines(option.lines, currency: option.currency, type: type, expectedTotal: option.totalAmount)
                            }
                        } else { estimateLines(estimate.lines, currency: estimate.lines.first?.unitPrice.currency ?? "USD", type: type) }
                    } else if let invoice {
                        Text("Invoice").font(Theme.customerFont(type.heading, weight: .medium))
                        CustomerStatusWord(status: invoice.status, type: type)
                        lines(invoice.lines, currency: invoice.currency, type: type)
                    }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.vertical, Theme.gutter)
                .frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
            CustomerCommitButton(title: "Hand back to technician", icon: "lock", busy: false, action: handBack)
                .padding(.horizontal, PaperCardMetrics.margin).padding(.vertical, 12)
        }
    }

    @ViewBuilder private func lines(_ lines: [FieldLine], currency: String, type: CustomerType) -> some View {
        CustomerIncludedLabel(type: type)
                    CustomerIncludedLines(lines: lines, type: type, rows: paperLinesTotal(lines).map { [CustomerAmountRow(label: "Total", amount: money($0, currency: currency), emphasis: true)] } ?? [])
    }

    @ViewBuilder private func estimateLines(_ lines: [FieldLine], currency: String, type: CustomerType, expectedTotal: Int? = nil) -> some View {
        if let display = customerEstimateDisplay(lines, currency: currency),
           expectedTotal.map({ $0 == display.amounts.total }) != false {
            CustomerIncludedLabel(type: type)
            CustomerIncludedLines(lines: display.lines, type: type,
                                  rows: customerAmountRows(display.amounts, currency: currency, invoice: false,
                                                           totalLabel: expectedTotal == nil ? "Total" : "Option total"))
        } else {
            Text("These amounts couldn't be verified. Hand the device back to your technician.")
                .font(Theme.customerFont(type.body))
        }
    }
}

/// Paper 38B's section label: 13 Semibold, muted, 4 in from the card's edge.
private func customerSectionLabel(_ title: String) -> some View {
    Text(title)
        .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
        .accessibilityAddTraits(.isHeader)
        .padding(.horizontal, 4)
}

/// One document on Customer view's home (Paper "Customer view"): the name over
/// "EST-1042 · Waiting for you", the amount at the trailing edge, then a chevron. The card it sits
/// on draws the surface and the hairlines. At accessibility sizes the amount drops under the name.
private struct CustomerHomeDocumentRow: View {
    let title: String
    let reference: String
    /// The document's state as a word; `tint` colours it (Paper draws "Waiting for you" in the warning word colour).
    let word: String
    var tint: Color? = nil
    var detail: String? = nil
    var amount: String? = nil
    var chevron = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                subtitle.fixedSize(horizontal: false, vertical: true)
                if stacked, let amount { amountText(amount) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !stacked, let amount { amountText(amount).fixedSize() }
            if chevron {
                PaperChevron()
                    .foregroundStyle(Theme.muted).accessibilityHidden(true)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(.leading, PaperCardMetrics.inset).padding(.trailing, 12).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: CustomerModeStyle.target, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var subtitle: Text {
        let quiet = Theme.font(14)
        var line = Text("\(reference) \u{00B7} ").font(quiet).foregroundStyle(Theme.muted)
            + Text(word).font(Theme.font(14, weight: tint == nil ? .regular : .medium))
                .foregroundStyle(tint ?? Theme.muted)
        if let detail, !detail.isEmpty {
            line = line + Text(" \u{00B7} \(detail)").font(quiet).foregroundStyle(Theme.muted)
        }
        return line
    }

    private func amountText(_ amount: String) -> some View {
        Text(amount).font(Theme.font(16, weight: .medium))
            .foregroundStyle(Theme.foreground).lineLimit(1).minimumScaleFactor(0.7)
    }
}

/// "Your details" on Customer view's home (Paper): Phone, Email and Address, each with Edit.
/// Until the customer's record has loaded it is one row; either way the whole card opens the form.
private struct CustomerHomeDetailsCard: View {
    @ObservedObject var model: CustomerSelfEditModel
    @EnvironmentObject private var api: APIClient
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            if let draft = model.draft {
                fact("Phone", draft.phone)
                WellDivider()
                fact("Email", draft.email)
                WellDivider()
                fact("Address", draft.address)
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check your details").font(Theme.font(16, weight: .medium))
                            .foregroundStyle(Theme.foreground)
                        Text("Name, phone, email, addresses and how to reach you")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    PaperChevron()
                        .foregroundStyle(Theme.muted).accessibilityHidden(true)
                }
                .padding(.leading, PaperCardMetrics.inset).padding(.trailing, 12).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: CustomerModeStyle.target, alignment: .leading)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelBackground()
        .contentShape(Rectangle())
        // The same read the form makes; it keeps the draft, so opening the form does not load twice.
        .task { await model.load(api: api) }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let shown = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                             : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            Text(label).font(Theme.font(15)).foregroundStyle(Theme.muted)
                .frame(width: stacked ? nil : 64, alignment: .leading)
            Text(shown.isEmpty ? "Not added" : shown).font(Theme.font(16, weight: .medium))
                .foregroundStyle(shown.isEmpty ? Theme.muted : Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(shown.isEmpty ? "Add" : "Edit").font(Theme.font(15, weight: .semibold))
                .foregroundStyle(Theme.brandText)
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: CustomerModeStyle.target, alignment: .leading)
    }
}

/// Paper "Customer view": handing back is the quiet pill (a lock and the words) under the commit.
/// The words wrap at large text so the pill grows instead of clipping.
private struct CustomerHandBackPill: View {
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView() }
                else { PaperIcon(.customerLock, size: 18, color: Theme.foreground).accessibilityHidden(true) }
                // Paper 38B's words. The spoken name stays the full sentence the other customer
                // screens use, which is also what the UI tests look for.
                Text("Hand back to technician").font(Theme.font(16, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.quietFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Hand back to technician")
        .disabled(busy)
    }
}

extension PaperGlyph {
    /// Paper 38B's lock on "Hand back to technician" (18 box, 1.6 stroke).
    static let customerLock = PaperGlyph(box: 18, [.rect(3.5, 8, 11, 7.5, rx: 2, 1.6), .stroke("M6 8V5.8a3 3 0 0 1 6 0V8", 1.6)])
}
