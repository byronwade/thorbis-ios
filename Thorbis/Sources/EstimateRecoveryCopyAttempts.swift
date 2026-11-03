import Foundation

/// Process-local unresolved attempts. A failed operation may already have
/// installed its record, so only the same ID and exact intent may be retried.
/// This does not replace durable, interprocess attempt coordination.
@MainActor final class EstimateRecoveryCopyAttempts<Scope: Hashable, Draft: Encodable> {
    enum Failure: Error { case changedIntent }
    private struct Pending { let id: UUID; let bytes: Data; let draft: Draft }
    private var pending: [Scope: Pending] = [:]
    private var confirmed: [Scope: Pending] = [:]

    func pendingDraft(for scope: Scope) -> Draft? { pending[scope]?.draft }

    func perform(_ draft: Draft, scope: Scope, operation: (UUID, Draft) throws -> Void) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let intended = try encoder.encode(draft)
        let attempt: Pending
        if let existing = pending[scope] {
            guard existing.bytes == intended else { throw Failure.changedIntent }
            attempt = existing
        } else if let existing = confirmed[scope], existing.bytes == intended {
            attempt = existing
            pending[scope] = attempt
        } else {
            attempt = Pending(id: UUID(), bytes: intended, draft: draft)
            pending[scope] = attempt
        }
        try operation(attempt.id, attempt.draft)
        confirmed[scope] = attempt
        pending.removeValue(forKey: scope)
    }
}
