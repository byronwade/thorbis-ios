import SwiftUI

private enum CustomerJobPaper: Hashable {
    case estimate(EstimateRecord)
    case invoice(InvoiceRecord)
}

/// Lives inside one CustomerModeContainer: browsing never exposes technician controls.
struct JobCustomerDocumentsView: View {
    let scope: JobDocumentScope
    @ObservedObject var documents: JobDocumentCollections
    let jobTitle: String
    let customerName: String
    let handBack: () -> Void
    let onUnlocked: () -> Void
    /// Called only after device-owner authentication, before the cover closes.
    let requestPayment: (String) -> Void
    let invoiceUpdated: (InvoiceRecord) -> Void
    var authenticateOwner: @MainActor (String) async -> Bool = { await StaffUnlock.unlock(reason: $0) }

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    private var estimates: JobDocumentRead<EstimateRecord>? { documents.estimates }
    private var invoices: JobDocumentRead<InvoiceRecord>? { documents.invoices }
    @State private var paper: CustomerJobPaper?
    @State private var openingID: String?
    @State private var paymentModel: InvoicePaymentCollectionModel?
    @State private var error: String?
    @State private var unlocking = false

    private var currentWorkspace: Bool { session.activeOrganization?.id == scope.organizationID }
    private var canViewEstimates: Bool { session.can("estimate.view", feature: "estimates") }
    private var canViewInvoices: Bool { session.can("invoice.view", feature: "invoicing") }

    var body: some View {
        Group {
            if currentWorkspace {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Your job documents").font(Theme.font(28, weight: .medium))
                                .accessibilityAddTraits(.isHeader)
                            Text(jobTitle).font(Theme.font(20)).fixedSize(horizontal: false, vertical: true)
                            Text("JOB-\(scope.jobID.suffix(4).uppercased()) · \(customerName)")
                                .font(Theme.font(15)).foregroundStyle(Theme.muted)
                        }
                        if let error { ErrorBanner(message: error) { await refresh() } }
                        if estimates?.isComplete == false || invoices?.isComplete == false {
                            ErrorBanner(message: "Some documents couldn't be refreshed. Please try again to see everything.") { await refresh() }
                        }
                        if canViewEstimates { estimateRows }
                        if canViewInvoices { invoiceRows }
                    }
                    .padding(.horizontal, Theme.gutter).padding(.vertical, 16)
                    .frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("customer-job-documents-list")
                .refreshable { await refresh() }
            } else {
                Text("Hand the device back to your technician to reload this job.")
                    .font(Theme.font(20)).padding(Theme.gutter)
            }
        }
        .navigationTitle("Documents")
        .safeAreaInset(edge: .bottom) {
            CustomerCommitButton(title: "Hand back to the technician", icon: "hand.wave", busy: openingID != nil, action: handBack)
                .padding(.horizontal, Theme.gutter).padding(.vertical, 12).background(Theme.background)
        }
        .navigationDestination(item: $paper) { destination in
            destinationView(destination)
                .disabled(unlocking)
                .navigationTitle(reference(destination))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
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
        .task(id: session.generation) {
            paper = nil
            paymentModel = nil
            await refresh()
        }
    }

    private var estimateRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaperGroupHeader(title: "Estimates", count: (estimates?.records.count ?? 0) + (estimates?.unavailableIDs.count ?? 0))
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

    private var invoiceRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaperGroupHeader(title: "Invoices", count: invoices?.records.count ?? 0)
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
                    onApproved: { _ in Task { await refresh() } }, onDone: handBack)
            } else {
                CustomerJobReadOnlyPaper(estimate: estimate, handBack: handBack)
            }
        case .invoice(let invoice):
            if ["issued", "paid"].contains(invoice.status) {
                CustomerInvoicePresentation(invoice: invoice, customerName: customerName,
                    canSign: session.can("invoice.edit", feature: "invoicing"),
                    onPay: paymentModel?.canRecordPayment == true && session.can("invoice.payment.create", feature: "payments")
                        ? { Task { await pay(invoice.id) } } : nil,
                    onSigned: { updated in
                        guard scope.contains(updated), updated.id == invoice.id else { return }
                        documents.replaceInvoice(updated)
                        paymentModel?.acceptInvoiceMutationResponse(updated)
                        paper = .invoice(updated)
                        invoiceUpdated(updated)
                    }, onDone: handBack)
            } else {
                CustomerJobReadOnlyPaper(invoice: invoice, handBack: handBack)
            }
        }
    }

    private func reference(_ destination: CustomerJobPaper) -> String {
        switch destination {
        case .estimate(let estimate): "EST-\(estimate.id.suffix(4).uppercased())"
        case .invoice(let invoice): "INV-\(invoice.id.suffix(4).uppercased())"
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(Theme.font(18)).foregroundStyle(Theme.muted).padding(.vertical, 8)
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

    private func openEstimate(_ id: String) async {
        guard openingID == nil, currentWorkspace, canViewEstimates else { return }
        openingID = id
        defer { openingID = nil }
        let generation = session.generation
        let published = await documents.loadEstimates(scope: scope, api: api) {
            session.generation == generation && currentWorkspace && canViewEstimates
        }
        guard session.generation == generation, currentWorkspace, published, let read = estimates else { return }
        guard read.freshIDs.contains(id), let estimate = read.records.first(where: { $0.id == id }) else {
            error = "This estimate couldn't be refreshed. Please try again."
            return
        }
        paper = .estimate(estimate)
    }

    private func openInvoice(_ id: String) async {
        guard openingID == nil, currentWorkspace, canViewInvoices else { return }
        openingID = id
        defer { openingID = nil }
        let generation = session.generation
        do {
            let invoice = try await api.fieldInvoice(id)
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
                paper = .invoice(latest)
            } else {
                paymentModel = nil
                throw Problem(title: model.loadError ?? "This invoice couldn't be refreshed", status: nil, detail: nil)
            }
        } catch is CancellationError { } catch { self.error = error.localizedDescription }
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
                        Text(estimate.title).font(Theme.font(type.heading, weight: .medium))
                        PaperStatusChip(status: estimate.status)
                        if let options = estimate.options, !options.isEmpty, estimate.status != "approved" {
                            ForEach(options) { option in
                                Text(option.title).font(Theme.font(type.heading, weight: .medium))
                                if !option.description.isEmpty { Text(option.description).font(Theme.font(type.body)) }
                                CustomerLinesCard(lines: option.lines, currency: option.currency, type: type,
                                    rows: [CustomerAmountRow(label: "Option total", amount: money(option.totalAmount, currency: option.currency), emphasis: true)])
                            }
                        } else { lines(estimate.lines, currency: estimate.lines.first?.unitPrice.currency ?? "USD", type: type) }
                    } else if let invoice {
                        Text("Invoice").font(Theme.font(type.heading, weight: .medium))
                        PaperStatusChip(status: invoice.status)
                        lines(invoice.lines, currency: invoice.currency, type: type)
                    }
                }
                .padding(Theme.gutter).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
            CustomerCommitButton(title: "Hand back to the technician", icon: "hand.wave", busy: false, action: handBack)
                .padding(Theme.gutter)
        }
    }

    private func lines(_ lines: [FieldLine], currency: String, type: CustomerType) -> some View {
        CustomerLinesCard(lines: lines, currency: currency, type: type,
            rows: paperLinesTotal(lines).map { [CustomerAmountRow(label: "Total", amount: money($0, currency: currency), emphasis: true)] } ?? [])
    }
}
