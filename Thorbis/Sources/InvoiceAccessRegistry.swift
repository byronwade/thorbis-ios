import Combine
import Foundation

/// Held integration: coordinates mounted invoice models in this process only.
/// It is not durable and does not mediate invoice lists or saved copies.
@MainActor final class InvoiceAccessRegistry: ObservableObject {
    struct Scope: Hashable {
        let actorWorkspace: String
        let origin: String
        let invoiceID: String
    }

    static let shared = InvoiceAccessRegistry()
    @Published private(set) var revision = UUID()
    private var denied: Set<Scope> = []
    private var versions: [Scope: UUID] = [:]
    let denial = PassthroughSubject<Scope, Never>()

    func scope(api: APIClient, invoiceID: String) -> Scope? {
        guard let identity = api.savedCopyScope, let origin = api.normalizedOrigin,
              let id = UUID(uuidString: invoiceID) else { return nil }
        return Scope(actorWorkspace: identity, origin: origin, invoiceID: id.uuidString.lowercased())
    }
    func isDenied(_ scope: Scope) -> Bool { denied.contains(scope) }
    func version(_ scope: Scope) -> UUID? { versions[scope] }
    func deny(_ scope: Scope) {
        versions[scope] = UUID()
        denied.insert(scope)
        revision = UUID()
        denial.send(scope)
    }
    func allow(_ scope: Scope) {
        if denied.remove(scope) != nil { revision = UUID() }
    }
}
