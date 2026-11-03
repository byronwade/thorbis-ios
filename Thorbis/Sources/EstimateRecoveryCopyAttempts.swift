import Foundation

/// Process-local unresolved attempts. A failed operation may already have
/// installed its record, so only the same ID and exact intent may be retried.
/// This does not replace durable, interprocess attempt coordination.
@MainActor final class EstimateRecoveryCopyAttempts<Scope: Hashable, Draft: Encodable> {
    enum Failure: Error { case changedIntent, pending, discardPending }
    struct Retry { let draft: Draft; let intentID: UUID? }
    private struct Pending { let id: UUID; let bytes: Data; let draft: Draft; let intentID: UUID? }
    private var pending: [Scope: Pending] = [:]
    private var confirmed: [Scope: Pending] = [:]
    private var discardOwners: [Scope: UUID] = [:]

    func pendingAttempt(for scope: Scope) -> Retry? {
        pending[scope].map { Retry(draft: $0.draft, intentID: $0.intentID) }
    }

    func hasPending(for scope: Scope) -> Bool { pending[scope] != nil }

    /// While a discard outcome is unresolved, no cooperating save can begin.
    func beginDiscard(for scope: Scope, owner: UUID) throws {
        guard pending[scope] == nil, discardOwners[scope] == nil || discardOwners[scope] == owner else { throw Failure.pending }
        discardOwners[scope] = owner
    }
    /// Call only after the store confirms removal of this exact ID.
    func finishDiscard(for scope: Scope, owner: UUID, id: UUID) throws {
        guard pending[scope] == nil, discardOwners[scope] == owner else { throw Failure.pending }
        if confirmed[scope]?.id == id { confirmed.removeValue(forKey: scope) }
        discardOwners.removeValue(forKey: scope)
    }

    func perform(_ draft: Draft, scope: Scope, intentID: UUID? = nil, operation: (UUID, Draft) throws -> Void) throws {
        guard discardOwners[scope] == nil else { throw Failure.discardPending }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let intended = try encoder.encode(draft)
        let attempt: Pending
        if let existing = pending[scope] {
            guard existing.bytes == intended, existing.intentID == intentID else { throw Failure.changedIntent }
            attempt = existing
        } else if let existing = confirmed[scope], existing.bytes == intended, existing.intentID == intentID {
            attempt = existing
            pending[scope] = attempt
        } else {
            attempt = Pending(id: UUID(), bytes: intended, draft: draft, intentID: intentID)
            pending[scope] = attempt
        }
        try operation(attempt.id, attempt.draft)
        confirmed[scope] = attempt
        pending.removeValue(forKey: scope)
    }
}
