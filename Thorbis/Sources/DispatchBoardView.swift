import SwiftUI

/// The dispatcher's board (Schedule › Board, roles with `job.assign`): today's jobs as compact cards
/// in columns by where they stand (Open, En route, On site, Done), each card naming its tech, with
/// the Unscheduled queue at the foot of Open. Tapping a job offers Assign, Reschedule, Open, or a
/// one-tap move to another technician. Live data only: the roster is the server's
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

    /// design.thorbis.com Rooms, "Board: Open, en route, on site. Compact cards." Today's work in
    /// columns by where it stands, plus Done; the Unscheduled queue sits at the foot of Open.
    struct Column: Identifiable {
        let id: String
        let title: String
        let tone: StatusTone
        let jobs: [Job]
        /// Open's second part: jobs that still need a time, oldest first.
        var waiting: [Job] = []
        /// The status this column already says; a card only names a status that differs.
        let usual: Set<String>
    }

    static func columns(today: [Job], unscheduled: [Job]) -> [Column] {
        // Open takes everything not yet moving (any status the board doesn't name too), so no job
        // booked today falls between columns; its card names the odd status.
        let moving: Set<String> = ["en_route", "arrived", "in_progress", "paused", "completed"]
        return [Column(id: "open", title: "Open", tone: .scheduled,
                jobs: today.filter { !moving.contains($0.status) }, waiting: unscheduled, usual: ["scheduled"]),
         Column(id: "en-route", title: "En route", tone: .dispatched, jobs: today.filter { $0.status == "en_route" }, usual: ["en_route"]),
         Column(id: "on-site", title: "On site", tone: .inProgress,
                jobs: today.filter { ["arrived", "in_progress", "paused"].contains($0.status) }, usual: ["arrived", "in_progress"]),
         Column(id: "done", title: "Done", tone: .done, jobs: today.filter { $0.status == "completed" }, usual: ["completed"])]
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 248

    var body: some View {
        let roster = people.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        let names = Dictionary(people.map { ($0.userId, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        let columns = Self.columns(today: today, unscheduled: unscheduled)
        VStack(alignment: .leading, spacing: 12) {
            if let error { ErrorBanner(message: error).paperCardMargin() }
            if typeSize.isAccessibilitySize {
                // At accessibility sizes the columns stack, so no card is squeezed or scrolled sideways.
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(columns) { column($0, names: names, roster: roster) }
                }
                .paperCardMargin()
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(columns) { column($0, names: names, roster: roster).frame(width: min(columnWidth, 320)) }
                    }
                    .padding(.horizontal, PaperCardMetrics.margin)
                }
                .scrollIndicators(.hidden)
            }
            if !rosterLoaded {
                SkeletonRows(count: 2, inset: 0).paperCardMargin()
            } else if canAssign && roster.isEmpty {
                Text("No one can be assigned right now.").font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4).paperCardMargin()
            }
        }
        .sensoryFeedback(.success, trigger: moved)
        .task(id: session.generation) { await loadRoster() }
        .task(id: "addr|\((unscheduled + today).map { "\($0.id):\($0.locationId ?? "")" }.joined(separator: ","))|\(session.generation)") {
            guard session.can("customer.view", feature: "core_crm") else { return }
            await addresses.load(unscheduled + today, api: api, organizationID: session.activeOrganization?.id,
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

    /// A column: its status as a word with its mark and the count, then compact cards. Space, not lines.
    private func column(_ column: Column, names: [String: String], roster: [FieldAssignee]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                StatusLabel(tone: column.tone, word: column.title)
                Text("\(column.jobs.count)").font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 32)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(column.title), \(column.jobs.count)")
            .accessibilityAddTraits(.isHeader)
            if column.jobs.isEmpty && column.waiting.isEmpty {
                Text(column.id == "open" ? "Nothing booked." : "None right now.")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4).frame(minHeight: 32, alignment: .leading)
            }
            ForEach(column.jobs) { card($0, usual: column.usual, age: false, names: names) }
            if column.id == "open" {
                // The queue: everyone's jobs that still need a time, worked from the oldest.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Needs a time").font(Theme.font(13, weight: .medium))
                    Text("\(column.waiting.count)").font(Theme.font(13)).monospacedDigit()
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 4).padding(.top, column.jobs.isEmpty ? 0 : 12)
                .frame(minHeight: 32)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Unscheduled, \(column.waiting.count)")
                .accessibilityAddTraits(.isHeader)
                if column.waiting.isEmpty {
                    Text("Everything has a time.").font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4).frame(minHeight: 32, alignment: .leading)
                }
                ForEach(column.waiting) { card($0, usual: ["scheduled", "draft"], age: true, names: names) }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// A compact card: when (or how long it has waited) and the tech, the street, then the problem
    /// and who. A status shows only where it differs from the column (Dispatched, Paused).
    private func card(_ job: Job, usual: Set<String>, age: Bool, names: [String: String]) -> some View {
        let customer = store.customerName(job.customerId)
        let street = addresses.street(job)
        let tech = job.assignedToUserId.flatMap { names[$0] ?? (job.assignedToUserId == session.user?.id ? session.user?.name : nil) }
        let when: (text: String, spoken: String) = {
            if age, let created = JobFiltering.date(job.createdAt) {
                return ("Waiting \(ScheduleCompactRow.age(since: created))", "Waiting since \(created.formatted(date: .abbreviated, time: .omitted))")
            }
            if let date = JobFiltering.date(job.scheduledFor) { return (date.clockTime, date.tradeTime) }
            return ("No time", "No time")
        }()
        let showsStatus = !usual.contains(job.status)
        return Button { menuJob = job } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    Text(when.text).font(Theme.font(13, weight: .medium)).monospacedDigit().foregroundStyle(Theme.muted)
                    Spacer(minLength: 4)
                    if movingJobID == job.id {
                        ProgressView().controlSize(.small)
                    } else if let tech {
                        InitialsAvatar(name: tech, size: 20)
                    } else {
                        // Unassigned, or someone outside the roster this person can assign to.
                        Text(job.assignedToUserId == nil ? "No tech" : "Other tech")
                            .font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
                    }
                }
                Text(street ?? job.title).font(Theme.font(16, weight: .medium))
                    .foregroundStyle(job.status == "completed" ? Theme.muted : Theme.foreground)
                    .multilineTextAlignment(.leading)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(street != nil ? "\(job.title) · \(customer)" : customer)
                    .font(Theme.font(13)).foregroundStyle(Theme.subtle)
                    .multilineTextAlignment(.leading)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if showsStatus {
                    StatusLabel(jobStatus: job.status, hasTime: job.scheduledFor != nil, emphasis: .quiet, size: 12).padding(.top, 2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(movingJobID != nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([street ?? job.title, street != nil ? job.title : nil, customer, when.spoken,
                             job.status.statusLabel, tech.map { "Assigned to \($0)" } ?? (job.assignedToUserId == nil ? "No tech" : "Assigned outside your roster")]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Assign, reschedule or open this job")
        .accessibilityIdentifier("board-row-\(job.id)")
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
