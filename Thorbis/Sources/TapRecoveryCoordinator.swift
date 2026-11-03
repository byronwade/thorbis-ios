import Foundation

/// Internal prototype for a future authenticated, read-only server response.
/// No production HTTP route or provider SDK calls this type yet.
struct TapRecoverySnapshot {
    enum Status { case pending, recorded }
    let operationID: String
    let jobID: String
    let attemptID: String
    let amount: Int
    let currency: String
    let status: Status
}

@MainActor
final class TapRecoveryCoordinator {
    enum Outcome: Equatable { case unresolved, recorded }
    private let store: TapRecoveryStore
    private var active = false

    init(store: TapRecoveryStore) { self.store = store }

    /// The injected preparation transport may send only the saved operation ID;
    /// it must never accept a client-selected job, amount or merchant as authority.
    func start(scope: TapRecoveryScope, jobID: String, amount: Int, currency: String,
               authorized: () -> Bool, termsCurrent: () -> Bool,
               prepare: (String) async throws -> TapRecoverySnapshot) async -> Outcome {
        guard !active, authorized(), termsCurrent() else { return .unresolved }
        active = true
        defer { active = false }
        do {
            let hold = try store.begin(scope: scope, jobID: jobID, amount: amount, currency: currency)
            guard authorized(), termsCurrent() else { return .unresolved }
            let snapshot = try await prepare(hold.operationID)
            guard authorized(), termsCurrent(), matches(snapshot, hold: hold) else { return .unresolved }
            try store.bindAttempt(scope: scope, operationID: hold.operationID, jobID: hold.jobID, attemptID: snapshot.attemptID)
        } catch { return .unresolved }
        // A preparation response is not a receipt, even if a transport labels it recorded.
        return .unresolved
    }

    /// Only an authenticated status lookup for the original operation may
    /// clear the hold; missing, denied, pending and ambiguous results stay held.
    func check(scope: TapRecoveryScope, authorized: () -> Bool,
               lookup: (String) async throws -> TapRecoverySnapshot) async -> Outcome {
        guard !active, authorized() else { return .unresolved }
        active = true
        defer { active = false }
        do {
            guard let hold = try store.pending(scope: scope), authorized() else { return .unresolved }
            let snapshot = try await lookup(hold.operationID)
            guard authorized(), matches(snapshot, hold: hold) else { return .unresolved }
            try store.bindAttempt(scope: scope, operationID: hold.operationID, jobID: hold.jobID, attemptID: snapshot.attemptID)
            guard authorized(), snapshot.status == .recorded else { return .unresolved }
            try store.confirmReceipt(scope: scope, operationID: hold.operationID, jobID: hold.jobID,
                                     attemptID: snapshot.attemptID, amount: snapshot.amount, currency: snapshot.currency)
            return .recorded
        } catch { return .unresolved }
    }

    private func matches(_ snapshot: TapRecoverySnapshot, hold: TapRecoveryHold) -> Bool {
        guard let operation = UUID(uuidString: snapshot.operationID),
              let job = UUID(uuidString: snapshot.jobID), UUID(uuidString: snapshot.attemptID) != nil else { return false }
        return operation.uuidString.lowercased() == hold.operationID && job.uuidString.lowercased() == hold.jobID &&
            snapshot.amount == hold.amount && snapshot.currency == hold.currency
    }
}
