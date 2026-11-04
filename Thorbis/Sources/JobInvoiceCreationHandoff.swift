import Foundation

/// Keeps asynchronous creation and refresh from opening a document after access changes.
@MainActor
enum JobInvoiceCreationHandoff {
    static func run<Value>(
        create: () async throws -> Value,
        isCurrent: () -> Bool,
        verify: (Value) throws -> Void,
        canView: () -> Bool,
        withoutView: () -> Void,
        prepareRefresh: (Value) -> Void,
        refresh: () async -> Void
    ) async throws -> Value? {
        let value = try await create()
        guard isCurrent() else { return nil }
        try verify(value)
        guard canView() else { withoutView(); return nil }
        prepareRefresh(value)
        await refresh()
        guard isCurrent(), canView() else { return nil }
        return value
    }
}
