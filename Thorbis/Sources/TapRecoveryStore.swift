import Foundation

/// Stable identities only. Session generations and provider secrets must never be persisted.
struct TapRecoveryScope: Codable, Equatable {
    let origin: String
    let organization: String
    let actor: String
    let invoice: String

    fileprivate var valid: Bool {
        [origin, organization, actor, invoice].allSatisfy { !$0.isEmpty }
    }
    fileprivate func sameInvoice(as other: Self) -> Bool {
        origin == other.origin && organization == other.organization && invoice == other.invoice
    }
}

/// An unfinished attempt is a hold, not evidence of a payment. A missing attempt ID
/// means the preparation response was lost and requires server-side reconciliation.
struct TapRecoveryHold: Codable, Equatable {
    let scope: TapRecoveryScope
    let amount: Int
    let currency: String
    var attemptID: String?
}

/// Protected, atomic local records. Callers must stop before any provider effect if a
/// write fails, and may clear only after independently verifying the canonical receipt.
@MainActor
final class TapRecoveryStore {
    enum Failure: Error { case invalid, held, mismatch }
    private let url: URL
    init(url: URL) { self.url = url }

    private func read() throws -> [TapRecoveryHold] {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return []
        }
        let holds = try JSONDecoder().decode([TapRecoveryHold].self, from: data)
        guard holds.allSatisfy({ $0.scope.valid && $0.amount > 0 && $0.currency == "USD" &&
            ($0.attemptID == nil || UUID(uuidString: $0.attemptID!) != nil) }) else { throw Failure.invalid }
        return holds
    }
    private func write(_ holds: [TapRecoveryHold]) throws {
        try JSONEncoder().encode(holds).write(to: url, options: [.atomic, .completeFileProtection])
    }
    func isHeld(scope: TapRecoveryScope) throws -> Bool {
        guard scope.valid else { throw Failure.invalid }
        return try read().contains { $0.scope.sameInvoice(as: scope) }
    }
    /// The initiating actor may inspect its saved identity, never another actor's.
    func pending(scope: TapRecoveryScope) throws -> TapRecoveryHold? {
        guard scope.valid else { throw Failure.invalid }
        return try read().first { $0.scope == scope }
    }
    func begin(scope: TapRecoveryScope, amount: Int, currency: String) throws {
        guard scope.valid, amount > 0, currency == "USD" else { throw Failure.invalid }
        var holds = try read()
        guard !holds.contains(where: { $0.scope.sameInvoice(as: scope) }) else { throw Failure.held }
        holds.append(TapRecoveryHold(scope: scope, amount: amount, currency: currency, attemptID: nil))
        try write(holds)
    }
    func bindAttempt(scope: TapRecoveryScope, attemptID: String) throws {
        guard UUID(uuidString: attemptID) != nil else { throw Failure.invalid }
        var holds = try read()
        guard let i = holds.firstIndex(where: { $0.scope == scope }),
              holds[i].attemptID == nil || holds[i].attemptID == attemptID else { throw Failure.mismatch }
        holds[i].attemptID = attemptID
        try write(holds)
    }
    /// Caller must first verify the authoritative receipt and current session.
    func confirmReceipt(scope: TapRecoveryScope, attemptID: String, amount: Int, currency: String) throws {
        var holds = try read()
        guard let i = holds.firstIndex(where: { $0.scope == scope }), holds[i].attemptID == attemptID,
              holds[i].amount == amount, holds[i].currency == currency else { throw Failure.mismatch }
        holds.remove(at: i)
        try write(holds)
    }
}
