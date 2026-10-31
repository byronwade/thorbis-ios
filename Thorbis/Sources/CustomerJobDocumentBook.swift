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
    @State private var selection: CustomerJobDocumentSelection
    @EnvironmentObject private var api: APIClient
    #if DEBUG
    @EnvironmentObject private var previewSession: SessionController
    @State private var previewDocumentChanged = false
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(scope: JobDocumentScope, sourceGeneration: UUID?, estimates: [EstimateRecord], invoices: [InvoiceRecord],
         freshEstimates: Set<String>, freshInvoices: Set<String>, unavailableEstimates: [String],
         initial: CustomerJobDocumentID, actionError: String?, refresh: @escaping () async -> Void,
         reviewEstimate: @escaping (String) -> Void, signInvoice: @escaping (String) -> Void,
         payInvoice: @escaping (String) -> Void, canSignInvoice: Bool, canPayInvoice: Bool) {
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
        #if DEBUG
        .task { await PaperPreview.expireDocumentSessionForTesting(previewSession) }
        .task {
            let args = ProcessInfo.processInfo.arguments
            guard PaperPreview.isJobDocumentsPreview,
                  args.contains("--paper-preview-description-stale") || args.contains("--paper-preview-description-replaced") else { return }
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled { previewDocumentChanged = true }
        }
        #endif
        .background(Theme.background)
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
        .font(Theme.font(17)).buttonStyle(.plain)
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
                CustomerEstimateBookPage(scope: scope, sourceGeneration: sourceGeneration, estimate: effectiveRecord, fresh: effectiveFresh, active: selection.selected == id,
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
                    canSign: canSignInvoice, canPay: canPayInvoice, active: selection.selected == id,
                    refresh: refresh, sign: { signInvoice(value) }, pay: { payInvoice(value) })
            }
        }
    }
}

private struct CustomerEstimateBookLoadID: Hashable {
    let estimate: EstimateRecord
    let fresh: Bool
}

private struct CustomerEstimateBookPage: View {
    let scope: JobDocumentScope
    let sourceGeneration: UUID?
    let estimate: EstimateRecord
    let fresh: Bool
    let active: Bool
    let refresh: () async -> Void
    let review: () -> Void
    @EnvironmentObject private var api: APIClient
    @Environment(\.horizontalSizeClass) private var sizeClass
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
    private var currency: String { issued?.currency ?? lines.first?.unitPrice.currency ?? "USD" }
    private var moneyVerified: Bool {
        if options.isEmpty { return CustomerDocumentAmounts(lines: lines, currency: currency) != nil }
        return options.allSatisfy { CustomerDocumentAmounts(lines: $0.lines, currency: $0.currency) != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(issued?.title ?? estimate.title).font(Theme.font(type.heading, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if fresh { CustomerStatusWord(status: estimate.status, type: type) }
                    else { Text("Status needs refresh").font(Theme.font(type.body)).foregroundStyle(Theme.muted) }
                    if !fresh {
                        Text("This copy needs a refresh before you can decide.").font(Theme.font(type.body))
                    } else if loading { CustomerSkeleton(caption: "Opening the current estimate…", heading: false) }
                    if let error { CustomerProblemBanner(message: error, actionTitle: "Try again") { await load() } }
                    if estimate.status != "sent" || issued != nil {
                        if options.isEmpty {
                            estimateLines(lines, currency: currency)
                        } else {
                            if estimate.status == "approved" {
                                Text("These are the quoted packages. The approved package selection isn't available here.")
                                    .font(Theme.font(type.body)).foregroundStyle(Theme.muted)
                            }
                            ForEach(options) { option in
                                Text(option.title).font(Theme.font(type.heading, weight: .medium))
                                if !option.description.isEmpty { ReadOnlyDocumentDescription(text: option.description, fontSize: type.body, access: readingAccess) }
                                estimateLines(option.lines, currency: option.currency)
                            }
                        }
                    }
                }
                .padding(Theme.gutter).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
            if fresh, estimate.status == "sent", issued != nil, !loading, moneyVerified {
                CustomerPresentationCommit(title: "Review and sign", enabled: true, busy: false, type: type, action: review)
                    .accessibilityIdentifier("customer-book-review-sign")
                    .padding(Theme.gutter)
            } else if !fresh {
                CustomerSecondaryButton(title: "Refresh documents", type: type) { Task { await refresh() } }.padding(Theme.gutter)
            }
        }
        .task(id: CustomerEstimateBookLoadID(estimate: estimate, fresh: fresh)) { await load() }
    }

    @ViewBuilder private func estimateLines(_ lines: [FieldLine], currency: String) -> some View {
        if let amounts = CustomerDocumentAmounts(lines: lines, currency: currency) {
            CustomerIncludedLabel(type: type)
                    CustomerIncludedLines(lines: lines, type: type, rows: customerAmountRows(amounts, currency: currency, invoice: false), readingAccess: readingAccess)
        } else {
            Text("These amounts couldn't be verified. Hand the device back to your technician.")
                .font(Theme.font(type.body)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func load() async {
        guard fresh, estimate.status == "sent" else { return }
        loading = true; error = nil; issued = nil
        defer { loading = false }
        do {
            let revision = try await api.customerIssuedEstimateRevision(for: estimate)
            try Task.checkCancellation()
            issued = revision
        } catch is CancellationError {} catch { self.error = error.customerSentence(.openEstimate) }
    }
}

private struct CustomerInvoiceBookPage: View {
    let original: InvoiceRecord
    let scope: JobDocumentScope
    let sourceGeneration: UUID?
    let fresh: Bool
    let canSign: Bool
    let canPay: Bool
    let active: Bool
    let refresh: () async -> Void
    let sign: () -> Void
    let pay: () -> Void
    @StateObject private var model: InvoicePaymentCollectionModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showPayments = false

    init(invoice: InvoiceRecord, scope: JobDocumentScope, sourceGeneration: UUID?, api: APIClient, fresh: Bool,
         canSign: Bool, canPay: Bool, active: Bool, refresh: @escaping () async -> Void,
         sign: @escaping () -> Void, pay: @escaping () -> Void) {
        original = invoice; self.scope = scope; self.sourceGeneration = sourceGeneration; self.fresh = fresh; self.canSign = canSign; self.canPay = canPay
        self.active = active; self.refresh = refresh; self.sign = sign; self.pay = pay
        _model = StateObject(wrappedValue: InvoicePaymentCollectionModel(api: api, invoiceID: invoice.id, expectedJobScope: scope))
    }

    private var type: CustomerType { CustomerType(sizeClass) }
    private var invoice: InvoiceRecord { model.invoice ?? original }
    private var readingAccess: DocumentDescriptionAccess {
        .init(identity: .invoice(scope: scope, record: invoice), organizationID: scope.organizationID,
              capability: "invoice.view", feature: "invoicing", sourceGeneration: sourceGeneration, fresh: fresh, active: active, scopeValid: scope.contains(invoice))
    }
    private var amounts: CustomerDocumentAmounts? { CustomerDocumentAmounts(lines: invoice.lines, currency: invoice.currency, amountPaid: invoice.amountPaid) }
    private var signed: Bool { invoice.customerAuthorization?.linesRevision == invoice.linesRevision }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(invoice.origin == "estimate_deposit" ? "Deposit invoice" : "Invoice")
                        .font(Theme.font(type.heading, weight: .medium)).accessibilityIdentifier("customer-invoice-summary")
                    if fresh { CustomerStatusWord(status: invoice.status, type: type) }
                    else { Text("Status needs refresh").font(Theme.font(type.body)).foregroundStyle(Theme.muted) }
                    if signed, let authorization = invoice.customerAuthorization {
                        Label("Signed by \(authorization.signerName)", systemImage: "signature")
                            .font(Theme.font(type.body))
                    }
                    if let amounts {
                        let balance = CustomerInvoiceBalanceSummary(status: invoice.status, fresh: fresh, amounts: amounts,
                            historyReconciled: model.historyComplete && model.paymentTotalCents == amounts.paid)
                        Text(balance.title)
                            .font(Theme.font(type.body)).foregroundStyle(Theme.muted)
                        if let headlineAmount = balance.amount {
                            Text(money(headlineAmount, currency: invoice.currency))
                                .font(Theme.font(type.total, weight: .medium)).monospacedDigit()
                        }
                        CustomerIncludedLabel(type: type)
                    CustomerIncludedLines(lines: invoice.lines, type: type, rows: customerAmountRows(amounts, currency: invoice.currency, invoice: invoice.status != "void"), readingAccess: readingAccess)
                    } else {
                        Text("These amounts couldn't be verified. Hand the device back to your technician.").font(Theme.font(type.body))
                    }
                    if !fresh { Text("This copy needs a refresh.").font(Theme.font(type.body)) }
                    if model.isLoading {
                        SkeletonRows(count: 2, leading: false, inset: 0)
                            .accessibilityLabel("Loading your payments")
                    } else if !model.historyComplete {
                        CustomerProblemBanner(message: "Payments couldn't be loaded. The invoice's paid amount is shown above.",
                                              actionTitle: "Try again") { await model.load() }
                    } else {
                        paymentHistory
                        if model.paymentTotalCents != invoice.amountPaid {
                            CustomerProblemBanner(message: "Payments are still updating. Refresh to confirm the balance.",
                                                  symbol: "arrow.clockwise", actionTitle: "Refresh payments") { await model.load() }
                        }
                    }
                }
                .padding(Theme.gutter).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
            if fresh, model.invoice != nil, amounts != nil, ["issued", "paid"].contains(invoice.status) {
                if !signed && canSign {
                    CustomerPresentationCommit(title: "Sign for the work", enabled: !model.isLoading, busy: false, type: type, action: sign)
                        .padding(Theme.gutter)
                } else if invoice.status == "issued", canPay, model.canRecordPayment, let amounts, amounts.due > 0 {
                    CustomerPresentationCommit(title: "Pay \(money(amounts.due, currency: invoice.currency))", enabled: true, busy: false, type: type, action: pay)
                        .padding(Theme.gutter)
                }
            } else if !fresh {
                CustomerSecondaryButton(title: "Refresh documents", type: type) { Task { await refresh() } }.padding(Theme.gutter)
            }
        }
        .task(id: original) { await model.load() }
    }

    private var paymentHistory: some View {
        DisclosureGroup(isExpanded: $showPayments) {
            if model.payments.isEmpty { Text("No payments yet.").font(Theme.font(type.body)).padding(.vertical, 12) }
            ForEach(model.payments.sorted { $0.recordedAt > $1.recordedAt }) { payment in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(payment.method == "ach" ? "Bank transfer" : FieldPaymentMethod(rawValue: payment.method)?.displayName ?? "Payment")
                        Spacer(minLength: 8)
                        Text(money(payment.amount.amount, currency: payment.amount.currency)).font(Theme.font(type.body)).monospacedDigit()
                    }
                    Text(customerPaymentDate(payment.recordedAt)).font(Theme.font(type.small)).foregroundStyle(Theme.muted)
                    let refunded = payment.refundedAmount ?? (payment.status == .refunded ? payment.amount.amount : 0)
                    if refunded > 0 {
                        Text("Refunded \(money(refunded, currency: payment.amount.currency))").font(Theme.font(type.body))
                        if let date = payment.refundedAt { Text(customerPaymentDate(date)).font(Theme.font(type.small)).foregroundStyle(Theme.muted) }
                        Text("Received after refund \(money(payment.netAmount?.amount ?? 0, currency: payment.amount.currency))")
                            .font(Theme.font(type.small))
                    }
                }
                .font(Theme.font(type.body)).padding(.vertical, 14).accessibilityElement(children: .combine)
            }
        } label: {
            HStack {
                Text("Payments and refunds")
                Spacer(minLength: 8)
                Text("\(model.payments.count)").foregroundStyle(Theme.muted)
            }
            .font(Theme.font(type.body, weight: .medium)).frame(minHeight: 56)
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
    return date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
}
