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
    /// The invoice and payments shown are the copy last saved on this phone (OF-04).
    @Published private(set) var offlineCopy = false
    /// Where cash and check go when there is no signal (OF-08); set by the screen that owns this.
    weak var outbox: FieldOutbox?
    var policyVersion = 0

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

    /// Cash and check taken on this phone and not yet recorded. They never lower the balance due
    /// (OF-02), but they do stop the same money being collected twice.
    var waitingCents: Int {
        guard let outbox else { return 0 }
        let queued = outbox.waitingPayments(invoiceID: invoiceID).reduce(0) { $0 + $1.amountCents }
        // Recorded from the queue but not yet in this screen's history: still held until reload.
        let landed = outbox.recordedPayments
            .filter { recorded in recorded.invoiceId == invoiceID && !payments.contains { $0.idempotencyKey == recorded.idempotencyKey } }
            .reduce(0) { $0 + $1.amountCents }
        return queued + landed
    }

    var collectableCents: Int? { outstandingCents.map { max(0, $0 - waitingCents) } }

    var canOfferCollection: Bool {
        invoice?.status == "issued" && invoice?.currency == "USD" && (collectableCents ?? 0) > 0
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
            offlineCopy = false
            JobDetailCache.save(invoice: loadedInvoice)
            if pendingRequest == nil {
                pendingRequest = intentStore.load(organizationID: loadedInvoice.organizationId, invoiceID: invoiceID)
            }
            try Task.checkCancellation()
            payments = try await api.fieldPayments(invoiceID)
            historyComplete = true
            JobDetailCache.save(payments: payments, invoiceID: invoiceID)
            loadError = nil
            if acceptedPaymentID == nil, let request = pendingRequest,
               let recovered = payments.first(where: { $0.idempotencyKey == request.idempotencyKey }) {
                acceptedPaymentID = recovered.id
            }
            reconcileAcceptedPayment()
        } catch is CancellationError {
        } catch {
            if error.isConnectivityFailure, let cached = invoice ?? JobDetailCache.invoice(invoiceID) {
                // No signal: the last copy, so cash and check can still be taken (OF-04, OF-08).
                invoice = cached
                // A payment sent before the app lost signal keeps its key (OF-05).
                if pendingRequest == nil {
                    pendingRequest = intentStore.load(organizationID: cached.organizationId, invoiceID: invoiceID)
                }
                if let saved = JobDetailCache.payments(invoiceID) {
                    payments = saved
                    historyComplete = true
                }
                offlineCopy = true
                loadError = nil
                return
            }
            loadError = error.localizedDescription
        }
    }

    /// Saves a cash or check payment on the phone to record once online (OF-08).
    private func queueOffline(_ request: FieldRecordPaymentRequest) -> Bool {
        guard request.method == .cash || request.method == .check, let outbox, let invoice,
              outbox.enqueue(.payment(.init(invoiceId: invoiceID, jobId: invoice.jobId, amountCents: request.amount.amount,
                                            method: request.method.rawValue, idempotencyKey: request.idempotencyKey)),
                             policyVersion: policyVersion) != nil else { return false }
        // The outbox now owns this payment and its key; the sheet is free for the next one.
        pendingRequest = nil
        intentStore.remove(organizationID: invoice.organizationId, invoiceID: invoiceID)
        paymentError = nil
        return true
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
        guard amountCents <= (collectableCents ?? 0) else {
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

        if offlineCopy {
            if queueOffline(request) { return true }
            paymentError = "Couldn't save this payment on the phone. Try again."
            return false
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
            if error.isConnectivityFailure, queueOffline(request) { return true }
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
    @EnvironmentObject private var outbox: FieldOutbox
    @State private var selectedPayment: FieldPaymentRecord?
    @State private var didOpenRefundPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                // Same header grammar as "Line items" and "Activity" above and below it.
                HStack(spacing: 6) {
                    Text("Payments").font(Theme.font(13, weight: .medium))
                    if !model.payments.isEmpty { Text("\(model.payments.count)").font(Theme.monoFont(12)) }
                }
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 2)
                Spacer()
                // Collect payment lives in the bottom bar; one entry point, not two.
            }

            VStack(spacing: 0) {
                // OF-08: money taken without signal is a record waiting, never Paid.
                ForEach(outbox.waitingPayments(invoiceID: invoice.id), id: \.idempotencyKey) { waiting in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(waiting.method.capitalized) received").font(Theme.font(15, weight: .medium))
                            WaitingToSyncLabel(text: "Records when you're back online")
                        }
                        Spacer(minLength: 8)
                        Text(money(waiting.amountCents, currency: invoice.currency)).moneyStyle(.row).foregroundStyle(Theme.foreground)
                    }
                    .padding(.horizontal, 15)
                    .frame(minHeight: 60)
                    .accessibilityElement(children: .combine)
                    Divider().overlay(Theme.border).padding(.leading, 15)
                }
                if let loadError = model.loadError {
                    VStack(alignment: .leading, spacing: 8) {
                        ErrorBanner(message: loadError) { await model.load() }
                    }
                    .padding(15)
                } else if model.isLoading && !model.historyComplete {
                    SkeletonRows(count: 2, leading: false, inset: 15)
                        .padding(.vertical, 8)
                } else if model.payments.isEmpty && outbox.waitingPayments(invoiceID: invoice.id).isEmpty {
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
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))

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
        .onChange(of: outbox.syncGeneration) { _, _ in
            // A queued payment or signature may have just landed: show the server's invoice, its
            // authorization and history, even when the amount paid didn't change.
            Task {
                await model.load()
                if let updated = model.invoice { onInvoiceUpdated(updated) }
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
                    .font(Theme.font(15, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                Text(paymentDate(payment.recordedAt))
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                let amount = payment.netAmount ?? payment.amount
                Text(money(amount.amount, currency: amount.currency))
                    .moneyStyle(.row)
                    .foregroundStyle(Theme.foreground)
                if payment.status == .refunded {
                    Text("Refunded").font(Theme.font(12)).foregroundStyle(Theme.warning)
                }
            }
            PaperDisclosure()
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
    var issueTitle = "Issue invoice"
    let busy: Bool
    let onCollect: () -> Void
    let onIssue: () -> Void

    var body: some View {
        Group {
            if model.canOfferCollection && canCollect {
                PrimaryButton(title: "Collect payment", busy: model.isRecording, action: onCollect)
                    .disabled(!model.canRecordPayment)
            } else if model.invoice?.status == "draft", canIssue {
                PrimaryButton(title: issueTitle, busy: busy, action: onIssue)
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
                            .moneyStyle(.hero)
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
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))

                    if refundModel.didComplete {
                        Label("Refund confirmed by Thorbis", systemImage: "checkmark.circle.fill")
                            .font(Theme.font(15, weight: .medium))
                            .foregroundStyle(Theme.success)
                            .padding(15)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.successSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
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
        .thorbisConfirm("Discard the saved refund reason?",
                        message: discardMessage,
                        isPresented: $confirmDiscard,
                        actions: [ThorbisConfirmAction("Discard saved reason", role: .destructive) { refundModel.discardSavedIntent() }])
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
                    Text(title).font(Theme.font(15, weight: .medium))
                    Text("Full payment · \(money(refundModel.payment.amount.amount, currency: refundModel.payment.amount.currency))")
                        .font(Theme.font(15)).monospacedDigit()
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                PaperDisclosure()
            }
            .foregroundStyle(Theme.foreground)
            .padding(15)
            .frame(minHeight: 58)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border))
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
                            .font(Theme.font(17, weight: .medium))
                            .foregroundStyle(Theme.success)
                        Text("Thorbis confirmed the full refund of \(amountText).")
                            .font(Theme.font(15))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.successSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
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
        .thorbisConfirm("Refund the full payment of \(amountText)?",
                        message: "This returns the entire recorded payment. Partial refunds are not available here, and this action cannot be undone.",
                        isPresented: $confirmRefund,
                        actions: [ThorbisConfirmAction("Refund \(amountText)", role: .destructive) {
                            Task {
                                if await model.submitRefund() {
                                    await onRefundCompleted()
                                    dismiss()
                                }
                            }
                        }])
        .thorbisConfirm("Discard the saved refund reason?",
                        message: model.intent?.state == .draft
                            ? "This removes the saved draft reason."
                            : "This removes the saved reason the app needs to check the refund outcome safely.",
                        isPresented: $confirmDiscard,
                        actions: [ThorbisConfirmAction("Discard saved reason", role: .destructive) { model.discardSavedIntent() }])
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
            .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))

            Text("Reason for refund")
                .font(Theme.font(15, weight: .medium))
                .accessibilityAddTraits(.isHeader)
            TextEditor(text: Binding(
                get: { model.reasonDraft },
                set: { model.updateReasonDraft($0) }
            ))
            .font(Theme.font(15))
            .frame(minHeight: 136)
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border))
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
            .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
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
    @EnvironmentObject private var outbox: FieldOutbox
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
        let cents = model.pendingRequest?.amount.amount ?? min(model.collectableCents ?? 0, 1_000_000_000_000)
        _amountText = State(initialValue: paymentAmountText(cents))
        // MF-09: open on the way this phone last collected (cash, check or link); otherwise on
        // the fastest path that actually takes money today. Tap to Pay is chosen in `.task`.
        let last = InvoiceCollectionOption.lastUsed
        _method = State(initialValue: model.pendingRequest?.method ?? (last == .check ? .check : .cash))
        // OF-09: without signal the sheet opens on cash, the way that still works.
        // Cash or check still waiting to record also rules out the full-balance link (OF-08).
        let opening = (model.offlineCopy || model.waitingCents > 0) && (last == nil || last == .paymentLink) ? .cash : (last ?? .paymentLink)
        // A locked cash or check retry opens on its own tender, so it can still go to the queue offline.
        let locked: InvoiceCollectionOption = switch model.pendingRequest?.method {
        case .cash: .cash
        case .check: .check
        default: .alreadyCollected
        }
        _option = State(initialValue: model.pendingRequest == nil ? opening : locked)
        _tapToPayController = StateObject(wrappedValue: TapToPayController(invoiceID: invoice.id))
    }

    private var amountCents: Int? {
        MoneyInput.cents(amountText, maximumCents: min(model.collectableCents ?? 0, 1_000_000_000_000))
    }

    private var hasLockedIntent: Bool { model.pendingRequest != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        amountHero
                        if tapToPayAvailable && !hasLockedIntent && !offline && !paymentWaiting { tapToPayCard }
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
            .navigationDestination(isPresented: $showPayLinkShare) {
                    VStack(alignment: .leading, spacing: 18) {
                        if let payLink, let shareURL = payLink.shareURL {
                            Text("Secure payment link ready")
                                .font(Theme.font(17, weight: .medium))
                            MoneyFigure(label: "Balance due", cents: model.outstandingCents ?? 0, currency: invoice.currency)
                            Text("Share this link with \(customerName) to pay by card.")
                                .font(Theme.font(15))
                                .foregroundStyle(Theme.muted)
                            ShareLink(item: shareURL) {
                                Label("Share payment link", systemImage: "square.and.arrow.up")
                                    .inkCommit()
                            }
                            .accessibilityIdentifier("share-invoice-payment-link")
                            Button("Copy link") { UIPasteboard.general.string = shareURL.absoluteString }
                                .font(Theme.font(15, weight: .medium))
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
                            // MF-10: the link is made; Done goes back to the invoice.
                            Button("Done") { dismiss() }
                                .frame(minWidth: 44, minHeight: 44)
                        }
                    }
            }
            .thorbisConfirm(recordConfirmationTitle,
                            message: recordConfirmationMessage,
                            isPresented: $showRecordConfirmation,
                            actions: [ThorbisConfirmAction(primaryTitle) { Task { await recordPayment() } }])
            .task {
                // Open on the iPhone reader when this workspace and phone can take cards in person.
                if tapToPayAvailable && model.pendingRequest == nil && !paymentWaiting && InvoiceCollectionOption.lastUsed == nil { option = .tapToPay }
                await loadReceiptDestination()
            }
        }
    }

    private var amountHero: some View {
        VStack(spacing: 7) {
            PaperEyebrow(reference: "INV-\(invoice.id.suffix(4).uppercased())", text: customerName)
            HStack(spacing: 3) {
                // MF-01: the amount being collected is the screen.
                Text("$")
                    .font(Theme.moneyFont(.hero))
                    .foregroundStyle(Theme.muted)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .font(Theme.moneyFont(.hero))
                    .monospacedDigit()
                    .tracking(-0.7)
                    .multilineTextAlignment(.leading)
                    .fixedSize()
                    .accessibilityLabel("Amount to collect in dollars")
                    .disabled(hasLockedIntent || model.waitingForProjection || option == .paymentLink || option == .tapToPay)
                if !hasLockedIntent && !model.waitingForProjection && option != .paymentLink && option != .tapToPay {
                    Button("Balance") {
                        amountText = paymentAmountText(min(model.collectableCents ?? 0, 1_000_000_000_000))
                    }
                    .font(Theme.font(12, weight: .medium))
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
            .frame(maxWidth: .infinity)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Balance due").font(Theme.font(15)).foregroundStyle(Theme.muted)
                Text(money(model.outstandingCents ?? 0, currency: invoice.currency)).moneyStyle(.row).foregroundStyle(Theme.foreground)
            }
            .accessibilityElement(children: .combine)
            if amountCents == nil {
                // MA-15: words in body colour; the amount rule is the exit.
                Label("Enter an amount up to the balance due.", systemImage: "exclamationmark.circle")
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.foreground)
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
            .background(option == .tapToPay ? Theme.brandSurface : Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(option == .tapToPay ? Theme.brand.opacity(0.5) : Theme.border, lineWidth: 1))
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
        guard !paymentWaiting else { return }
        let tapToPay = tapToPayController
        let before = model.payments.count
        await tapToPay.charge(api: api) { [model] in
            await model.load()
            return model.payments.count > before || model.outstandingCents == 0
        }
        if tapToPay.phase == .paid {
            InvoiceCollectionOption.lastUsed = nil
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
                optionRow(title: "Card · send payment link", subtitle: paymentLinkSubtitle,
                          icon: "link", selected: option == .paymentLink, busy: isCreatingPayLink, needsSignal: true,
                          unavailable: paymentWaiting) {
                    guard !hasLockedIntent && !model.waitingForProjection else { return }
                    option = .paymentLink
                    amountText = paymentAmountText(min(model.outstandingCents ?? 0, 1_000_000_000_000))
                }
                Divider().overlay(Theme.border).padding(.leading, 48)
                optionRow(title: "Check", subtitle: offline ? "Records when you're back online" : "Record a check already received", icon: "doc.text.viewfinder",
                          selected: option == .check) {
                    guard !hasLockedIntent && !model.waitingForProjection else { return }
                    option = .check
                    method = .check
                }
                Divider().overlay(Theme.border).padding(.leading, 48)
                optionRow(title: "Cash", subtitle: offline ? "Records when you're back online" : "Record cash received", icon: "banknote",
                          selected: option == .cash) {
                    guard !hasLockedIntent && !model.waitingForProjection else { return }
                    option = .cash
                    method = .cash
                }
                Divider().overlay(Theme.border).padding(.leading, 48)
                optionRow(title: "Already collected", subtitle: offline ? "Needs signal" : "Record a card, ACH, or other tender", icon: "checkmark.circle",
                          selected: option == .alreadyCollected, needsSignal: true) {
                    guard !hasLockedIntent && !model.waitingForProjection else { return }
                    option = .alreadyCollected
                }
            }
            .padding(.horizontal, 12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border, lineWidth: 1))
            .disabled(hasLockedIntent || model.waitingForProjection)
        }
    }

    private var existingPaymentMethod: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hasLockedIntent ? "Payment already collected by" : "Tender already received")
                .font(Theme.font(13, weight: .medium))
                .foregroundStyle(Theme.muted)
            ThorbisSelect(options: FieldPaymentMethod.allCases.map { ($0, $0.rawValue.uppercased()) },
                          selection: $method, menuTitle: "Tender already received")
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
                .font(.system(size: 15))
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

    /// No signal, or only the copy saved on this phone: card, link and Tap to Pay can't work (OF-09).
    private var offline: Bool { session.isOffline || model.offlineCopy }

    /// Cash or check on this phone that hasn't recorded yet. Tap to Pay and the link charge the
    /// whole balance, so they wait until it lands rather than charge money already taken (OF-08).
    private var paymentWaiting: Bool { model.waitingCents > 0 }

    private var paymentLinkSubtitle: String {
        if offline { return "Card payments need signal" }
        if paymentWaiting { return "After the waiting payment records" }
        return "Text or email a secure card checkout"
    }

    private func optionRow(title: String, subtitle: String, icon: String, selected: Bool,
                           busy: Bool = false, needsSignal: Bool = false, unavailable: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selected ? Theme.brand : Theme.muted)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.font(15, weight: .medium))
                    Text(subtitle).font(Theme.font(12)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                if busy {
                    ProgressView().controlSize(.small)
                } else if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.brandText)
                }
                else {
                    PaperDisclosure()
                }
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy || !session.can("invoice.payment.create", feature: "payments") || !model.canRecordPayment || (needsSignal && offline) || unavailable)
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
        if offline && option != .cash && option != .check { return false }
        if (option == .tapToPay || option == .paymentLink) && paymentWaiting { return false }
        if option == .tapToPay { return tapToPayAvailable && (model.collectableCents ?? 0) > 0 && tapToPay?.busy != true }
        if option == .paymentLink { return model.collectableCents == amountCents }
        guard let amountCents else { return false }
        if hasLockedIntent {
            return model.pendingRequest?.amount.amount == amountCents && model.pendingRequest?.method == method
        }
        return amountCents <= (model.collectableCents ?? 0)
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
        // MF-08: the commit already says "Record $480.00 cash received", so cash and check record
        // at once. A payment collected elsewhere still confirms that nothing is charged here.
        if hasLockedIntent || option == .cash || option == .check {
            await recordPayment()
        } else {
            showRecordConfirmation = true
        }
    }

    private func recordPayment() async {
        guard let amountCents else { return }
        let accepted = await model.record(amountCents: amountCents, method: method)
        if accepted {
            if option == .cash || option == .check { InvoiceCollectionOption.lastUsed = option }
            // The sheet closes on success, so a view-bound sensoryFeedback would never play.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        }
    }

    private func createPayLink() async {
        guard session.can("invoice.payment.create", feature: "payments"),
              model.canRecordPayment, !paymentWaiting, model.outstandingCents == amountCents else { return }
        isCreatingPayLink = true
        defer { isCreatingPayLink = false }
        do {
            payLink = try await api.openFieldPayLink(invoice.id)
            payLinkError = nil
            InvoiceCollectionOption.lastUsed = .paymentLink
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

private enum InvoiceCollectionOption: String, Equatable {
    case tapToPay
    case paymentLink
    case cash
    case check
    case alreadyCollected

    /// MF-09: the last way this phone collected, so the sheet opens on it. Nil means Tap to Pay
    /// (when available) or the payment link. "Already collected" is never remembered.
    static var lastUsed: InvoiceCollectionOption? {
        get {
            UserDefaults.standard.string(forKey: "thorbis.payment.lastOption")
                .flatMap(InvoiceCollectionOption.init(rawValue:))
                .flatMap { [InvoiceCollectionOption.cash, .check, .paymentLink].contains($0) ? $0 : nil }
        }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: "thorbis.payment.lastOption") }
    }
}

@MainActor
private func paymentDetail(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(label).foregroundStyle(Theme.muted)
        Spacer()
        // MF-02: amounts in the detail read at the line size; dates stay body text.
        if value.first == "$" || value.first == "-" {
            Text(value).moneyStyle(.line).foregroundStyle(Theme.foreground)
        } else {
            Text(value).foregroundStyle(Theme.foreground).multilineTextAlignment(.trailing)
        }
    }
    .font(Theme.font(15))
    .padding(.vertical, 12)
}

private func paymentDate(_ value: String) -> String {
    guard let date = ISO8601DateFormatter().date(from: value) else { return value }
    return date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
}

func paymentAmountText(_ cents: Int) -> String {
    "\(cents / 100).\(String(format: "%02d", cents % 100))"
}
