import Combine
import Foundation
import SwiftUI

@MainActor
final class InvoicePaymentIntentStore {
    static let shared = InvoicePaymentIntentStore(defaults: .standard)

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load(organizationID: String, invoiceID: String) -> FieldRecordPaymentRequest? {
        guard let data = defaults.data(forKey: key(organizationID: organizationID, invoiceID: invoiceID)) else {
            return nil
        }
        return try? JSONDecoder().decode(FieldRecordPaymentRequest.self, from: data)
    }

    @discardableResult
    func save(_ request: FieldRecordPaymentRequest, organizationID: String, invoiceID: String) -> Bool {
        guard let data = try? JSONEncoder().encode(request) else { return false }
        defaults.set(data, forKey: key(organizationID: organizationID, invoiceID: invoiceID))
        return true
    }

    func remove(organizationID: String, invoiceID: String) {
        defaults.removeObject(forKey: key(organizationID: organizationID, invoiceID: invoiceID))
    }

    private func key(organizationID: String, invoiceID: String) -> String {
        "thorbis.invoice-payment.pending.\(organizationID).\(invoiceID)"
    }
}

@MainActor
final class InvoicePaymentCollectionModel: ObservableObject {
    @Published private(set) var invoice: InvoiceRecord?
    @Published private(set) var payments: [FieldPaymentRecord] = []
    @Published private(set) var historyComplete = false
    @Published private(set) var isLoading = false
    @Published private(set) var isRecording = false
    @Published private(set) var loadError: String?
    @Published private(set) var paymentError: String?
    @Published private(set) var pendingRequest: FieldRecordPaymentRequest?

    private let api: APIClient
    private let invoiceID: String
    private let intentStore: InvoicePaymentIntentStore
    private let makeIdempotencyKey: () -> String
    private var acceptedPaymentID: String?

    init(api: APIClient, invoiceID: String,
         intentStore: InvoicePaymentIntentStore = .shared,
         makeIdempotencyKey: @escaping () -> String = { UUID().uuidString.lowercased() }) {
        self.api = api
        self.invoiceID = invoiceID
        self.intentStore = intentStore
        self.makeIdempotencyKey = makeIdempotencyKey
    }

    var totalCents: Int? {
        guard let invoice, invoice.currency == "USD" else { return nil }
        var total = 0
        for line in invoice.lines {
            guard line.quantity >= 0, line.unitPrice.amount >= 0,
                  line.unitPrice.currency == invoice.currency else { return nil }
            let (lineTotal, productOverflow) = line.quantity.multipliedReportingOverflow(by: line.unitPrice.amount)
            let (nextTotal, sumOverflow) = total.addingReportingOverflow(lineTotal)
            guard !productOverflow, !sumOverflow else { return nil }
            total = nextTotal
        }
        return total
    }

    var outstandingCents: Int? {
        guard let invoice, let total = totalCents else { return nil }
        let (balance, overflow) = total.subtractingReportingOverflow(invoice.amountPaid)
        guard !overflow else { return nil }
        return max(0, balance)
    }

    var canOfferCollection: Bool {
        invoice?.status == "issued" && invoice?.currency == "USD" && (outstandingCents ?? 0) > 0
    }

    var paymentTotalCents: Int? {
        guard historyComplete else { return nil }
        var total = 0
        for payment in payments {
            let received = payment.netAmount ?? (payment.status == .refunded
                ? FieldMoney(amount: 0, currency: "USD")
                : payment.amount)
            guard received.currency == "USD", received.amount >= 0 else { return nil }
            let (nextTotal, overflow) = total.addingReportingOverflow(received.amount)
            guard !overflow else { return nil }
            total = nextTotal
        }
        return total
    }

    var waitingForProjection: Bool { acceptedPaymentID != nil }

    var canRecordPayment: Bool {
        canOfferCollection && !isLoading && !isRecording && !waitingForProjection &&
            historyComplete && paymentTotalCents == invoice?.amountPaid
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        historyComplete = false
        defer { isLoading = false }
        do {
            try Task.checkCancellation()
            let loadedInvoice = try await api.fieldInvoice(invoiceID)
            invoice = loadedInvoice
            if pendingRequest == nil {
                pendingRequest = intentStore.load(organizationID: loadedInvoice.organizationId, invoiceID: invoiceID)
            }
            try Task.checkCancellation()
            payments = try await api.fieldPayments(invoiceID)
            historyComplete = true
            loadError = nil
            if acceptedPaymentID == nil, let request = pendingRequest,
               let recovered = payments.first(where: { $0.idempotencyKey == request.idempotencyKey }) {
                acceptedPaymentID = recovered.id
            }
            reconcileAcceptedPayment()
        } catch is CancellationError {
        } catch {
            loadError = error.localizedDescription
        }
    }

    func acceptInvoiceMutationResponse(_ updated: InvoiceRecord) {
        guard updated.id == invoiceID else { return }
        invoice = updated
    }

    @discardableResult
    func record(amountCents: Int, method: FieldPaymentMethod) async -> Bool {
        guard canRecordPayment else { return false }
        guard (1...1_000_000_000_000).contains(amountCents) else {
            paymentError = "Enter a payment amount greater than zero with no more than two decimal places."
            return false
        }
        guard amountCents <= (outstandingCents ?? 0) else {
            paymentError = "The payment cannot be greater than the invoice balance."
            return false
        }

        let request: FieldRecordPaymentRequest
        if let pendingRequest {
            guard pendingRequest.amount.amount == amountCents, pendingRequest.amount.currency == "USD",
                  pendingRequest.method == method else {
                paymentError = "Retry the previous payment with the same amount and method before starting another."
                return false
            }
            request = pendingRequest
        } else {
            request = FieldRecordPaymentRequest(
                amount: FieldMoney(amount: amountCents, currency: "USD"),
                method: method,
                idempotencyKey: makeIdempotencyKey()
            )
            guard let organizationID = invoice?.organizationId,
                  intentStore.save(request, organizationID: organizationID, invoiceID: invoiceID) else {
                paymentError = "Could not save this payment for a safe retry. Please try again."
                return false
            }
            pendingRequest = request
        }

        isRecording = true
        paymentError = nil
        defer { isRecording = false }
        do {
            let accepted = try await api.recordFieldPayment(invoiceID, request: request)
            guard accepted.idempotencyKey == request.idempotencyKey else {
                throw Problem(title: "Payment receipt did not match the recorded request", status: nil,
                              detail: "Retry safely to retrieve the receipt for this payment intent.")
            }
            acceptedPaymentID = accepted.id
            await load()
            if waitingForProjection {
                paymentError = "Payment recorded. The invoice and payment history are still updating."
                return false
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            if let problem = error as? Problem, let status = problem.status, (400..<500).contains(status) {
                pendingRequest = nil
                if let organizationID = invoice?.organizationId {
                    intentStore.remove(organizationID: organizationID, invoiceID: invoiceID)
                }
            }
            paymentError = error.localizedDescription
            return false
        }
    }

    private func reconcileAcceptedPayment() {
        guard let acceptedPaymentID,
              historyComplete,
              paymentTotalCents == invoice?.amountPaid,
              let payment = payments.first(where: { $0.id == acceptedPaymentID }),
              payment.status == .recorded || payment.status == .refunded else { return }
        self.acceptedPaymentID = nil
        pendingRequest = nil
        if let organizationID = invoice?.organizationId {
            intentStore.remove(organizationID: organizationID, invoiceID: invoiceID)
        }
        paymentError = nil
    }
}

struct InvoicePaymentsSection: View {
    @ObservedObject var model: InvoicePaymentCollectionModel
    let invoice: InvoiceRecord
    let onCollectPayment: () -> Void
    let onInvoiceUpdated: (InvoiceRecord) -> Void
    @State private var selectedPayment: FieldPaymentRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 7) {
                    Text("Payments").font(Theme.font(16, weight: .semibold))
                    Text("\(model.payments.count)")
                        .font(Theme.monoFont(12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Button(action: onCollectPayment) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!model.canRecordPayment)
                .accessibilityLabel("Collect payment")
            }

            VStack(spacing: 0) {
                if let loadError = model.loadError {
                    VStack(alignment: .leading, spacing: 8) {
                        ErrorBanner(message: loadError)
                        Button("Retry payment history") { Task { await model.load() } }
                            .font(Theme.font(13, weight: .medium))
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .padding(15)
                } else if model.isLoading && !model.historyComplete {
                    ProgressView("Loading payments…")
                        .font(Theme.font(13))
                        .frame(maxWidth: .infinity, minHeight: 72)
                } else if model.payments.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No payments recorded yet.")
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.muted)
                        if invoice.status == "draft" {
                            Text("Payments can be recorded once this invoice is issued.")
                                .font(Theme.font(12))
                                .foregroundStyle(Theme.subtle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
                } else {
                    ForEach(Array(model.payments.enumerated()), id: \.element.id) { row in
                        let index = row.offset
                        let payment = row.element
                        Button { selectedPayment = payment } label: {
                            paymentRow(payment)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 15)
                        .frame(minHeight: 60)
                        if index < model.payments.count - 1 {
                            Divider().overlay(Theme.border).padding(.leading, 15)
                        }
                    }
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))

            if let modelError = model.paymentError {
                ErrorBanner(message: modelError)
            }
            if !model.isLoading, model.loadError == nil, model.historyComplete,
               model.paymentTotalCents != invoice.amountPaid {
                Label("Payment history is still syncing with the invoice.", systemImage: "arrow.triangle.2.circlepath")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 2)
            }
        }
        .onChange(of: model.invoice?.amountPaid) { _, _ in
            if let updated = model.invoice { onInvoiceUpdated(updated) }
        }
        .sheet(item: $selectedPayment) { payment in
            InvoicePaymentDetailSheet(payment: payment)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func paymentRow(_ payment: FieldPaymentRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: payment.status == .refunded ? "arrow.uturn.backward.circle" : "checkmark.circle")
                .font(.system(size: 20))
                .foregroundStyle(payment.status == .refunded ? Theme.warning : Theme.success)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(payment.method.capitalized)
                    .font(Theme.font(14, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                Text(paymentDate(payment.recordedAt))
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                let amount = payment.netAmount ?? payment.amount
                Text(money(amount.amount, currency: amount.currency))
                    .font(Theme.font(14, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                if payment.status == .refunded {
                    Text("Refunded").font(Theme.font(11)).foregroundStyle(Theme.warning)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows payment details")
    }
}

struct InvoiceDetailFooter: View {
    @ObservedObject var model: InvoicePaymentCollectionModel
    let canIssue: Bool
    let busy: Bool
    let onCollect: () -> Void
    let onIssue: () -> Void

    var body: some View {
        Group {
            if model.canOfferCollection {
                PrimaryButton(title: "Collect payment", busy: model.isRecording, action: onCollect)
                    .disabled(!model.canRecordPayment)
            } else if model.invoice?.status == "draft", canIssue {
                PrimaryButton(title: "Issue invoice", busy: busy, action: onIssue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.chrome)
    }
}

private struct InvoicePaymentDetailSheet: View {
    let payment: FieldPaymentRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(money((payment.netAmount ?? payment.amount).amount,
                               currency: (payment.netAmount ?? payment.amount).currency))
                        .font(Theme.font(30, weight: .semibold))
                        .tracking(-0.45)
                    Text("Net received")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                }
                VStack(spacing: 0) {
                    paymentDetail("Method", payment.method.capitalized)
                    paymentDetail("Status", payment.status == .refunded ? "Refunded" : "Recorded")
                    paymentDetail("Amount recorded", money(payment.amount.amount, currency: payment.amount.currency))
                    if let refundedAmount = payment.refundedAmount {
                        paymentDetail("Refunded", money(refundedAmount, currency: payment.amount.currency))
                    }
                    paymentDetail("Recorded", paymentDate(payment.recordedAt))
                    if let refundedAt = payment.refundedAt {
                        paymentDetail("Refund date", paymentDate(refundedAt))
                    }
                }
                .padding(.horizontal, 15)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Theme.background.ignoresSafeArea())
            .foregroundStyle(Theme.foreground)
            .navigationTitle("Payment details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }
}

struct InvoicePaymentCollectionSheet: View {
    @ObservedObject var model: InvoicePaymentCollectionModel
    let invoice: InvoiceRecord
    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFocused: Bool
    @State private var amountText: String
    @State private var method: FieldPaymentMethod

    init(model: InvoicePaymentCollectionModel, invoice: InvoiceRecord) {
        self.model = model
        self.invoice = invoice
        let cents = model.pendingRequest?.amount.amount ?? min(model.outstandingCents ?? 0, 1_000_000_000_000)
        _amountText = State(initialValue: paymentAmountText(cents))
        _method = State(initialValue: model.pendingRequest?.method ?? .cash)
    }

    private var amountCents: Int? {
        MoneyInput.cents(amountText, maximumCents: min(model.outstandingCents ?? 0, 1_000_000_000_000))
    }

    private var hasLockedIntent: Bool { model.pendingRequest != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Invoice balance")
                                .font(Theme.font(13))
                                .foregroundStyle(Theme.muted)
                            Text(money(model.outstandingCents ?? 0, currency: invoice.currency))
                                .font(Theme.font(28, weight: .semibold))
                                .tracking(-0.4)
                                .accessibilityAddTraits(.updatesFrequently)
                        }

                        VStack(alignment: .leading, spacing: 9) {
                            Text("Amount collected").font(Theme.font(13, weight: .medium))
                            HStack(spacing: 8) {
                                Text("$").font(Theme.font(18, weight: .medium)).foregroundStyle(Theme.muted)
                                TextField("0.00", text: $amountText)
                                    .keyboardType(.decimalPad)
                                    .focused($amountFocused)
                                    .font(Theme.font(20, weight: .medium))
                                    .accessibilityLabel("Amount collected in dollars")
                                    .disabled(hasLockedIntent || model.waitingForProjection)
                                if !hasLockedIntent && !model.waitingForProjection {
                                    Button("Balance") {
                                        amountText = paymentAmountText(min(model.outstandingCents ?? 0, 1_000_000_000_000))
                                    }
                                    .font(Theme.font(12, weight: .medium))
                                    .frame(minWidth: 44, minHeight: 44)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 52)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 11))
                            if amountCents == nil {
                                Text("Enter an amount in dollars with up to two decimal places.")
                                    .font(Theme.font(12))
                                    .foregroundStyle(Theme.destructive)
                            }
                        }

                        VStack(alignment: .leading, spacing: 9) {
                            Text("Payment method").font(Theme.font(13, weight: .medium))
                            Picker("Payment method", selection: $method) {
                                ForEach(FieldPaymentMethod.allCases, id: \.self) { value in
                                    Text(value.rawValue.uppercased()).tag(value)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .padding(.horizontal, 12)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 11))
                            .disabled(hasLockedIntent || model.waitingForProjection)
                            .accessibilityHint("Choose the type of payment already collected")
                        }

                        Label("Records a payment already collected. This does not charge a card or bank account.",
                              systemImage: "info.circle")
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        if let paymentError = model.paymentError {
                            ErrorBanner(message: paymentError)
                        }
                    }
                    .padding(20)
                }

                PrimaryButton(title: primaryTitle, busy: model.isRecording || model.isLoading) {
                    amountFocused = false
                    Task { await submit() }
                }
                .disabled(!canSubmit)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(Theme.chrome)
            }
            .background(Theme.background.ignoresSafeArea())
            .foregroundStyle(Theme.foreground)
            .navigationTitle("Collect payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }.frame(minWidth: 44, minHeight: 44)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { amountFocused = false }.frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }

    private var primaryTitle: String {
        if model.waitingForProjection { return "Check payment status" }
        if hasLockedIntent { return "Retry recording" }
        return "Record payment"
    }

    private var canSubmit: Bool {
        guard !model.isRecording, !model.isLoading else { return false }
        if model.waitingForProjection { return true }
        guard model.canRecordPayment, let amountCents else { return false }
        if hasLockedIntent {
            return model.pendingRequest?.amount.amount == amountCents && model.pendingRequest?.method == method
        }
        return amountCents <= (model.outstandingCents ?? 0)
    }

    private func submit() async {
        if model.waitingForProjection {
            await model.load()
            if !model.waitingForProjection { dismiss() }
            return
        }
        guard let amountCents else { return }
        let accepted = await model.record(amountCents: amountCents, method: method)
        if accepted { dismiss() }
    }
}

private func paymentDetail(_ label: String, _ value: String) -> some View {
    HStack(spacing: 10) {
        Text(label).foregroundStyle(Theme.muted)
        Spacer()
        Text(value).foregroundStyle(Theme.foreground).multilineTextAlignment(.trailing)
    }
    .font(Theme.font(13))
    .padding(.vertical, 13)
}

private func paymentDate(_ value: String) -> String {
    guard let date = ISO8601DateFormatter().date(from: value) else { return value }
    return date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
}

private func paymentAmountText(_ cents: Int) -> String {
    "\(cents / 100).\(String(format: "%02d", cents % 100))"
}
