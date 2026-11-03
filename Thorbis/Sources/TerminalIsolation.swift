import Foundation

struct TerminalAttemptScope: Equatable {
    let actor: String
    let organization: String
    let sessionGeneration: UUID
    let authorityRevision: UUID
    let apiGeneration: UUID
    let origin: String
}

/// Serializes the process-wide Stripe Terminal SDK. A confirmation with an
/// unknown outcome quarantines the SDK for the rest of this process; the
/// server must reconcile the original attempt before another can be opened.
@MainActor
final class TerminalIsolation {
    private var owner: UUID?
    private(set) var needsReconciliation = false

    func acquire() -> UUID? {
        guard owner == nil, !needsReconciliation else { return nil }
        let id = UUID()
        owner = id
        return id
    }

    func owns(_ id: UUID) -> Bool { owner == id }

    static func tokenMatches(expected: String, actual: String) -> Bool {
        !expected.isEmpty && expected == actual
    }

    static func matchesReviewedPayment(_ reviewed: FieldMoney, server: FieldMoney,
                                       stripeAmount: Int, stripeCurrency: String) -> Bool {
        reviewed.amount > 0 && reviewed.currency == "USD" &&
            reviewed == server && stripeAmount == reviewed.amount &&
            stripeCurrency.uppercased() == reviewed.currency
    }

    static func matchesCollectedPayment(_ reviewed: FieldMoney, server: FieldMoney, expectedID: String,
                                        actualID: String?, stripeAmount: Int, stripeCurrency: String, tip: NSNumber?) -> Bool {
        !expectedID.isEmpty && actualID == expectedID && (tip == nil || tip?.compare(NSNumber(value: 0)) == .orderedSame) &&
            matchesReviewedPayment(reviewed, server: server, stripeAmount: stripeAmount, stripeCurrency: stripeCurrency)
    }

    func release(_ id: UUID, uncertain: Bool) {
        guard owner == id else { return }
        if uncertain { needsReconciliation = true }
        owner = nil
    }

    static func reset(connected: Bool, disconnect: () async throws -> Void,
                      clear: () throws -> Void) async throws {
        if connected { try await disconnect() }
        try clear()
    }
}
