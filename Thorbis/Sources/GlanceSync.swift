import SwiftUI

/// Keeps the out-of-app surfaces in step with the job list: writes today's snapshot for the
/// widgets and the Control Center control, with each job's street (from its own service location
/// only) and the same "mine or everyone's" scope the Today screen opens on, and hands the streets
/// to Spotlight so results read street first.
struct GlanceSnapshotWriter: ViewModifier {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @StateObject private var streets = JobAddressBook()

    func body(content: Content) -> some View {
        content
            .onChange(of: store.jobs, initial: true) { write() }
            .onChange(of: store.customers) { write() }
            .onChange(of: streets.streets) {
                write()
                SpotlightIndex.shared.update(streets: jobStreets(store.jobs))
            }
            .task(id: "glance|\(today.map { "\($0.id):\($0.locationId ?? "")" }.joined(separator: ","))|\(session.generation)|\(session.isOffline)") {
                guard session.can("customer.view", feature: "core_crm"), !today.isEmpty else { return }
                await streets.load(today, api: api, organizationID: session.activeOrganization?.id,
                                   identity: "\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)")
            }
    }

    /// The Today screen's opening scope: a technician's own jobs, everyone's for the office.
    private var scoped: [Job] {
        let actor = session.user?.id
        let assignee = ScheduleScope.initial(schedulesOwnDay: WorkRole(session).schedulesOwnDay, actorID: actor)
            .assignee(actor, range: .today)
        return store.jobs.filter { assignee == nil || $0.assignedToUserId == assignee }
    }

    /// The jobs the widgets can show: under way, or booked today.
    private var today: [Job] {
        scoped.filter { job in
            TodaySnapshot.liveStatuses.contains(job.status) ||
                (JobFiltering.date(job.scheduledFor).map { Calendar.current.isDateInToday($0) } ?? false)
        }
    }

    private func jobStreets(_ jobs: [Job]) -> [String: String] {
        Dictionary(jobs.compactMap { job in streets.street(job).map { (job.id, $0) } }, uniquingKeysWith: { first, _ in first })
    }

    private func write() {
        guard !store.jobs.isEmpty, session.can("job.view", feature: "jobs") else { return }
        let items = scoped.map {
            TodaySnapshot.Item(id: $0.id, at: JobFiltering.date($0.scheduledFor), title: $0.title,
                               customer: store.customerName($0.customerId), status: $0.status, street: streets.street($0))
        }
        TodaySnapshot.save(TodaySnapshot(items: items, writtenAt: Date()))
    }
}
