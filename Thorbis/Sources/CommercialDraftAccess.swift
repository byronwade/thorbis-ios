import Foundation

/// A draft is visible only while the exact authority that made its fresh resource read remains current.
@MainActor enum CommercialDraftAccess {
    static func matchesLocation(expected: String?, actual: String?) -> Bool {
        expected == actual
    }
    static func verify<Scope: Equatable, Record>(
        expectedScope: Scope,
        currentScope: () -> Scope?,
        read: () async throws -> Record,
        matches: (Record) -> Bool
    ) async -> Bool {
        guard !Task.isCancelled, currentScope() == expectedScope else { return false }
        do {
            let record = try await read()
            return !Task.isCancelled && currentScope() == expectedScope && matches(record)
        } catch { return false }
    }
}
