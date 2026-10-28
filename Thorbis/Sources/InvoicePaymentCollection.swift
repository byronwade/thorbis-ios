import Combine
import Foundation
import SwiftUI
import UIKit

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
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var selectedPayment: FieldPaymentRecord?
    @State private var didOpenRefundPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                // Same header grammar as "Line items" and "Activity" above and below it.
                HStack(spacing: 6) {
                    Text("Payments").font(Theme.font(13, weight: .medium))
                    Text("\(model.payments.count)").font(Theme.monoFont(12))
                }
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 2)
                Spacer()
                // Collect payment lives in the bottom bar; one entry point, not two.
            }

            VStack(spacing: 0) {
                if let loadError = model.loadError {
                    VStack(alignment: .leading, spacing: 8) {
                        ErrorBanner(message: loadError) { await model.load() }
                    }
                    .padding(15)
                } else if model.isLoading && !model.historyComplete {
                    SkeletonRows(count: 2, leading: false, inset: 15)
                        .padding(.vertical, 8)
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
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))

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
            InvoicePaymentDetailSheet(
                payment: payment,
                api: api,
                actorID: session.user?.id,
                canRefund: session.can("invoice.refund", feature: "payments"),
                intentStore: paymentRefundIntentStore(for: payment),
                onRefundCompleted: { await model.load() }
            )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
#if DEBUG
        .task(id: model.historyComplete) {
            guard PaperPreview.enabled, PaperPreview.isPaymentRefundPreview,
                  model.historyComplete, !didOpenRefundPreview,
                  let payment = model.payments.first else { return }
            didOpenRefundPreview = true
            selectedPayment = payment
        }
#endif
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
                    .font(Theme.font(14, weight: .medium))
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

    private func paymentRefundIntentStore(for payment: FieldPaymentRecord) -> PaymentRefundIntentStoring {
#if DEBUG
        if PaperPreview.enabled { return PaperPreview.refundIntentStore(for: payment) }
#endif
        return KeychainPaymentRefundIntentStore.shared
    }
}

struct InvoiceDetailFooter: View {
    @ObservedObject var model: InvoicePaymentCollectionModel
    let canCollect: Bool
    let canIssue: Bool
    let busy: Bool
    let onCollect: () -> Void
    let onIssue: () -> Void

    var body: some View {
        Group {
            if model.canOfferCollection && canCollect {
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
    let canRefund: Bool
    let onRefundCompleted: () async -> Void
    @StateObject private var refundModel: InvoicePaymentRefundModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDiscard = false
    #if DEBUG
    @State private var previewRefundForm = false
    #endif

    init(
        payment: FieldPaymentRecord,
        api: APIClient,
        actorID: String?,
        canRefund: Bool,
        intentStore: PaymentRefundIntentStoring,
        onRefundCompleted: @escaping () async -> Void
    ) {
        self.canRefund = canRefund
        self.onRefundCompleted = onRefundCompleted
        _refundModel = StateObject(wrappedValue: InvoicePaymentRefundModel(
            api: api,
            actorID: actorID,
            payment: payment,
            intentStore: intentStore
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        let received = refundModel.payment.netAmount ?? refundModel.payment.amount
                        Text(money(received.amount, currency: received.currency))
                            .font(Theme.font(30, weight: .medium))
                            .tracking(-0.45)
                        Text("Net received")
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.muted)
                    }

                    VStack(spacing: 0) {
                        paymentDetail("Method", refundModel.payment.method.capitalized)
                        paymentDetail("Status", refundModel.payment.status == .refunded ? "Refunded" : "Recorded")
                        paymentDetail("Amount recorded", money(refundModel.payment.amount.amount, currency: refundModel.payment.amount.currency))
                        if let refundedAmount = refundModel.payment.refundedAmount {
                            paymentDetail("Refunded", money(refundedAmount, currency: refundModel.payment.amount.currency))
                        }
                        paymentDetail("Recorded", paymentDate(refundModel.payment.recordedAt))
                        if let refundedAt = refundModel.payment.refundedAt {
                            paymentDetail("Refund date", paymentDate(refundedAt))
                        }
                    }
                    .padding(.horizontal, 15)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))

                    if refundModel.didComplete {
                        Label("Refund confirmed by Thorbis", systemImage: "checkmark.circle.fill")
                            .font(Theme.font(14, weight: .medium))
                            .foregroundStyle(Theme.success)
                            .padding(15)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.successSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    }

                    if let error = refundModel.errorMessage {
                        ErrorBanner(message: error)
                    }

                    if let intent = refundModel.intent {
                        if intent.state == .draft {
                            if canRefund, refundModel.isIntentStoreReady {
                                refundLink(title: "Resume refund")
                            } else {
                                Text("A refund reason is saved, but the current workspace access or secure storage is unavailable.")
                                    .font(Theme.font(13))
                                    .foregroundStyle(Theme.muted)
                            }
                            discardReasonButton
                        } else {
                            InvoicePaymentRefundStatusPanel(model: refundModel) {
                                await onRefundCompleted()
                            }
                        }
                    } else if canRefund, refundModel.canOfferRefund, refundModel.isIntentStoreReady {
                        refundLink(title: "Refund payment")
                    }

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .foregroundStyle(Theme.foreground)
            .navigationTitle("Payment details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(refundModel.isSubmitting)
                }
            }
            #if DEBUG
            .navigationDestination(isPresented: $previewRefundForm) {
                InvoicePaymentRefundForm(model: refundModel, onRefundCompleted: onRefundCompleted)
            }
            #endif
        }
        .interactiveDismissDisabled(refundModel.isSubmitting)
        .confirmationDialog("Discard the saved refund reason?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard saved reason", role: .destructive) { refundModel.discardSavedIntent() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(discardMessage)
        }
        #if DEBUG
        .task {
            guard PaperPreview.enabled,
                  PaperPreview.screen == "invoice-payment-refund-form" || PaperPreview.screen == "invoice-payment-refund-confirmation" else { return }
            refundModel.updateReasonDraft("Customer approved a duplicate invoice payment.")
            previewRefundForm = true
        }
        #endif
    }

    private func refundLink(title: String) -> some View {
        NavigationLink {
            InvoicePaymentRefundForm(model: refundModel, onRefundCompleted: onRefundCompleted)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.destructive)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.font(14, weight: .medium))
                    Text("Full payment · \(money(refundModel.payment.amount.amount, currency: refundModel.payment.amount.currency))")
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.foreground)
            .padding(15)
            .frame(minHeight: 58)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Refunds the entire recorded payment after you review and confirm it")
    }

    private var discardReasonButton: some View {
        Button("Discard saved reason", role: .destructive) { confirmDiscard = true }
            .font(Theme.font(13, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private var discardMessage: String {
        refundModel.intent?.state == .draft
            ? "This removes the saved draft reason."
            : "This removes the saved reason the app needs to check the refund outcome safely."
    }
}

private struct InvoicePaymentRefundForm: View {
    @ObservedObject var model: InvoicePaymentRefundModel
    let onRefundCompleted: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var reasonFocused: Bool
    @State private var confirmRefund = false
    @State private var confirmDiscard = false

    private var amountText: String {
        money(model.payment.amount.amount, currency: model.payment.amount.currency)
    }

    private var showsReasonForm: Bool {
        guard let intent = model.intent else { return !model.didComplete }
        return intent.state == .draft
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.didComplete {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Refund confirmed", systemImage: "checkmark.circle.fill")
                            .font(Theme.font(18, weight: .medium))
                            .foregroundStyle(Theme.success)
                        Text("Thorbis confirmed the full refund of \(amountText).")
                            .font(Theme.font(14))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.successSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                } else if showsReasonForm {
                    reasonEntry
                } else {
                    InvoicePaymentRefundStatusPanel(model: model) {
                        await onRefundCompleted()
                        dismiss()
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.foreground)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if showsReasonForm {
                PrimaryButton(title: "Review full refund", busy: false) {
                    reasonFocused = false
                    confirmRefund = true
                }
                .disabled(!model.canSubmitRefund)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Theme.chrome)
            }
        }
        .navigationTitle("Refund payment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(model.isSubmitting)
            }
        }
        .interactiveDismissDisabled(model.isSubmitting)
        #if DEBUG
        .task {
            if PaperPreview.enabled, PaperPreview.screen == "invoice-payment-refund-confirmation" {
                confirmRefund = true
            }
        }
        #endif
        .confirmationDialog("Refund the full payment of \(amountText)?", isPresented: $confirmRefund, titleVisibility: .visible) {
            Button("Refund \(amountText)", role: .destructive) {
                Task {
                    if await model.submitRefund() {
                        await onRefundCompleted()
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This returns the entire recorded payment. Partial refunds are not available here, and this action cannot be undone.")
        }
        .confirmationDialog("Discard the saved refund reason?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard saved reason", role: .destructive) { model.discardSavedIntent() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(model.intent?.state == .draft
                 ? "This removes the saved draft reason."
                 : "This removes the saved reason the app needs to check the refund outcome safely.")
        }
    }

    private var reasonEntry: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Label("Full payment", systemImage: "arrow.uturn.backward.circle")
                    .font(Theme.font(13, weight: .medium))
                    .foregroundStyle(Theme.warning)
                Text(amountText)
                    .font(Theme.font(30, weight: .medium))
                    .tracking(-0.45)
                Text("This refunds the entire recorded payment. Partial refunds are not available here.")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))

            Text("Reason for refund")
                .font(Theme.font(14, weight: .medium))
                .accessibilityAddTraits(.isHeader)
            TextEditor(text: Binding(
                get: { model.reasonDraft },
                set: { model.updateReasonDraft($0) }
            ))
            .font(Theme.font(15))
            .frame(minHeight: 136)
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
            .focused($reasonFocused)
            .accessibilityLabel("Reason for refund")
            .accessibilityHint("Enter between 3 and 2,000 characters")
            .accessibilityIdentifier("payment-refund-reason")

            HStack {
                Text("3–2,000 characters")
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("\(model.reasonDraft.utf16.count)/2,000")
                    .foregroundStyle(model.reasonDraft.utf16.count > 2_000 ? Theme.destructive : Theme.muted)
                    .monospacedDigit()
            }
            .font(Theme.font(12))

            if let error = model.errorMessage {
                ErrorBanner(message: error)
            }

            if model.intent?.state == .draft {
                Button("Discard saved reason", role: .destructive) { confirmDiscard = true }
                    .font(Theme.font(13, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
    }
}

private struct InvoicePaymentRefundStatusPanel: View {
    @ObservedObject var model: InvoicePaymentRefundModel
    let onRefundCompleted: () async -> Void

    var body: some View {
        if let intent = model.intent {
            VStack(alignment: .leading, spacing: 12) {
                Label(title(for: intent.state), systemImage: symbol(for: intent.state))
                    .font(Theme.font(15, weight: .medium))
                    .foregroundStyle(Theme.warning)
                Text(message(for: intent.state))
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.muted)

                if let error = model.errorMessage {
                    ErrorBanner(message: error)
                }

                PrimaryButton(title: "Check refund status", busy: model.isSubmitting) {
                    Task {
                        if await model.checkRefundStatus() {
                            await onRefundCompleted()
                        }
                    }
                }
                .disabled(!model.canCheckRefundStatus)

            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        }
    }

    private func title(for state: FieldPaymentRefundIntentState) -> String {
        switch state {
        case .draft: "Refund reason saved"
        case .pending: "Refund pending"
        case .reconciliationRequired: "Refund needs reconciliation"
        case .uncertain: "Refund status unconfirmed"
        }
    }

    private func symbol(for state: FieldPaymentRefundIntentState) -> String {
        switch state {
        case .draft: "doc.text"
        case .pending: "clock"
        case .reconciliationRequired: "arrow.triangle.2.circlepath"
        case .uncertain: "questionmark.circle"
        }
    }

    private func message(for state: FieldPaymentRefundIntentState) -> String {
        switch state {
        case .draft: "The reason is saved securely on this device."
        case .pending: "The refund has been accepted and is still processing. Check again to refresh its status."
        case .reconciliationRequired: "Thorbis needs to reconcile the refund before it can be confirmed. Check again to refresh its status."
        case .uncertain: "The last request did not confirm whether the refund completed. Check status using the same saved reason."
        }
    }
}

struct InvoicePaymentCollectionSheet: View {
    @ObservedObject var model: InvoicePaymentCollectionModel
    let invoice: InvoiceRecord
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFocused: Bool
    @State private var amountText: String
    @State private var method: FieldPaymentMethod
    @State private var option: InvoiceCollectionOption
    @State private var showRecordConfirmation = false
    @State private var isCreatingPayLink = false
    @State private var payLink: FieldInvoicePayLink?
    @State private var payLinkError: String?
    @State private var showPayLinkShare = false
    @State private var receiptDestination: String?
    @State private var receiptDestinationLoaded = false
    @StateObject private var tapToPayController: TapToPayController
    private var tapToPay: TapToPayController? { tapToPayController }

    init(model: InvoicePaymentCollectionModel, invoice: InvoiceRecord) {
        self.model = model
        self.invoice = invoice
        let cents = model.pendingRequest?.amount.amount ?? min(model.outstandingCents ?? 0, 1_000_000_000_000)
        _amountText = State(initialValue: paymentAmountText(cents))
        _method = State(initialValue: model.pendingRequest?.method ?? .cash)
        // Tap to Pay needs Apple's entitlement and a card-present terminal first;
        // open on the fastest path that actually takes money today.
        _option = State(initialValue: model.pendingRequest == nil ? .paymentLink : .alreadyCollected)
        _tapToPayController = StateObject(wrappedValue: TapToPayController(invoiceID: invoice.id))
    }

    private var amountCents: Int? {
        MoneyInput.cents(amountText, maximumCents: min(model.outstandingCents ?? 0, 1_000_000_000_000))
    }

    private var hasLockedIntent: Bool { model.pendingRequest != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        amountHero
                        if tapToPayAvailable && !hasLockedIntent { tapToPayCard }
                        paymentOptions
                        receiptRow
                        if option == .alreadyCollected {
                            existingPaymentMethod
                        }
                        if let payLinkError { ErrorBanner(message: payLinkError) }
                        if let paymentError = model.paymentError {
                            ErrorBanner(message: paymentError)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }

                footer
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
            .sheet(isPresented: $showPayLinkShare) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 18) {
                        if let payLink, let shareURL = payLink.shareURL {
                            Text("Secure payment link ready")
                                .font(Theme.font(18, weight: .medium))
                            Text("Share the invoice balance with \(customerName).")
                                .font(Theme.font(13))
                                .foregroundStyle(Theme.muted)
                            ShareLink(item: shareURL) {
                                Label("Share payment link", systemImage: "square.and.arrow.up")
                                    .inkCommit()
                            }
                            .accessibilityIdentifier("share-invoice-payment-link")
                            Button("Copy link") { UIPasteboard.general.string = shareURL.absoluteString }
                                .font(Theme.font(14, weight: .medium))
                                .frame(maxWidth: .infinity, minHeight: 44)
                            if let expiration = JobFiltering.date(payLink.expiresAt) {
                                Text("Expires \(expiration.formatted(date: .abbreviated, time: .shortened))")
                                    .font(Theme.font(12))
                                    .foregroundStyle(Theme.subtle)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(20)
                    .background(Theme.background.ignoresSafeArea())
                    .navigationTitle("Payment link")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showPayLinkShare = false }
                                .frame(minWidth: 44, minHeight: 44)
                        }
                    }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .confirmationDialog(recordConfirmationTitle, isPresented: $showRecordConfirmation, titleVisibility: .visible) {
                Button(primaryTitle) { Task { await recordPayment() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(recordConfirmationMessage)
            }
            .task {
                // Open on the iPhone reader when this workspace and phone can take cards in person.
                if tapToPayAvailable && model.pendingRequest == nil { option = .tapToPay }
                await loadReceiptDestination()
            }
        }
    }

    private var amountHero: some View {
        VStack(spacing: 7) {
            PaperEyebrow(reference: "INV-\(invoice.id.suffix(4).uppercased())", text: customerName)
            HStack(spacing: 3) {
                Text("$")
                    .font(Theme.monoFont(26, weight: .medium))
                    .foregroundStyle(Theme.muted)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .font(Theme.monoFont(32, weight: .medium))
                    .tracking(-0.7)
                    .multilineTextAlignment(.leading)
                    .fixedSize()
                    .accessibilityLabel("Amount to collect in dollars")
                    .disabled(hasLockedIntent || model.waitingForProjection || option == .paymentLink || option == .tapToPay)
                if !hasLockedIntent && !model.waitingForProjection && option != .paymentLink && option != .tapToPay {
                    Button("Balance") {
                        amountText = paymentAmountText(min(model.outstandingCents ?? 0, 1_000_000_000_000))
                    }
                    .font(Theme.font(12, weight: .medium))
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
            .frame(maxWidth: .infinity)
            Text("Balance due \(money(model.outstandingCents ?? 0, currency: invoice.currency))")
                .font(Theme.font(12))
                .foregroundStyle(Theme.muted)
            if amountCents == nil {
                Text("Enter an amount within the invoice balance.")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.destructive)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// Paper 39: the card reader is the iPhone itself. Shown only when the workspace has Tap to Pay
    /// and this iPhone supports it; everything else about the sheet is unchanged.
    private var tapToPayCard: some View {
        Button {
            guard !hasLockedIntent && !model.waitingForProjection else { return }
            option = .tapToPay
            amountText = paymentAmountText(min(model.outstandingCents ?? 0, 1_000_000_000_000))
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "wave.3.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.brandText)
                    .frame(width: 60, height: 60)
                    .overlay(Circle().stroke(Theme.brand, lineWidth: 1.5))
                Text(tapToPayHeadline)
                    .font(Theme.font(17, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                Text("Accepts contactless cards, Apple Pay and other wallets")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 168)
            .background(option == .tapToPay ? Theme.brandSurface : Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(option == .tapToPay ? Theme.brand.opacity(0.5) : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tap to Pay on iPhone")
        .accessibilityAddTraits(option == .tapToPay ? .isSelected : [])
        .accessibilityIdentifier("tap-to-pay")
    }

    private var tapToPayHeadline: String {
        switch tapToPay?.phase {
        case .preparing: "Getting ready…"
        case .waitingForCard: "Hold card near your phone"
        case .processing: "Processing…"
        case .recording: "Approved · recording payment"
        case .paid: "Paid"
        default: "Tap to Pay on iPhone"
        }
    }

    private var tapToPayAvailable: Bool {
        session.isFeatureOn(TapToPayController.feature) && TapToPayController.deviceSupported
            && session.can("invoice.payment.create", feature: "payments")
    }

    private func charge() async {
        let tapToPay = tapToPayController
        let before = model.payments.count
        await tapToPay.charge(api: api) { [model] in
            await model.load()
            return model.payments.count > before || model.outstandingCents == 0
        }
        if tapToPay.phase == .paid {
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        }
    }

    private var paymentOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How is the customer paying?")
                .font(Theme.font(13, weight: .medium))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 2)
            VStack(spacing: 0) {
                optionRow(title: "Card · send payment link", subtitle: "Text or email a secure card checkout", icon: "link",
                          selected: option == .paymentLink, busy: isCreatingPayLink) {
                    guard !hasLockedIntent && !model.waitingForProjection else { return }
                    option = .paymentLink
                    amountText = paymentAmountText(min(model.outstandingCents ?? 0, 1_000_000_000_000))
                }
                Divider().overlay(Theme.border).padding(.leading, 48)
                optionRow(title: "Check", subtitle: "Record a check already received", icon: "doc.text.viewfinder",
                          selected: option == .check) {
                    guard !hasLockedIntent && !model.waitingForProjection else { return }
                    option = .check
                    method = .check
                }
                Divider().overlay(Theme.border).padding(.leading, 48)
                optionRow(title: "Cash", subtitle: "Record cash received", icon: "banknote",
                          selected: option == .cash) {
                    guard !hasLockedIntent && !model.waitingForProjection else { return }
                    option = .cash
                    method = .cash
                }
                Divider().overlay(Theme.border).padding(.leading, 48)
                optionRow(title: "Already collected", subtitle: "Record a card, ACH, or other tender", icon: "checkmark.circle",
                          selected: option == .alreadyCollected) {
                    guard !hasLockedIntent && !model.waitingForProjection else { return }
                    option = .alreadyCollected
                }
            }
            .padding(.horizontal, 12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1))
            .disabled(hasLockedIntent || model.waitingForProjection)
        }
    }

    private var existingPaymentMethod: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hasLockedIntent ? "Payment already collected by" : "Tender already received")
                .font(Theme.font(13, weight: .medium))
                .foregroundStyle(Theme.muted)
            Picker("Tender already received", selection: $method) {
                ForEach(FieldPaymentMethod.allCases, id: \.self) { value in
                    Text(value.rawValue.uppercased()).tag(value)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .disabled(hasLockedIntent || model.waitingForProjection)
            Label("This records a payment collected elsewhere; it does not charge a card or bank account.", systemImage: "info.circle")
                .font(Theme.font(12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var receiptRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Receipt destination")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.muted)
                Text(receiptDestination ?? (receiptDestinationLoaded ? "No email on file" : "Loading contact…"))
                    .font(Theme.font(13, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if option == .tapToPay, case .failed(let message) = tapToPay?.phase {
                Text(message)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.warning)
                    .multilineTextAlignment(.center)
            }
            PrimaryButton(title: primaryTitle, busy: isCreatingPayLink || model.isRecording || model.isLoading || tapToPay?.busy == true) {
                amountFocused = false
                Task { await submit() }
            }
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Theme.chrome)
    }

    private func optionRow(title: String, subtitle: String, icon: String, selected: Bool,
                           busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selected ? Theme.brand : Theme.muted)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.font(14, weight: selected ? .semibold : .medium))
                    Text(subtitle).font(Theme.font(11)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                if busy {
                    ProgressView().controlSize(.small)
                } else if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.brandText)
                }
                else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.subtle)
                }
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy || !session.can("invoice.payment.create", feature: "payments") || !model.canRecordPayment)
        .accessibilityHint(subtitle)
    }

    private var primaryTitle: String {
        if model.waitingForProjection { return "Check payment status" }
        if hasLockedIntent { return "Retry recording" }
        switch option {
        case .tapToPay:
            if case .failed = tapToPay?.phase { return "Try again" }
            return "Charge \(money(model.outstandingCents ?? 0, currency: invoice.currency))"
        case .paymentLink:
            return "Create payment link"
        case .cash:
            return amountCents.map { "Record \(money($0, currency: invoice.currency)) cash received" } ?? "Record cash received"
        case .check:
            return amountCents.map { "Record \(money($0, currency: invoice.currency)) check received" } ?? "Record check received"
        case .alreadyCollected:
            return amountCents.map { "Record \(money($0, currency: invoice.currency)) already collected" } ?? "Record payment already collected"
        }
    }

    private var canSubmit: Bool {
        guard !model.isRecording, !model.isLoading, !isCreatingPayLink else { return false }
        if model.waitingForProjection { return true }
        guard session.can("invoice.payment.create", feature: "payments"), model.canRecordPayment else { return false }
        if option == .tapToPay { return tapToPayAvailable && (model.outstandingCents ?? 0) > 0 && tapToPay?.busy != true }
        if option == .paymentLink { return model.outstandingCents == amountCents }
        guard let amountCents else { return false }
        if hasLockedIntent {
            return model.pendingRequest?.amount.amount == amountCents && model.pendingRequest?.method == method
        }
        return amountCents <= (model.outstandingCents ?? 0)
    }

    private var recordConfirmationTitle: String {
        switch method {
        case .cash: "Confirm cash received"
        case .check: "Confirm check received"
        case .card, .ach: "Confirm payment already collected"
        }
    }

    private var recordConfirmationMessage: String {
        guard let amountCents else { return "Confirm the payment was received before recording it." }
        return "Confirm \(money(amountCents, currency: invoice.currency)) was already received by \(method.rawValue.uppercased()). This action records the payment; it does not charge the customer."
    }

    private func submit() async {
        if model.waitingForProjection {
            await model.load()
            if !model.waitingForProjection { dismiss() }
            return
        }
        if option == .paymentLink {
            await createPayLink()
            return
        }
        if option == .tapToPay {
            await charge()
            return
        }
        guard amountCents != nil else { return }
        if hasLockedIntent {
            await recordPayment()
        } else {
            showRecordConfirmation = true
        }
    }

    private func recordPayment() async {
        guard let amountCents else { return }
        let accepted = await model.record(amountCents: amountCents, method: method)
        if accepted { dismiss() }
    }

    private func createPayLink() async {
        guard session.can("invoice.payment.create", feature: "payments"),
              model.canRecordPayment, model.outstandingCents == amountCents else { return }
        isCreatingPayLink = true
        defer { isCreatingPayLink = false }
        do {
            payLink = try await api.openFieldPayLink(invoice.id)
            payLinkError = nil
            showPayLinkShare = true
        } catch is CancellationError {
        } catch {
            payLinkError = error.localizedDescription
        }
    }

    private func loadReceiptDestination() async {
        guard session.can("customer.view", feature: "core_crm") else {
            receiptDestinationLoaded = true
            return
        }
        do {
            let customer = try await api.fieldCustomer(invoice.customerId)
            let contacts = try await api.fieldContacts(invoice.customerId)
            receiptDestination = contacts.first(where: \.primary)?.email ?? customer.email
            receiptDestinationLoaded = true
        } catch is CancellationError {
        } catch {
            receiptDestination = nil
            receiptDestinationLoaded = true
        }
    }

    private var customerName: String {
        store.customerName(invoice.customerId)
    }
}

private enum InvoiceCollectionOption: Equatable {
    case tapToPay
    case paymentLink
    case cash
    case check
    case alreadyCollected
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

func paymentAmountText(_ cents: Int) -> String {
    "\(cents / 100).\(String(format: "%02d", cents % 100))"
}
