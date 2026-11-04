import Foundation

/// Process-local provenance only; losing this information restores the
/// conservative recovery-choice UI rather than hiding a saved copy.
@MainActor final class EstimateAutomaticCopies<Scope: Hashable> {
    private var ids: [Scope: Set<UUID>] = [:]
    private var promoted: [Scope: Set<UUID>] = [:]
    func mark(_ id: UUID, scope: Scope) {
        guard promoted[scope]?.contains(id) != true else { return }
        ids[scope, default: []].insert(id)
    }
    func promote(_ id: UUID, scope: Scope) {
        ids[scope]?.remove(id)
        promoted[scope, default: []].insert(id)
    }
    func onlyAutomatic(_ candidates: [UUID], scope: Scope) -> Bool {
        candidates.allSatisfy { ids[scope]?.contains($0) == true }
    }
    func clear() { ids.removeAll(); promoted.removeAll() }
}
