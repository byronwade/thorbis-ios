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
    /// Paper 53: each technician's day folds behind the chevron by their name.
    @State private var folded: Set<String> = []
    @State private var attentionFolded = false
    /// The whole waiting queue as its own page; the Schedule shows only the oldest few.
    var waitingOnly = false
    @State private var showsAllWaiting = false
    @State private var waitingSearch = ""
    /// How many waiting jobs the Schedule itself lists before "See all".
    static let waitingPreview = 3
    /// Paper 53's toast after a one-tap move ("Job reassigned to Mike Tran · Undo"); the screen
    /// that hosts the board draws it at its foot.
    var toast: Binding<BoardToast?>? = nil

    struct BoardToast: Identifiable {
        let id = UUID()
        let message: String
        /// Puts the job back with the tech it came from; nil when it had none.
        let undo: (() -> Void)?
    }
    /// iPad only (Paper T12C): the Schedule's range. When set, the board draws its own title, the
    /// range segments and the day's numbers, and scrolls by itself; nil is the phone's Board tab.
    var tabletRange: Binding<String>? = nil
    /// The day the board shows (Paper 53's Today | Tomorrow); the name `today` is kept for callers.
    var day: Date = .now

    private enum Pending { case open(Job), schedule(Job), assign(Job) }

    private var canAssign: Bool { session.can("job.assign", feature: "jobs") }

    /// The day's two lists, worked out once per change to the jobs or the day. They are read many
    /// times while the board draws (once per waiting row, once per tech); filtering and sorting
    /// the whole book on every read froze the app on a company with thousands of jobs.
    @State private var lists = BoardLists()

    /// Oldest waiting first: the queue is worked from the top.
    var unscheduled: [Job] { lists.resolve(store.jobs, day: day).unscheduled }

    /// Today's visits, finished ones included (dimmed) so each tech's day reads whole.
    var today: [Job] { lists.resolve(store.jobs, day: day).today }

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
            if waitingOnly {
                waitingPage
            } else if let tabletRange {
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
        .thorbisDestination(isPresented: $showsAllWaiting) { DispatchBoardView(waitingOnly: true) }
    }

    /// Every job that still needs a time, oldest first, with a filter by job or customer. Rows are
    /// built as they scroll into view, so a queue of hundreds opens at once.
    private var waitingPage: some View {
        let all = unscheduled
        let needle = waitingSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = needle.isEmpty ? all : all.filter {
            $0.title.localizedCaseInsensitiveContains(needle) || store.customerName($0.customerId).localizedCaseInsensitiveContains(needle)
        }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PaperPageTitle(title: "Waiting for a slot",
                               subtitle: all.count == 1 ? "1 job needs a time" : "\(PaperCount.text(all.count)) jobs need a time")
                PaperSearchInput(text: $waitingSearch, label: "Search waiting jobs", placeholder: "Search") { EmptyView() }
                    .paperCardMargin().padding(.top, 16).padding(.bottom, 16)
                if let error { ErrorBanner(message: error) }
                if shown.isEmpty {
                    ListRoomEmpty(title: all.isEmpty ? "Everything has a time" : "No waiting jobs match",
                                  message: all.isEmpty ? "New jobs without a time show up here." : "Try a job name or a customer.")
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, job in
                    VStack(alignment: .leading, spacing: 0) {
                        if index > 0 { WellDivider() }
                        waitingRow(job)
                    }
                    .paperRowsCardSlice(first: index == 0, last: index == shown.count - 1)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The board's sections, in the phone's order: jobs no one has, each tech's day, the queue.
    @ViewBuilder
    private func boardSections(roster: [FieldAssignee], names: [String: String], unassigned: [Job], elsewhere: [Job],
                               attentionTitle: String) -> some View {
        if let error { ErrorBanner(message: error) }
        if !unassigned.isEmpty {
            PaperSection(attentionTitle, count: unassigned.count, collapsed: $attentionFolded) {
                ForEach(unassigned) { job in
                    if job.id != unassigned.first?.id { WellDivider(leading: PaperCardMetrics.inset + 30) }
                    boardRow(job, names: names, assignChip: canAssign)
                }
            }
        }
        if !rosterLoaded {
            SkeletonRows(count: 2, inset: 0)
        } else if canAssign && roster.isEmpty {
            PaperInlineEmpty("No one can be assigned right now.")
                .padding(.horizontal, 4)
        }
        ForEach(roster) { person in
            let jobs = today.filter { $0.assignedToUserId == person.userId }
            techSection(id: person.userId, name: person.displayName, jobs: jobs, names: names)
        }
        if !elsewhere.isEmpty {
            // Without the roster (a role that can't assign) every assigned job lands here.
            techSection(id: "elsewhere", name: roster.isEmpty ? "Assigned" : "Other techs", jobs: elsewhere, names: names)
        }
        // Finished with no tech on it: not "needs assignment", but still part of the day.
        let doneLoose = today.filter { $0.assignedToUserId == nil && $0.status == "completed" }
        if !doneLoose.isEmpty {
            techSection(id: "done-loose", name: "Done", jobs: doneLoose, names: names)
        }
        // The queue: everyone's jobs that still need a time, worked from the oldest.
        PaperSection("Waiting for a slot", count: unscheduled.count) {
            if unscheduled.isEmpty {
                Text("Everything has a time.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 56, alignment: .leading)
            } else {
                // Paper 53 keeps the Schedule to the day. The queue shows its oldest few here and
                // the rest on its own page, so hundreds of waiting jobs never bury the techs.
                let all = unscheduled
                let waiting = Array(all.prefix(Self.waitingPreview))
                ForEach(waiting) { job in
                    if job.id != waiting.first?.id { WellDivider() }
                    waitingRow(job)
                }
                if all.count > waiting.count {
                    WellDivider()
                    PaperSeeAllRow(count: all.count, label: "See all \(all.count) waiting jobs", identifier: "board-waiting-all") { showsAllWaiting = true }
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
                PaperPageTitle(title: "Schedule", subtitle: out == 0 ? day : "\(day) · \(out) tech\(out == 1 ? "" : "s") out",
                               underBar: false, titleIdentifier: "schedule-title")
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

    /// Paper 53: the fold chevron, the tech's initials and name, what they are doing now and
    /// "3 jobs" at the trailing edge, then their day on one card.
    @ViewBuilder
    private func techSection(id: String, name: String, jobs: [Job], names: [String: String]) -> some View {
        // A tech with nothing booked has nothing to unfold: the chevron points right, as Paper's does.
        let isFolded = jobs.isEmpty || folded.contains(id)
        let state = Self.boardState(jobs)
        let count = "\(jobs.count) job\(jobs.count == 1 ? "" : "s")"
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withMotion { if folded.contains(id) { folded.remove(id) } else { folded.insert(id) } }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    PaperIcon(.chevronDown, size: 12, color: Theme.muted)
                        .rotationEffect(.degrees(isFolded ? -90 : 0))
                    InitialsAvatar(name: name, size: 24)
                    Text(name).font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    // Paper 53: what the tech is doing now, as a word beside the name.
                    if let state {
                        Text(state.word).font(Theme.font(13, weight: .semibold))
                            .foregroundStyle(state.tone == .late ? Theme.destructive : Theme.success)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(count).font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 4)
                // 44pt to the finger, Paper's 24 to the eye.
                .frame(minHeight: 44).contentShape(Rectangle()).padding(.vertical, -10)
            }
            .buttonStyle(PressStyle())
            .disabled(jobs.isEmpty)
            .padding(.bottom, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([name, state?.word, count].compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(jobs.isEmpty ? "" : (isFolded ? "Collapsed" : "Expanded"))
            .accessibilityIdentifier("board-tech-\(id)")
            if !isFolded {
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

    /// Paper 53's word beside a tech's name: "Running late" (a booked start has passed and the job
    /// has not begun), else where they are. Nothing when neither is known: the app has no
    /// availability record, so it never prints Paper's "Available".
    static func boardState(_ jobs: [Job], now: Date = .now) -> TechState? {
        if TodayNumbers.late(jobs, now: now) > 0 { return TechState(word: "Running late", tone: .late) }
        return nowWord(jobs).map { TechState(word: $0, tone: .good) }
    }

    /// "25 min behind" for a booked job whose start has passed without it beginning; nil otherwise.
    static func behindWord(_ job: Job, now: Date = .now) -> String? {
        guard ["scheduled", "dispatched"].contains(job.status), let start = JobFiltering.date(job.scheduledFor), start < now else { return nil }
        let minutes = max(1, Int(now.timeIntervalSince(start) / 60))
        return minutes < 60 ? "\(minutes) min behind" : "\(minutes / 60) hr \(minutes % 60) min behind"
    }

    /// Paper 53's second line word: "Done", "On site now", "25 min behind", else the status.
    static func rowWord(_ job: Job, now: Date = .now) -> String {
        if let behind = behindWord(job, now: now) { return behind }
        switch job.status {
        case "completed": return "Done"
        case "arrived", "in_progress": return "On site now"
        case "en_route": return "On the way"
        default: return job.status.statusLabel
        }
    }

    /// Paper 53's row: the status mark, "AC tune-up · 88 Birch Ln" over "9:00 AM · Done", then the
    /// tech's initials (or Assign). Tapping it offers Assign, Reschedule, Open or a move.
    private func boardRow(_ job: Job, names: [String: String], assignChip: Bool) -> some View {
        let customer = store.customerName(job.customerId)
        let street = addresses.street(job)
        let tech = job.assignedToUserId.flatMap { names[$0] ?? (job.assignedToUserId == session.user?.id ? session.user?.name : nil) }
        let time = JobFiltering.date(job.scheduledFor)
        let behind = Self.behindWord(job) != nil
        let statusWord = job.assignedToUserId == nil && job.status != "completed" ? "No tech assigned" : Self.rowWord(job)
        let detail = [time?.clockTime, statusWord].compactMap { $0 }.joined(separator: " · ")
        // Paper 53: "AC tune-up · 88 Birch Ln"; the job no one has reads "Drain backup — 214 Maple St".
        let joiner = assignChip ? " \u{2014} " : " \u{00B7} "
        let title = "\(job.title)\(joiner)\(street ?? customer)"
        let detailTint: Color = assignChip ? Theme.muted
            : behind ? Theme.destructive : (ScheduleLead.activeStatuses.contains(job.status) ? Theme.warning : Theme.muted)
        return HStack(spacing: 0) {
            Button { menuJob = job } label: {
                HStack(spacing: 0) {
                    if assignChip {
                        // Paper 53: a dashed circle around a person, 20pt in a 30pt slot.
                        NoTechGlyph().frame(width: 30, alignment: .leading)
                    } else {
                        StatusGlyph(tone: StatusTone(jobStatus: job.status, hasTime: job.scheduledFor != nil),
                                    label: job.status.statusLabel, size: 22)
                            .frame(width: 34, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        // Paper 53: a visit under way reads in the warning hue.
                        Text(detail).font(Theme.font(14)).monospacedDigit()
                            .foregroundStyle(detailTint)
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
                                 Self.rowWord(job), tech.map { "Assigned to \($0)" } ?? (job.assignedToUserId == nil ? "No tech" : "Assigned outside your roster")]
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
                    Text(job.title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        .multilineTextAlignment(.leading)
                    Text([customer, waited].compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                }
                .padding(.leading, PaperCardMetrics.inset).padding(.vertical, 10)
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
                Button { scheduling = job } label: { Text("Schedule").paperButton(.compact, tone: .tinted) }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Schedule \(job.title)")
                    .padding(.trailing, 10)
            }
        }
    }

    /// The brand chip Paper uses for a row's one action (Assign, Schedule): the compact 36pt pill,
    /// the same as the waiting rows' Schedule, so a long title keeps the row's width.
    private func brandChip(_ title: String) -> some View {
        Text(title).paperButton(.compact, tone: .tinted)
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
    private func move(_ job: Job, to person: FieldAssignee, announce: Bool = true) async {
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
            // Paper 53: the move is confirmed at the foot of the screen with a way back.
            let before = job.assignedToUserId.flatMap { id in people.first { $0.userId == id } }
            if announce {
                let moved = Job(id: job.id, customerId: job.customerId, title: job.title, status: job.status, createdAt: job.createdAt,
                                updatedAt: job.updatedAt, allowedTransitions: job.allowedTransitions, scheduledFor: job.scheduledFor,
                                assignedToUserId: person.userId, locationId: job.locationId)
                toast?.wrappedValue = BoardToast(message: "Job reassigned to \(person.displayName)", undo: before.map { prior in
                    { Task { await move(moved, to: prior, announce: false) } }
                })
            } else {
                toast?.wrappedValue = nil
            }
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


/// Paper 53's mark for a job no one has: a person inside a dashed ring (20pt, 1.3 stroke, muted).
private struct NoTechGlyph: View {
    var body: some View {
        ZStack {
            Circle().inset(by: 1.8).stroke(Theme.muted, style: StrokeStyle(lineWidth: 1.3, dash: [2.5, 2.5]))
            PaperIcon(.noTechPerson, size: 20, color: Theme.muted)
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

extension PaperGlyph {
    /// The person inside Paper 53's dashed ring.
    static let noTechPerson = PaperGlyph(box: 20, [.circle(10, 8, 2.2, 1.3),
                                                   .stroke("M6.2 14C6.8 12.5 8.2 11.7 10 11.7C11.8 11.7 13.2 12.5 13.8 14", 1.3)])
    /// Paper 53's toast arrow (undo).
    static let undoArrow = PaperGlyph(box: 20, [.stroke("M7.5 5L4 8.5L7.5 12M4.5 8.5H12C14.2 8.5 16 10.3 16 12.5C16 14.7 14.2 16.5 12 16.5H9.5", 1.7)])
}

/// `DispatchBoardView`'s day, kept between redraws. Held in `@State` as a reference so reading it
/// while the view draws never invalidates the view.
final class BoardLists {
    private var jobs: [Job] = []
    private var day: Date?
    private(set) var today: [Job] = []
    private(set) var unscheduled: [Job] = []

    /// Recomputes only when the jobs or the day changed (comparing the same array is immediate).
    func resolve(_ jobs: [Job], day: Date, calendar: Calendar = .current) -> BoardLists {
        if let last = self.day, calendar.isDate(last, inSameDayAs: day), jobs == self.jobs { return self }
        self.jobs = jobs
        self.day = day
        unscheduled = JobFiltering.schedule(jobs, range: .unscheduled).sortedByDate(\.createdAt, missing: .distantFuture)
        today = jobs.filter { job in
            job.status != "canceled" && (JobFiltering.date(job.scheduledFor).map { calendar.isDate($0, inSameDayAs: day) } ?? false)
        }.sortedByDate(\.scheduledFor, missing: .distantFuture)
        return self
    }
}
