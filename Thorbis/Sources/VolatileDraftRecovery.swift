import Foundation

/// Process-local holding area; it never writes to disk or grants access.
@MainActor final class VolatileDraftRecovery<Scope: Hashable, Draft> {
    private var held: [Scope: Draft] = [:]
    func hold(_ draft: Draft, for scope: Scope) { held[scope] = draft }
    func read(for scope: Scope) -> Draft? { held[scope] }
    func clear(for scope: Scope) { held.removeValue(forKey: scope) }
}
