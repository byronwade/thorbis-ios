import SwiftUI

/// The dispatcher's board (Schedule › Board, roles with `job.assign`), Paper 53: today's jobs that
/// need a tech first, then each technician's day on one card, then the queue waiting for a slot.
/// `columns` keeps the by-status grouping for callers and tests. Tapping a job offers Assign, Reschedule, Open, or a
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
    /// iPad only (Paper T12C): the Schedule's range. When set, the board draws its own title, the
    /// range segments and the day's numbers, and scrolls by itself; nil is the phone's Board tab.
    var tabletRange: Binding<String>? = nil
    /// The day the board shows (Paper 53's Today | Tomorrow); the name `today` is kept for callers.
    var day: Date = .now

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
            job.status != "canceled" && (JobFiltering.date(job.scheduledFor).map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false)
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

    /// Paper 53: today's jobs grouped by technician, with the jobs no one has yet on top.
    /// iPad (`tabletRange`), Paper T12C: the day's numbers, then the same sections beside the techs.
    var body: some View {
        let roster = people.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        let names = Dictionary(people.map { ($0.userId, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        let rosterIDs = Set(people.map(\.userId))
        let unassigned = today.filter { $0.assignedToUserId == nil && $0.status != "completed" }
        let elsewhere = today.filter { job in job.assignedToUserId.map { !rosterIDs.contains($0) } ?? false }
        Group {
            if let tabletRange {
                tabletBoard(range: tabletRange, roster: roster, names: names, unassigned: unassigned, elsewhere: elsewhere)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    boardSections(roster: roster, names: names, unassigned: unassigned, elsewhere: elsewhere,
                                  attentionTitle: "Needs assignment")
                }
                .paperCardMargin()
            }
        }
        .sensoryFeedback(.success, trigger: moved)
        .task(id: session.generation) { await loadRoster() }
        .task(id: "addr|\((unscheduled + today).map { "\($0.id):\($0.locationId ?? "")" }.joined(separator: ","))|\(session.generation)") {
            guard session.can("customer.view", feature: "core_crm") else { return }
            await addresses.load(unscheduled + today, api: api, organizationID: session.activeOrganization?.id,
                                 identity: "\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)", limit: 30)
        }
        .sheet(item: $menuJob, onDismiss: runPending) { job in SheetSurface {
            ThorbisMenuCard(items: choices(for: job, roster: roster), title: menuTitle(job)) { item in
                item.action()
                menuJob = nil
            }
        } }
        .sheet(item: $scheduling) { value in SheetSurface { QuickScheduleSheet(jobID: value.id) } }
        .thorbisDestination(item: $assigning) { JobAssignmentView(jobID: $0.id) }
        .thorbisDestination(item: $opening) { JobDetailView(jobId: $0.id) }
    }

    /// The board's sections, in the phone's order: jobs no one has, each tech's day, the queue.
    @ViewBuilder
    private func boardSections(roster: [FieldAssignee], names: [String: String], unassigned: [Job], elsewhere: [Job],
                               attentionTitle: String) -> some View {
        if let error { ErrorBanner(message: error) }
        if !unassigned.isEmpty {
            PaperSection(attentionTitle, count: unassigned.count) {
                ForEach(unassigned) { job in
                    if job.id != unassigned.first?.id { WellDivider(leading: PaperCardMetrics.inset + 30) }
                    boardRow(job, names: names, assignChip: canAssign)
                }
            }
        }
        if !rosterLoaded {
            SkeletonRows(count: 2, inset: 0)
        } else if canAssign && roster.isEmpty {
            Text("No one can be assigned right now.").font(Theme.font(14)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)
        }
        ForEach(roster) { person in
            let jobs = today.filter { $0.assignedToUserId == person.userId }
            techSection(name: person.displayName, jobs: jobs, names: names)
        }
        if !elsewhere.isEmpty {
            // Without the roster (a role that can't assign) every assigned job lands here.
            techSection(name: roster.isEmpty ? "Assigned" : "Other techs", jobs: elsewhere, names: names)
        }
        // Finished with no tech on it: not "needs assignment", but still part of the day.
        let doneLoose = today.filter { $0.assignedToUserId == nil && $0.status == "completed" }
        if !doneLoose.isEmpty {
            techSection(name: "Done", jobs: doneLoose, names: names)
        }
        // The queue: everyone's jobs that still need a time, worked from the oldest.
        PaperSection("Waiting for a slot", count: unscheduled.count) {
            if unscheduled.isEmpty {
                Text("Everything has a time.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 56, alignment: .leading)
            } else {
                ForEach(unscheduled) { job in
                    if job.id != unscheduled.first?.id { WellDivider() }
                    waitingRow(job)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Unscheduled, \(unscheduled.count)")
    }

    // MARK: iPad (Paper T12C)

    /// What a tech is doing now, as one word for the iPad's Techs card.
    struct TechState: Equatable {
        enum Tone: Equatable { case late, good, quiet }
        let word: String
        let tone: Tone
    }

    /// Late first (it needs someone), then on site, driving, what is left, done.
    static func techState(_ jobs: [Job], now: Date = .now) -> TechState {
        if TodayNumbers.late(jobs, now: now) > 0 { return TechState(word: "Running late", tone: .late) }
        if jobs.contains(where: { ["arrived", "in_progress", "paused"].contains($0.status) }) {
            return TechState(word: "On site", tone: .good)
        }
        if jobs.contains(where: { $0.status == "en_route" }) { return TechState(word: "Driving", tone: .quiet) }
        let left = TodayNumbers.left(jobs)
        if left > 0 { return TechState(word: "\(left) job\(left == 1 ? "" : "s") left", tone: .quiet) }
        if jobs.isEmpty { return TechState(word: "No jobs today", tone: .quiet) }
        return TechState(word: "Done", tone: .good)
    }

    /// Paper T12C: "Schedule" and the day, the segments, "Jobs today" beside three number tiles, then
    /// the board's sections beside the techs.
    private func tabletBoard(range: Binding<String>, roster: [FieldAssignee], names: [String: String],
                             unassigned: [Job], elsewhere: [Job]) -> some View {
        let onSite = today.filter { ["arrived", "in_progress", "paused"].contains($0.status) }
        let working = Set(onSite.compactMap(\.assignedToUserId)).count
        let late = TodayNumbers.late(today)
        let underWay = today.filter { ["en_route", "arrived", "in_progress", "paused", "completed"].contains($0.status) }.count
        let out = Set(today.filter { $0.status != "completed" }.compactMap(\.assignedToUserId)).count
        let day = Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let stacked = typeSize.isAccessibilitySize
        let row = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Schedule").font(Theme.font(34, weight: .bold)).tracking(-0.68)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("schedule-title")
                    Text(out == 0 ? day : "\(day) · \(out) tech\(out == 1 ? "" : "s") out")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 12)
                PaperTabs(options: PaperTabletSchedule.rangeOptions(board: true), selection: range)
                    .frame(maxWidth: 480, alignment: .leading)
                    .padding(.top, 12)
                VStack(alignment: .leading, spacing: 20) {
                    row {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Jobs today").font(Theme.font(15)).foregroundStyle(Theme.muted)
                            Text("\(today.count)").font(Theme.monoFont(34, weight: .bold)).foregroundStyle(Theme.foreground)
                            Text("\(underWay) done or under way").font(Theme.font(14, weight: .semibold))
                                .foregroundStyle(Theme.subtle)
                                .padding(.horizontal, 12).frame(minHeight: 40)
                                .background(Theme.fill, in: Capsule())
                        }
                        .padding(.leading, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        boardTile("On site", "\(onSite.count)", working == 1 ? "1 tech working now" : "\(working) techs working now")
                        boardTile("Running late", "\(late)", late == 0 ? "everyone on time" : "past their time")
                        boardTile("Waiting for a slot", "\(unscheduled.count)", unscheduled.count == 1 ? "needs a time" : "need a time")
                    }
                    row {
                        VStack(alignment: .leading, spacing: 20) {
                            boardSections(roster: roster, names: names, unassigned: unassigned, elsewhere: elsewhere,
                                          attentionTitle: "Needs attention")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if canAssign && rosterLoaded && !roster.isEmpty {
                            techsCard(roster)
                                .frame(maxWidth: stacked ? .infinity : 340)
                        }
                    }
                }
                .paperCardMargin()
                .padding(.top, 20)
            }
            .padding(.bottom, 24)
        }
        .refreshable { await store.refresh(api) }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Paper T12C's number tile: the label, the figure in bold, what it counts.
    private func boardTile(_ label: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.font(14)).foregroundStyle(Theme.muted)
                .padding(.bottom, 12)
            Text(value).font(Theme.monoFont(24, weight: .bold)).foregroundStyle(Theme.foreground)
            Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 200, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Paper T12C's Techs card: each tech with what they are doing now.
    private func techsCard(_ roster: [FieldAssignee]) -> some View {
        PaperSection("Techs", count: roster.count) {
            ForEach(roster) { person in
                if person.id != roster.first?.id { WellDivider() }
                techStateRow(person)
            }
        }
    }

    private func techStateRow(_ person: FieldAssignee) -> some View {
        let state = Self.techState(today.filter { $0.assignedToUserId == person.userId })
        let tint: Color = state.tone == .late ? Theme.warning : (state.tone == .good ? Theme.success : Theme.muted)
        return HStack(spacing: 8) {
            Text(person.displayName).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            Spacer(minLength: 8)
            Text(state.word).font(Theme.font(14, weight: .medium)).foregroundStyle(tint)
        }
        .padding(.horizontal, PaperCardMetrics.inset)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }

    /// Paper 53: the tech's initials, name, and "3 jobs" at the trailing edge, then their day on one card.
    @ViewBuilder
    private func techSection(name: String, jobs: [Job], names: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                InitialsAvatar(name: name, size: 24).accessibilityHidden(true)
                Text(name).font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                // Paper 53: what the tech is doing now, as a word beside the name.
                if let now = Self.nowWord(jobs) {
                    Text(now).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.success)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(jobs.count) job\(jobs.count == 1 ? "" : "s")").font(Theme.font(13)).monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 26)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([name, Self.nowWord(jobs), "\(jobs.count) job\(jobs.count == 1 ? "" : "s")"].compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(.isHeader)
            if !jobs.isEmpty {
                PaperCard {
                    ForEach(jobs) { job in
                        if job.id != jobs.first?.id { WellDivider(leading: PaperCardMetrics.inset + 34) }
                        boardRow(job, names: names, assignChip: false)
                    }
                }
            }
        }
    }

    /// "On site" while one of the tech's jobs is being worked, "On the way" while they drive to
    /// one; nil otherwise (the section never guesses where a tech is).
    static func nowWord(_ jobs: [Job]) -> String? {
        if jobs.contains(where: { ["arrived", "in_progress"].contains($0.status) }) { return "On site" }
        if jobs.contains(where: { $0.status == "en_route" }) { return "On the way" }
        return nil
    }

    /// Paper 53's row: the status mark, "AC tune-up · 88 Birch Ln" over "9:00 AM · Done", then the
    /// tech's initials (or Assign). Tapping it offers Assign, Reschedule, Open or a move.
    private func boardRow(_ job: Job, names: [String: String], assignChip: Bool) -> some View {
        let customer = store.customerName(job.customerId)
        let street = addresses.street(job)
        let tech = job.assignedToUserId.flatMap { names[$0] ?? (job.assignedToUserId == session.user?.id ? session.user?.name : nil) }
        let time = JobFiltering.date(job.scheduledFor)
        let statusWord = job.assignedToUserId == nil && job.status != "completed" ? "No tech assigned" : job.status.statusLabel
        let detail = [time?.clockTime, statusWord].compactMap { $0 }.joined(separator: " · ")
        let title = street.map { "\(job.title) · \($0)" } ?? "\(job.title) · \(customer)"
        return HStack(spacing: 0) {
            Button { menuJob = job } label: {
                HStack(spacing: 0) {
                    StatusRing(status: job.status, size: 18)
                        .frame(width: 34, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        // Paper 53: a visit under way reads in the warning hue.
                        Text(detail).font(Theme.font(14)).monospacedDigit()
                            .foregroundStyle(ScheduleLead.activeStatuses.contains(job.status) ? Theme.warning : Theme.muted)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !assignChip {
                        if movingJobID == job.id {
                            ProgressView().controlSize(.small).frame(width: 28)
                        } else if let tech {
                            InitialsAvatar(name: tech, size: 28).accessibilityHidden(true)
                        } else if job.assignedToUserId != nil {
                            Text("Other tech").font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(.leading, PaperCardMetrics.inset).padding(.trailing, assignChip ? 8 : PaperCardMetrics.inset)
                .padding(.vertical, 11)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .disabled(movingJobID != nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([street ?? job.title, street != nil ? job.title : nil, customer, time?.tradeTime ?? "No time",
                                 job.status.statusLabel, tech.map { "Assigned to \($0)" } ?? (job.assignedToUserId == nil ? "No tech" : "Assigned outside your roster")]
                .compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Assign, reschedule or open this job")
            .accessibilityIdentifier("board-row-\(job.id)")
            if assignChip {
                Button { assigning = job } label: { brandChip("Assign") }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Assign \(job.title)")
                    .padding(.trailing, 10)
            }
        }
    }

    /// Paper 57F's row: the job over who and how long it has waited, with Schedule on the right.
    private func waitingRow(_ job: Job) -> some View {
        let customer = store.customerName(job.customerId)
        let waited = JobFiltering.date(job.createdAt).map { "waiting \(ScheduleCompactRow.age(since: $0))" }
        return HStack(spacing: 8) {
            Button { menuJob = job } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title).font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .multilineTextAlignment(.leading)
                    Text([customer, waited].compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                }
                .padding(.leading, PaperCardMetrics.inset).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .disabled(movingJobID != nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([job.title, customer, waited].compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Assign, reschedule or open this job")
            .accessibilityIdentifier("board-row-\(job.id)")
            if canAssign {
                Button { scheduling = job } label: { brandChip("Schedule") }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Schedule \(job.title)")
                    .padding(.trailing, 10)
            }
        }
    }

    /// The brand chip Paper uses for a row's one action (Assign, Schedule), 44 tall.
    private func brandChip(_ title: String) -> some View {
        Text(title).font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.brandText)
            .fixedSize()
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(Theme.brandSurface, in: Capsule())
            .contentShape(Capsule())
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
