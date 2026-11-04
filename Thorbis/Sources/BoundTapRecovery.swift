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
    /// Persisted before the create request; optional for older held markers.
    var operationID: String? = nil
}

@MainActor protocol BoundTapRecoveryStoring {
    func load() throws -> BoundTapRecovery?
    /// Atomic insert, returning false if another process already owns a receipt.
    func create(_ recovery: BoundTapRecovery) throws -> Bool
    func save(_ recovery: BoundTapRecovery) throws
    func remove() throws
}

@MainActor enum BoundTapRecoveryManager {
    static func recovered(marker: BoundTapRecovery, attemptID: String?, intentID: String?, amount: Int?, currency: String?) -> BoundTapRecovery? {
        guard marker.attemptID == nil, marker.paymentIntentID == nil, marker.amount == nil, marker.currency == nil,
              let operation = marker.operationID, UUID(uuidString: operation) != nil,
              let attemptID, attemptID.lowercased() == operation.lowercased(),
              let intentID, !intentID.isEmpty, intentID.utf8.count <= 255,
              intentID.utf8.allSatisfy({ (0x21...0x7e).contains($0) }),
              let amount, amount > 0, let currency, !currency.isEmpty else { return nil }
        var receipt = marker
        receipt.attemptID = attemptID
        receipt.paymentIntentID = intentID
        receipt.amount = amount
        receipt.currency = currency
        return receipt
    }
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
              receipt.operationID == marker.operationID,
              let attemptID = receipt.attemptID, UUID(uuidString: attemptID) != nil,
              marker.operationID == nil || marker.operationID?.lowercased() == attemptID.lowercased(),
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
