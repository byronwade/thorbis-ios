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

    private let api: APIClient
    private let actorID: String?
    private let intentStore: PaymentRefundIntentStoring
    private var storageReady: Bool

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
        return await send(inFlight)
    }

    @discardableResult
    func checkRefundStatus() async -> Bool {
        guard canCheckRefundStatus, let intent, let actorID else { return false }
        let retryIntent = FieldPaymentRefundIntent(reason: intent.reason, state: .uncertain)
        do {
            try intentStore.save(
                retryIntent,
                actorID: actorID,
                organizationID: payment.organizationId,
                paymentID: payment.id
            )
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        self.intent = retryIntent
        return await send(retryIntent)
    }

    func discardSavedIntent() {
        guard !isSubmitting, intent?.state == .draft, let actorID else { return }
        do {
            try intentStore.remove(
                actorID: actorID,
                organizationID: payment.organizationId,
                paymentID: payment.id
            )
            intent = nil
            reasonDraft = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send(_ request: FieldPaymentRefundIntent) async -> Bool {
        guard !isSubmitting else { return false }
        isSubmitting = true
        didComplete = false
        errorMessage = nil
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
        } catch is CancellationError {
            retainUncertainIntent(request)
            errorMessage = "The refund request was interrupted. Check its status before trying again."
            return false
        } catch {
            retainUncertainIntent(request)
            errorMessage = error.localizedDescription
            return false
        }
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
        guard case .recorded = payment.status,
              payment.amount.amount > 0,
              payment.refundedAmount == nil || payment.refundedAmount == 0 else { return false }
        return true
    }

    private static func isCanonicallyRefunded(_ payment: FieldPaymentRecord) -> Bool {
        if case .refunded = payment.status { return true }
        guard let refundedAmount = payment.refundedAmount, payment.amount.amount > 0 else { return false }
        return refundedAmount >= payment.amount.amount
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
