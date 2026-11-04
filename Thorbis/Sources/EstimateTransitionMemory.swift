import Foundation

/// Copies all held estimates before retiring process-local contents. Nothing is
/// cleared if an install/readback is uncertain or an older attempt remains.
@MainActor enum EstimateTransitionMemory {
    static func retire<Scope: Hashable, Draft: Encodable>(
        primary: VolatileDraftRecovery<Scope, Draft>,
        edits: VolatileDraftRecovery<RecoveryCopyEditKey<Scope>, RecoveryCopyEditState<Draft>>,
        attempts: EstimateRecoveryCopyAttempts<Scope, Draft>,
        install: (UUID, Scope, Draft) throws -> Void
    ) -> Bool {
        let drafts = primary.entries()
        let copyEdits = edits.entries()
        do {
            // A prior write may have installed its copy before reporting failure.
            // Resolve that exact ID and intent before attempting newer work.
            for (scope, retry) in attempts.pendingAttempts() {
                try attempts.perform(retry.draft, scope: scope, intentID: retry.intentID) { id, value in
                    try install(id, scope, value)
                }
            }
            for (scope, draft) in drafts {
                try attempts.perform(draft, scope: scope) { id, value in try install(id, scope, value) }
            }
            for (key, state) in copyEdits {
                try attempts.perform(state.draft, scope: key.scope, intentID: state.sessionID) { id, value in try install(id, key.scope, value) }
            }
            guard !attempts.hasPendingAttempts else { return false }
        } catch { return false }
        for (scope, _) in drafts { primary.clear(for: scope) }
        for (key, _) in copyEdits { edits.clear(for: key) }
        attempts.retireConfirmed()
        return true
    }
}
