import Foundation

/// Capture first, then attempt an independent create-only copy. A failed write
/// or readback is ambiguous and leaves the process-local draft and attempt held.
/// This does not prove power-loss durability or authorize future access.
@MainActor enum EstimateTeardownPreservation {
    enum Outcome: Equatable { case notCaptured, memoryOnly, copyConfirmed }

    static func preserve<Scope: Hashable, Draft: Encodable>(
        _ draft: Draft, scope: Scope, intentID: UUID?, attempts: EstimateRecoveryCopyAttempts<Scope, Draft>,
        hold: () -> Bool, install: (UUID, Draft) throws -> Void
    ) -> Outcome {
        guard hold() else { return .notCaptured }
        do {
            try attempts.perform(draft, scope: scope, intentID: intentID, operation: install)
            return .copyConfirmed
        } catch {
            return .memoryOnly
        }
    }
}
