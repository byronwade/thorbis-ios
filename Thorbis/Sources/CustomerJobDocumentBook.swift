import SwiftUI

/// Read-only browsing; consent and signature remain in their existing separate destinations.
struct CustomerJobDocumentBook: View {
    let scope: JobDocumentScope
    let sourceGeneration: UUID?
    let estimates: [EstimateRecord]
    let invoices: [InvoiceRecord]
    let freshEstimates: Set<String>
    let freshInvoices: Set<String>
    let unavailableEstimates: [String]
    let actionError: String?
    let refresh: () async -> Void
    let reviewEstimate: (String) -> Void
    let signInvoice: (String) -> Void
    let payInvoice: (String) -> Void
    let canSignInvoice: Bool
    let canPayInvoice: Bool
    let onSelectionChanged: () -> Void
    @State private var selection: CustomerJobDocumentSelection
    @EnvironmentObject private var api: APIClient
    #if DEBUG
    @State private var previewDocumentChanged = false
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(scope: JobDocumentScope, sourceGeneration: UUID?, estimates: [EstimateRecord], invoices: [InvoiceRecord],
         freshEstimates: Set<String>, freshInvoices: Set<String>, unavailableEstimates: [String],
         initial: CustomerJobDocumentID, actionError: String?, refresh: @escaping () async -> Void,
         reviewEstimate: @escaping (String) -> Void, signInvoice: @escaping (String) -> Void,
         payInvoice: @escaping (String) -> Void, canSignInvoice: Bool, canPayInvoice: Bool,
         onSelectionChanged: @escaping () -> Void = {}) {
        self.scope = scope
        self.sourceGeneration = sourceGeneration
        self.estimates = estimates
        self.invoices = invoices.filter(scope.contains)
        self.freshEstimates = freshEstimates
        self.freshInvoices = freshInvoices
        self.unavailableEstimates = unavailableEstimates
        self.actionError = actionError
        self.refresh = refresh
        self.reviewEstimate = reviewEstimate
        self.signInvoice = signInvoice
        self.payInvoice = payInvoice
        self.canSignInvoice = canSignInvoice
        self.canPayInvoice = canPayInvoice
        self.onSelectionChanged = onSelectionChanged
        _selection = State(initialValue: .init(ids: estimates.map { .estimate($0.id) }
            + unavailableEstimates.map { .estimate($0) }
            + invoices.filter(scope.contains).map { .invoice($0.id) }, selected: initial))
    }

    private var ids: [CustomerJobDocumentID] {
        estimates.map { .estimate($0.id) } + unavailableEstimates.map { .estimate($0) } + invoices.map { .invoice($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let actionError {
                CustomerProblemBanner(message: actionError, actionTitle: "Try again") { await refresh() }
                    .padding(.horizontal, Theme.gutter).padding(.bottom, 12)
            }
            pagingControls
            if selection.selected == nil {
                ScrollView {
                    CustomerStateMessage(symbol: "doc.text.magnifyingglass", title: "This document isn’t available any more",
                                         message: "Choose another document above, or go back to your job documents.")
                        .padding(.horizontal, Theme.gutter)
                }
            } else {
                TabView(selection: Binding(get: { selection.selected }, set: { if let id = $0 { selection.select(id) } })) {
                    ForEach(selection.ids) { id in
                        page(id).tag(Optional(id))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .accessibilityIdentifier("customer-document-pages")
            }
        }
        .navigationTitle(selection.selected?.reference ?? "Documents")
        .onChange(of: ids) { _, value in selection.reconcile(value) }
        .onChange(of: selection.selected) { _, _ in onSelectionChanged() }
        #if DEBUG
        .task {
            let args = ProcessInfo.processInfo.arguments
            guard PaperPreview.isJobDocumentsPreview,
                  args.contains("--paper-preview-description-stale") || args.contains("--paper-preview-description-replaced") else { return }
            // Count from the open Description, so the UI test's taps to reach it can't use up the delay.
            while !PaperPreview.descriptionOpened {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
            }
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled { previewDocumentChanged = true }
        }
        #endif
        .background(Theme.canvas)
    }

    private var pagingControls: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize { compactControls }
            else {
                ViewThatFits(in: .horizontal) {
                    regularControls.fixedSize(horizontal: true, vertical: true)
                    compactControls
                }
            }
        }
        .font(Theme.customerFont(17)).buttonStyle(.plain)
        .padding(.horizontal, Theme.gutter).padding(.bottom, 12)
    }

    private var regularControls: some View {
        VStack(spacing: 4) {
            HStack(spacing: 16) {
                previousButton
                documentMenu
                nextButton
            }
            Text(selection.position).foregroundStyle(Theme.muted)
                .accessibilityIdentifier("customer-document-position")
        }
        .frame(maxWidth: .infinity)
    }

    private var compactControls: some View {
        VStack(spacing: 4) {
            HStack {
                previousButton.labelStyle(.iconOnly).font(.system(size: 24))
                Spacer(minLength: 8)
                Text(compactPosition).foregroundStyle(Theme.muted)
                    .accessibilityLabel(selection.position)
                    .accessibilityIdentifier("customer-document-position")
                Spacer(minLength: 8)
                nextButton.labelStyle(.iconOnly).font(.system(size: 24))
            }
            documentMenu.labelStyle(.titleOnly).frame(maxWidth: .infinity)
        }
    }

    private var compactPosition: String {
        guard let selected = selection.selected, let index = selection.ids.firstIndex(of: selected) else { return "—" }
        return "\(index + 1) of \(selection.ids.count)"
    }

    private var previousButton: some View {
        Button { move(selection.previous) } label: {
            Label("Previous", systemImage: "chevron.left")
                .frame(minWidth: 56, minHeight: 56).contentShape(Rectangle())
        }
        .accessibilityLabel("Previous document").disabled(selection.previous == nil)
    }

    private var nextButton: some View {
        Button { move(selection.next) } label: {
            Label("Next", systemImage: "chevron.right")
                .frame(minWidth: 56, minHeight: 56).contentShape(Rectangle())
        }
        .accessibilityLabel("Next document").disabled(selection.next == nil)
    }

    private var documentMenu: some View {
        ThorbisMenu(items: selection.ids.map { id in
            ThorbisMenuItem(id.reference, isSelected: id == selection.selected) { selection.select(id) }
        }, title: "Job documents", accessibilityLabel: "Choose a job document", customerFacing: true) {
            Label("All documents", systemImage: "square.stack")
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 56, minHeight: 56).contentShape(Rectangle())
        }
    }

    private func move(_ id: CustomerJobDocumentID?) {
        guard let id else { return }
        if reduceMotion { selection.select(id) }
        else { withAnimation(.easeInOut(duration: 0.2)) { selection.select(id) } }
    }

    @ViewBuilder private func page(_ id: CustomerJobDocumentID) -> some View {
        switch id {
        case .estimate(let value):
            if let record = estimates.first(where: { $0.id == value }) {
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                let effectiveRecord = previewDocumentChanged && args.contains("--paper-preview-description-replaced")
                    ? PaperPreview.replacedDescriptionEstimate(record) : record
                let effectiveFresh = freshEstimates.contains(value) && !(previewDocumentChanged && args.contains("--paper-preview-description-stale"))
                #else
                let effectiveRecord = record
                let effectiveFresh = freshEstimates.contains(value)
                #endif
                CustomerEstimateBookPage(scope: scope, sourceGeneration: sourceGeneration, estimate: effectiveRecord, fresh: effectiveFresh, active: selection.selected == id, activation: selection.activation,
                    refresh: refresh, review: { reviewEstimate(value) })
            } else {
                ScrollView {
                    CustomerStateMessage(symbol: "arrow.clockwise", title: "This estimate needs a refresh",
                                         message: "Refresh to see it. Your other job documents are still here.",
                                         actionTitle: "Refresh documents") { Task { await refresh() } }
                        .padding(.horizontal, Theme.gutter)
                }
            }
        case .invoice(let value):
            if let record = invoices.first(where: { $0.id == value }) {
                CustomerInvoiceBookPage(invoice: record, scope: scope, sourceGeneration: sourceGeneration, api: api, fresh: freshInvoices.contains(value),
                    canSign: canSignInvoice, canPay: canPayInvoice, active: selection.selected == id, activation: selection.activation,
                    refresh: refresh, sign: { signInvoice(value) }, pay: { payInvoice(value) })
            }
        }
    }
}

private struct CustomerEstimateBookLoadID: Hashable {
    let estimate: EstimateRecord
    let fresh: Bool
    let active: Bool
    let activation: UUID
    let sessionGeneration: UUID
    let authorityRevision: UUID
    let apiGeneration: UUID
    let scopeRevision: UUID
    let retry: UUID
}

private struct CustomerEstimateBookPage: View {
    let scope: JobDocumentScope
    let sourceGeneration: UUID?
    let estimate: EstimateRecord
    let fresh: Bool
    let active: Bool
    let activation: UUID
    let refresh: () async -> Void
    let review: () -> Void
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var receipt: CustomerEstimateAcceptanceReceipt?
    @State private var receiptAuthority: CustomerHandoffExitAuthority?
    @State private var receiptActivation: UUID?
    @State private var retry = UUID()
    @State private var loadToken = UUID()
    @State private var issued: CustomerIssuedEstimateRevision?
    @State private var loading = false
    @State private var error: String?
    private var type: CustomerType { CustomerType(sizeClass) }
    private var readingAccess: DocumentDescriptionAccess {
        .init(identity: .estimate(scope: scope, record: estimate, issued: issued), organizationID: scope.organizationID,
              capability: "estimate.view", feature: "estimates", sourceGeneration: sourceGeneration, fresh: fresh, active: active, scopeValid: scope.contains(estimate, requestedID: estimate.id))
    }
    private var options: [FieldEstimateOption] { issued.map { $0.options ?? [] } ?? estimate.options ?? [] }
    private var lines: [FieldLine] { issued?.lines ?? estimate.lines }
    private var currency: String? { issued?.currency ?? lines.first?.unitPrice.currency }
    // Issued revisions have an explicit USD currency and at least one base line. Drafts can be empty.
    private var issuedStructureValid: Bool {
        issued.map { !$0.lines.isEmpty && $0.currency == "USD" } ?? true
    }
    private var moneyVerified: Bool {
        guard issuedStructureValid else { return false }
        if options.isEmpty {
            guard !lines.isEmpty, let currency, let display = customerEstimateDisplay(lines, currency: currency) else { return false }
            return issued.map { display.amounts.total == $0.totalAmount } ?? true
        }
        return options.allSatisfy { option in
            guard !option.lines.isEmpty, option.currency == "USD",
                  let display = customerEstimateDisplay(option.lines, currency: option.currency) else { return false }
            return display.amounts.total == option.totalAmount
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if estimate.status != "approved" || (readingAccess.permits(session) &&
                        receiptActivation == activation && receiptAuthority?.isCurrent(api: api, session: session) == true &&
                        issued?.matchesDetails(for: estimate) == true) {
                        Text(issued?.title ?? estimate.title).font(Theme.customerFont(type.heading, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        if fresh { CustomerStatusWord(status: estimate.status, type: type) }
                        else { Text("Status needs refresh").font(Theme.customerFont(type.body)).foregroundStyle(Theme.muted) }
                    }
                    if !fresh {
                        Text("This copy needs a refresh before you can decide.").font(Theme.customerFont(type.body))
                    } else if loading { CustomerSkeleton(caption: "Opening the current estimate…", heading: false) }
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--paper-preview-handoff-receipt-return") {
                        Button("Remove sample link") { JobEstimateHandoffPreview.shared.removeFirst() }
                    }
                    if ProcessInfo.processInfo.arguments.contains("--paper-preview-handoff-receipt-retirement") {
                        Button("Retire receipt authority") { api.invalidateRequests() }
                    }
                    #endif
                    if let error { CustomerProblemBanner(message: error, actionTitle: "Try again") { retry = UUID() } }
                    if estimate.status == "approved" {
                        if fresh, readingAccess.permits(session), let issued, let receipt, let receiptAuthority,
                           receiptActivation == activation, receiptAuthority.isCurrent(api: api, session: session), issued.matchesDetails(for: estimate), (try? receipt.validate(for: issued)) != nil {
                            if let title = receipt.optionTitle {
                                Text(title).font(Theme.customerFont(type.heading, weight: .medium))
                            }
                            estimateLines(receipt.lines, currency: receipt.currency, expectedTotal: receipt.totalAmount,
                                          requireUSDCurrency: true, descriptionContext: "EST-\(estimate.id.suffix(4).uppercased())")
                        }
                    } else if estimate.status != "sent" || issued != nil {
                        if !issuedStructureValid {
                            Text("These amounts couldn't be verified. Hand the device back to your technician.")
                                .font(Theme.customerFont(type.body)).fixedSize(horizontal: false, vertical: true)
                        } else if options.isEmpty {
                            estimateLines(lines, currency: currency, expectedTotal: issued?.totalAmount,
                                          descriptionContext: "EST-\(estimate.id.suffix(4).uppercased())")
                        } else {
                            if estimate.status == "approved" {
                                Text("These are the quoted packages. The approved package selection isn't available here.")
                                    .font(Theme.customerFont(type.body)).foregroundStyle(Theme.muted)
                            }
                            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                                Text(option.title).font(Theme.customerFont(type.heading, weight: .medium))
                                if !option.description.isEmpty { ReadOnlyDocumentDescription(text: option.description, fontSize: type.body, access: readingAccess, customerFacing: true,
                                                                                              accessibilityContext: "EST-\(estimate.id.suffix(4).uppercased()), package \(index + 1)") }
                                estimateLines(option.lines, currency: option.currency, expectedTotal: option.totalAmount, requireUSDCurrency: true,
                                              descriptionContext: "EST-\(estimate.id.suffix(4).uppercased()), package \(index + 1)")
                            }
                        }
                    }
                }
                .padding(Theme.gutter).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("customer-estimate-page-\(estimate.id)")
            if fresh, estimate.status == "sent", issued != nil, !loading, moneyVerified {
                CustomerPresentationCommit(title: "Review and sign", enabled: true, busy: false, type: type, action: review)
                    .accessibilityIdentifier("customer-book-review-sign")
                    .padding(Theme.gutter)
            } else if !fresh {
                CustomerSecondaryButton(title: "Refresh documents", type: type) { Task { await refresh() } }.padding(Theme.gutter)
            }
        }
        .task(id: CustomerEstimateBookLoadID(estimate: estimate, fresh: fresh, active: active, activation: activation,
            sessionGeneration: session.generation, authorityRevision: session.authorityRevision,
            apiGeneration: api.requestGeneration, scopeRevision: api.savedCopyScopeRevision, retry: retry)) { await load() }
    }

    @ViewBuilder private func estimateLines(_ lines: [FieldLine], currency: String?, expectedTotal: Int?,
                                            requireUSDCurrency: Bool = false, descriptionContext: String) -> some View {
        if !lines.isEmpty, let currency, (!requireUSDCurrency || currency == "USD"),
           let display = customerEstimateDisplay(lines, currency: currency),
           expectedTotal.map({ $0 == display.amounts.total }) ?? true {
            CustomerIncludedLabel(type: type)
                    CustomerIncludedLines(lines: display.lines, type: type, rows: customerAmountRows(display.amounts, currency: currency, invoice: false), readingAccess: readingAccess, descriptionContext: descriptionContext)
        } else {
            Text("These amounts couldn't be verified. Hand the device back to your technician.")
                .font(Theme.customerFont(type.body)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func load() async {
        let token = UUID(); loadToken = token
        receipt = nil; receiptAuthority = nil; receiptActivation = nil; issued = nil; error = nil; loading = false
        guard fresh, active, scope.contains(estimate, requestedID: estimate.id),
              estimate.status == "sent" || estimate.status == "approved",
              sourceGeneration == session.generation,
              let authority = CustomerHandoffExitAuthority.capture(api: api, session: session) else { return }
        let current: @MainActor () -> Bool = {
            !Task.isCancelled && loadToken == token && authority.isCurrent(api: api, session: session) &&
            session.can("estimate.view", feature: "estimates")
        }
        guard current() else { return }
        loading = true
        defer { if loadToken == token { loading = false } }
        func verifyMembership() async throws {
            let job = try await api.liveFieldJob(scope.jobID)
            guard current() else { throw CancellationError() }
            guard job.id == scope.jobID, job.organizationId == scope.organizationID,
                  job.customerId == scope.customerID else {
                throw Problem(title: "This job changed", status: 409, detail: nil)
            }
            if job.estimateId != estimate.id {
                let link = try await api.liveFieldJobEstimateLink(scope.jobID, estimateID: estimate.id)
                guard current() else { throw CancellationError() }
                guard link.jobId == scope.jobID, link.estimateId == estimate.id else {
                    throw Problem(title: "This estimate is no longer on this job", status: 409, detail: nil)
                }
            }
        }
        do {
            if estimate.status == "approved" { try await verifyMembership() }
            let revision = try await api.customerIssuedEstimateRevision(for: estimate,
                allowApprovedForReading: estimate.status == "approved", currentAuthority: current)
            if estimate.status == "approved" {
                guard let signed = try await api.customerEstimateAcceptanceReceipt(for: revision, currentAuthority: current) else {
                    if current() { error = "The signed estimate isn't available. Hand the device back to your technician." }
                    return
                }
                try await verifyMembership()
                guard current() else { return }
                receipt = signed; receiptAuthority = authority; receiptActivation = activation
            }
            guard current() else { return }
            issued = revision
        } catch is CancellationError {
        } catch is CustomerIssuedEstimateAmountsUnavailable {
            if current() { self.error = "These amounts couldn't be verified. Hand the device back to your technician." }
        } catch {
            if current() { self.error = error.customerSentence(.openEstimate) }
        }
    }
}

private struct CustomerInvoiceBookLoadID: Hashable {
    let invoice: InvoiceRecord
    let fresh: Bool
    let active: Bool
    let activation: UUID
    let sessionGeneration: UUID
    let authorityRevision: UUID
    let apiGeneration: UUID
    let scopeRevision: UUID
    let retry: UUID
}

private struct CustomerInvoiceBookPage: View {
    let original: InvoiceRecord
    let scope: JobDocumentScope
    let sourceGeneration: UUID?
    let fresh: Bool
    let canSign: Bool
    let canPay: Bool
    let active: Bool
    let activation: UUID
    let refresh: () async -> Void
    let sign: () -> Void
    let pay: () -> Void
    @StateObject private var model: InvoicePaymentCollectionModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var customerSummary: CustomerInvoiceSummary?
    @State private var summaryAuthority: CustomerHandoffExitAuthority?
    @State private var summaryActivation: UUID?
    @State private var summaryToken = UUID()
    @State private var summaryRetry = UUID()
    @State private var summaryLoading = false
    @State private var summaryError: String?
    @State private var showPayments = false
    @State private var choseInitialPaymentVisibility = false

    init(invoice: InvoiceRecord, scope: JobDocumentScope, sourceGeneration: UUID?, api: APIClient, fresh: Bool,
         canSign: Bool, canPay: Bool, active: Bool, activation: UUID, refresh: @escaping () async -> Void,
         sign: @escaping () -> Void, pay: @escaping () -> Void) {
        original = invoice; self.scope = scope; self.sourceGeneration = sourceGeneration; self.fresh = fresh; self.canSign = canSign; self.canPay = canPay
        self.active = active; self.activation = activation; self.refresh = refresh; self.sign = sign; self.pay = pay
        _model = StateObject(wrappedValue: InvoicePaymentCollectionModel(api: api, invoiceID: invoice.id, expectedJobScope: scope))
    }

    private var type: CustomerType { CustomerType(sizeClass) }
    private var invoice: InvoiceRecord { model.invoice ?? original }
    private var readingAccess: DocumentDescriptionAccess {
        .init(identity: .invoice(scope: scope, record: invoice), organizationID: scope.organizationID,
              capability: "invoice.view", feature: "invoicing", sourceGeneration: sourceGeneration, fresh: fresh, active: active, scopeValid: scope.contains(invoice))
    }
    private var verifiedSummary: CustomerInvoiceSummary? {
        guard fresh, readingAccess.permits(session), let summary = customerSummary, let authority = summaryAuthority,
              summaryActivation == activation, authority.isCurrent(api: api, session: session),
              summary.matches(scope: scope, invoiceID: invoice.id, linesRevision: invoice.linesRevision) else { return nil }
        return summary
    }
    private var customerLines: [FieldLine] {
        verifiedSummary?.lines.map { FieldLine(id: $0.id, description: $0.description, quantity: $0.quantity, unitPrice: $0.unitPrice, source: nil) } ?? []
    }
    private var amounts: CustomerDocumentAmounts? {
        guard let summary = verifiedSummary else { return nil }
        return CustomerDocumentAmounts(lines: customerLines, currency: summary.currency, amountPaid: summary.amountPaid)
    }
    private var signed: Bool { invoice.customerAuthorization?.linesRevision == invoice.linesRevision }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(invoice.origin == "estimate_deposit" ? "Deposit invoice" : "Invoice")
                        .font(Theme.customerFont(type.heading, weight: .medium)).accessibilityIdentifier("customer-invoice-summary")
                    if let summary = verifiedSummary, let amounts {
                        CustomerStatusWord(status: summary.status, type: type)
                        Text("Customer summary · not the signed invoice").font(Theme.customerFont(type.small)).foregroundStyle(Theme.muted)
                        let balance = CustomerInvoiceBalanceSummary(status: summary.status, fresh: true, amounts: amounts,
                            historyReconciled: model.historyComplete && model.paymentTotalCents == summary.amountPaid)
                        Text(balance.title).font(Theme.customerFont(type.body)).foregroundStyle(Theme.muted)
                        if let headlineAmount = balance.amount {
                            Text(money(headlineAmount, currency: summary.currency))
                                .font(Theme.customerFont(type.total, weight: .medium)).monospacedDigit()
                        }
                        CustomerIncludedLabel(type: type)
                        CustomerIncludedLines(lines: customerLines, type: type, rows: customerAmountRows(amounts, currency: summary.currency, invoice: summary.status != "void"), readingAccess: readingAccess,
                                              descriptionContext: "INV-\(invoice.id.suffix(4).uppercased())")
                        if !signed && canSign && ["issued", "paid"].contains(summary.status) {
                            Text("Signing this customer summary isn't available yet. Ask your technician for help.")
                                .font(Theme.customerFont(type.body)).foregroundStyle(Theme.muted)
                        }
                    } else if summaryLoading {
                        CustomerSkeleton(caption: "Opening your invoice…", heading: false)
                    } else {
                        CustomerProblemBanner(message: summaryError ?? "Invoice details aren't available. Hand the device back to your technician.",
                                              actionTitle: "Try again") { summaryRetry = UUID() }
                    }
                    if model.isLoading {
                        SkeletonRows(count: 2, leading: false, inset: 0)
                            .accessibilityLabel("Loading your payments")
                    } else if !model.historyComplete {
                        CustomerProblemBanner(message: "Payments couldn't be loaded. Try again to see payment history.",
                                              actionTitle: "Try again") {
                            #if DEBUG
                            if PaperPreview.isJobDocumentsPreview { PaperPreviewProtocol.restoreDocumentHistory() }
                            #endif
                            await model.load()
                            summaryRetry = UUID()
                        }
                    } else {
                        paymentHistory
                        if let summary = verifiedSummary, model.paymentTotalCents != summary.amountPaid {
                            CustomerProblemBanner(message: "Payments are still updating. Refresh to confirm the balance.",
                                                  symbol: "arrow.clockwise", actionTitle: "Refresh payments") {
                                #if DEBUG
                                if PaperPreview.isJobDocumentsPreview { PaperPreviewProtocol.restoreDocumentHistory() }
                                #endif
                                await model.load()
                                summaryRetry = UUID()
                            }
                        }
                    }
                }
                .padding(Theme.gutter).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
            if let summary = verifiedSummary, let amounts, model.invoice != nil,
               summary.status == "issued", (signed || !canSign), canPay, model.canRecordPayment,
               !model.isLoading, model.historyComplete, model.paymentTotalCents == summary.amountPaid, amounts.due > 0 {
                CustomerPresentationCommit(title: "Pay \(money(amounts.due, currency: summary.currency))", enabled: true, busy: false, type: type, action: pay)
                    .padding(Theme.gutter)
            } else if !fresh {
                CustomerSecondaryButton(title: "Refresh documents", type: type) { Task { await refresh() } }.padding(Theme.gutter)
            }
        }
        .task(id: original) { await model.load() }
        .task(id: CustomerInvoiceBookLoadID(invoice: invoice, fresh: fresh, active: active, activation: activation,
            sessionGeneration: session.generation, authorityRevision: session.authorityRevision,
            apiGeneration: api.requestGeneration, scopeRevision: api.savedCopyScopeRevision, retry: summaryRetry)) { await loadSummary() }
        .onChange(of: model.historyComplete) { _, complete in
            guard complete, !choseInitialPaymentVisibility else { return }
            // Show a short history immediately; keep large histories easy to scan.
            showPayments = model.payments.count <= 2
            choseInitialPaymentVisibility = true
        }
    }

    private func loadSummary() async {
        let token = UUID(); summaryToken = token
        summaryError = nil; summaryLoading = false
        guard fresh, active, scope.contains(invoice), sourceGeneration == session.generation,
              let authority = CustomerHandoffExitAuthority.capture(api: api, session: session) else {
            customerSummary = nil; summaryAuthority = nil; summaryActivation = nil
            return
        }
        func current() -> Bool {
            !Task.isCancelled && summaryToken == token && authority.isCurrent(api: api, session: session) &&
            session.can("invoice.view", feature: "invoicing")
        }
        guard current() else { return }
        summaryLoading = true
        defer { if summaryToken == token { summaryLoading = false } }
        do {
            let latest = try await api.liveFieldInvoice(invoice.id)
            guard current() else { return }
            guard scope.contains(latest), latest.id == invoice.id, latest.linesRevision == invoice.linesRevision else {
                throw Problem(title: "This invoice changed", status: 409, detail: nil)
            }
            let value = try await api.customerInvoiceSummary(scope: scope, invoiceID: latest.id,
                linesRevision: latest.linesRevision, currentAuthority: current)
            guard current() else { return }
            customerSummary = value; summaryAuthority = authority; summaryActivation = activation
        } catch is CancellationError {
        } catch {
            if current() { summaryError = "Invoice details aren't available. Hand the device back to your technician." }
        }
    }

    private var paymentHistory: some View {
        DisclosureGroup(isExpanded: $showPayments) {
            if model.payments.isEmpty { Text("No payments yet.").font(Theme.customerFont(type.body)).padding(.vertical, 12) }
            ForEach(model.payments.sorted { $0.recordedAt > $1.recordedAt }) { payment in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(payment.method == "ach" ? "Bank transfer" : FieldPaymentMethod(rawValue: payment.method)?.displayName ?? "Payment")
                        Spacer(minLength: 8)
                        Text(money(payment.amount.amount, currency: payment.amount.currency)).font(Theme.customerFont(type.body)).monospacedDigit()
                    }
                    Text(customerPaymentDate(payment.recordedAt)).font(Theme.customerFont(type.small)).foregroundStyle(Theme.muted)
                    let refunded = payment.refundedAmount ?? (payment.status == .refunded ? payment.amount.amount : 0)
                    if refunded > 0 {
                        Text("Refunded \(money(refunded, currency: payment.amount.currency))").font(Theme.customerFont(type.body))
                        if let date = payment.refundedAt { Text(customerPaymentDate(date)).font(Theme.customerFont(type.small)).foregroundStyle(Theme.muted) }
                        Text("Received after refund \(money(payment.netAmount?.amount ?? 0, currency: payment.amount.currency))")
                            .font(Theme.customerFont(type.small))
                    }
                }
                .font(Theme.customerFont(type.body)).padding(.vertical, 14).accessibilityElement(children: .combine)
            }
        } label: {
            HStack {
                Text("Payments and refunds")
                Spacer(minLength: 8)
                Text("\(model.payments.count)").foregroundStyle(Theme.muted)
            }
            .font(Theme.customerFont(type.body, weight: .medium)).frame(minHeight: 56)
        }
        .tint(Theme.foreground).accessibilityIdentifier("customer-payment-history")
    }
}

private func customerPaymentDate(_ raw: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let fractional = formatter.date(from: raw)
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = fractional ?? formatter.date(from: raw) else { return "Date unavailable" }
    return date.stampLabel()
}
