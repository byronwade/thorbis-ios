import Foundation

enum BoundTapFlowError: Error, Equatable { case unavailable, busy, retired, recoveryPending, recoveryUnavailable, uncertain }
enum BoundTapPreflightError: Error { case recoveryPending, recoveryUnavailable }

/// Process-local lease starts before server attempt creation. A missing server
/// response or collection failure is uncertain and deliberately blocks retry.
/// This is only a seam: process-local state is not durable recovery.
@MainActor enum BoundTapPaymentFlow {
    private static var busy = false
    private static var uncertain = false

    #if DEBUG
    static func resetForTests() { busy = false; uncertain = false }
    #endif

    static func run<Attempt, Result>(
        enabled: Bool,
        supported: Bool,
        isCurrent: @escaping @MainActor () -> Bool,
        create: @MainActor () async throws -> Attempt,
        collect: @MainActor (Attempt) async throws -> Result
    ) async throws -> Result {
        guard enabled, supported else { throw BoundTapFlowError.unavailable }
        guard !uncertain else { throw BoundTapFlowError.uncertain }
        guard !busy else { throw BoundTapFlowError.busy }
        guard isCurrent(), !Task.isCancelled else { throw BoundTapFlowError.retired }
        busy = true
        defer { busy = false }
        do {
            let attempt = try await create()
            guard isCurrent(), !Task.isCancelled else { throw BoundTapFlowError.retired }
            let result = try await collect(attempt)
            guard isCurrent(), !Task.isCancelled else { throw BoundTapFlowError.retired }
            return result
        } catch BoundTapPreflightError.recoveryPending {
            throw BoundTapFlowError.recoveryPending
        } catch BoundTapPreflightError.recoveryUnavailable {
            throw BoundTapFlowError.recoveryUnavailable
        } catch {
            uncertain = true
            throw BoundTapFlowError.uncertain
        }
    }
}

/// Snapshot of verified identity and published authority, not a sanitized cache key.
struct BoundTapAuthority: Equatable {
    let actorID: String
    let organizationID: String
    let sessionGeneration: UUID
    let authorityRevision: UUID
    let apiGeneration: UUID
    let origin: String
    let permitted: Bool
}
