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
    let diagnosticID = UUID()
    struct Pop: Equatable {
        let id = UUID()
        let routes: [JobInvoiceRoute]
    }
    @Published private(set) var pop: Pop?

    func consume(_ id: UUID) {
        typedRouteProbe("owner=\(diagnosticID) consume=\(id)")
        if pop?.id == id { pop = nil }
    }

    func discardPendingPop() { pop = nil }

    func changed(from old: [PaperTypedJobsRoute], to new: [PaperTypedJobsRoute]) {
        typedRouteProbe("owner=\(diagnosticID) path old=\(old.count) new=\(new.count)")
        guard old != new else { return }
        let routes = JobInvoiceRouteTransition.completedPops(from: old, to: new, invoice: { value in
            if case let .invoice(route) = value { return route }
            return nil
        })
        guard !routes.isEmpty else { discardPendingPop(); return }
        pop = Pop(routes: routes)
        typedRouteProbe("owner=\(diagnosticID) event routes=\(routes.map { $0.invoiceID + ":" + $0.presentationID.uuidString }.joined(separator: ","))")
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

/// Temporary preview gate while typed ownership is being migrated stack by stack.
enum PaperTypedRouteExperiment {
    static var enabled: Bool {
        #if DEBUG
        return PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--invoice-route-owner-experiment")
        #else
        return false
        #endif
    }
}

/// Shared destination mapping for independent typed stacks.
struct PaperTypedDestination: View {
    let route: PaperTypedJobsRoute
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var api: APIClient

    @ViewBuilder var body: some View {
        switch route {
        case .job(let job):
            if session.can("job.view", feature: "jobs") { JobDetailView(jobId: job.id) }
            else { ContentUnavailableView("Job unavailable", systemImage: "lock") }
        case .customer(let customer):
            if session.can("customer.view", feature: "core_crm") { CustomerDetailView(customer: customer) }
            else { ContentUnavailableView("Customer unavailable", systemImage: "lock") }
        case .paper(.job(let id)):
            if session.can("job.view", feature: "jobs") { JobDetailView(jobId: id) }
            else { ContentUnavailableView("Job unavailable", systemImage: "lock") }
        case .paper(let value): PaperRouteView(route: value)
        case .invoice(let value):
            if session.phase == .ready, session.user?.id == value.actorID,
               session.activeOrganization?.id == value.organizationID, session.generation == value.sessionGeneration,
               session.authorityRevision == value.authorityRevision, api.requestGeneration == value.apiGeneration,
               api.normalizedOrigin == value.apiOrigin, session.can("job.view", feature: "jobs"),
               session.can("invoice.view", feature: "invoicing") {
                InvoiceDetailView(id: value.invoiceID, expectedJobScope: .init(jobID: value.jobID, organizationID: value.organizationID, customerID: value.customerID))
            } else {
                ContentUnavailableView("Invoice unavailable", systemImage: "lock", description: Text("Return to the job to refresh this invoice."))
            }
        }
    }
}

@MainActor func typedRouteProbe(_ message: @autoclosure () -> String) {
    #if DEBUG
    guard PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--typed-route-diagnostics") else { return }
    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("typed-route-diagnostic.txt")
    let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    try? (previous + message() + "\n").write(to: url, atomically: true, encoding: .utf8)
    #endif
}
