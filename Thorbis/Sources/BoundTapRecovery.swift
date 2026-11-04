import Foundation

enum BoundTapRecoveryResult: Equatable { case confirmed, pending, settledNeedsReview, otherAccount, unknownAttempt, restartRequired }

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
    /// Atomic insert, returning false if another process already owns a receipt.
    func create(_ recovery: BoundTapRecovery) throws -> Bool
    func save(_ recovery: BoundTapRecovery) throws
    func remove() throws
}

@MainActor enum BoundTapRecoveryManager {
    static func begin(store: BoundTapRecoveryStoring, marker: BoundTapRecovery) throws {
        let created: Bool
        do { created = try store.create(marker) }
        catch { throw BoundTapPreflightError.recoveryUnavailable }
        guard created else { throw BoundTapPreflightError.recoveryPending }
    }
    static func record<Attempt>(store: BoundTapRecoveryStoring, marker: BoundTapRecovery,
                                attempt: Attempt,
                                identify: @MainActor (Attempt, BoundTapRecovery) throws -> BoundTapRecovery) throws {
        let receipt = try identify(attempt, marker)
        guard receipt.origin == marker.origin, receipt.actorID == marker.actorID,
              receipt.organizationID == marker.organizationID, receipt.invoiceID == marker.invoiceID,
              let attemptID = receipt.attemptID, UUID(uuidString: attemptID) != nil,
              let intentID = receipt.paymentIntentID, !intentID.isEmpty,
              let amount = receipt.amount, amount > 0,
              let currency = receipt.currency, !currency.isEmpty else { throw BoundTapFlowError.uncertain }
        try store.save(receipt)
    }
    static func prepare<Attempt>(store: BoundTapRecoveryStoring, marker: BoundTapRecovery,
                                 create: @MainActor () async throws -> Attempt,
                                 identify: @MainActor (Attempt, BoundTapRecovery) throws -> BoundTapRecovery) async throws -> Attempt {
        try begin(store: store, marker: marker)
        let attempt = try await create()
        try record(store: store, marker: marker, attempt: attempt, identify: identify)
        return attempt
    }
}

@MainActor enum BoundTapGuardedRelease {
    static func apply(enabled: Bool, verified: Bool, sdkInitialized: Bool,
                      current: () -> Bool, lease: BoundTapProcessLease,
                      store: BoundTapRecoveryStoring, expected: BoundTapRecovery) throws -> BoundTapRecoveryResult {
        guard verified, current() else { return .pending }
        guard enabled else { return .settledNeedsReview }
        guard !sdkInitialized, lease.isHeld, current(), try store.load() == expected else { return .restartRequired }
        try store.remove()
        return .confirmed
    }
}
