import Foundation

/// Reads today's jobs ahead, while there is signal, so each one opens later without it.
///
/// When the schedule loads, today's jobs (yours first; everyone's if none are yours), at most
/// twelve, are read one after another at utility priority through the same API calls their
/// screens make, so the saved copies (SavedCopies.swift) land under the same keys the screens
/// ask for: the job, notes, past visits, follow-ups, its estimates and invoices with their
/// lines, and the customer's record, contacts, addresses, equipment and recent history.
/// Nothing runs offline or in Low Data Mode; an unchanged job is read again at most hourly.
/// Sign-out or a workspace change cancels it.
@MainActor
final class DayPrefetch {
    static let shared = DayPrefetch()
    /// Low Data Mode (set by ConnectivityMonitor): the phone asked apps to hold back.
    var constrained = false
    private var task: Task<Void, Never>?
    /// When each job was last read ahead, and the `updatedAt` it had then.
    private var readAt: [String: (at: Date, updatedAt: String?)] = [:]
    private let maxJobs = 12
    /// An unchanged job is read again at most hourly; a job the server changed, after ten minutes.
    private let unchangedFor: TimeInterval = 3600
    private let changedFor: TimeInterval = 600

    func cancel() {
        task?.cancel()
        task = nil
        readAt = [:]
    }

    /// Lets a DEBUG preview wait for the read-ahead before it turns signal off.
    func waitUntilIdle() async { await task?.value }

    func start(jobs: [Job], api: APIClient, session: SessionController) {
        guard !constrained, !session.isOffline, session.phase == .ready, session.can("job.view", feature: "jobs") else { return }
        let actor = session.user?.id
        var today = JobFiltering.schedule(jobs, range: .today, assignedTo: actor)
        if today.isEmpty { today = JobFiltering.schedule(jobs, range: .today) }
        let now = Date()
        let due = today.prefix(maxJobs).filter { job in
            guard let last = readAt[job.id] else { return true }
            let age = now.timeIntervalSince(last.at)
            return last.updatedAt == job.updatedAt ? age > unchangedFor : age > changedFor
        }
        guard !due.isEmpty else { return }
        task?.cancel()
        let generation = session.generation
        task = Task(priority: .utility) { [weak self] in
            await PerfProbe.measure("day-prefetch") {
                var customersRead = Set<String>()
                for job in due {
                    guard !Task.isCancelled, session.generation == generation, !session.isOffline else { return }
                    await self?.read(job: job, api: api, session: session, customersRead: &customersRead)
                    self?.readAt[job.id] = (Date(), job.updatedAt)
                }
            }
        }
    }

    private func read(job: Job, api: APIClient, session: SessionController, customersRead: inout Set<String>) async {
        let generation = session.generation
        func current() -> Bool { !Task.isCancelled && session.generation == generation && !session.isOffline }
        guard current(), let record = try? await api.fieldJob(job.id) else { return }
        guard current(), record.organizationId == session.activeOrganization?.id else { return }
        JobDetailCache.save(record)
        if let notes = try? await api.fieldNotes(job.id), current() { JobDetailCache.save(notes: notes, jobID: job.id) }
        guard current() else { return }
        _ = try? await api.fieldVisitHistory(job.id)
        guard current() else { return }
        _ = try? await api.fieldFollowUps(job.id)
        guard current() else { return }
        if ["arrived", "in_progress", "paused"].contains(record.status) { _ = try? await api.fieldCloseout(job.id) }
        if session.can("estimate.view", feature: "estimates") {
            var ids = record.estimateId.map { [$0] } ?? []
            if let links = try? await api.fieldJobEstimateLinks(job.id) { ids += links.map(\.estimateId) }
            for id in Array(Set(ids)).sorted() {
                guard current() else { return }
                _ = try? await api.fieldEstimate(id)
            }
        }
        if session.can("invoice.view", feature: "invoicing"), current(),
           let invoices = try? await api.fieldJobInvoices(job.id) {
            for invoice in invoices.prefix(6) {
                guard current() else { return }
                _ = try? await api.fieldInvoice(invoice.id)
            }
        }
        let customerID = record.customerId
        guard current(), customersRead.insert(customerID).inserted else { return }
        // What the job's Overview and the customer profile read.
        _ = try? await api.fieldContacts(customerID)
        guard current() else { return }
        _ = try? await api.fieldCustomer(customerID)
        guard current() else { return }
        _ = try? await api.fieldLocations(customerID)
        guard current() else { return }
        _ = try? await api.customerEquipment(customerID)
        guard current() else { return }
        _ = try? await api.memberPricing(customerID)
        guard current(), session.can("customer.view", feature: "core_crm") else { return }
        _ = try? await api.fieldCustomerHistory(customerID)
        guard current() else { return }
        _ = try? await api.fieldJobs(customerID: customerID)
    }
}
