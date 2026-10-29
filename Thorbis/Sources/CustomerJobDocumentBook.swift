import SwiftUI

/// Read-only browsing; consent and signature remain in their existing separate destinations.
struct CustomerJobDocumentBook: View {
    let scope: JobDocumentScope
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(scope: JobDocumentScope, estimates: [EstimateRecord], invoices: [InvoiceRecord],
         freshEstimates: Set<String>, freshInvoices: Set<String>, unavailableEstimates: [String],
         initial: CustomerJobDocumentID, actionError: String?, refresh: @escaping () async -> Void,
         reviewEstimate: @escaping (String) -> Void, signInvoice: @escaping (String) -> Void,
         payInvoice: @escaping (String) -> Void, canSignInvoice: Bool, canPayInvoice: Bool) {
        self.scope = scope
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
            if let actionError { ErrorBanner(message: actionError) { await refresh() }.padding(.horizontal, Theme.gutter) }
            pagingControls
            if selection.selected == nil {
                ContentUnavailableView("Document no longer available", systemImage: "doc.text.magnifyingglass",
                    description: Text("Return to Documents or choose another document above."))
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
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
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
        Menu {
            ForEach(selection.ids) { id in Button(id.reference) { selection.select(id) } }
        } label: {
            Label("All documents", systemImage: "square.stack")
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 56, minHeight: 56).contentShape(Rectangle())
        }
        .accessibilityLabel("Choose a job document")
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
                CustomerEstimateBookPage(estimate: record, fresh: freshEstimates.contains(value),
                    refresh: refresh, review: { reviewEstimate(value) })
            } else {
                VStack(spacing: 16) {
                    Text("Estimate unavailable").font(Theme.font(24, weight: .medium))
                    Text("Refresh to see this estimate. Your other job documents are still available.").font(Theme.font(20))
                    Button("Refresh documents") { Task { await refresh() } }.frame(minHeight: 56)
                }.padding(Theme.gutter)
            }
        case .invoice(let value):
            if let record = invoices.first(where: { $0.id == value }) {
                CustomerInvoiceBookPage(invoice: record, scope: scope, api: api, fresh: freshInvoices.contains(value),
                    canSign: canSignInvoice, canPay: canPayInvoice,
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
    let estimate: EstimateRecord
    let fresh: Bool
    let refresh: () async -> Void
    let review: () -> Void
    @EnvironmentObject private var api: APIClient
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var issued: CustomerIssuedEstimateRevision?
    @State private var loading = false
    @State private var error: String?
    private var type: CustomerType { CustomerType(sizeClass) }
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
                    PaperStatusChip(status: estimate.status)
                    if !fresh {
                        Text("This copy needs a refresh before you can decide.").font(Theme.font(type.body))
                    } else if loading { ProgressView("Opening current estimate…").font(Theme.font(type.body)) }
                    if let error { ErrorBanner(message: error) { await load() } }
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
                                if !option.description.isEmpty { Text(option.description).font(Theme.font(type.body)) }
                                estimateLines(option.lines, currency: option.currency)
                            }
                        }
                    }
                }
                .padding(Theme.gutter).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
            if fresh, estimate.status == "sent", issued != nil, !loading, moneyVerified {
                CustomerPresentationCommit(title: "Review and sign", enabled: true, busy: false, type: type, action: review)
                    .padding(Theme.gutter)
            } else if !fresh {
                CustomerSecondaryButton(title: "Refresh documents", type: type) { Task { await refresh() } }.padding(Theme.gutter)
            }
        }
        .task(id: CustomerEstimateBookLoadID(estimate: estimate, fresh: fresh)) { await load() }
    }

    @ViewBuilder private func estimateLines(_ lines: [FieldLine], currency: String) -> some View {
        if let amounts = CustomerDocumentAmounts(lines: lines, currency: currency) {
            CustomerLinesCard(lines: lines, currency: currency, type: type,
                rows: customerAmountRows(amounts, currency: currency, invoice: false))
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
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

private struct CustomerInvoiceBookPage: View {
    let original: InvoiceRecord
    let fresh: Bool
    let canSign: Bool
    let canPay: Bool
    let refresh: () async -> Void
    let sign: () -> Void
    let pay: () -> Void
    @StateObject private var model: InvoicePaymentCollectionModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showPayments = false

    init(invoice: InvoiceRecord, scope: JobDocumentScope, api: APIClient, fresh: Bool,
         canSign: Bool, canPay: Bool, refresh: @escaping () async -> Void,
         sign: @escaping () -> Void, pay: @escaping () -> Void) {
        original = invoice; self.fresh = fresh; self.canSign = canSign; self.canPay = canPay
        self.refresh = refresh; self.sign = sign; self.pay = pay
        _model = StateObject(wrappedValue: InvoicePaymentCollectionModel(api: api, invoiceID: invoice.id, expectedJobScope: scope))
    }

    private var type: CustomerType { CustomerType(sizeClass) }
    private var invoice: InvoiceRecord { model.invoice ?? original }
    private var amounts: CustomerDocumentAmounts? { CustomerDocumentAmounts(lines: invoice.lines, currency: invoice.currency, amountPaid: invoice.amountPaid) }
    private var signed: Bool { invoice.customerAuthorization?.linesRevision == invoice.linesRevision }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(invoice.origin == "estimate_deposit" ? "Deposit invoice" : "Invoice")
                        .font(Theme.font(type.heading, weight: .medium)).accessibilityIdentifier("customer-invoice-summary")
                    PaperStatusChip(status: invoice.status)
                    if signed, let authorization = invoice.customerAuthorization {
                        Label("Signed by \(authorization.signerName)", systemImage: "signature")
                            .font(Theme.font(type.body))
                    }
                    if let amounts {
                        Text(invoice.status == "void" ? "Voided invoice" : amounts.due == 0 ? "Paid in full" : "Amount due")
                            .font(Theme.font(type.body)).foregroundStyle(Theme.muted)
                        if invoice.status != "void" {
                            Text(money(amounts.due, currency: invoice.currency)).font(Theme.monoFont(type.total, weight: .medium))
                        }
                        CustomerLinesCard(lines: invoice.lines, currency: invoice.currency, type: type,
                            rows: customerAmountRows(amounts, currency: invoice.currency, invoice: invoice.status != "void"))
                    } else {
                        Text("These amounts couldn't be verified. Hand the device back to your technician.").font(Theme.font(type.body))
                    }
                    if !fresh { Text("This copy needs a refresh.").font(Theme.font(type.body)) }
                    if model.isLoading { ProgressView("Opening payments…") }
                    else if !model.historyComplete {
                        ErrorBanner(message: "Payments couldn't be loaded. The invoice's paid amount is shown above.") { await model.load() }
                    } else {
                        paymentHistory
                        if model.paymentTotalCents != invoice.amountPaid {
                            Text("Payments are still updating. Refresh to confirm the balance.").font(Theme.font(type.body))
                            Button("Refresh payments") { Task { await model.load() } }.frame(minHeight: 56)
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
                        Text(money(payment.amount.amount, currency: payment.amount.currency)).font(Theme.monoFont(type.body))
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
                Rectangle().fill(Theme.border).frame(height: 1)
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
