import Foundation

/// Serializes protected customer presentations across app-level owners.
@MainActor
final class CustomerHandoffArbiter {
    enum Owner: Equatable { case documents, photos }
    private(set) var owner: Owner?
    private(set) var revision = UUID()

    func claim(_ requested: Owner) -> Bool {
        guard owner == nil else { return false }
        owner = requested
        revision = UUID()
        return true
    }

    func release(_ requested: Owner) {
        guard owner == requested else { return }
        owner = nil
        revision = UUID()
    }
}
