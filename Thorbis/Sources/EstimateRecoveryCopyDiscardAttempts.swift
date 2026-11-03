import Foundation

/// Held process-local discard intent. The store can have installed a marker
/// even when removal fails, so a retry must use the same scope, ID and content.
/// This does not establish resource authorization or interprocess edit ownership.
@MainActor final class EstimateRecoveryCopyDiscardAttempts<Scope: Hashable, Draft: Encodable> {
    enum Failure: Error { case blocked, changedIntent }
    struct Pending { let id: UUID; let draft: Draft; fileprivate let bytes: Data; fileprivate let owner: UUID }
    private var attempts: [Scope: Pending] = [:]
    func pending(for scope: Scope) -> Pending? { attempts[scope] }

    func perform(_ draft: Draft, scope: Scope, id: UUID, hasUnsavedEdits: Bool,
                 saves: EstimateRecoveryCopyAttempts<Scope, Draft>,
                 operation: (UUID, Draft) throws -> Void) throws {
        guard !hasUnsavedEdits, !saves.hasPending(for: scope) else { throw Failure.blocked }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let encoded = try encoder.encode(draft)
        let pending: Pending
        if let existing = attempts[scope] {
            guard existing.id == id, existing.bytes == encoded else { throw Failure.changedIntent }
            pending = existing
        } else {
            pending = Pending(id: id, draft: draft, bytes: encoded, owner: UUID())
        }
        try saves.beginDiscard(for: scope, owner: pending.owner)
        attempts[scope] = pending
        try operation(pending.id, pending.draft)
        try saves.finishDiscard(for: scope, owner: pending.owner, id: pending.id)
        attempts.removeValue(forKey: scope)
    }
}
