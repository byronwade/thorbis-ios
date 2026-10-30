import SwiftUI
import Combine

/// Experimental typed path for the phone Jobs tab. Other stacks keep their existing paths.
enum PaperTypedJobsRoute: Hashable {
    case job(Job)
    case customer(Customer)
    case paper(PaperRoute)
    case invoice(JobInvoiceRoute)

    static func wrapping<Value: Hashable>(_ value: Value) -> Self? {
        if let job = value as? Job { return .job(job) }
        if let customer = value as? Customer { return .customer(customer) }
        if let route = value as? PaperRoute { return .paper(route) }
        if let route = value as? JobInvoiceRoute { return .invoice(route) }
        return nil
    }
}

@MainActor
final class PaperTypedJobsOwner: ObservableObject {
    struct Pop: Equatable {
        let id = UUID()
        let route: JobInvoiceRoute
    }
    @Published private(set) var pop: Pop?

    func consume(_ id: UUID) {
        if pop?.id == id { pop = nil }
    }

    func discardPendingPop() { pop = nil }

    func changed(from old: [PaperTypedJobsRoute], to new: [PaperTypedJobsRoute]) {
        guard old != new else { return }
        guard let route = JobInvoiceRouteTransition.completedPop(from: old, to: new, invoice: { value in
            if case let .invoice(route) = value { return route }
            return nil
        }) else {
            discardPendingPop()
            return
        }
        pop = Pop(route: route)
    }
}

private struct PaperTypedJobsOwnerKey: EnvironmentKey {
    static let defaultValue: PaperTypedJobsOwner? = nil
}

extension EnvironmentValues {
    var paperTypedJobsOwner: PaperTypedJobsOwner? {
        get { self[PaperTypedJobsOwnerKey.self] }
        set { self[PaperTypedJobsOwnerKey.self] = newValue }
    }
}

/// Preserves existing native links outside the experimental typed Jobs stack.
struct PaperCompatibleLink<Value: Hashable, Label: View>: View {
    let value: Value
    let label: Label
    @Environment(\.paperTypedJobsOwner) private var owner

    init(value: Value, @ViewBuilder label: () -> Label) {
        self.value = value
        self.label = label()
    }

    var body: some View {
        if owner != nil, let route = PaperTypedJobsRoute.wrapping(value) {
            NavigationLink(value: route) { label }
        } else {
            NavigationLink(value: value) { label }
        }
    }
}
