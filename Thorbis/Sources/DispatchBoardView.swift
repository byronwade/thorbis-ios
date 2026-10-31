import SwiftUI

/// The dispatcher's board (Schedule › Board, roles with `job.assign`): the Unscheduled queue on
/// top, then each technician's day in a time column. Tapping a job offers Assign, Reschedule,
/// Open, or a one-tap move to another technician. Live data only: the roster is the server's
/// assignee list and the jobs are the ones this person can see.
struct DispatchBoardView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @StateObject private var addresses = JobAddressBook()
    @State private var people: [FieldAssignee] = []
    @State private var rosterLoaded = false
    /// The job whose choices are showing.
    @State private var menuJob: Job?
    /// What to open once the choice card has finished closing (two sheets in one pass drop the second).
    @State private var pending: Pending?
    @State private var scheduling: Job?
    @State private var assigning: Job?
    @State private var opening: Job?
    @State private var movingJobID: String?
    @State private var error: String?
    @State private var moved = 0

    private enum Pending { case open(Job), schedule(Job), assign(Job) }

    private var canAssign: Bool { session.can("job.assign", feature: "jobs") }

    /// Oldest waiting first: the queue is worked from the top.
    var unscheduled: [Job] {
        JobFiltering.schedule(store.jobs, range: .unscheduled)
            .sorted { (JobFiltering.date($0.createdAt) ?? .distantFuture) < (JobFiltering.date($1.createdAt) ?? .distantFuture) }
    }

    /// Today's visits, finished ones included (dimmed) so each tech's day reads whole.
    var today: [Job] {
        store.jobs.filter { job in
            job.status != "canceled" && (JobFiltering.date(job.scheduledFor).map { Calendar.current.isDateInToday($0) } ?? false)
        }
        .sorted { (JobFiltering.date($0.scheduledFor) ?? .distantFuture) < (JobFiltering.date($1.scheduledFor) ?? .distantFuture) }
    }

    var body: some View {
        let todays = today
        let roster = people.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        let rosterIDs = Set(roster.map(\.userId))
        let noTech = todays.filter { $0.assignedToUserId == nil }
        let outside = todays.filter { $0.assignedToUserId.map { !rosterIDs.contains($0) } ?? false }
        VStack(alignment: .leading, spacing: 18) {
            if let error { ErrorBanner(message: error) }
            PaperSection("Unscheduled", count: unscheduled.count) {
                if unscheduled.isEmpty {
                    emptyRow("Everything has a time.")
                } else {
                    rows(unscheduled, age: true)
                }
            }
            ForEach(roster) { person in
                let theirs = todays.filter { $0.assignedToUserId == person.userId }
                PaperSection(person.displayName, count: theirs.count) {
                    if theirs.isEmpty { emptyRow("Nothing booked today.") } else { rows(theirs, age: false) }
                }
            }
            if !noTech.isEmpty {
                PaperSection("No tech yet", count: noTech.count) { rows(noTech, age: false) }
            }
            if !outside.isEmpty {
                PaperSection("Outside your roster", count: outside.count) { rows(outside, age: false) }
            }
            if !rosterLoaded {
                SkeletonRows(count: 2, inset: 0)
            } else if roster.isEmpty {
                Text("No one can be assigned right now.").font(Theme.font(14)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            }
        }
        .paperCardMargin()
        .sensoryFeedback(.success, trigger: moved)
        .task(id: session.generation) { await loadRoster() }
        .task(id: "addr|\((unscheduled + todays).map { "\($0.id):\($0.locationId ?? "")" }.joined(separator: ","))|\(session.generation)") {
            guard session.can("customer.view", feature: "core_crm") else { return }
            await addresses.load(unscheduled + todays, api: api, organizationID: session.activeOrganization?.id,
                                 identity: "\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)", limit: 30)
        }
        .sheet(item: $menuJob, onDismiss: runPending) { job in
            ThorbisMenuCard(items: choices(for: job, roster: roster), title: menuTitle(job)) { item in
                item.action()
                menuJob = nil
            }
        }
        .sheet(item: $scheduling) { QuickScheduleSheet(jobID: $0.id) }
        .thorbisDestination(item: $assigning) { JobAssignmentView(jobID: $0.id) }
        .thorbisDestination(item: $opening) { JobDetailView(jobId: $0.id) }
    }

    @ViewBuilder private func rows(_ jobs: [Job], age: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(jobs) { job in row(job, age: age) }
        }
        .padding(.vertical, PaperCardMetrics.edge)
    }

    private func row(_ job: Job, age: Bool) -> some View {
        let customer = store.customerName(job.customerId)
        let street = addresses.street(job)
        let leading: PaperRowLeading
        if age, let created = JobFiltering.date(job.createdAt) {
            leading = .text(ScheduleCompactRow.age(since: created),
                            accessibility: "Waiting since \(created.formatted(date: .abbreviated, time: .omitted))")
        } else if let when = JobFiltering.date(job.scheduledFor) {
            leading = .text(when.tradeTime)
        } else {
            leading = .text("No time")
        }
        return Button { menuJob = job } label: {
            PaperListRow(leading: leading, title: street ?? job.title,
                         subtitle: street != nil ? "\(job.title) · \(customer)" : customer,
                         dimmed: job.status == "completed") {
                if movingJobID == job.id {
                    ProgressView().controlSize(.small)
                } else {
                    StatusWord(jobStatus: job.status)
                }
            }
        }
        .buttonStyle(RowPressStyle())
        .disabled(movingJobID != nil)
        .accessibilityHint("Assign, reschedule or open this job")
        .accessibilityIdentifier("board-row-\(job.id)")
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).font(Theme.font(15)).foregroundStyle(Theme.muted)
            .padding(.horizontal, PaperCardMetrics.inset).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    }

    private func menuTitle(_ job: Job) -> String {
        let who = store.customerName(job.customerId)
        return addresses.street(job).map { "\($0) · \(job.title)" } ?? "\(job.title) · \(who)"
    }

    private func choices(for job: Job, roster: [FieldAssignee]) -> [ThorbisMenuItem] {
        var items: [ThorbisMenuItem] = []
        if canAssign {
            items.append(ThorbisMenuItem(job.scheduledFor == nil ? "Schedule" : "Reschedule", icon: "calendar",
                                         subtitle: "Day and arrival window") { pending = .schedule(job) })
            items.append(ThorbisMenuItem(job.assignedToUserId == nil ? "Assign tech" : "Change tech", icon: "person.crop.circle",
                                         subtitle: "Pick from the whole roster") { pending = .assign(job) })
            // Tap-to-move: straight to another technician without leaving the board.
            if job.status != "completed" {
                for person in roster where person.userId != job.assignedToUserId {
                    items.append(ThorbisMenuItem("Move to \(person.displayName)", icon: "arrow.right") {
                        Task { await move(job, to: person) }
                    })
                }
            }
        }
        if session.can("job.view", feature: "jobs") {
            items.append(ThorbisMenuItem("Open job", icon: "arrow.up.right") { pending = .open(job) })
        }
        return items
    }

    private func runPending() {
        guard let next = pending else { return }
        pending = nil
        switch next {
        case .open(let job): opening = job
        case .schedule(let job): scheduling = job
        case .assign(let job): assigning = job
        }
    }

    private func loadRoster() async {
        guard canAssign else { rosterLoaded = true; return }
        let generation = session.generation
        do {
            let team = try await api.fieldAssignees()
            guard session.generation == generation else { return }
            people = team
        } catch is CancellationError { return } catch {
            guard session.generation == generation else { return }
            self.error = "The team list didn't load. \(error.localizedDescription)"
        }
        rosterLoaded = true
    }

    /// Reassigns with the assignee the board showed as the expected prior, so a change someone
    /// else made meanwhile is refused (409) instead of overwritten.
    private func move(_ job: Job, to person: FieldAssignee) async {
        guard canAssign, movingJobID == nil else { return }
        let generation = session.generation
        movingJobID = job.id
        defer { movingJobID = nil }
        let expected: FieldExpectedAssignee = job.assignedToUserId.map(FieldExpectedAssignee.user) ?? .unassigned
        do {
            _ = try await api.assignFieldJob(job.id, request: FieldAssignRequest(userId: person.userId, expected: expected))
            guard session.generation == generation else { return }
            error = nil
            moved += 1
            if await store.refresh(api) == .failed { error = "Moved. The board could not refresh; pull to refresh." }
        } catch is CancellationError {
        } catch let problem as Problem where problem.status == 409 {
            error = "Someone changed this job's tech meanwhile. Pull to refresh and try again."
            _ = await store.refresh(api)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
