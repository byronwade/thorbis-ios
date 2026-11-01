import SwiftUI

private enum CustomerJobPaper: Hashable {
    case estimate(EstimateRecord)
    case invoice(InvoiceRecord, signing: Bool)
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
    private var estimates: JobDocumentRead<EstimateRecord>? { documents.estimates }
    private var invoices: JobDocumentRead<InvoiceRecord>? { documents.invoices }
    @State private var paper: CustomerJobPaper?
    @State private var book: CustomerJobDocumentID?
    @State private var openingID: String?
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
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Your job documents").font(Theme.customerFont(28, weight: .medium))
                                .accessibilityAddTraits(.isHeader)
                            Text(jobTitle).font(Theme.customerFont(20)).fixedSize(horizontal: false, vertical: true)
                            Text("JOB-\(scope.jobID.suffix(4).uppercased()) · \(customerName)")
                                .font(Theme.customerFont(17)).foregroundStyle(Theme.muted)
                        }
                        if let error { CustomerProblemBanner(message: error, actionTitle: "Try again") { await refresh() } }
                        else if estimates?.isComplete == false || invoices?.isComplete == false {
                            CustomerProblemBanner(message: "Some documents couldn't be refreshed. Try again to see everything.",
                                                  actionTitle: "Try again") { await refresh() }
                        }
                        if canViewEstimates { estimateRows }
                        if canViewInvoices { invoiceRows }
                        if canEditDetails { detailsRow }
                    }
                    .padding(.horizontal, Theme.gutter).padding(.vertical, 16)
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
            CustomerCommitButton(title: "Hand back to the technician", icon: "hand.wave", busy: openingID != nil, action: handBack)
                .padding(.horizontal, Theme.gutter).padding(.vertical, 12).background(Theme.canvas)
        }
        .thorbisDestination(item: $book) { initial in
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
                    payInvoice: { id in Task { await openInvoice(id, payment: true) } },
                    canSignInvoice: session.can("invoice.edit", feature: "invoicing"),
                    canPayInvoice: session.can("invoice.payment.create", feature: "payments"))
                    .disabled(unlocking || openingID != nil)
                    .thorbisDestination(item: $paper) { destination in
                        destinationView(destination)
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
                CustomerSelfEditForm(model: details) { editingDetails = false }
                    .navigationTitle("Your details")
                    .toolbar { ThorbisToolbarItem(placement: .topBarTrailing, customerFacing: true) { CustomerModeOwnerUnlockButton() } }
            } else {
                customerHandBackState(withAction: true)
            }
        }
        .task(id: session.generation) {
            paper = nil
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

    private var estimateRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            customerSectionLabel("Estimates", count: (estimates?.records.count ?? 0) + (estimates?.unavailableIDs.count ?? 0))
            approveEstimates
            if let estimates {
                if estimates.records.isEmpty && estimates.isComplete { empty("No estimates for this job yet.") }
                ForEach(estimates.records) { estimate in
                    Button { Task { await openEstimate(estimate.id) } } label: {
                        JobDocumentRow(estimate: estimate, fresh: estimates.freshIDs.contains(estimate.id), customerFacing: true)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("customer-estimate-\(estimate.id)")
                    .disabled(openingID != nil || !estimates.freshIDs.contains(estimate.id))
                }
                ForEach(estimates.unavailableIDs, id: \.self) { id in
                    JobDocumentRow(reference: "EST-\(id.suffix(4).uppercased())", title: "Estimate unavailable",
                                   status: "unavailable", amount: nil, fresh: false, customerFacing: true)
                        .accessibilityIdentifier("customer-estimate-unavailable-\(id)")
                }
            } else { SkeletonRows(count: 2, leading: false, inset: 0) }
        }
    }

    /// Approving goes through the job's one multi-estimate review: select one or several, review,
    /// then sign each. Already approved estimates stay listed without approving again.
    @ViewBuilder private var approveEstimates: some View {
        if handoff != nil, let estimates, estimates.records.contains(where: { $0.status == "sent" }) {
            CustomerSecondaryButton(title: "Choose estimates to approve", type: CustomerType(nil)) { approving = true }
                .accessibilityIdentifier("customer-view-approve-estimates")
                .disabled(openingID != nil)
        }
    }

    private var detailsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            customerSectionLabel("Your details")
            Button { editingDetails = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle").font(.system(size: 22)).foregroundStyle(Theme.brandText)
                        .frame(width: 30).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Check your details").font(Theme.customerFont(18, weight: .medium))
                        Text("Name, phone, email, addresses and how to reach you")
                            .font(Theme.customerFont(15)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.muted).accessibilityHidden(true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: CustomerModeStyle.target, alignment: .leading)
                .panelBackground(cornerRadius: 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Your details")
            .accessibilityHint("Check and fix your name, phone, email and addresses")
            .accessibilityIdentifier("customer-view-details")
            .disabled(openingID != nil)
        }
    }

    private var invoiceRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            customerSectionLabel("Invoices", count: invoices?.records.count ?? 0)
            if let invoices {
                if invoices.records.isEmpty && invoices.isComplete { empty("No invoices for this job yet.") }
                ForEach(invoices.records) { invoice in
                    Button { Task { await openInvoice(invoice.id) } } label: {
                        JobDocumentRow(invoice: invoice, fresh: invoices.freshIDs.contains(invoice.id), customerFacing: true)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("customer-invoice-\(invoice.id)")
                    .disabled(openingID != nil || !invoices.freshIDs.contains(invoice.id))
                }
            } else { SkeletonRows(count: 2, leading: false, inset: 0) }
        }
    }

    @ViewBuilder private func destinationView(_ destination: CustomerJobPaper) -> some View {
        switch destination {
        case .estimate(let estimate):
            if estimate.status == "sent", TechJobFlow.canShow(estimate, can: .init(
                sendEstimate: session.can("estimate.send", feature: "estimates"),
                approveEstimate: session.can("estimate.approve", feature: "estimates"))) {
                CustomerEstimatePresentation(estimate: estimate, jobID: scope.jobID, customerName: customerName,
                    returnToDocuments: {
                        returnToJobDocuments()
                    },
                    onApproved: { approved in
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
                    onSigned: { updated in
                        guard scope.contains(updated), updated.id == invoice.id else { return }
                        documents.replaceInvoice(updated)
                        paymentModel?.acceptInvoiceMutationResponse(updated)
                        paper = .invoice(updated, signing: false)
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
        paper = nil
        book = nil
        approving = false
        editingDetails = false
        handBack()
    }

    /// The session or workspace changed under the customer: only the technician can reopen it.
    /// On the home the pinned "Hand back to the technician" is the one action, so the state is
    /// words only; pushed pages have no pinned bar and carry it themselves.
    private func customerHandBackState(withAction: Bool) -> some View {
        let handBack: (() -> Void)? = withAction ? { beginHandBack() } : nil
        return CustomerStateMessage(symbol: "hand.raised", title: "Please hand the device back",
                             message: "Your technician needs to reload this job.",
                             actionTitle: withAction ? "Hand back to the technician" : nil,
                             action: handBack)
            .padding(.horizontal, Theme.gutter)
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(Theme.customerFont(18)).foregroundStyle(Theme.muted).padding(.vertical, 8)
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
        paper = nil
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
        guard openingID == nil, currentWorkspace, canViewEstimates else { return }
        openingID = id
        defer { openingID = nil }
        let generation = session.generation
        let published = await documents.loadEstimates(scope: scope, api: api) {
            session.generation == generation && currentWorkspace && canViewEstimates
        }
        guard session.generation == generation, currentWorkspace, published, let read = estimates else { return }
        guard read.freshIDs.contains(id), let estimate = read.records.first(where: { $0.id == id }) else {
            error = "This estimate couldn't be refreshed. Try again in a moment."
            return
        }
        if decision { paper = .estimate(estimate) }
        else { book = .estimate(id) }
    }

    private func openInvoice(_ id: String, decision: Bool = false, sign: Bool = false, payment: Bool = false) async {
        guard openingID == nil, currentWorkspace, canViewInvoices else { return }
        openingID = id
        defer { openingID = nil }
        let generation = session.generation
        do {
            let invoice = try await api.liveFieldInvoice(id)
            guard session.generation == generation, currentWorkspace, canViewInvoices else { return }
            guard invoice.id == id, scope.contains(invoice) else {
                throw Problem(title: "This invoice couldn't be verified for this job", status: nil, detail: nil)
            }
            let model = InvoicePaymentCollectionModel(api: api, invoiceID: id, expectedJobScope: scope)
            await model.load()
            guard session.generation == generation, currentWorkspace, canViewInvoices else { return }
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
                    paper = .invoice(latest, signing: sign)
                } else { book = .invoice(id) }
            } else {
                paymentModel = nil
                throw Problem(title: model.loadError ?? "This invoice couldn't be refreshed", status: nil, detail: nil)
            }
        } catch is CancellationError { } catch { self.error = error.customerSentence(.openInvoice) }
    }

    private func pay(_ invoiceID: String) async {
        let generation = session.generation
        guard !unlocking, currentWorkspace, paymentModel?.invoice?.id == invoiceID,
              paymentModel?.canRecordPayment == true,
              session.can("invoice.payment.create", feature: "payments") else { return }
        unlocking = true
        defer { unlocking = false }
        let unlocked = await authenticateOwner("Unlock to take payment")
        if unlocked, session.generation == generation, currentWorkspace {
            requestPayment(invoiceID)
        } else if session.generation == generation, currentWorkspace {
            error = "Your technician needs to unlock before taking payment."
        }
    }

    private func unlock() async {
        guard !unlocking else { return }
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
                                CustomerIncludedLabel(type: type)
                    CustomerIncludedLines(lines: option.lines, type: type, rows: [CustomerAmountRow(label: "Option total", amount: money(option.totalAmount, currency: option.currency), emphasis: true)])
                            }
                        } else { lines(estimate.lines, currency: estimate.lines.first?.unitPrice.currency ?? "USD", type: type) }
                    } else if let invoice {
                        Text("Invoice").font(Theme.customerFont(type.heading, weight: .medium))
                        CustomerStatusWord(status: invoice.status, type: type)
                        lines(invoice.lines, currency: invoice.currency, type: type)
                    }
                }
                .padding(Theme.gutter).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
            CustomerCommitButton(title: "Hand back to the technician", icon: "hand.wave", busy: false, action: handBack)
                .padding(Theme.gutter)
        }
    }

    @ViewBuilder private func lines(_ lines: [FieldLine], currency: String, type: CustomerType) -> some View {
        CustomerIncludedLabel(type: type)
                    CustomerIncludedLines(lines: lines, type: type, rows: paperLinesTotal(lines).map { [CustomerAmountRow(label: "Total", amount: money($0, currency: currency), emphasis: true)] } ?? [])
    }
}

/// A section label at customer size (17pt): the customer reads this screen, not the tech.
private func customerSectionLabel(_ title: String, count: Int? = nil) -> some View {
    Text(count.flatMap { $0 > 0 ? "\(title) · \($0)" : nil } ?? title)
        .font(Theme.customerFont(17, weight: .medium)).monospacedDigit().foregroundStyle(Theme.muted)
        .accessibilityAddTraits(.isHeader)
        .frame(minHeight: 32, alignment: .leading)
}
