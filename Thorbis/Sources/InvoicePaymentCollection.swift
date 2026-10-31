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
    private let expectedJobScope: JobDocumentScope?
    private let intentStore: InvoicePaymentIntentStore
    private let makeIdempotencyKey: () -> String
    private var acceptedPaymentID: String?
    private var verifiedHistoryGeneration: UUID?

    init(api: APIClient, invoiceID: String,
         intentStore: InvoicePaymentIntentStore = .shared,
         makeIdempotencyKey: @escaping () -> String = { UUID().uuidString.lowercased() },
         expectedJobScope: JobDocumentScope? = nil) {
        self.api = api
        self.invoiceID = invoiceID
        self.expectedJobScope = expectedJobScope
        self.intentStore = intentStore
        self.makeIdempotencyKey = makeIdempotencyKey
    }

    var totalCents: Int? {
        guard let invoice, invoice.currency == "USD" else { return nil }
        return CustomerDocumentAmounts(lines: invoice.lines, currency: invoice.currency,
                                       amountPaid: invoice.amountPaid)?.total
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

    /// Why Collect payment is off, while nothing is running; nil when it can be pressed. Every
    /// place that offers Collect payment shows it under the commit (design.thorbis.com Controls).
    var collectBlockedReason: String? {
        guard !canRecordPayment, !isRecording, !isLoading else { return nil }
        if waitingForProjection { return "The last payment is still updating on this invoice." }
        if loadError != nil { return "Payments need a fresh copy of this invoice. Pull down to refresh." }
        if !historyComplete { return "Checking this invoice's payments first." }
        return "Payment history is still syncing with the invoice. Pull down to refresh."
    }

    /// The server settles this attempt through its verified Stripe webhook. Neither another
    /// receipt nor a zero invoice balance proves that this particular card was recorded.
    func hasRecordedCardPresentPayment(_ intent: CardPresentIntent) -> Bool {
        guard historyComplete, !isLoading, loadError == nil,
              verifiedHistoryGeneration == api.requestGeneration, let invoice,
              paymentTotalCents == invoice.amountPaid,
              UUID(uuidString: intent.attemptId) != nil,
              intent.amount.amount > 0, intent.amount.currency == invoice.currency else { return false }
        // Compatibility with prepareInvoiceCardPresentIntent / recordSucceededAttempt:
        // the deployed response omits its opaque key, but canonical history retains it.
        // If the server changes this convention, stay pending rather than infer success.
        let key = "tap:\(invoice.id):\(intent.attemptId)"
        return payments.contains { payment in
            payment.organizationId == invoice.organizationId && payment.invoiceId == invoice.id &&
                payment.idempotencyKey == key && payment.method == "card" &&
                payment.status == .recorded && payment.amount.amount == intent.amount.amount &&
                payment.amount.currency == intent.amount.currency && (payment.refundedAmount ?? 0) == 0 &&
                (payment.netAmount?.amount ?? payment.amount.amount) == intent.amount.amount
        }
    }

    func load() async {
        guard !isLoading else { return }
        let generation = api.requestGeneration
        isLoading = true
        historyComplete = false
        verifiedHistoryGeneration = nil
        payments = []
        defer { isLoading = false }
        do {
            try Task.checkCancellation()
            let loadedInvoice = try await api.fieldInvoice(invoiceID)
            try Task.checkCancellation()
            guard generation == api.requestGeneration else { throw CancellationError() }
            guard acceptInvoiceMutationResponse(loadedInvoice) else { return }
            // A copy saved on this phone can be read, never collected on: payments wait for a live read.
            if api.savedCopyDate("/v1/invoices/\(invoiceID)") != nil {
                loadError = "Saved on this phone. Payments need a connection."
                return
            }
            if pendingRequest == nil {
                pendingRequest = intentStore.load(organizationID: loadedInvoice.organizationId, invoiceID: invoiceID)
            }
            try Task.checkCancellation()
            let loadedPayments = try await api.fieldPayments(invoiceID)
            try Task.checkCancellation()
            guard generation == api.requestGeneration else { throw CancellationError() }
            guard validHistory(loadedPayments, for: loadedInvoice) else {
                throw Problem(title: "Payment history couldn't be verified. Refresh this invoice to try again.", status: nil, detail: nil)
            }
            payments = loadedPayments
            verifiedHistoryGeneration = generation
            historyComplete = true
            loadError = nil
            if acceptedPaymentID == nil, let request = pendingRequest,
               let recovered = payments.first(where: { $0.idempotencyKey == request.idempotencyKey }) {
                acceptedPaymentID = recovered.id
            }
            reconcileAcceptedPayment()
        } catch is CancellationError {
            invoice = nil
            payments = []
            pendingRequest = nil
            historyComplete = false
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func validHistory(_ records: [FieldPaymentRecord], for invoice: InvoiceRecord) -> Bool {
        var ids = Set<String>()
        return records.allSatisfy { payment in
            guard payment.invoiceId == invoice.id, payment.organizationId == invoice.organizationId,
                  ids.insert(payment.id.lowercased()).inserted,
                  payment.amount.currency == invoice.currency, payment.amount.amount > 0 else { return false }
            let refunded = payment.refundedAmount ?? (payment.status == .refunded ? payment.amount.amount : 0)
            guard refunded >= 0, refunded <= payment.amount.amount else { return false }
            let received = payment.amount.amount - refunded
            if payment.status == .refunded && received != 0 { return false }
            if let net = payment.netAmount {
                return net.currency == invoice.currency && net.amount == received
            }
            // Legacy full refunds can omit netAmount; a partial refund must supply it.
            return refunded == 0 || payment.status == .refunded
        }
    }

    @discardableResult
    func acceptInvoiceMutationResponse(_ updated: InvoiceRecord) -> Bool {
        guard updated.id == invoiceID, expectedJobScope?.contains(updated) != false else {
            invoice = nil
            payments = []
            historyComplete = false
            loadError = "This invoice couldn't be verified. Refresh the job before continuing."
            return false
        }
        invoice = updated
        return true
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
        VStack(alignment: .leading, spacing: 0) {
            // Same header grammar as "Line items" above it (redesign: semibold header and count).
            // Collect payment lives in the bottom bar; one entry point, not two.
            SectionHeader(title: "Payments", count: model.payments.isEmpty ? nil : model.payments.count)
                .padding(.bottom, 2)

            Well {
                if let loadError = model.loadError {
                    VStack(alignment: .leading, spacing: 8) {
                        ErrorBanner(message: loadError) { await model.load() }
                    }
                    .padding(15)
                } else if model.isLoading && !model.historyComplete {
                    SkeletonRows(count: 2, leading: false, inset: 15)
                        .padding(.vertical, 8)
                } else if model.payments.isEmpty {
                    // Empty names the one action (design.thorbis.com States).
                    Text(invoice.status == "draft" ? "No payments. Issue the invoice to take one."
                         : invoice.status == "issued" ? "No payments yet. Collect payment records the first one."
                         : "No payments recorded.")
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(PaperCardMetrics.inset)
                } else {
                    ForEach(model.payments) { payment in
                        Button { selectedPayment = payment } label: {
                            paymentRow(payment)
                        }
                        .buttonStyle(RowPressStyle())
                        .padding(.horizontal, PaperCardMetrics.inset)
                        .frame(minHeight: 56)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let modelError = model.paymentError {
                ErrorBanner(message: modelError).padding(.top, 12)
            }
            if !model.isLoading, model.loadError == nil, model.historyComplete,
               model.paymentTotalCents != invoice.amountPaid {
                Label("Payment history is still syncing with the invoice.", systemImage: "arrow.triangle.2.circlepath")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 2)
                    .padding(.top, 10)
            }
        }
        .onChange(of: model.invoice?.amountPaid) { _, _ in
            if let updated = model.invoice { onInvoiceUpdated(updated) }
        }
        .sheet(item: $selectedPayment) { payment in SheetSurface {
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
        } }
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

    /// v2: the method and when on the left; the tabular amount over the status word on the right.
    private func paymentRow(_ payment: FieldPaymentRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(FieldPaymentMethod(rawValue: payment.method)?.displayName ?? payment.method.capitalized)
                    .font(Theme.font(15, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                Text(paymentDate(payment.recordedAt))
                    .font(Theme.font(13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                let amount = payment.netAmount ?? payment.amount
                Text(money(amount.amount, currency: amount.currency))
                    .font(Theme.rowAmountFont(15))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(Theme.foreground)
                StatusLabel(tone: payment.status == .refunded ? .cancelled : .done,
                            word: payment.status == .refunded ? "Refunded" : "Received", emphasis: .quiet)
            }
        }
        .padding(.vertical, 8)
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
        if (model.canOfferCollection && canCollect) || (model.invoice?.status == "draft" && canIssue) { bar }
    }

    private var bar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.canOfferCollection && canCollect {
                PrimaryButton(title: "Collect payment", busy: model.isRecording, action: onCollect)
                    .disabled(!model.canRecordPayment)
                    .accessibilityHint(collectBlockedReason ?? "")
                // A disabled commit says why (design.thorbis.com Controls).
                if let collectBlockedReason {
                    Text(collectBlockedReason).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                }
            } else if model.invoice?.status == "draft", canIssue {
                PrimaryButton(title: issueTitle, busy: busy, action: onIssue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.canvas)
    }

    private var collectBlockedReason: String? { model.collectBlockedReason }
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
                    VStack(alignment: .leading, spacing: 2) {
                        let received = refundModel.payment.netAmount ?? refundModel.payment.amount
                        Text("Net received")
                            .font(Theme.font(13, weight: .medium))
                            .foregroundStyle(Theme.muted)
                        Text(money(received.amount, currency: received.currency))
                            .font(Theme.moneyHeroFont).tracking(-0.6)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .accessibilityElement(children: .combine)

                    VStack(spacing: 0) {
                        paymentDetail("Method", FieldPaymentMethod(rawValue: refundModel.payment.method)?.displayName ?? refundModel.payment.method.capitalized)
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
                    .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 4)
                    .panelBackground(cornerRadius: Theme.cardRadius)

                    if refundModel.didComplete {
                        StateNote(tone: .done, word: "Refunded", message: "Thorbis confirmed the refund.")
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
            .background(Theme.canvas)
            .foregroundStyle(Theme.foreground)
            .navigationTitle("Payment details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(refundModel.isSubmitting)
                }
            }
            #if DEBUG
            .thorbisDestination(isPresented: $previewRefundForm) {
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

    /// The way into a refund, in the danger tone with its consequence under it. No box (v2).
    private func refundLink(title: String) -> some View {
        NavigationLink {
            InvoicePaymentRefundForm(model: refundModel, onRefundCompleted: onRefundCompleted).thorbisBackButton()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.destructive)
                    Text("Returns the full \(money(refundModel.payment.amount.amount, currency: refundModel.payment.amount.currency)) to the customer")
                        .font(Theme.font(14)).monospacedDigit()
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                PaperDisclosure()
            }
            .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
            .frame(minHeight: 56)
            .panelBackground(cornerRadius: Theme.cardRadius)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
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
    @State private var reasonError: String?

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
                    StateNote(tone: .done, word: "Refunded", message: "Thorbis confirmed the full refund of \(amountText).")
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
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if showsReasonForm {
                // Destructive is a tone (design.thorbis.com): the same commit in the danger colour, its
                // word naming the consequence. Not pre-disabled: a short reason is said under the field.
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        reasonFocused = false
                        if model.canSubmitRefund { reasonError = nil; confirmRefund = true }
                        else { reasonError = refundBlockedReason }
                    } label: {
                        Text("Refund \(amountText)").dangerCommit()
                    }
                    .buttonStyle(PressStyle())
                    .disabled(model.isSubmitting)
                    .accessibilityIdentifier("payment-refund-review")
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Theme.canvas)
            }
        }
        .navigationTitle("Refund payment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ThorbisToolbarItem(placement: .topBarTrailing) {
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

    /// Why the refund can't be reviewed yet, said under the reason after they press.
    private var refundBlockedReason: String {
        let count = model.reasonDraft.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
        if count < 3 { return "Write why you're refunding, at least 3 characters, like \u{201C}Charged twice.\u{201D}" }
        if count > 2_000 { return "Keep the reason under 2,000 characters." }
        return "This refund can't be started right now. Check your connection and your role, then try again."
    }

    private var reasonEntry: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Full payment").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                Text(amountText)
                    .font(Theme.moneyHeroFont).tracking(-0.6)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("Returns the entire recorded payment to the customer. Partial refunds aren't available here, and a refund can't be undone.")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            .accessibilityElement(children: .combine)

            FormField(label: "Reason", help: "\(model.reasonDraft.utf16.count) of 2,000 characters. Saved on this phone until the refund is confirmed.",
                      error: reasonError) {
                TextEditor(text: Binding(
                    get: { model.reasonDraft },
                    set: { model.updateReasonDraft($0); reasonError = nil }
                ))
                .font(Theme.font(15))
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .fieldWell()
                .overlay(alignment: .topLeading) {
                    if model.reasonDraft.isEmpty {
                        Text("Charged twice for the same visit").font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 12).padding(.vertical, 12).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .focused($reasonFocused)
                .accessibilityLabel("Reason for refund")
                .accessibilityHint("Enter between 3 and 2,000 characters")
                .accessibilityIdentifier("payment-refund-reason")
            }

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

    /// Pending is not success: the state as a word, what is known, and the way to check. No tinted box.
    var body: some View {
        if let intent = model.intent {
            VStack(alignment: .leading, spacing: 12) {
                StateNote(tone: intent.state == .draft ? .scheduled : .inProgress,
                          word: title(for: intent.state), message: message(for: intent.state))

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
            .frame(maxWidth: .infinity, alignment: .leading)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFocused: Bool
    @State private var amountText: String
    @State private var option: InvoiceCollectionOption
    @State private var showRecordConfirmation = false
    @State private var isCreatingPayLink = false
    @State private var payLink: FieldInvoicePayLink?
    @State private var payLinkBalanceCents: Int?
    @State private var payLinkError: String?
    @State private var showPayLinkShare = false
    @State private var receiptDestination: String?
    @State private var receiptDestinationLoaded = false
    @State private var amountError: String?
    @StateObject private var tapToPayController: TapToPayController
    private var tapToPay: TapToPayController? { tapToPayController }

    init(model: InvoicePaymentCollectionModel, invoice: InvoiceRecord) {
        self.model = model
        self.invoice = invoice
        let cents = model.pendingRequest?.amount.amount ?? min(model.outstandingCents ?? 0, 1_000_000_000_000)
        _amountText = State(initialValue: paymentAmountText(cents))
        // MF-09: open on the way this phone last collected (cash, check or link); otherwise on
        // the fastest path that actually takes money today. Tap to Pay is chosen in `.task`.
        let last = InvoiceCollectionOption.lastUsed
        _option = State(initialValue: InvoiceCollectionOption.initial(
            pendingMethod: model.pendingRequest?.method, lastUsed: last))
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
                    // v2 modal: the amount large, the method as quiet chips with the rest in a popover,
                    // the custom amount in a sunk well with its $ inside, then the one ink commit.
                    VStack(alignment: .leading, spacing: 24) {
                        amountHero
                        if hasLockedIntent || model.waitingForProjection {
                            VStack(alignment: .leading, spacing: 6) {
                                pendingNote
                                // What the last check said, quietly, so a second failed check still shows.
                                if hasLockedIntent, let paymentError = model.paymentError {
                                    Text("Last answer: \(paymentError)").font(Theme.font(13)).foregroundStyle(Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        paymentOptions
                        if option.takesCustomAmount && !hasLockedIntent && !model.waitingForProjection { amountField }
                        receiptRow
                        if let payLinkError { ErrorBanner(message: payLinkError) }
                        if let paymentError = model.paymentError, !hasLockedIntent, !model.waitingForProjection {
                            ErrorBanner(message: paymentError)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)

                footer
            }
            .background(Theme.surface.ignoresSafeArea())
            .foregroundStyle(Theme.foreground)
            .navigationTitle("Collect payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // v2 sheet grammar: the close circle at top right.
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    PaperCircleButton(symbol: "xmark", label: "Close", size: 30, fill: Theme.fill) { dismiss() }
                }
                ThorbisKeyboardDoneBar { amountFocused = false }
            }
            .thorbisDestination(isPresented: $showPayLinkShare) {
                InvoicePaymentLinkView(
                    model: model, payLink: payLink, requestedBalanceCents: payLinkBalanceCents,
                    customerName: customerName, isCreating: isCreatingPayLink,
                    canCreate: session.can("invoice.payment.create", feature: "payments") && model.canRecordPayment && !isCreatingPayLink,
                    error: payLinkError,
                    onCreate: {
                        amountText = paymentAmountText(min(model.outstandingCents ?? 0, 1_000_000_000_000))
                        Task { await createPayLink() }
                    },
                    onDone: { dismiss() })
            }
            .thorbisConfirm(recordConfirmationTitle,
                            message: recordConfirmationMessage,
                            isPresented: $showRecordConfirmation,
                            actions: [ThorbisConfirmAction(primaryTitle) { Task { await recordPayment() } }])
            .task {
                // Open on the iPhone reader when this workspace and phone can take cards in person.
                if tapToPayAvailable && model.pendingRequest == nil && InvoiceCollectionOption.lastUsed == nil { option = .tapToPay }
                await loadReceiptDestination()
#if DEBUG
                if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-payment-timeout"),
                   model.pendingRequest == nil {
                    // Drives the real record path into a timeout (the preview answers POST …/payments with one).
                    option = .cash
                    amountText = paymentAmountText(min(model.outstandingCents ?? 0, 1_000_000_000_000))
                    await recordPayment()
                }
                if let link = PaperPreview.paymentLinkPreview {
                    option = .paymentLink
                    payLink = link
                    payLinkBalanceCents = model.outstandingCents
                    showPayLinkShare = true
                }
#endif
            }
        }
    }

    /// The amount being collected: who and which invoice, then the figure at 30pt, then what's due.
    private var amountHero: some View {
        VStack(spacing: 4) {
            PaperEyebrow(reference: "INV-\(invoice.id.suffix(4).uppercased())", text: customerName)
            // MF-01: the amount being collected is the screen.
            Text(money(amountCents ?? model.pendingRequest?.amount.amount ?? model.outstandingCents ?? 0, currency: invoice.currency))
                .font(Theme.moneyHeroFont).tracking(-0.6)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .padding(.top, 4)
                .accessibilityLabel("Collecting \(money(amountCents ?? model.outstandingCents ?? 0, currency: invoice.currency))")
            Text("Balance due \(money(model.outstandingCents ?? 0, currency: invoice.currency))")
                .font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    /// The custom amount: a sunk well with the $ inside, the full balance one tap away, help under it
    /// and the error in help's place. Checked when they press the commit, not on every key.
    private var amountField: some View {
        FormField(label: "Amount", help: "Up to the balance due. Take part now and the rest later.", error: amountError) {
            HStack(spacing: 8) {
                MoneyFieldWell {
                    TextField(paymentAmountText(model.outstandingCents ?? 0), text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .font(Theme.monoFont(16))
                        .accessibilityLabel("Amount to collect in dollars")
                        .onChange(of: amountText) { _, _ in amountError = nil }
                }
                if amountCents != model.outstandingCents {
                    Button("Full balance") {
                        amountText = paymentAmountText(min(model.outstandingCents ?? 0, 1_000_000_000_000))
                        amountError = nil
                    }
                    .font(Theme.font(13, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(PressStyle())
                }
            }
        }
    }

    /// Pending is not success (design.thorbis.com "Immediate acknowledgment is not confirmed success"):
    /// a payment was sent and nothing has confirmed it. Say what is known and offer the check.
    private var pendingNote: some View {
        let amount = model.pendingRequest.map { money($0.amount.amount, currency: $0.amount.currency) }
        return StateNote(
            tone: .inProgress,
            word: model.waitingForProjection ? "Recorded, updating" : "Not confirmed yet",
            message: model.waitingForProjection
                ? "Thorbis accepted the payment. The invoice and its payment history are still catching up. Check again in a moment."
                : "The last attempt\(amount.map { " to record \($0)" } ?? "") didn't get a clear answer, so the result isn't known yet. Check its status before you take money again; checking uses the same request and can't record it twice.")
        .accessibilityIdentifier("payment-pending")
    }

    private var tapToPayHeadline: String {
        switch tapToPay?.phase {
        case .preparing: "Getting ready…"
        case .waitingForCard: "Hold card near your phone"
        case .processing: "Processing…"
        case .recording: "Approved · recording payment"
        case .paid: "Paid"
        case .unavailable: "Choose another payment method"
        default: "Tap to Pay on iPhone"
        }
    }

    private var tapToPayAvailable: Bool {
        TapToPayReadiness.allows(
            buildEnabled: TapToPayController.buildEnabled,
            deviceSupported: TapToPayController.deviceSupported,
            featureEnabled: session.isFeatureOn(TapToPayController.feature),
            canCollect: session.can("invoice.payment.create", feature: "payments")
        )
    }

    private func charge() async {
        let tapToPay = tapToPayController
        await tapToPay.charge(api: api) { [model] intent in
            await model.load()
            return model.hasRecordedCardPresentPayment(intent)
        }
        if tapToPay.phase == .paid {
            InvoiceCollectionOption.lastUsed = nil
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        }
    }

    /// How they're paying: Tap to Pay (when this iPhone can), a payment link, check and cash as quiet
    /// chips, and the other received methods in a popover from their chip. The help under the row
    /// says what the chosen method does.
    private var paymentOptions: some View {
        let locked = hasLockedIntent || model.waitingForProjection
        let off = locked || !session.can("invoice.payment.create", feature: "payments") || !model.canRecordPayment
        return FormField(label: "Method", help: methodHelp) {
            FlowRow(spacing: 8, lineSpacing: 8) {
                if tapToPayAvailable && !hasLockedIntent {
                    methodChip("Tap to Pay", selected: option == .tapToPay, off: locked) {
                        option = .tapToPay
                        amountText = paymentAmountText(min(model.outstandingCents ?? 0, 1_000_000_000_000))
                    }
                    .accessibilityIdentifier("tap-to-pay")
                }
                methodChip("Payment link", selected: option == .paymentLink, busy: isCreatingPayLink, off: off) {
                    option = .paymentLink
                    amountText = paymentAmountText(min(model.outstandingCents ?? 0, 1_000_000_000_000))
                }
                .accessibilityLabel("Card · send payment link")
                methodChip("Check", selected: option == .check, off: off) { option = .check }
                methodChip("Cash", selected: option == .cash, off: off) { option = .cash }
                ThorbisMenu(items: [
                    ThorbisMenuItem("Bank transfer (ACH) received", icon: "building.columns", isSelected: option == .bankTransfer) { option = .bankTransfer },
                    ThorbisMenuItem("Card collected elsewhere", icon: "creditcard", isSelected: option == .externalCard) { option = .externalCard }
                ], title: "Payment received", accessibilityLabel: "Other payment received") {
                    chipLabel(option.isExternalReceipt ? (option.recordedMethod?.displayName ?? "Other") : "Other",
                              selected: option.isExternalReceipt, trailingSymbol: "chevron.down")
                }
                .disabled(off)
                .accessibilityIdentifier("received-payment-methods")
            }
        }
    }

    private var methodHelp: String {
        switch option {
        case .tapToPay: tapToPayHeadline == "Tap to Pay on iPhone" ? "Contactless cards, Apple Pay and other wallets, on this iPhone." : tapToPayHeadline
        case .paymentLink: "Text or email a secure card checkout for the full balance."
        case .check: "Record a check already in your hand."
        case .cash: "Record cash already in your hand."
        case .bankTransfer, .externalCard: "Only record money already received. This doesn't charge a card or bank account."
        }
    }

    private func methodChip(_ title: String, selected: Bool, busy: Bool = false, off: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            chipLabel(title, selected: selected, busy: busy)
        }
        .buttonStyle(PressStyle())
        .disabled(off || busy)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A method chip: a pill, ink when chosen (the one selected thing), quiet fill at rest.
    private func chipLabel(_ title: String, selected: Bool, busy: Bool = false, trailingSymbol: String? = nil) -> some View {
        HStack(spacing: 6) {
            if busy { ProgressView().controlSize(.mini).tint(selected ? Theme.onInk : Theme.foreground) }
            Text(title).font(Theme.font(14, weight: .medium)).lineLimit(1)
            if let trailingSymbol {
                Image(systemName: trailingSymbol).font(.system(size: 10, weight: .medium)).accessibilityHidden(true)
            }
        }
        .foregroundStyle(selected ? Theme.onInk : Theme.foreground)
        .padding(.horizontal, 14).frame(minHeight: 34)
        .background(selected ? Theme.ink : Theme.fill, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
        .padding(.vertical, 5).contentShape(Rectangle()).padding(.vertical, -5)
    }

    private var receivedPaymentNote: some View {
        Label("Only record money you have already received. This does not charge a card or bank account.", systemImage: "info.circle")
            .font(Theme.font(13))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var receiptRow: some View {
        EvidenceProperty(label: "Receipt to", value: receiptDestination ?? (receiptDestinationLoaded ? "No email on file" : "Loading contact…"))
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
            .accessibilityHint(blockedReason ?? "")
            // Money keeps its guard, but a disabled commit always says why.
            if let blockedReason {
                Text(blockedReason).font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Theme.surface)
    }

    private var primaryTitle: String {
        if model.waitingForProjection { return "Check payment status" }
        if hasLockedIntent { return "Check payment status" }
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
        case .bankTransfer:
            return amountCents.map { "Record \(money($0, currency: invoice.currency)) bank transfer received" } ?? "Record bank transfer received"
        case .externalCard:
            return amountCents.map { "Record \(money($0, currency: invoice.currency)) card payment received" } ?? "Record card payment received"
        }
    }

    /// Why the commit is off, in a sentence (nil while it can be pressed or while work is running).
    /// The amount is not a reason: it's checked when they press (design.thorbis.com "Don't lock the commit").
    private var blockedReason: String? {
        guard !canSubmit, !model.isRecording, !model.isLoading, !isCreatingPayLink, tapToPay?.busy != true else { return nil }
        if !session.can("invoice.payment.create", feature: "payments") { return "Your role can't take payments. Ask your office." }
        if !model.canRecordPayment { return "This invoice can't take a payment right now." }
        if option == .tapToPay {
            if !tapToPayAvailable { return "Tap to Pay isn't ready on this iPhone. Pick another way to pay." }
            return (model.outstandingCents ?? 0) > 0 ? nil : "Nothing is due on this invoice."
        }
        if option == .paymentLink { return "A payment link is for the full balance due." }
        return nil
    }

    private var canSubmit: Bool {
        guard !model.isRecording, !model.isLoading, !isCreatingPayLink else { return false }
        if model.waitingForProjection { return true }
        guard session.can("invoice.payment.create", feature: "payments"), model.canRecordPayment else { return false }
        if option == .tapToPay { return tapToPayAvailable && (model.outstandingCents ?? 0) > 0 && tapToPay?.busy != true }
        if option == .paymentLink { return model.outstandingCents == amountCents }
        return true
    }

    /// The amount problem shown under the field after they press the commit; nil when it's fine.
    private var amountProblem: String? {
        if hasLockedIntent {
            let matches = model.pendingRequest?.amount.amount == amountCents && model.pendingRequest?.method == option.recordedMethod
            return matches ? nil : "Finish the payment already started first, with the same amount and method."
        }
        guard let amountCents else {
            return "Enter an amount up to \(money(model.outstandingCents ?? 0, currency: invoice.currency)), like \(paymentAmountText(model.outstandingCents ?? 0))."
        }
        return amountCents > (model.outstandingCents ?? 0)
            ? "That's more than the balance due of \(money(model.outstandingCents ?? 0, currency: invoice.currency))." : nil
    }

    private var recordConfirmationTitle: String {
        switch option {
        case .cash: "Confirm cash received"
        case .check: "Confirm check received"
        case .bankTransfer: "Confirm bank transfer received"
        case .externalCard: "Confirm card payment received"
        case .paymentLink, .tapToPay: "Confirm payment received"
        }
    }

    private var recordConfirmationMessage: String {
        guard let amountCents else { return "Confirm the payment was received before recording it." }
        return "Confirm \(money(amountCents, currency: invoice.currency)) was already received by \(option.recordedMethod?.displayName ?? "the selected method"). This action records the payment; it does not charge the customer."
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
        if let problem = amountProblem {
            amountError = problem
            return
        }
        // MF-08: the commit already says "Record $480.00 cash received", so cash and check record
        // at once. A payment collected elsewhere still confirms that nothing is charged here.
        if hasLockedIntent || option == .cash || option == .check {
            await recordPayment()
        } else {
            showRecordConfirmation = true
        }
    }

    private func recordPayment() async {
        guard let amountCents, let method = option.recordedMethod else { return }
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
              model.canRecordPayment, model.outstandingCents == amountCents else { return }
        isCreatingPayLink = true
        defer { isCreatingPayLink = false }
        do {
            let requestedBalance = model.outstandingCents
            payLink = try await api.openFieldPayLink(invoice.id)
            payLinkBalanceCents = requestedBalance
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
    guard let date = JobFiltering.date(value) else { return value }
    return date.stampLabel()
}

func paymentAmountText(_ cents: Int) -> String {
    "\(cents / 100).\(String(format: "%02d", cents % 100))"
}

private extension InvoiceCollectionOption {
    /// Methods that record money already in hand, so the amount may be part of the balance.
    var takesCustomAmount: Bool { self == .cash || self == .check || isExternalReceipt }
}
