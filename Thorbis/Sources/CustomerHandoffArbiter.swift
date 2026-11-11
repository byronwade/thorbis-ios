import Foundation
import Combine

/// Serializes protected customer presentations across app-level owners.
@MainActor
final class CustomerHandoffArbiter {
    enum Owner: Equatable { case documents, photos, legacy(UUID) }
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

/// Held by both the local presenter and its customer cover. If the presenting branch is
/// destroyed, ownership lasts as long as the cover and retires when its last holder goes away.
@MainActor
final class LegacyCustomerHandoffLease: ObservableObject {
    private let arbiter: CustomerHandoffArbiter
    private let id: UUID
    init(arbiter: CustomerHandoffArbiter, id: UUID) { self.arbiter = arbiter; self.id = id }
    func release() { arbiter.release(.legacy(id)) }
    deinit {
        let arbiter = arbiter
        let id = id
        Task { @MainActor in arbiter.release(.legacy(id)) }
    }
}
