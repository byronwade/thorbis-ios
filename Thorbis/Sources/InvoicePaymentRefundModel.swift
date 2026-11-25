import Combine
import Foundation

@MainActor
final class InvoicePaymentRefundModel: ObservableObject {
    @Published private(set) var payment: FieldPaymentRecord
    @Published private(set) var reasonDraft: String
    @Published private(set) var intent: FieldPaymentRefundIntent?
    @Published private(set) var isSubmitting = false
    @Published private(set) var didComplete = false
    @Published private(set) var errorMessage: String?
    /// An unconfirmed refund may be withdrawn only for a cash or check payment, and only after a
    /// fresh read of the invoice's payments showed it still recorded and not refunded. A card
    /// refund can be under way at the card company while the payment still reads as recorded.
    @Published private(set) var canDiscardUnconfirmed = false

    private let api: APIClient
    private let actorID: String?
    private let intentStore: PaymentRefundIntentStoring
    private var storageReady: Bool
    /// Moves on with every send, so a payment read begun before a send never settles after it.
    private var sendGeneration = 0
    private var isReadingPayment = false

    init(
        api: APIClient,
        actorID: String?,
        payment: FieldPaymentRecord,
        intentStore: PaymentRefundIntentStoring = KeychainPaymentRefundIntentStore.shared
    ) {
        self.api = api
        self.actorID = actorID
        self.payment = payment
        self.intentStore = intentStore

        var restoredIntent: FieldPaymentRefundIntent?
        var storageError: Error?
        if let actorID {
            do {
                restoredIntent = try intentStore.load(
                    actorID: actorID,
                    organizationID: payment.organizationId,
                    paymentID: payment.id
                )
            } catch {
                storageError = error
            }
        } else {
            storageError = RefundIntentUnavailableError.missingIdentity
        }

        if Self.isCanonicallyRefunded(payment), restoredIntent != nil, let actorID {
            do {
                try intentStore.remove(
                    actorID: actorID,
                    organizationID: payment.organizationId,
                    paymentID: payment.id
                )
                restoredIntent = nil
            } catch {
                storageError = error
            }
        }

        self.intent = restoredIntent
        self.reasonDraft = restoredIntent?.reason ?? ""
        self.storageReady = actorID != nil && storageError == nil
        self.errorMessage = storageError?.localizedDescription
    }

    var canOfferRefund: Bool {
        actorID != nil && Self.isRefundEligible(payment)
    }

    var canSubmitRefund: Bool {
        guard canOfferRefund, storageReady, !isSubmitting,
              let intent, intent.state == .draft, intent.reason == reasonDraft else { return false }
        let reason = Self.normalizedReason(reasonDraft)
        return (3...2_000).contains(reason.utf16.count)
    }

    var canCheckRefundStatus: Bool {
        guard storageReady, !isSubmitting, let intent else { return false }
        return intent.state == .pending || intent.state == .reconciliationRequired || intent.state == .uncertain
    }

    /// Changes with each settled send while the refund is unconfirmed; nil otherwise. The status
    /// panel reads the invoice's payments again whenever it changes.
    var unconfirmedReadKey: Int? {
        intent?.state == .uncertain && !isSubmitting ? sendGeneration : nil
    }

    var hasSavedIntent: Bool { intent != nil }
    var isIntentStoreReady: Bool { storageReady }

    func updateReasonDraft(_ value: String) {
        guard storageReady, !isSubmitting,
              intent == nil || intent?.state == .draft,
              let actorID else { return }

        reasonDraft = value
        let trimmed = Self.normalizedReason(value)
        do {
            if trimmed.isEmpty {
                try intentStore.remove(
                    actorID: actorID,
                    organizationID: payment.organizationId,
                    paymentID: payment.id
                )
                intent = nil
            } else {
                let draft = FieldPaymentRefundIntent(reason: value, state: .draft)
                try intentStore.save(
                    draft,
                    actorID: actorID,
                    organizationID: payment.organizationId,
                    paymentID: payment.id
                )
                intent = draft
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func submitRefund() async -> Bool {
        guard !isSubmitting else { return false }
        guard storageReady, let actorID else {
            errorMessage = errorMessage ?? "Secure refund recovery is unavailable. Try again before submitting the refund."
            return false
        }
        guard canOfferRefund else {
            errorMessage = "This payment is no longer eligible for a full refund. Refresh payment history."
            return false
        }

        let normalizedReason = Self.normalizedReason(reasonDraft)
        guard (3...2_000).contains(normalizedReason.utf16.count) else {
            errorMessage = "Enter a refund reason between 3 and 2,000 characters."
            return false
        }
        guard let draft = intent, draft.state == .draft, draft.reason == reasonDraft else {
            errorMessage = "The refund reason could not be saved securely. Try again before submitting the refund."
            return false
        }

        let inFlight = FieldPaymentRefundIntent(reason: normalizedReason, state: .uncertain)
        do {
            try intentStore.save(
                inFlight,
                actorID: actorID,
                organizationID: payment.organizationId,
                paymentID: payment.id
            )
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        intent = inFlight
        reasonDraft = normalizedReason
        return await send(inFlight, from: .draft)
    }

    @discardableResult
    func checkRefundStatus() async -> Bool {
        guard canCheckRefundStatus, let intent, let actorID else { return false }
        // Asking again keeps the saved state. A pending or reconciling refund was accepted by the
        // server, and asking again cannot make that less true. The write proves storage still works.
        do {
            try intentStore.save(
                intent,
                actorID: actorID,
                organizationID: payment.organizationId,
                paymentID: payment.id
            )
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        return await send(intent, from: intent.state)
    }

    func discardSavedIntent() {
        guard !isSubmitting, let actorID, let state = intent?.state,
              state == .draft || (state == .uncertain && canDiscardUnconfirmed) else { return }
        do {
            try intentStore.remove(
                actorID: actorID,
                organizationID: payment.organizationId,
                paymentID: payment.id
            )
            intent = nil
            reasonDraft = ""
            errorMessage = nil
            canDiscardUnconfirmed = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// After an unconfirmed refund, reads the invoice's payments straight from Thorbis, never a
    /// saved copy. A cash or check payment still recorded and not refunded lets the person
    /// withdraw the refund; a refunded one ends it here. Returns true when the read showed the
    /// payment refunded.
    @discardableResult
    func readPaymentAfterUnconfirmedRefund() async -> Bool {
        guard storageReady, !isSubmitting, !isReadingPayment, intent?.state == .uncertain else { return false }
        let generation = sendGeneration
        isReadingPayment = true
        defer { isReadingPayment = false }
        let read: FieldPaymentHistoryRead
        do {
            read = try await api.fieldPaymentsWithProvenance(payment.invoiceId, requireFresh: true)
        } catch {
            return false
        }
        guard generation == sendGeneration, !isSubmitting, intent?.state == .uncertain,
              read.pages.allSatisfy({ $0.source == .urlSession(cacheBypassed: true) }) else { return false }

        switch RefundPaymentRead.verdict(read.payments, for: payment) {
        case let .notRefunded(record):
            payment = record
            canDiscardUnconfirmed = RefundPaymentRead.refundsInOneStep(record)
            return false
        case let .refunded(record):
            payment = record
            intent = nil
            reasonDraft = ""
            canDiscardUnconfirmed = false
            didComplete = true
            errorMessage = nil
            if let actorID {
                do {
                    try intentStore.remove(
                        actorID: actorID,
                        organizationID: payment.organizationId,
                        paymentID: payment.id
                    )
                } catch {
                    errorMessage = "Refund confirmed. Saved recovery data could not be cleared: \(error.localizedDescription)"
                }
            }
            return true
        case .unknown:
            return false
        }
    }

    /// - Parameter prior: the saved state the request was sent from. A failure that proves
    ///   nothing about an earlier request never moves it to a weaker state (RefundSendFailure).
    private func send(_ request: FieldPaymentRefundIntent, from prior: FieldPaymentRefundIntentState) async -> Bool {
        guard !isSubmitting else { return false }
        isSubmitting = true
        didComplete = false
        errorMessage = nil
        canDiscardUnconfirmed = false
        sendGeneration += 1
        defer { isSubmitting = false }

        do {
            switch try await api.refundFieldPayment(payment.id, reason: request.reason) {
            case let .completed(updatedPayment):
                guard updatedPayment.id == payment.id,
                      updatedPayment.organizationId == payment.organizationId else {
                    throw Problem(title: "Invalid refund response", status: nil,
                                  detail: "The server returned a different payment.")
                }
                payment = updatedPayment
                intent = nil
                reasonDraft = ""
                didComplete = true
                if let actorID {
                    do {
                        try intentStore.remove(
                            actorID: actorID,
                            organizationID: payment.organizationId,
                            paymentID: payment.id
                        )
                    } catch {
                        errorMessage = "Refund confirmed. Saved recovery data could not be cleared: \(error.localizedDescription)"
                    }
                }
                return true

            case let .accepted(outcome, responsePaymentID):
                guard responsePaymentID == payment.id else {
                    throw Problem(title: "Invalid refund response", status: 202,
                                  detail: "The accepted refund did not match the selected payment.")
                }
                let nextState: FieldPaymentRefundIntentState = switch outcome {
                case .pending: .pending
                case .reconciliationRequired: .reconciliationRequired
                }
                let acceptedIntent = FieldPaymentRefundIntent(reason: request.reason, state: nextState)
                intent = acceptedIntent
                do {
                    if let actorID {
                        try intentStore.save(
                            acceptedIntent,
                            actorID: actorID,
                            organizationID: payment.organizationId,
                            paymentID: payment.id
                        )
                    }
                } catch {
                    errorMessage = "Refund is \(nextState == .pending ? "pending" : "awaiting reconciliation"). Status could not be saved, so keep this screen open and check again."
                }
                return false
            }
        } catch {
            let failure = RefundSendFailure.of(error)
            let next = failure.state(sentFrom: prior, inOneStep: RefundPaymentRead.refundsInOneStep(payment))
            let message = failure.message(for: error, sentFrom: prior, next: next)
            switch next {
            case .draft:
                returnToDraft(request, message: message)
            case .uncertain:
                errorMessage = message
                retainUncertainIntent(request)
            case let accepted:
                // Pending or reconciling stays as it was saved before this request.
                errorMessage = message
                intent = FieldPaymentRefundIntent(reason: request.reason, state: accepted)
            }
            return false
        }
    }

    /// The failure proves no refund was made (RefundSendFailure.state): it goes back to a draft with
    /// the exact reason it was sent with. For a card payment the server ties the first reason it
    /// prepares to the refund and refuses a different one, so keeping it keeps the retry the same refund.
    private func returnToDraft(_ request: FieldPaymentRefundIntent, message: String) {
        let draft = FieldPaymentRefundIntent(reason: request.reason, state: .draft)
        guard let actorID else {
            errorMessage = message
            retainUncertainIntent(request)
            return
        }
        do {
            try intentStore.save(
                draft,
                actorID: actorID,
                organizationID: payment.organizationId,
                paymentID: payment.id
            )
        } catch {
            // The store still holds the unconfirmed request saved before sending; say the same here.
            intent = FieldPaymentRefundIntent(reason: request.reason, state: .uncertain)
            errorMessage = "\(message) The saved refund could not be updated, so it still shows as unconfirmed."
            return
        }
        intent = draft
        reasonDraft = request.reason
        errorMessage = message
    }

    private func retainUncertainIntent(_ request: FieldPaymentRefundIntent) {
        let uncertain = FieldPaymentRefundIntent(reason: request.reason, state: .uncertain)
        intent = uncertain
        guard let actorID else { return }
        do {
            try intentStore.save(
                uncertain,
                actorID: actorID,
                organizationID: payment.organizationId,
                paymentID: payment.id
            )
        } catch {
            errorMessage = "The refund outcome is uncertain. The saved reason could not be updated: \(error.localizedDescription)"
        }
    }

    private static func isRefundEligible(_ payment: FieldPaymentRecord) -> Bool {
        RefundPaymentRead.isRefundEligible(payment)
    }

    private static func isCanonicallyRefunded(_ payment: FieldPaymentRecord) -> Bool {
        RefundPaymentRead.isCanonicallyRefunded(payment)
    }

    private static func normalizedReason(_ reason: String) -> String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum RefundIntentUnavailableError: LocalizedError {
    case missingIdentity

    var errorDescription: String? {
        "A verified workspace session is required before a refund can be saved securely."
    }
}

/// What a failed refund request proves (BYR-1707). The server keys a refund on its payment: one
/// full refund per payment, and for a card payment the first reason it prepares is the refund's
/// idempotency key. So the saved reason is the retry key, and every state below keeps it.
enum RefundSendFailure: Equatable {
    /// Refused before the server could move any money: a validation refusal, or a refund over the
    /// role's limit. The server checks both before it asks the card company.
    case refusedUpFront(String)
    /// Any other 4xx answer except 408 and 429. For a card payment the server can give one after
    /// the card company has refunded (a role changed mid-request, a record that no longer matches),
    /// so it proves no refund only for a cash or check payment, which is refunded in one step.
    case refused(String)
    /// No internet, data not allowed, roaming off, or the host could not be found or connected to.
    /// iOS can also report no internet for a request already in flight, so like `refused` it
    /// proves nothing was sent only for a cash or check payment.
    case notSent(String)
    /// A timeout, a lost connection, a 5xx, a cancellation or an answer that could not be read.
    /// The refund may have been made.
    case unconfirmed

    /// The server's words for a refund over the role's limit: `ForbiddenError` with the
    /// `condition_exceeded` reason from the `maxRefundAmount` condition on `invoice.refund`.
    static let overLimitDetail = "not permitted: invoice.refund (condition_exceeded)"
    static let overLimitMessage = "This refund is more than your role can approve. Ask your office."
    static let roleRefusedMessage = "Your role can\u{2019}t refund this payment. Ask your office."
    static let notSentMessage = "This phone couldn\u{2019}t reach Thorbis, so the refund wasn\u{2019}t sent. Try again when you have signal."
    static let lostConnectionMessage = "This phone lost its connection, so it can\u{2019}t tell whether Thorbis got the refund. Send it again when you have signal."
    static let unchangedOfflineMessage = "This phone couldn\u{2019}t reach Thorbis, so nothing about this refund changed. Try again when you have signal."
    static let stillUnconfirmedNote = "Thorbis may already have made this refund, so it stays unconfirmed."
    static let interruptedMessage = "The refund request was interrupted. Try again to confirm it."

    static func of(_ error: Error) -> RefundSendFailure {
        if error is CancellationError { return .unconfirmed }
        if let problem = error as? Problem, let status = problem.status {
            guard (400..<500).contains(status), status != 408, status != 429 else { return .unconfirmed }
            if status == 403, problem.category == "authorization" {
                return problem.detail == overLimitDetail ? .refusedUpFront(overLimitMessage) : .refused(roleRefusedMessage)
            }
            let reason = problem.detail ?? problem.title ?? "Request failed (\(status))"
            let words = "Thorbis refused this refund: \(reason)"
            return problem.category == "validation" ? .refusedUpFront(words) : .refused(words)
        }
        // Never a helper that counts a timeout as no connection: a timed-out request may have arrived.
        if error.neverReachedServer { return .notSent(notSentMessage) }
        return .unconfirmed
    }

    /// The state a saved refund takes after this failure. Only a failure that proves no refund was
    /// made returns it to a draft, which can be edited or discarded.
    /// - A draft goes back to a draft when it was refused up front, or when a cash or check
    ///   payment (`inOneStep`) was refused or never sent. Otherwise it becomes unconfirmed.
    /// - An unconfirmed refund stays unconfirmed whatever this request got: the server checks the
    ///   role before it looks for an earlier refund, so a refusal says nothing about the earlier request.
    /// - A pending or reconciling refund stays as it was: the server already accepted it.
    func state(sentFrom prior: FieldPaymentRefundIntentState, inOneStep: Bool) -> FieldPaymentRefundIntentState {
        switch (prior, self) {
        case (.draft, .refusedUpFront): .draft
        case (.draft, .refused), (.draft, .notSent): inOneStep ? .draft : .uncertain
        case (.draft, .unconfirmed): .uncertain
        case (.uncertain, _): .uncertain
        case (.pending, _): .pending
        case (.reconciliationRequired, _): .reconciliationRequired
        }
    }

    /// What the person reads after this failure moved the refund from `prior` to `next`.
    func message(for error: Error, sentFrom prior: FieldPaymentRefundIntentState,
                 next: FieldPaymentRefundIntentState) -> String {
        switch self {
        case let .refusedUpFront(words), let .refused(words):
            return next == .uncertain ? "\(words) \(Self.stillUnconfirmedNote)" : words
        case let .notSent(words):
            // Only a draft can say the refund wasn't sent: otherwise a request may have arrived.
            if next == .draft { return words }
            return prior == .draft ? Self.lostConnectionMessage : Self.unchangedOfflineMessage
        case .unconfirmed:
            return error is CancellationError ? Self.interruptedMessage : error.localizedDescription
        }
    }
}

/// What a fresh read of the invoice's payments says about the payment being refunded.
enum RefundPaymentRead {
    case notRefunded(FieldPaymentRecord)
    case refunded(FieldPaymentRecord)
    /// Missing, another workspace's or invoice's, or partly refunded.
    case unknown

    static func verdict(_ payments: [FieldPaymentRecord], for payment: FieldPaymentRecord) -> RefundPaymentRead {
        let matches = payments.filter { $0.id == payment.id }
        guard matches.count == 1, let record = matches.first,
              record.organizationId == payment.organizationId,
              record.invoiceId == payment.invoiceId else { return .unknown }
        if isCanonicallyRefunded(record) { return .refunded(record) }
        if isRefundEligible(record) { return .notRefunded(record) }
        return .unknown
    }

    /// Cash and check payments are refunded in one step on the server, with no card company, so a
    /// refusal or a read that shows them not refunded is the whole answer. Any other method may
    /// have a refund under way at the card company that the payment does not show.
    static func refundsInOneStep(_ payment: FieldPaymentRecord) -> Bool {
        payment.method == "cash" || payment.method == "check"
    }

    static func isRefundEligible(_ payment: FieldPaymentRecord) -> Bool {
        guard case .recorded = payment.status,
              payment.amount.amount > 0,
              payment.refundedAmount == nil || payment.refundedAmount == 0 else { return false }
        return true
    }

    static func isCanonicallyRefunded(_ payment: FieldPaymentRecord) -> Bool {
        if case .refunded = payment.status { return true }
        guard let refundedAmount = payment.refundedAmount, payment.amount.amount > 0 else { return false }
        return refundedAmount >= payment.amount.amount
    }
}
