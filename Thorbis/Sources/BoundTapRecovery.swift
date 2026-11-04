import Foundation

/// Contains no Stripe token or client secret. A nil attempt means the create
/// request may have reached the server but no response was observed.
struct BoundTapRecovery: Codable, Equatable {
    let origin: String
    let actorID: String
    let organizationID: String
    let invoiceID: String
    var attemptID: String?
    var paymentIntentID: String?
    var amount: Int?
    var currency: String?
}

@MainActor protocol BoundTapRecoveryStoring {
    func load() throws -> BoundTapRecovery?
    func save(_ recovery: BoundTapRecovery) throws
    func remove() throws
}

@MainActor enum BoundTapRecoveryManager {
    static func prepare<Attempt>(store: BoundTapRecoveryStoring, marker: BoundTapRecovery,
                                 create: @MainActor () async throws -> Attempt,
                                 identify: @MainActor (Attempt, BoundTapRecovery) throws -> BoundTapRecovery) async throws -> Attempt {
        let existing: BoundTapRecovery?
        do { existing = try store.load() }
        catch { throw BoundTapPreflightError.recoveryUnavailable }
        guard existing == nil else { throw BoundTapPreflightError.recoveryPending }
        do { try store.save(marker) }
        catch { throw BoundTapPreflightError.recoveryUnavailable }
        let attempt = try await create()
        let receipt = try identify(attempt, marker)
        guard receipt.origin == marker.origin, receipt.actorID == marker.actorID,
              receipt.organizationID == marker.organizationID, receipt.invoiceID == marker.invoiceID,
              let attemptID = receipt.attemptID, UUID(uuidString: attemptID) != nil,
              let intentID = receipt.paymentIntentID, !intentID.isEmpty,
              let amount = receipt.amount, amount > 0,
              let currency = receipt.currency, !currency.isEmpty else { throw BoundTapFlowError.uncertain }
        try store.save(receipt)
        return attempt
    }
}
