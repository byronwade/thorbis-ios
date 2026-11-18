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
    private let expectedJobScope: JobDocumentScope?
    private let intentStore: InvoicePaymentIntentStore
    private let makeIdempotencyKey: () -> String
    private var acceptedPaymentID: String?
    private var verifiedHistoryGeneration: UUID?
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []

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
        // Offline, a saved history may be missing or older than the invoice. Only cash and check can
        // be taken then, and the server checks the balance when they record (OF-08).
        canOfferCollection && !isLoading && !isRecording && !waitingForProjection &&
            (offlineCopy || (historyComplete && paymentTotalCents == invoice?.amountPaid))
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
        defer {
            isLoading = false
            let waiters = loadWaiters
            loadWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        do {
            try Task.checkCancellation()
            let loadedInvoice = try await api.fieldInvoice(invoiceID)
            try Task.checkCancellation()
            guard generation == api.requestGeneration else { throw CancellationError() }
            guard acceptInvoiceMutationResponse(loadedInvoice) else { return }
            // A copy saved on this phone is never charged: card, link and Tap to Pay wait for a live
            // read. Cash and check can still be taken and record once back online (OF-04, OF-08).
            if api.savedCopyDate("/v1/invoices/\(invoiceID)") != nil {
                guard outbox != nil else {
                    loadError = "Saved on this phone. Payments need a connection."
                    return
                }
                useOfflineCopy(loadedInvoice)
                return
            }
            offlineCopy = false
            JobDetailCache.save(invoice: loadedInvoice)
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
            JobDetailCache.save(payments: loadedPayments, invoiceID: invoiceID)
            // Saved with the payments in it, so the saved copy now holds them (OF-08).
            outbox?.forgetRecorded(seen: Set(loadedPayments.map(\.idempotencyKey)))
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
            if error.isConnectivityFailure, outbox != nil,
               let cached = invoice ?? JobDetailCache.invoice(invoiceID), acceptInvoiceMutationResponse(cached) {
                // No signal: the last copy, so cash and check can still be taken (OF-04, OF-08).
                useOfflineCopy(cached)
                return
            }
            loadError = error.localizedDescription
        }
    }

    /// Wait for a read started by another owner without changing the model's
    /// own refresh semantics (payment reconciliation may need a new read).
    func waitForCurrentLoad() async -> Bool {
        guard isLoading else { return false }
        await withCheckedContinuation { loadWaiters.append($0) }
        return true
    }

    /// Shows the copy saved on this phone so cash and check can go to the outbox (OF-08). A payment
    /// sent before the app lost signal keeps its key (OF-05).
    private func useOfflineCopy(_ cached: InvoiceRecord) {
        if pendingRequest == nil {
            pendingRequest = intentStore.load(organizationID: cached.organizationId, invoiceID: invoiceID)
        }
        if let saved = JobDetailCache.payments(invoiceID), validHistory(saved, for: cached) {
            payments = saved
            historyComplete = true
        }
        offlineCopy = true
        loadError = nil
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
    /// The invoice's number as its own screen shows it ("INV-2192"); named on a payment's detail
    /// and its refund (Paper 39M, 39I, 39S). Left out there when the screen doesn't pass it.
    var invoiceReference: String? = nil
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @State private var selectedPayment: FieldPaymentRecord?
    @State private var didOpenRefundPreview = false

    /// Nothing taken, nothing waiting to sync, and nothing loading or failed.
    private var emptyPayments: Bool {
        model.loadError == nil && !(model.isLoading && !model.historyComplete)
            && model.payments.isEmpty && outbox.waitingPayments(invoiceID: invoice.id).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Same header grammar as "Line items" above it (redesign: semibold header and count).
            // Paper 24: a brand plus at the label's trailing edge opens Collect payment, like the bar.
            // Paper 40C: with nothing taken yet, Payments is one card row ("Payments", where it
            // stands under it) with Record payment at its trailing edge. Once there are payments,
            // or something to load or report, the labelled list shows.
            if emptyPayments {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Payments").font(Theme.font(15)).foregroundStyle(Theme.foreground)
                        Text(invoice.status == "draft" ? "None yet \u{00B7} issue the invoice to take one" : "None yet")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    if model.canOfferCollection, session.can("invoice.payment.create", feature: "payments") {
                        Button(action: onCollectPayment) {
                            Text("Record payment").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.brandText)
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .disabled(!model.canRecordPayment)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            } else {
                SectionHeader(title: "Payments", count: model.payments.isEmpty ? nil : model.payments.count) {
                    if model.canOfferCollection, session.can("invoice.payment.create", feature: "payments") {
                        Button(action: onCollectPayment) {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Theme.brandText)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .disabled(!model.canRecordPayment)
                        .padding(.vertical, -6)
                        .accessibilityLabel("Record payment")
                    }
                }
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
                    } else if model.payments.isEmpty && outbox.waitingPayments(invoiceID: invoice.id).isEmpty {
                        // Empty names the one action (design.thorbis.com States).
                        Text(invoice.status == "draft" ? "No payments. Issue the invoice to take one."
                             : invoice.status == "issued" ? "No payments yet"
                             : "No payments recorded.")
                            .font(Theme.font(14))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(PaperCardMetrics.inset)
                    } else {
                        VStack(spacing: 0) {
                            // OF-08: money taken without signal is a record waiting, never Paid.
                            ForEach(outbox.waitingPayments(invoiceID: invoice.id), id: \.idempotencyKey) { waiting in
                                waitingRow(waiting)
                                    .padding(.horizontal, PaperCardMetrics.inset)
                                    .frame(minHeight: 56)
                            }
                            ForEach(model.payments) { payment in
                                Button { selectedPayment = payment } label: {
                                    paymentRow(payment)
                                }
                                .buttonStyle(RowPressStyle())
                                .padding(.horizontal, PaperCardMetrics.inset)
                                .frame(minHeight: 56)
                            }
                        }
                        .padding(.vertical, 4)
                    }
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
        .onChange(of: outbox.syncGeneration) { _, _ in
            // A queued payment or signature may have just landed: show the server's invoice, its
            // authorization and history, even when the amount paid didn't change.
            Task {
                await model.load()
                if let updated = model.invoice { onInvoiceUpdated(updated) }
            }
        }
        .sheet(item: $selectedPayment) { payment in SheetSurface {
            InvoicePaymentDetailSheet(
                payment: payment,
                invoiceReference: invoiceReference,
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

    /// A cash or check payment taken on this phone and waiting to record: same row, no detail.
    private func waitingRow(_ waiting: OutboxEntry.PaymentPayload) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(waiting.method.capitalized) received")
                    .font(Theme.font(16, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                WaitingToSyncLabel(text: "Records when you're back online")
            }
            Spacer(minLength: 8)
            Text(money(waiting.amountCents, currency: invoice.currency))
                .font(Theme.rowAmountFont(16))
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(Theme.foreground)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    /// Paper v2 row (16 Medium over 14 muted): the method and when on the left; the tabular amount over the status word on the right.
    private func paymentRow(_ payment: FieldPaymentRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(FieldPaymentMethod(rawValue: payment.method)?.displayName ?? payment.method.capitalized)
                    .font(Theme.font(16, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                Text(paymentDate(payment.recordedAt))
                    .font(Theme.font(14))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                let amount = payment.netAmount ?? payment.amount
                Text(money(amount.amount, currency: amount.currency))
                    .font(Theme.rowAmountFont(16))
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
                        .padding(.horizontal, 4)
                        .accessibilityHidden(true)
                }
            } else if model.invoice?.status == "draft", canIssue {
                PrimaryButton(title: issueTitle, busy: busy, action: onIssue)
            }
        }
        // Paper 40C: the commit pill sits 16 from the screen edge, like the cards above it.
        .padding(.horizontal, PaperCardMetrics.margin)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.canvas)
    }

    private var collectBlockedReason: String? { model.collectBlockedReason }
}

private struct InvoicePaymentDetailSheet: View {
    let invoiceReference: String?
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
        invoiceReference: String?,
        api: APIClient,
        actorID: String?,
        canRefund: Bool,
        intentStore: PaymentRefundIntentStoring,
        onRefundCompleted: @escaping () async -> Void
    ) {
        self.invoiceReference = invoiceReference
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
                // Paper 39M (payment detail): how it was paid beside the status word, the amount in the
                // largest Bold, the invoice and when; one card of the method and amounts, one of dates.
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("\(methodName) payment")
                                .font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            statusPill
                        }
                        Text(money(refundModel.payment.amount.amount, currency: refundModel.payment.amount.currency))
                            .font(Theme.font(34, weight: .bold)).monospacedDigit().tracking(-1)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(headerLine)
                            .font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4).padding(.bottom, 4)
                    .accessibilityElement(children: .combine)

                    PaperCard {
                        VStack(spacing: 0) {
                            detailRow("Method", methodName)
                            if let refundedAmount = refundModel.payment.refundedAmount, refundedAmount > 0 {
                                WellDivider(leading: 0)
                                detailRow("Refunded", "\u{2212}\(money(refundedAmount, currency: refundModel.payment.amount.currency))")
                            }
                            WellDivider(leading: 0)
                            netRow
                        }
                        .padding(.horizontal, PaperCardMetrics.inset)
                    }

                    PaperCard {
                        VStack(spacing: 0) {
                            detailRow("Recorded", paymentDate(refundModel.payment.recordedAt))
                            if let refundedAt = refundModel.payment.refundedAt {
                                WellDivider(leading: 0)
                                detailRow("Refund date", paymentDate(refundedAt))
                            }
                        }
                        .padding(.horizontal, PaperCardMetrics.inset)
                    }

                    // Paper 39M: what a refund does, in 13 under the cards, while one can be started.
                    if refundEntryTitle != nil {
                        Text(refundNote)
                            .font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.subtle)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }

                    if refundModel.didComplete {
                        StateNote(tone: .done, word: "Refunded", message: "Thorbis confirmed the refund.")
                    }

                    if let error = refundModel.errorMessage {
                        ErrorBanner(message: error)
                    }

                    if let intent = refundModel.intent {
                        if intent.state == .draft {
                            if !canRefund || !refundModel.isIntentStoreReady {
                                Text("A refund reason is saved, but the current workspace access or secure storage is unavailable.")
                                    .font(Theme.font(13))
                                    .foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 4)
                            }
                            discardReasonButton
                        } else {
                            InvoicePaymentRefundStatusPanel(model: refundModel) {
                                await onRefundCompleted()
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, PaperCardMetrics.margin)
                .padding(.top, 8).padding(.bottom, 20)
            }
            // Paper 39M: Refund is a pill on the card tone, in the danger colour, under the page.
            .safeAreaInset(edge: .bottom) {
                if let refundEntryTitle { refundBar(title: refundEntryTitle) }
            }
            .background(Theme.background)
            .foregroundStyle(Theme.foreground)
            .navigationTitle("Payment details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Paper sheet grammar: the 44 close circle on the card tone, as on Collect payment.
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    PaperCircleButton(symbol: "xmark", label: "Close", size: 44, fill: Theme.card) { dismiss() }
                        .disabled(refundModel.isSubmitting)
                }
            }
            #if DEBUG
            .thorbisDestination(isPresented: $previewRefundForm) {
                InvoicePaymentRefundForm(model: refundModel, invoiceReference: invoiceReference, onRefundCompleted: onRefundCompleted)
            }
            #endif
        }
        .interactiveDismissDisabled(refundModel.isSubmitting)
        .thorbisConfirm("Discard the saved refund reason?",
                        message: discardMessage,
                        isPresented: $confirmDiscard,
                        actions: [ThorbisConfirmAction("Discard", role: .destructive) { refundModel.discardSavedIntent() }])
        #if DEBUG
        .task {
            guard PaperPreview.enabled,
                  PaperPreview.screen == "invoice-payment-refund-form" || PaperPreview.screen == "invoice-payment-refund-confirmation" else { return }
            refundModel.updateReasonDraft("Customer approved a duplicate invoice payment.")
            previewRefundForm = true
        }
        #endif
    }

    private var methodName: String {
        FieldPaymentMethod(rawValue: refundModel.payment.method)?.displayName ?? refundModel.payment.method.capitalized
    }

    /// "INV-2192 · Nov 3, 2026, 4:18 p.m.": the invoice when this screen was told it, and when.
    private var headerLine: String {
        let when = paymentDate(refundModel.payment.recordedAt)
        guard let invoiceReference else { return when }
        return "\(invoiceReference) \u{00B7} \(when)"
    }

    /// Paper 39M's status word on its tinted pill: 12 Semibold in the success text colour.
    private var statusPill: some View {
        let refunded = refundModel.payment.status == .refunded
        let word = refunded ? "Refunded" : (refundModel.payment.method == "card" ? "Succeeded" : "Recorded")
        return Text(word)
            .font(Theme.font(12, weight: .semibold))
            .foregroundStyle(refunded ? Theme.muted : Theme.success)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(refunded ? Theme.fill : Theme.successSurface, in: Capsule())
    }

    /// A Paper 39M card row: the label in 16 on the left, its value in 16 muted on the right, 52 tall.
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(Theme.font(16)).foregroundStyle(Theme.foreground)
            Spacer(minLength: 8)
            Text(value).font(Theme.font(16)).monospacedDigit().foregroundStyle(Theme.muted)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    /// What was received after any refund: 16 Semibold against 16 Bold, green while money was kept.
    private var netRow: some View {
        let net = refundModel.payment.netAmount ?? refundModel.payment.amount
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Net").font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
            Spacer(minLength: 8)
            Text(money(net.amount, currency: net.currency))
                .font(Theme.font(16, weight: .bold)).monospacedDigit()
                .foregroundStyle(net.amount > 0 ? Theme.success : Theme.foreground)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    /// "Refund" when one can be started, "Resume refund" when a reason is saved; nil when neither.
    private var refundEntryTitle: String? {
        guard canRefund, refundModel.isIntentStoreReady else { return nil }
        if let intent = refundModel.intent { return intent.state == .draft ? "Resume refund" : nil }
        return refundModel.canOfferRefund ? "Refund" : nil
    }

    private var refundNote: String {
        let amount = money(refundModel.payment.amount.amount, currency: refundModel.payment.amount.currency)
        return refundModel.payment.method == "card"
            ? "A refund returns the full \(amount). It goes back to the card in 5 to 10 days."
            : "A refund returns the full \(amount) to the customer."
    }

    /// The way into a refund (Paper 39M): one pill on the card tone, 52 tall, its word in the danger colour.
    private func refundBar(title: String) -> some View {
        NavigationLink {
            InvoicePaymentRefundForm(model: refundModel, invoiceReference: invoiceReference, onRefundCompleted: onRefundCompleted)
                .thorbisBackButton()
        } label: {
            Text(title).paperButton(.commit, tone: .dangerQuiet, fills: true)
        }
        .buttonStyle(PressStyle())
        .accessibilityHint("Refunds the entire recorded payment after you review and confirm it")
        .paperActionBarGround()
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
    var invoiceReference: String? = nil
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
                    refundIssued
                } else if showsReasonForm {
                    reasonEntry
                } else {
                    // A check that confirms the refund leaves this screen on Refund issued (39S).
                    InvoicePaymentRefundStatusPanel(model: model) {
                        await onRefundCompleted()
                    }
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin)
            .padding(.top, 8).padding(.bottom, 20)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if showsReasonForm {
                // Paper 39I: how long a card refund takes in 13 muted over the brand commit, its word
                // naming the consequence; the confirm that follows carries the danger tone. Not
                // pre-disabled: a short reason is said under the field.
                VStack(spacing: 10) {
                    if model.payment.method == "card" {
                        Text("Refunds take 5 to 10 days to reach the card.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        reasonFocused = false
                        if model.canSubmitRefund { reasonError = nil; confirmRefund = true }
                        else { reasonError = refundBlockedReason }
                    } label: {
                        Text("Refund \(amountText)").monospacedDigit().inkCommit()
                    }
                    .buttonStyle(PressStyle())
                    .disabled(model.isSubmitting)
                    .accessibilityIdentifier("payment-refund-review")
                }
                .paperActionBarGround(top: model.payment.method == "card" ? PaperActionBarMetrics.topUnderHint : PaperActionBarMetrics.top)
            } else if model.didComplete {
                // Paper 39S: where the refund shows, in 13 over the brand Done.
                VStack(spacing: 12) {
                    Text("Shows on \(invoiceReference ?? "the invoice") and in Payments. Can't be undone.")
                        .font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.subtle)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                    PrimaryButton(title: "Done") { dismiss() }
                }
                .paperActionBarGround(top: PaperActionBarMetrics.topUnderHint)
            }
        }
        // Paper 39I: "Refund" as the large title. Refund issued (39S) has none: the check leads.
        .navigationTitle(model.didComplete ? "" : "Refund")
        .navigationBarTitleDisplayMode(model.didComplete ? .inline : .large)
        .toolbar {
            ThorbisToolbarItem(placement: .topBarTrailing) {
                // Refund issued has its own brand Done under the page.
                if !model.didComplete {
                    Button("Done") { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(model.isSubmitting)
                }
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
                                // Confirmed: this screen turns into Refund issued (39S); Done leaves it.
                                if await model.submitRefund() {
                                    await onRefundCompleted()
                                }
                            }
                        }])
        .thorbisConfirm("Discard the saved refund reason?",
                        message: model.intent?.state == .draft
                            ? "This removes the saved draft reason."
                            : "This removes the saved reason the app needs to check the refund outcome safely.",
                        isPresented: $confirmDiscard,
                        actions: [ThorbisConfirmAction("Discard", role: .destructive) { model.discardSavedIntent() }])
    }

    /// Why the refund can't be reviewed yet, said under the reason after they press.
    private var refundBlockedReason: String {
        let count = model.reasonDraft.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
        if count < 3 { return "Write why you're refunding, at least 3 characters, like \u{201C}Charged twice.\u{201D}" }
        if count > 2_000 { return "Keep the reason under 2,000 characters." }
        return "This refund can't be started right now. Check your connection and your role, then try again."
    }

    /// "INV-8790 · Card · paid $210.00": Paper 39I's line under the title.
    private var paidLine: String {
        let method = FieldPaymentMethod(rawValue: model.payment.method)?.displayName ?? model.payment.method.capitalized
        let paid = "\(method) \u{00B7} paid \(amountText)"
        guard let invoiceReference else { return paid }
        return "\(invoiceReference) \u{00B7} \(paid)"
    }

    private var reasonEntry: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Paper 39I: the invoice, how it was paid and what was paid in 15 muted under the title,
            // then the refund amount centred in the largest Bold. Paper's Full / Custom choice is left
            // out: only full refunds are available.
            Text(paidLine)
                .font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            VStack(spacing: 8) {
                Text(amountText)
                    .font(Theme.paymentAmountFont()).tracking(Theme.paymentAmountTracking)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text("Returns the entire recorded payment to the customer. Partial refunds aren't available here, and a refund can't be undone.")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.subtle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16).padding(.bottom, 12)
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

            // Paper 39I summary, under the reason: what this payment was and the refund in red, 15 on
            // a card padded 16. The invoice's paid amount after the refund is the server's to say, so
            // it isn't worked out here.
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Paid").foregroundStyle(Theme.muted)
                    Spacer(minLength: 8)
                    Text(amountText).monospacedDigit().foregroundStyle(Theme.foreground)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Refund").foregroundStyle(Theme.muted)
                    Spacer(minLength: 8)
                    Text(amountText).monospacedDigit().foregroundStyle(Theme.destructive)
                }
            }
            .font(Theme.font(15))
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .accessibilityElement(children: .combine)

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

    /// Paper 39S Refund issued: the green check, the amount in the largest Bold, "Refund issued" and
    /// where the money goes back to, then one card of what was paid and what was refunded.
    private var refundIssued: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 6) {
                PaperIcon(.check, size: 30, color: Theme.success)
                    .frame(width: 72, height: 72)
                    .background(Theme.successSurface, in: Circle())
                Text(amountText)
                    .font(Theme.paymentAmountFont()).tracking(Theme.paymentAmountTracking)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .padding(.top, 14)
                Text("Refund issued")
                    .font(Theme.font(22, weight: .bold)).tracking(-0.44)
                    .accessibilityAddTraits(.isHeader)
                Text(model.payment.method == "card" ? "Back to the card in 5 to 10 days" : "Thorbis confirmed the full refund.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24).padding(.bottom, 12)
            .accessibilityElement(children: .combine)

            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(invoiceReference.map { "\($0) paid" } ?? "Paid").foregroundStyle(Theme.subtle)
                    Spacer(minLength: 8)
                    Text(amountText).font(Theme.font(15, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Theme.foreground)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Refunded").foregroundStyle(Theme.subtle)
                    Spacer(minLength: 8)
                    Text("\u{2212}\(amountText)").font(Theme.font(15, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Theme.destructive)
                }
            }
            .font(Theme.font(15))
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .accessibilityElement(children: .combine)

            // "Refund confirmed. Saved recovery data could not be cleared…" still has to be said.
            if let error = model.errorMessage {
                ErrorBanner(message: error)
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
    let invoiceReference: String
    /// Paper 39A "Finish job": set by the job screen when the job can still be wrapped up. The paid
    /// screen's commit then closes the sheet and opens the job's wrap-up. Nil keeps "Done".
    var onFinishJob: (() -> Void)? = nil
    /// Paper 39A "Book the next visit": set by the job screen when a return visit can be asked for.
    var onBookNextVisit: (() -> Void)? = nil
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var outbox: FieldOutbox
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
    /// Which of Paper 39's two pay-link rows is marked chosen ("Show a code" or "Text a pay link"); both open the same link.
    @State private var linkByText = false
    @State private var receiptDestination: String?
    @State private var receiptDestinationLoaded = false
    @State private var amountError: String?
    /// Paper F6: set once the server has recorded the payment; the sheet then shows Paid and the
    /// next stop instead of closing. Money saved on the phone to record later never sets it (OF-08).
    @State private var paid: PaidSummary?
    /// The next stop as GET /v1/jobs/{id} last answered, so "On my way" is only offered when allowed.
    @State private var nextStopServed: JobRecord?
    @State private var startingNextStop = false
    @State private var nextStopError: String?
    @StateObject private var nextStopAddresses = JobAddressBook()
    @StateObject private var tapToPayController: TapToPayController
    private var tapToPay: TapToPayController? { tapToPayController }

    private struct PaidSummary: Equatable {
        let amountCents: Int
        let method: String
    }

    init(model: InvoicePaymentCollectionModel, invoice: InvoiceRecord, invoiceReference: String? = nil,
         onFinishJob: (() -> Void)? = nil, onBookNextVisit: (() -> Void)? = nil) {
        self.model = model
        self.invoice = invoice
        self.invoiceReference = invoiceReference ?? "INV-\(invoice.id.suffix(4).uppercased())"
        self.onFinishJob = onFinishJob
        self.onBookNextVisit = onBookNextVisit
        let cents = model.pendingRequest?.amount.amount ?? min(model.collectableCents ?? 0, 1_000_000_000_000)
        _amountText = State(initialValue: paymentAmountText(cents))
        // MF-09: open on the way this phone last collected (cash, check or link); otherwise on
        // the fastest path that actually takes money today. Tap to Pay is chosen in `.task`.
        let last = InvoiceCollectionOption.lastUsed
        // OF-09: without signal the sheet opens on cash, the way that still works. Cash or check
        // still waiting to record also rules out the full-balance link (OF-08).
        let offlineOpening = model.pendingRequest == nil && (model.offlineCopy || model.waitingCents > 0)
            && (last == nil || last == .paymentLink)
        _option = State(initialValue: offlineOpening ? .cash : InvoiceCollectionOption.initial(
            pendingMethod: model.pendingRequest?.method, lastUsed: last))
        _tapToPayController = StateObject(wrappedValue: TapToPayController(invoiceID: invoice.id))
    }

    private var amountCents: Int? {
        MoneyInput.cents(amountText, maximumCents: min(model.collectableCents ?? 0, 1_000_000_000_000))
    }

    private var hasLockedIntent: Bool { model.pendingRequest != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let paid {
                paidState(paid)
                paidFooter
                } else {
                ScrollViewReader { proxy in
                ScrollView {
                    // Paper 39 / 39F: the invoice and the amount centred, the Tap to Pay card when this
                    // iPhone can take cards, the other ways as one card of rows, the receipt row, then
                    // the one brand commit. A record method (39H) shows its amount well inline.
                    VStack(alignment: .leading, spacing: 20) {
                        amountHero
                        if showsTapToPayCard { tapToPayCard }
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
                        if option.takesCustomAmount && !hasLockedIntent && !model.waitingForProjection { amountField.id("payment-amount") }
                        receiptRow
                        if let payLinkError { ErrorBanner(message: payLinkError) }
                        if let paymentError = model.paymentError, !hasLockedIntent, !model.waitingForProjection {
                            ErrorBanner(message: paymentError)
                        }
                    }
                    .padding(.horizontal, PaperCardMetrics.margin)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                // The Done bar's clearance lands after the keyboard scrolled the field into view,
                // leaving it half under the footer; bring the field and its help back once it has.
                .onChange(of: amountFocused) { _, focused in
                    guard focused else { return }
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        withAnimation { proxy.scrollTo("payment-amount", anchor: .bottom) }
                    }
                }
                }

                footer
                }
            }
            // The number pad's Done, with the footer lifted clear of it: the bare Done bar floated
            // over the commit's trailing end.
            .keyboardDoneButton()
            .background(Theme.background.ignoresSafeArea())
            .foregroundStyle(Theme.foreground)
            .navigationTitle(paid == nil ? "Collect payment" : "")
            // Paper 39: "Collect payment" as the large title under the circle row. Paid (F6) has no
            // title: the check and the amount lead.
            .navigationBarTitleDisplayMode(paid == nil ? .large : .inline)
            .toolbar {
                // Paper 39: the 44 back circle on the card tone at top left closes the sheet.
                ThorbisToolbarItem(placement: .topBarLeading) {
                    PaperCircleButton(symbol: "chevron.left", label: "Close", size: 44, fill: Theme.card) { dismiss() }
                }
            }
            .thorbisDestination(isPresented: $showPayLinkShare) {
                InvoicePaymentLinkView(
                    model: model, payLink: payLink, requestedBalanceCents: payLinkBalanceCents,
                    invoiceReference: invoiceReference, customerName: customerName, isCreating: isCreatingPayLink,
                    canCreate: session.can("invoice.payment.create", feature: "payments") && model.canRecordPayment && !isCreatingPayLink,
                    error: payLinkError,
                    onCreate: {
                        amountText = paymentAmountText(min(model.collectableCents ?? 0, 1_000_000_000_000))
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
                if tapToPayAvailable && model.pendingRequest == nil && !offline && !paymentWaiting
                    && InvoiceCollectionOption.lastUsed == nil { option = .tapToPay }
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

    /// Paper 39: "INV-2209 · customer" in 15 muted over the amount in the largest Bold, centred.
    private var amountHero: some View {
        VStack(spacing: 4) {
            Text("\(invoiceReference) \u{00B7} \(customerName)")
                .font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .accessibilityIdentifier("collect-payment-invoice")
            // MF-01: the amount being collected is the screen.
            Text(money(amountCents ?? model.pendingRequest?.amount.amount ?? model.collectableCents ?? 0, currency: invoice.currency))
                .font(Theme.paymentAmountFont()).tracking(Theme.paymentAmountTracking)
                .lineLimit(1).minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .accessibilityLabel("Collecting \(money(amountCents ?? model.collectableCents ?? 0, currency: invoice.currency))")
            // Only when collecting part of it (Paper 39T): what's due on the invoice, in 15 under the amount.
            if amountCents != model.outstandingCents {
                Text("of \(money(model.outstandingCents ?? 0, currency: invoice.currency)) due")
                    .font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.subtle)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Balance due \(money(model.outstandingCents ?? 0, currency: invoice.currency))")
            }
            if model.waitingCents > 0 {
                // OF-08: what's waiting to record isn't paid yet, but it can't be collected twice.
                WaitingToSyncLabel(text: "\(money(model.waitingCents, currency: invoice.currency)) waiting to record")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    /// The custom amount (Paper 39T): a sunk well with the $ inside, help under it and the error in
    /// help's place; then the full balance or half of it one tap away, and what that leaves to pay.
    /// Checked when they press the commit, not on every key.
    private var amountField: some View {
        let full = min(model.collectableCents ?? 0, 1_000_000_000_000)
        return VStack(alignment: .leading, spacing: 12) {
            FormField(label: "Amount", help: "Up to the balance due. Take part now and the rest later.", error: amountError) {
                MoneyFieldWell {
                    TextField(paymentAmountText(model.collectableCents ?? 0), text: $amountText, prompt: .placeholder(paymentAmountText(model.collectableCents ?? 0)))
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .font(Theme.monoFont(16))
                        .accessibilityLabel("Amount to collect in dollars")
                        .onChange(of: amountText) { _, _ in amountError = nil }
                }
            }
            // Side by side; one under the other when the largest text sizes don't fit the row.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    amountChip("Full", cents: full)
                    if full > 1 { amountChip("Half", cents: full / 2) }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 8) {
                    amountChip("Full", cents: full)
                    if full > 1 { amountChip("Half", cents: full / 2) }
                }
            }
            if let amountCents, amountCents < full {
                HStack(spacing: 12) {
                    Text("Left to pay")
                        .font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                    Spacer(minLength: 8)
                    Text(money(full - amountCents, currency: invoice.currency))
                        .font(Theme.font(17, weight: .bold)).monospacedDigit().foregroundStyle(Theme.warning)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.horizontal, PaperCardMetrics.inset)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// A Paper 39T amount chip ("Full $340.00", "Half $170.00"): 15 Semibold on a card pill, in the
    /// brand tone while the field holds that amount. It fills the field; the commit still checks it.
    private func amountChip(_ word: String, cents: Int) -> some View {
        let selected = amountCents == cents
        return Button {
            amountText = paymentAmountText(cents)
            amountError = nil
        } label: {
            Text("\(word) \(money(cents, currency: invoice.currency))")
                .font(Theme.font(15, weight: .semibold)).monospacedDigit()
                .foregroundStyle(selected ? Theme.brandText : Theme.foreground)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(selected ? Theme.brandTint : Theme.quietFill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
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
        // What the Charge button said, read before the invoice reloads with the payment in it.
        let charging = min(model.collectableCents ?? 0, 1_000_000_000_000)
        await tapToPay.charge(api: api) { [model] intent in
            await model.load()
            return model.hasRecordedCardPresentPayment(intent)
        }
        if tapToPay.phase == .paid {
            InvoiceCollectionOption.lastUsed = nil
            try? await Task.sleep(nanoseconds: 900_000_000)
            // Paper F6: Paid and the next stop, instead of closing.
            paid = PaidSummary(amountCents: charging, method: "Card \u{00B7} Tap to Pay")
        }
    }

    /// Paper 39: the Tap to Pay card leads when this iPhone can take cards in person. It is the
    /// method chosen by default; tapping it chooses it again after another row was picked.
    private var showsTapToPayCard: Bool {
        tapToPayAvailable && !hasLockedIntent && !offline && !paymentWaiting
    }

    private var tapToPayCard: some View {
        let locked = hasLockedIntent || model.waitingForProjection
        let selected = option == .tapToPay
        let paid = tapToPayController.phase == .paid
        return Button {
            option = .tapToPay
            amountText = paymentAmountText(min(model.collectableCents ?? 0, 1_000_000_000_000))
        } label: {
            VStack(spacing: 6) {
                Group {
                    // Paper 39: the three waves in brand, 26pt; the check once it is paid (39A).
                    if paid { PaperIcon(.check, size: 26, color: Theme.statusDone) }
                    else { PaperIcon(.contactless, size: 26, color: Theme.brand) }
                }
                    .frame(width: 64, height: 64)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().strokeBorder(paid ? Theme.statusDone : Theme.brand, lineWidth: 1.5))
                    .accessibilityHidden(true)
                Text(selected ? tapToPayCardTitle : "Tap to Pay on iPhone")
                    .font(Theme.font(22, weight: .bold)).tracking(-0.44)
                    .foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                Text("Accepts tap, Apple Pay, and chip cards")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28).padding(.horizontal, 24)
            .background(selected ? Theme.brandSurface : Theme.card,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(locked)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("tap-to-pay")
    }

    /// The card's headline follows the reader: "Tap to Pay on iPhone" until Charge starts it, Paper's
    /// "Hold card near your phone" only while it waits for a card, then "Payment received" (39A).
    private var tapToPayCardTitle: String {
        tapToPayController.phase == .paid ? "Payment received" : tapToPayHeadline
    }

    /// How else they're paying (Paper 39 "Or take it another way", 39F "Choose how to take it"):
    /// one card of rows. Picking a row chooses it (a check marks it); the commit does the rest. The
    /// other received methods open a popover from their row. The help under the card says what the
    /// chosen method does.
    private var paymentOptions: some View {
        let locked = hasLockedIntent || model.waitingForProjection
        let off = locked || !session.can("invoice.payment.create", feature: "payments") || !model.canRecordPayment
        // OF-09: card, link and Tap to Pay need signal; they also wait while cash or check is
        // still recording, since they charge the whole balance (OF-08).
        let needsSignalOff = off || offline
        let linkOff = needsSignalOff || paymentWaiting
        return VStack(alignment: .leading, spacing: 8) {
            PaperSection(showsTapToPayCard ? "Or take it another way" : "Choose how to take it") {
                // Paper 39 lists the code and the texted link as two rows; both are the one pay link,
                // which opens with its code and its Text and Email buttons.
                methodRow("Show a code to scan", glyph: .payCode,
                          selected: option == .paymentLink && !linkByText, busy: isCreatingPayLink && !linkByText, off: linkOff, divider: false) {
                    linkByText = false
                    option = .paymentLink
                    amountText = paymentAmountText(min(model.collectableCents ?? 0, 1_000_000_000_000))
                }
                .accessibilityLabel("Card · send payment link")
                methodRow("Text a pay link", glyph: .payLink,
                          selected: option == .paymentLink && linkByText, busy: isCreatingPayLink && linkByText, off: linkOff, divider: true) {
                    linkByText = true
                    option = .paymentLink
                    amountText = paymentAmountText(min(model.collectableCents ?? 0, 1_000_000_000_000))
                }
                methodRow("Check", glyph: .payCheck, selected: option == .check, off: off, divider: true) { option = .check }
                methodRow("Cash", glyph: .payCash, selected: option == .cash, off: off, divider: true) { option = .cash }
                ThorbisMenu(items: [
                    ThorbisMenuItem("Bank transfer (ACH) received", icon: "building.columns", isSelected: option == .bankTransfer) { option = .bankTransfer },
                    ThorbisMenuItem("Card collected elsewhere", icon: "creditcard", isSelected: option == .externalCard) { option = .externalCard }
                ], title: "Payment received", accessibilityLabel: "Other payment received") {
                    methodRowLabel(option.isExternalReceipt ? (option.recordedMethod?.displayName ?? "Other") : "Bank transfer or other",
                                   glyph: .payCard, selected: option.isExternalReceipt, divider: true)
                        .opacity(needsSignalOff ? 0.4 : 1)
                }
                .disabled(needsSignalOff)
                .accessibilityIdentifier("received-payment-methods")
            }
            // Paper 39 draws no line under the card. One stays only when it says why a way is
            // unavailable or what recording does (no charge is made).
            if let methodNotice {
                Text(methodNotice)
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var methodNotice: String? {
        switch option {
        case .tapToPay: return tapToPayHeadline == "Tap to Pay on iPhone" ? nil : tapToPayHeadline
        case .paymentLink: return offline || paymentWaiting ? methodHelp : nil
        case .check, .cash: return offline ? methodHelp : nil
        case .bankTransfer, .externalCard: return methodHelp
        }
    }

    private var methodHelp: String {
        switch option {
        case .tapToPay: tapToPayHeadline == "Tap to Pay on iPhone" ? "Contactless cards, Apple Pay and other wallets, on this iPhone." : tapToPayHeadline
        case .paymentLink:
            offline ? "Card payments need signal."
                : paymentWaiting ? "Available after the waiting payment records."
                : "Text or email a secure card checkout for the full balance."
        case .check: offline ? "Records when you're back online." : "Record a check already in your hand."
        case .cash: offline ? "Records when you're back online." : "Record cash already in your hand."
        case .bankTransfer, .externalCard:
            offline ? "Needs signal." : "Only record money already received. This doesn't charge a card or bank account."
        }
    }

    /// No signal, or only the copy saved on this phone: card, link and Tap to Pay can't work (OF-09).
    private var offline: Bool { session.isOffline || model.offlineCopy }

    /// Cash or check on this phone that hasn't recorded yet. Tap to Pay and the link charge the
    /// whole balance, so they wait until it lands rather than charge money already taken (OF-08).
    private var paymentWaiting: Bool { model.waitingCents > 0 }

    private func methodRow(_ title: String, glyph: PaperGlyph, value: String? = nil, selected: Bool, busy: Bool = false,
                           off: Bool, divider: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            methodRowLabel(title, glyph: glyph, value: value, selected: selected, busy: busy, divider: divider)
                .opacity(off ? 0.4 : 1)
        }
        .buttonStyle(RowPressStyle())
        .disabled(off || busy)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A Paper 39 method row: a 24pt glyph slot, the 16 Medium name, an optional 15 value, and a
    /// brand check on the chosen row. A hairline above every row but the first.
    private func methodRowLabel(_ title: String, glyph: PaperGlyph, value: String? = nil, selected: Bool,
                                busy: Bool = false, divider: Bool) -> some View {
        HStack(spacing: 12) {
            PaperIcon(glyph, size: 19, color: Theme.foreground)
                .frame(width: 24, height: 24)
            HStack(spacing: 12) {
                Text(title)
                    .font(Theme.font(16, weight: .medium)).tracking(-0.16)
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let value {
                    Text(value).font(Theme.font(15)).foregroundStyle(Theme.subtle).lineLimit(1)
                }
                if busy {
                    ProgressView().controlSize(.small)
                } else if selected {
                    // The chosen way wears the brand check where Paper's row has its chevron.
                    PaperIcon(.check, size: 16, color: Theme.brandText)
                } else {
                    PaperIcon(.chevronRight, size: 16, color: Theme.muted)
                }
            }
            .padding(.trailing, PaperCardMetrics.inset)
            .padding(.vertical, 13)
            .frame(minHeight: 48)
            .overlay(alignment: .top) {
                if divider { WellDivider(leading: 0) }
            }
        }
        .padding(.leading, PaperCardMetrics.inset)
        .contentShape(Rectangle())
    }

    private var receivedPaymentNote: some View {
        Label("Only record money you have already received. This does not charge a card or bank account.", systemImage: "info.circle")
            .font(Theme.font(13))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Paper 39 "Text receipt to": one card row, 56 tall. The app sends receipts by email.
    private var receiptRow: some View {
        HStack(spacing: 12) {
            Text("Email receipt to")
                .font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(receiptDestination ?? (receiptDestinationLoaded ? "No email on file" : "Loading contact…"))
                .font(Theme.font(16)).monospacedDigit().foregroundStyle(Theme.subtle)
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, PaperCardMetrics.inset)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
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
            // Paper 39H: a record method says it charges nothing, over the commit.
            if option.takesCustomAmount && !hasLockedIntent && !model.waitingForProjection {
                Text("This does not charge the customer.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 6)
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
        .padding(.horizontal, PaperCardMetrics.margin)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Theme.background)
    }

    private var primaryTitle: String {
        if model.waitingForProjection { return "Check payment status" }
        if hasLockedIntent { return "Check payment status" }
        switch option {
        case .tapToPay:
            if case .failed = tapToPay?.phase { return "Try again" }
            return "Charge \(money(model.collectableCents ?? 0, currency: invoice.currency))"
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
        if offline && option != .cash && option != .check { return "Without signal, record cash or check. They record when you're back online." }
        if (option == .tapToPay || option == .paymentLink) && paymentWaiting {
            return "A cash or check payment is still recording. Charge a card once it lands."
        }
        if option == .tapToPay {
            if !tapToPayAvailable { return "Tap to Pay isn't ready on this iPhone. Pick another way to pay." }
            return (model.collectableCents ?? 0) > 0 ? nil : "Nothing is due on this invoice."
        }
        if option == .paymentLink { return "A payment link is for the full balance due." }
        return nil
    }

    private var canSubmit: Bool {
        guard !model.isRecording, !model.isLoading, !isCreatingPayLink else { return false }
        if model.waitingForProjection { return true }
        guard session.can("invoice.payment.create", feature: "payments"), model.canRecordPayment else { return false }
        if offline && option != .cash && option != .check { return false }
        if (option == .tapToPay || option == .paymentLink) && paymentWaiting { return false }
        if option == .tapToPay { return tapToPayAvailable && (model.collectableCents ?? 0) > 0 && tapToPay?.busy != true }
        if option == .paymentLink { return model.collectableCents == amountCents }
        return true
    }

    /// The amount problem shown under the field after they press the commit; nil when it's fine.
    private var amountProblem: String? {
        if hasLockedIntent {
            let matches = model.pendingRequest?.amount.amount == amountCents && model.pendingRequest?.method == option.recordedMethod
            return matches ? nil : "Finish the payment already started first, with the same amount and method."
        }
        guard let amountCents else {
            return "Enter an amount up to \(money(model.collectableCents ?? 0, currency: invoice.currency)), like \(paymentAmountText(model.collectableCents ?? 0))."
        }
        return amountCents > (model.collectableCents ?? 0)
            ? "That's more than the balance left to collect, \(money(model.collectableCents ?? 0, currency: invoice.currency))." : nil
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
        let waitingBefore = model.waitingCents
        let accepted = await model.record(amountCents: amountCents, method: method)
        if accepted {
            if option == .cash || option == .check { InvoiceCollectionOption.lastUsed = option }
            // The sheet closes on success, so a view-bound sensoryFeedback would never play.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // OF-08: money saved on this phone to record later is waiting, never Paid, so the sheet
            // closes as before. Only a payment the server recorded shows Paid (Paper F6).
            if model.offlineCopy || model.waitingCents > waitingBefore {
                dismiss()
            } else {
                paid = PaidSummary(amountCents: amountCents, method: method.displayName)
            }
        }
    }

    // MARK: Paid (Paper F6)

    /// Today's next booked stop for the person who took the payment: never this invoice's job, and
    /// never one with a step already waiting on this phone.
    private var nextStop: Job? {
        guard let userID = session.user?.id else { return nil }
        let visits = TodayNumbers.visits(store.jobs, assignee: userID)
            .filter { $0.id != invoice.jobId && outbox.pendingStatus(for: $0.id) == nil }
        return PaperWorkGroups.scheduled(visits).min {
            (JobFiltering.date($0.scheduledFor) ?? .distantFuture) < (JobFiltering.date($1.scheduledFor) ?? .distantFuture)
        }
    }

    /// "On my way" is offered only when it is the next step the server (or, offline, what this
    /// phone has learned) allows for that stop: the same rule as Today's commit.
    private var canStartNextStop: Bool {
        guard let job = nextStop else { return false }
        var served: (status: String, allowed: [String])?
        if let record = nextStopServed, record.id == job.id {
            served = (status: record.status, allowed: record.allowedTransitions ?? [])
        }
        let step = JobMoves.next(listedStatus: job.status, served: served,
                                 queued: outbox.pendingStatus(for: job.id), isOffline: session.isOffline,
                                 learned: outbox.offlineSteps(from:), canEdit: session.can("job.edit", feature: "jobs"))
        return step == "en_route"
    }

    /// "On my way to Larch Ave": the street without its house number, as Paper F6 says it.
    private func onMyWayTitle(_ job: Job) -> String {
        guard let street = nextStopAddresses.street(job) else { return "On my way" }
        let parts = street.split(separator: " ")
        let numbered = parts.count > 1 && (parts.first?.first?.isNumber ?? false)
        let name = numbered ? parts.dropFirst().joined(separator: " ") : street
        return "On my way to \(name)"
    }

    /// Paper 39A: the green check, the amount, "Payment received", then how it was paid, the invoice
    /// and who; the invoice's state; then the next stop when today has one for this person (F6).
    private func paidState(_ paid: PaidSummary) -> some View {
        let jobDone = invoice.jobId.flatMap { id in store.jobs.first { $0.id == id } }?.status == "completed"
        let balanceWord: String? = model.outstandingCents.map { $0 == 0 ? "Paid" : "\(money($0, currency: invoice.currency)) due" }
        let settled = model.outstandingCents == 0
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 4) {
                    PaperIcon(.check, size: 30, color: Theme.success)
                        .frame(width: 72, height: 72)
                        .background(Theme.statusDone.opacity(0.22), in: Circle())
                    Text(money(paid.amountCents, currency: invoice.currency))
                        .font(Theme.paymentAmountFont()).tracking(Theme.paymentAmountTracking)
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .padding(.top, 14)
                        .accessibilityLabel("Paid \(money(paid.amountCents, currency: invoice.currency))")
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("payment-paid")
                    Text("Payment received")
                        .font(Theme.font(22, weight: .bold)).tracking(-0.44)
                        .foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(paid.method) \u{00B7} \(invoiceReference) \u{00B7} \(customerName)")
                        .font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                // Paper 39A has no invoice card: the line above names the invoice. One stays only while
                // a balance is still due, so a part payment never reads as settled.
                if !settled { PaperSection(jobDone ? "Job closed" : "Invoice") {
                    HStack(spacing: 12) {
                        Text("Invoice \(invoiceReference)")
                            .font(Theme.font(16, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let balanceWord {
                            Text(balanceWord)
                                .font(Theme.font(17, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(settled ? Theme.success : Theme.foreground)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, PaperCardMetrics.inset)
                    .frame(minHeight: 60)
                    .accessibilityElement(children: .combine)
                } }
                // Paper 39A: where the receipt goes, when the customer has an email on file.
                if let receiptDestination { paidReceiptCard(receiptDestination) }
                // Paper 39A "While you are here": what the job screen can open next.
                if let onBookNextVisit, !jobDone { whileYouAreHere(onBookNextVisit) }
                if let job = nextStop { nextStopCard(job) }
                if let nextStopError { ErrorBanner(message: nextStopError) }
            }
            .padding(.horizontal, PaperCardMetrics.margin)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .task { await loadNextStop() }
    }

    /// Paper 39A's receipt card: 16 Medium over 14 muted. The server emails the receipt when the
    /// workspace has receipts on, so the card says where it goes rather than that it was sent.
    private func paidReceiptCard(_ destination: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Receipt")
                .font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
            Text("By email to \(destination)")
                .font(Theme.font(14)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("payment-receipt")
    }

    /// Paper 39A "While you are here": a 13 Semibold label over a card whose 56pt row books the
    /// next visit. The row closes this sheet; the job screen then opens its return-visit form.
    private func whileYouAreHere(_ book: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("While you are here")
                .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            Button {
                dismiss()
                book()
            } label: {
                HStack(spacing: 12) {
                    Text("Book the next visit")
                        .font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PaperIcon(.chevronRight, size: 16, color: Theme.muted)
                }
                .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 13)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityHint("Asks the office to book a return visit")
            .accessibilityIdentifier("payment-book-next-visit")
        }
    }

    /// Paper 39A's commit: "Finish job" in the brand pill when the job screen can wrap the job up
    /// (it closes this sheet and opens the wrap-up); otherwise "Done".
    @ViewBuilder private var finishOrDoneButton: some View {
        let jobDone = invoice.jobId.flatMap { id in store.jobs.first { $0.id == id } }?.status == "completed"
        if let onFinishJob, !jobDone {
            PrimaryButton(title: "Finish job") {
                dismiss()
                onFinishJob()
            }
            .accessibilityHint("Opens the job's wrap-up")
            .accessibilityIdentifier("payment-finish-job")
        } else {
            PrimaryButton(title: "Done") { dismiss() }
        }
    }

    /// Paper F6's Next stop card: the label and time in brand text, the street in 22 Bold (the job
    /// when its place has not been read), then the problem and who.
    private func nextStopCard(_ job: Job) -> some View {
        let street = nextStopAddresses.street(job)
        let customer = store.customerName(job.customerId)
        let label = JobFiltering.date(job.scheduledFor).map { "Next stop \u{00B7} \($0.tradeTime)" } ?? "Next stop"
        return VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.font(14, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Theme.brandText)
            Text(street ?? job.title)
                .font(Theme.font(22, weight: .bold)).tracking(-0.44)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text(street == nil ? customer : "\(job.title) \u{00B7} \(customer)")
                .font(Theme.font(15)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("payment-next-stop")
    }

    /// Paper F6's footer: the solid brand commit, 60 tall, "On my way to <street>", under a quiet
    /// Done. Without a next stop (or a move the server allows) Done is the one commit.
    private var paidFooter: some View {
        VStack(spacing: 10) {
            if let job = nextStop, canStartNextStop {
                Button { dismiss() } label: { RimmedButtonLabel(title: "Done", symbol: "checkmark") }
                    .buttonStyle(PressStyle())
                    .disabled(startingNextStop)
                Button { Task { await startNextStop(job) } } label: {
                    HStack(spacing: 10) {
                        if startingNextStop {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "location.fill").font(.system(size: 18, weight: .semibold))
                                .accessibilityHidden(true)
                        }
                        Text(onMyWayTitle(job))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .paperButton(.field, tone: .brand, fills: true)
                }
                .buttonStyle(PressStyle())
                .disabled(startingNextStop)
                .accessibilityHint("Tells the office and customer you are driving to this job")
                .accessibilityIdentifier("payment-next-stop-commit")
            } else {
                finishOrDoneButton
            }
        }
        .padding(.horizontal, PaperCardMetrics.margin)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Theme.background)
    }

    /// Reads the next stop's street and its allowed moves once Paid shows.
    private func loadNextStop() async {
        guard let job = nextStop else { return }
        let organizationID = session.activeOrganization?.id
        if session.can("customer.view", feature: "core_crm") {
            await nextStopAddresses.load([job], api: api, organizationID: organizationID,
                                         identity: "\(session.user?.id ?? "")|\(organizationID ?? "")|\(session.generation)")
        }
        guard session.can("job.view", feature: "jobs"), !session.isOffline,
              let record = try? await api.fieldJob(job.id), record.organizationId == organizationID else { return }
        nextStopServed = record
        outbox.learn(record)
    }

    /// Sends "On my way" for the next stop the way Today does (sent, or saved on the phone without
    /// signal), then closes. A refusal stays on screen with the reason.
    private func startNextStop(_ job: Job) async {
        guard !startingNextStop else { return }
        startingNextStop = true
        nextStopError = nil
        defer { startingNextStop = false }
        switch await JobProgressRun.run(jobID: job.id, request: .enRoute(etaMinutes: nil), api: api, store: store,
                                        session: session, outbox: outbox) {
        case .sent, .queued:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        case .refused(let message):
            nextStopError = message
        case .cancelled:
            break
        }
    }

    private func createPayLink() async {
        guard session.can("invoice.payment.create", feature: "payments"),
              model.canRecordPayment, !paymentWaiting, model.outstandingCents == amountCents else { return }
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
