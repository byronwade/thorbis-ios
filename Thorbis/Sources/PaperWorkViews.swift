import SwiftUI
import UIKit

func statusIcon(_ status: String) -> (String, Color) {
    switch status {
    case "completed": ("checkmark.circle.fill", Theme.success)
    case "in_progress", "arrived": ("circle.lefthalf.filled", Theme.warning)
    case "paused": ("pause.circle", Theme.warning)
    case "en_route": ("arrow.right.circle", Theme.brandText)
    case "dispatched": ("circle.dashed", Theme.brandText)
    case "canceled": ("xmark.circle", Theme.muted)
    default: ("circle", Theme.muted)
    }
}

/// How a job is shared in words: what, who and when, never an internal ID.
enum JobShareText {
    static func text(title: String, customer: String, scheduledFor: String?) -> String {
        var parts = [title, customer]
        if let date = JobFiltering.date(scheduledFor) {
            // Absolute, never "Today": the message may be read another day.
            parts.append("\(date.weekdayStampLabel)")
        }
        return parts.joined(separator: " · ")
    }
}

extension View {
    /// design.thorbis.com MA-12: a job row's common actions on long-press. Each one also exists on
    /// the job itself, so the gesture is a shortcut, never the only way.
    func jobContextMenu(_ job: Job, customer: String) -> some View {
        contextMenu {
            Button("Copy job number", systemImage: "doc.on.doc") { UIPasteboard.general.string = job.shortRef }
            ShareLink(item: JobShareText.text(title: job.title, customer: customer, scheduledFor: job.scheduledFor)) {
                Label("Share job", systemImage: "square.and.arrow.up")
            }
        }
    }
}

enum PaperWorkGroups {
    static func inProgress(_ jobs: [Job]) -> [Job] {
        jobs.filter { ["in_progress", "arrived", "en_route", "paused"].contains($0.status) }
    }
    static func scheduled(_ jobs: [Job]) -> [Job] {
        jobs.filter { ["scheduled", "dispatched"].contains($0.status) }
    }
    static func completed(_ jobs: [Job]) -> [Job] { jobs.filter { $0.status == "completed" } }
    /// The job under way, else the earliest booked one: what "open my next job" means.
    static func next(_ jobs: [Job]) -> Job? {
        inProgress(jobs).first ?? scheduled(jobs).min {
            (JobFiltering.date($0.scheduledFor) ?? .distantFuture) < (JobFiltering.date($1.scheduledFor) ?? .distantFuture)
        }
    }
    static func other(_ jobs: [Job]) -> [Job] {
        jobs.filter { !["in_progress", "arrived", "en_route", "paused", "scheduled", "dispatched", "completed"].contains($0.status) }
    }
}

/// Paper 18 / 79: the technician's day. "Next up" opens the job, where its next step lives; each
/// row's swipe still offers the next move.
enum ScheduleLead {
    /// Statuses that mean the tech is already on this job.
    static let activeStatuses: Set<String> = ["en_route", "arrived", "in_progress", "paused"]
}

struct ScheduleView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @State private var tab = "Today"
    /// Nil until the person picks; until then the role decides (technicians: Mine).
    @State private var pickedScope: ScheduleScope?
    @State private var showNew = false
    /// A job without a time whose Schedule button was tapped; the sheet reads it fresh.
    @State private var scheduling: Job?
    @State private var progressError: String?
    /// The Next up job as GET /v1/jobs/{id} returns it: list items carry no allowed transitions,
    /// so the hero's commit is read from the server rather than guessed from status.
    @State private var hero: JobRecord?
    /// Today's lead job's own address and number, read live or from the last copy.
    @State private var stop: NextStopPlace?
    @StateObject private var eta = NextStopETA()
    /// Street lines for the rows (street first, design 2026-10-30).
    @StateObject private var addresses = JobAddressBook()
    /// The Next stop card's "Turn on location" line, once dismissed, stays away this launch.
    @State private var locationNoticeDismissed = NextStopLocationNotice.dismissedThisLaunch
    /// Who each tech is, for the rows' avatars. Never kept on the phone: offline the rows show none
    /// rather than guess.
    @State private var roster: [String: String] = [:]
    /// The rows' swipes: what each row has read (allowed moves, a number to call) and the moves sent.
    @StateObject private var swipes = JobRowSwipeBook()
    /// The day a Week tile was tapped for; the list scrolls to that day's group, then this clears.
    @State private var weekJump: Date?
    /// Paper 53: the board's "Job reassigned to Mike Tran · Undo" at the foot of the screen.
    @State private var boardToast: DispatchBoardView.BoardToast?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var range: ScheduleRange {
        switch tab {
        case "Week": .week
        case "Unscheduled": .unscheduled
        case "Map", "Tomorrow": .today
        default: .today
        }
    }
    private var scope: ScheduleScope {
        pickedScope ?? .initial(schedulesOwnDay: WorkRole(session).schedulesOwnDay, actorID: session.user?.id)
    }
    /// Mine/Everyone applies to a day, week or map; Unscheduled is everyone's queue.
    private var showsScope: Bool { range != .unscheduled && session.user?.id != nil }
    /// Finding a job is the bar's Search; this screen narrows by range and whose jobs only.
    private var jobs: [Job] {
        let assignee = scope.assignee(session.user?.id, range: range)
        // Paper 79: the Week strip starts today and runs seven days, so the list does too.
        if range == .week, let span = Self.rollingWeek() {
            return store.jobs.filter { job in
                !["completed", "canceled"].contains(job.status) && (assignee == nil || job.assignedToUserId == assignee) &&
                    (JobFiltering.date(job.scheduledFor).map(span.contains) ?? false)
            }
            .sorted { (JobFiltering.date($0.scheduledFor) ?? .distantFuture) < (JobFiltering.date($1.scheduledFor) ?? .distantFuture) }
        }
        return JobFiltering.schedule(store.jobs, range: range, assignedTo: assignee)
    }

    /// Today and the six days after it (Paper 79 "Jul 21 – 27" with today's tile first).
    static func rollingWeek(now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 7, to: start).map { DateInterval(start: start, end: $0.addingTimeInterval(-1)) }
    }
    private var canSchedule: Bool { session.can("job.assign", feature: "jobs") }

    /// Paper 53: roles that assign get Today | Tomorrow | Week, each day drawn by technician; the map
    /// moves behind the filter circle. Paper 18: a technician gets Today | Week | Map.
    private var tabOptions: [String] { canSchedule ? ["Today", "Tomorrow", "Week"] : ["Today", "Week", "Map"] }
    /// The dispatcher's day by technician (Paper 53): everyone's jobs, today or tomorrow.
    private var showsBoard: Bool { canSchedule && scope == .everyone && (tab == "Today" || tab == "Tomorrow") }
    private var boardDay: Date {
        tab == "Tomorrow" ? (Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now) : .now
    }

    /// The filter circle reads as on while it narrows the screen past the role's usual view.
    private var filterNarrows: Bool {
        tab == "Unscheduled" || (showsScope && scope == .everyone && WorkRole(session).schedulesOwnDay)
    }

    /// Paper 18: what narrows the schedule sits in the search field as chips; × takes it off.
    private var scheduleChips: [PaperFilterChip] {
        var chips: [PaperFilterChip] = []
        if tab == "Unscheduled" {
            chips.append(PaperFilterChip(id: "unscheduled", title: "Unscheduled") { tab = "Today" })
        } else if showsScope && scope == .mine {
            chips.append(PaperFilterChip(id: "mine", title: "My jobs") { pickedScope = .everyone })
        } else if showsScope && canSchedule {
            // Paper 53: the dispatcher's field reads "All techs"; × narrows to their own jobs.
            chips.append(PaperFilterChip(id: "everyone", title: "All techs") { pickedScope = .mine })
        }
        if tab == "Map" && canSchedule {
            chips.append(PaperFilterChip(id: "map", title: "Map") { tab = "Today" })
        }
        return chips
    }

    /// Paper 18 / 79 / 80: "Tuesday, July 21 · 5 jobs", "Jul 21 – 27 · 22 jobs", "Today · 4 stops".
    private var headerSubtitle: String {
        if range == .unscheduled { return subtitle }
        if showsBoard { return boardSubtitle }
        if tab == "Map" {
            let count = jobs.filter { $0.status != "canceled" }.count
            return "Today · \(count) stop\(count == 1 ? "" : "s")"
        }
        if range == .week {
            return "\(weekSpan) · \(jobs.count) job\(jobs.count == 1 ? "" : "s")"
        }
        // Paper 19: an empty board greets the person, "Tue, Jul 21 · Welcome, Byron".
        if store.jobs.isEmpty && !store.loading {
            let short = Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            let first = session.user?.name?.split(separator: " ").first.map(String.init) ?? ""
            return first.isEmpty ? short : "\(short) \u{00B7} Welcome, \(first)"
        }
        let day = Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let count = todayVisits.count
        return count == 0 ? day : "\(day) · \(count) job\(count == 1 ? "" : "s")"
    }

    /// "Jul 21 – 27" (or "Jul 28 – Aug 3" across a month): this week, as the Week range reads it.
    private var weekSpan: String {
        let calendar = Calendar.current
        guard let week = Self.rollingWeek() else { return "This week" }
        let last = week.end
        let start = week.start.formatted(.dateTime.month(.abbreviated).day())
        let sameMonth = calendar.component(.month, from: week.start) == calendar.component(.month, from: last)
        let end = sameMonth ? last.formatted(.dateTime.day()) : last.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }

    private var canSeeMoney: Bool { session.can("invoice.view", feature: "invoicing") }

    /// Whose jobs and the Unscheduled queue: the secondary filters behind the view circle.
    private var filterItems: [ThorbisMenuItem] {
        var items: [ThorbisMenuItem] = []
        if session.user?.id != nil {
            items.append(ThorbisMenuItem("My jobs", icon: "person", isSelected: tab != "Unscheduled" && scope == .mine) {
                pickedScope = .mine
                if tab == "Unscheduled" { tab = "Today" }
            })
            items.append(ThorbisMenuItem("Everyone", icon: "person.2", isSelected: tab != "Unscheduled" && scope == .everyone) {
                pickedScope = .everyone
                if tab == "Unscheduled" { tab = "Today" }
            })
        }
        if canSchedule {
            // Paper 53 has no Map segment for the office: the map stays one tap away here.
            items.append(ThorbisMenuItem("Map", icon: "map", subtitle: "Today's stops on the map", isSelected: tab == "Map") {
                tab = tab == "Map" ? "Today" : "Map"
            })
        }
        items.append(ThorbisMenuItem("Unscheduled", icon: "calendar.badge.exclamationmark",
                                     subtitle: "Jobs that still need a time", isSelected: tab == "Unscheduled") {
            tab = tab == "Unscheduled" ? "Today" : "Unscheduled"
        })
        return items
    }

    var body: some View {
        ScrollView {
          ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                // Paper 18: the menu and + circles, "Schedule" and the day, the search field holding
                // whose-jobs as a chip and the filter circle, then Today / Week / Map segments.
                PaperHeader(title: "Schedule", subtitle: headerSubtitle, showsCreate: true, titleIdentifier: "schedule-title")
                PaperSearchBar(placeholder: "Search or ask", chips: scheduleChips) {
                    ThorbisMenu(items: filterItems, title: "Show", accessibilityLabel: "Filter schedule") {
                        PaperFilterCircle(active: filterNarrows)
                    }
                    .accessibilityValue(filterNarrows ? "Filtered" : "")
                    .accessibilityIdentifier("header-filter")
                }
                .paperCardMargin()
                PaperTabs(options: tabOptions, selection: $tab)
                    .padding(.top, 16)
                OfflineBanner()
                if let error = store.error { ErrorBanner(message: error) { _ = await store.refresh(api) } }
                if let progressError { ErrorBanner(message: progressError) }
                if let problem = swipes.problem { ErrorBanner(message: problem) }
                // Paper 57F: follow-ups the field asked for that the office has to book. A different
                // queue from the jobs below (those have no time; these are the server's office reviews).
                if tab == "Unscheduled" { OfficeSlotQueueSection(roster: roster) }
                if store.loading && store.jobs.isEmpty {
                    SkeletonList(count: 4, leading: true).paperCardMargin()
                } else if showsBoard {
                    DispatchBoardView(toast: $boardToast, day: boardDay)
                        .padding(.top, 22)
                } else if jobs.isEmpty {
                    emptyState
                    if range == .today { doneToday }
                } else if tab == "Map" {
                    ScheduleMapView(jobs: jobs.filter { $0.status != "canceled" })
                } else if range == .week {
                    weekContent
                } else {
                    dayContent
                }
            }
            .padding(.bottom, 24)
            // Paper 79: a Week tile jumps the list to its day.
            .onChange(of: weekJump) { _, day in
                guard let day else { return }
                withMotion(.easeOut(duration: 0.2)) { proxy.scrollTo(day, anchor: .top) }
                weekJump = nil
            }
          }
        }
        .refreshable { await store.refresh(api) }
        .overlay(alignment: .bottom) {
            if let boardToast, showsBoard {
                ThorbisToast(symbol: "arrow.uturn.backward", message: boardToast.message,
                             actionTitle: boardToast.undo == nil ? nil : "Undo",
                             action: boardToast.undo.map { undo in { self.boardToast = nil; undo() } })
                    .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 12)
                    .transition(ThorbisToast.transition(reduceMotion: reduceMotion))
                    .task(id: boardToast.id) {
                        try? await Task.sleep(for: .seconds(6))
                        if !Task.isCancelled { withMotion { self.boardToast = nil } }
                    }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: boardToast?.id)
        // An open row closes as soon as the list moves.
        .onScrollPhaseChange { _, phase in if phase != .idle { swipes.rows.close() } }
        .background(Theme.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNew) { SheetSurface { NewJobSheet() } }
        .sheet(item: $scheduling) { value in SheetSurface { QuickScheduleSheet(jobID: value.id) } }
        // A swiped move: success once the server took it; a lighter tap when it is only saved here.
        .sensoryFeedback(.success, trigger: swipes.confirmed)
        .sensoryFeedback(.impact(weight: .light), trigger: swipes.queued)
        .task(id: "swipes|\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)") {
            swipes.reset(identity: "\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)")
        }
        .task(id: "roster|\(session.generation)|\(session.isOffline)") {
            guard session.can("job.view", feature: "jobs"), !session.isOffline,
                  let people = try? await api.fieldAssignees() else { return }
            roster = Dictionary(people.map { ($0.userId, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        }
        .task(id: "addr|\(jobs.map { "\($0.id):\($0.locationId ?? "")" }.joined(separator: ","))|\(session.generation)|\(session.isOffline)") {
            guard tab != "Map", session.can("customer.view", feature: "core_crm") else { return }
            await addresses.load(jobs, api: api, organizationID: session.activeOrganization?.id,
                                 identity: "\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)")
        }
        #if DEBUG
        .onAppear {
            if PaperPreview.enabled && PaperPreview.screen == "schedule-map" { tab = "Map" }
            if PaperPreview.enabled && PaperPreview.screen == "schedule-week" { tab = "Week" }
            if PaperPreview.enabled && PaperPreview.screen == "schedule-unscheduled" { tab = "Unscheduled" }
            if PaperPreview.enabled && PaperPreview.screen == "dispatch-board" { tab = "Today"; pickedScope = .everyone }
        }
        #endif
    }

    private var subtitle: String {
        let count = jobs.count
        let who = showsScope && scope == .mine ? "Your jobs" : "Everyone"
        return switch range {
        case .today: NextStopDay.subtitle(jobs: todayVisits, lead: leadJob)
        case .week: "\(who) · \(count) job\(count == 1 ? "" : "s")"
        case .unscheduled: "\(count) job\(count == 1 ? "" : "s") need a time · everyone's"
        }
    }

    /// Paper 53: "Tue, Jul 21 · 7 techs out · 1 unassigned".
    private var boardSubtitle: String {
        let day = boardDay
        let booked = store.jobs.filter { job in
            job.status != "canceled" && (JobFiltering.date(job.scheduledFor).map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false)
        }
        let out = Set(booked.filter { $0.status != "completed" }.compactMap(\.assignedToUserId)).count
        let unassigned = booked.filter { $0.assignedToUserId == nil && $0.status != "completed" }.count
        var parts = [day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                     "\(out) tech\(out == 1 ? "" : "s") out"]
        if unassigned > 0 { parts.append("\(unassigned) unassigned") }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The job the tech is on right now leads, even when an earlier slot is still open;
    /// otherwise the next one by time.
    private var leadJob: Job? {
        if let active = jobs.first(where: { ScheduleLead.activeStatuses.contains($0.status) }) { return active }
        // Today the next stop is the earliest booked visit, not a finished one from this morning.
        if range == .today, let booked = PaperWorkGroups.next(jobs) { return booked }
        return jobs.first
    }

    /// Today's visits in scope, finished ones included (the list itself hides them), so the
    /// subtitle can say "visit 3 of 6" and Done today can count them.
    private var todayVisits: [Job] {
        let assignee = scope.assignee(session.user?.id, range: .today)
        return store.jobs.filter { job in
            job.status != "canceled" && (assignee == nil || job.assignedToUserId == assignee) &&
                (JobFiltering.date(job.scheduledFor).map { Calendar.current.isDateInToday($0) } ?? false)
        }
    }

    /// Paper 18: the lead job on its own "Next up" card, then "Later today" as one card of rows.
    /// The Unscheduled queue has no lead: every job is a row with its Schedule button.
    @ViewBuilder private var dayContent: some View {
        let isToday = range == .today
        // Today hides finished visits from the open list; they sit under Done today.
        let open = isToday ? jobs.filter { $0.status != "completed" } : jobs
        if range == .unscheduled {
            section("Needs a time", jobs, leading: .age)
        } else if let first = leadJob, open.contains(where: { $0.id == first.id }) {
            let isActive = ScheduleLead.activeStatuses.contains(first.status)
            let place = stop.flatMap { $0.jobID == first.id ? $0 : nil }
            let driving = ["scheduled", "dispatched", "en_route"].contains(outbox.pendingStatus(for: first.id) ?? first.status)
            let rest = open.filter { $0.id != first.id }
            VStack(alignment: .leading, spacing: 0) {
                ScheduleHero(label: isActive ? "Now" : "Next up",
                             job: first, customer: store.customerName(first.customerId), pendingStatus: outbox.pendingStatus(for: first.id),
                             place: place, street: addresses.street(first),
                             etaMinutes: place != nil && driving ? eta.minutes : nil,
                             onSiteSince: onSiteSince(first),
                             locationNotice: place?.coordinates != nil && driving && !session.isOffline && eta.locationOff && !locationNoticeDismissed
                                ? { NextStopLocationNotice.dismissedThisLaunch = true
                                    withMotion(.easeOut(duration: 0.2)) { locationNoticeDismissed = true } } : nil)
                    .task(id: "\(first.id)|\(first.status)|\(first.updatedAt ?? "")") { await loadHero(first) }
                    .task(id: "stop|\(first.id)|\(first.customerId ?? "")|\(first.locationId ?? "")|\(session.generation)|\(session.isOffline)") {
                        await loadStop(first)
                    }
                    .task(id: "eta|\(place?.jobID ?? "")|\(place?.coordinates.map { "\($0.latitude),\($0.longitude)" } ?? "")|\(driving)") {
                        guard let place else { return }
                        await eta.update(to: place.coordinates, key: "\(place.jobID)|\(place.locationID ?? "")",
                                         enabled: driving && !session.isOffline)
                    }
                    .paperCardMargin()
                    .padding(.top, 16)
                if !rest.isEmpty { section("Later today", rest, leading: .time) }
                doneToday
            }
        } else {
            emptyState
            doneToday
        }
    }

    /// When the tech reached the lead job, from the server's own arrival (or start) time. Nil when the
    /// record has not loaded or carries neither, so the card never guesses a duration.
    private func onSiteSince(_ job: Job) -> Date? {
        guard let hero, hero.id == job.id, ["arrived", "in_progress", "paused"].contains(outbox.pendingStatus(for: job.id) ?? job.status)
        else { return nil }
        return JobFiltering.date(hero.arrivedAt) ?? JobFiltering.date(hero.startedAt)
    }

    /// A group (Paper 18): the 13 Semibold label with "4 jobs" at the trailing edge, 8 above one
    /// card of rows; 22 between groups. A Week day shows the bare count and one-line rows, and a
    /// day past tomorrow prints its label in ink (Paper 79).
    private func section(_ title: String, _ list: [Job], leading: ScheduleCompactRow.TimeStyle,
                         week: Bool = false, titleColor: Color = Theme.muted) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if week {
                PaperCardLabel(title: title, count: list.count, titleColor: titleColor)
            } else {
                PaperCardLabel(title: title, countText: "\(list.count) job\(list.count == 1 ? "" : "s")")
            }
            PaperRowsCard { jobRows(list, leading: leading, week: week) }
        }
        .padding(.top, 22)
    }

    /// Finished visits today as their own group under the open ones (Paper 20 "Done today").
    @ViewBuilder private var doneToday: some View {
        let done = todayVisits.filter { $0.status == "completed" }
            .sorted { (JobFiltering.date($0.scheduledFor) ?? .distantPast) < (JobFiltering.date($1.scheduledFor) ?? .distantPast) }
        if !done.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PaperCardLabel(title: "Done today", count: done.count)
                PaperRowsCard { jobRows(done, leading: .time) }
            }
            .padding(.top, 22)
            .accessibilityIdentifier("schedule-done-today")
        }
    }

    /// The rows of one card (Paper 18): the time column, the job, customer · street, the status
    /// circle trailing; an inset hairline between rows. The tech's initials show only where they
    /// tell something (on one tech's day they would repeat on every row).
    @ViewBuilder private func jobRows(_ list: [Job], leading: ScheduleCompactRow.TimeStyle, week: Bool = false) -> some View {
        // Who, only where it varies: on everyone's jobs with more than one tech in the group.
        let everyone = !(showsScope && scope == .mine) && Set(list.compactMap(\.assignedToUserId)).count > 1
        ForEach(Array(list.enumerated()), id: \.element.id) { index, job in
            let customer = store.customerName(job.customerId)
            if index > 0 { WellDivider(leading: week ? TodayRow.weekDividerInset : TodayRow.dividerInset) }
            // Swipe right: Call, Directions. Swipe left: the next move the server allows.
            JobSwipeRow(job: job, customer: customer, book: swipes, places: addresses) { actions in
                TodayRow(job: job, customer: customer, street: addresses.street(job),
                         timeStyle: leading, pendingStatus: outbox.pendingStatus(for: job.id),
                         assignee: everyone ? job.assignedToUserId.flatMap { roster[$0] } : nil,
                         week: week,
                         schedule: job.scheduledFor == nil && canSchedule ? { scheduling = job } : nil,
                         swipeActions: actions)
                    .background(Theme.card)
            }
        }
    }

    /// Today and the six days after it, as the Week range reads it.
    private var weekDays: [Date] {
        let calendar = Calendar.current
        guard let week = Self.rollingWeek() else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
    }

    /// Paper 79: the week as a strip of day tiles, then one group per day with its count.
    @ViewBuilder private var weekContent: some View {
        let calendar = Calendar.current
        let days = Dictionary(grouping: jobs) { calendar.startOfDay(for: JobFiltering.date($0.scheduledFor) ?? .now) }
        let sorted = days.keys.sorted()
        let counts = days.mapValues { $0.count }
        VStack(alignment: .leading, spacing: 0) {
            WeekDayStrip(days: weekDays, counts: counts) { weekJump = $0 }
                .paperCardMargin()
                .padding(.top, 14)
            ForEach(sorted, id: \.self) { day in
                let dayJobs = days[day] ?? []
                section(dayTitle(day), dayJobs, leading: .time, week: true,
                        titleColor: Calendar.current.isDateInToday(day) || Calendar.current.isDateInTomorrow(day) ? Theme.muted : Theme.foreground)
                    .id(day)
            }
        }
    }

    /// "Tue 21 · Today", "Wed 22 · Tomorrow", "Thu 23" (Paper 79).
    private func dayTitle(_ day: Date) -> String {
        let label = "\(day.formatted(.dateTime.weekday(.abbreviated))) \(day.formatted(.dateTime.day()))"
        if Calendar.current.isDateInToday(day) { return "\(label) · Today" }
        if Calendar.current.isDateInTomorrow(day) { return "\(label) · Tomorrow" }
        return label
    }

    /// Paper 19: an empty board says the workspace is ready and offers its first job; an empty day
    /// or week keeps saying what is missing and how to see more.
    @ViewBuilder private var emptyState: some View {
        let boardEmpty = store.jobs.isEmpty
        let mine = showsScope && scope == .mine
        let canCreate = session.can("job.create", feature: "jobs")
        if boardEmpty && range != .unscheduled {
            ScheduleEmptyState(title: "Nothing on the board yet", message: "Your workspace is live. New jobs will land here.",
                               actionTitle: canCreate ? "Create your first job" : nil) { showNew = true }
            // Paper 19: what is left of setup sits under the empty board.
            FinishSetupCard()
        } else {
            ScheduleEmptyState(
                // design.thorbis.com States: empty names the one action ("No jobs today. Create a job.").
                title: range == .unscheduled ? "Every job has a time" : "No jobs \(mine ? "for you " : "")\(range == .today ? (todayVisits.isEmpty ? "today" : "left today") : "this week")",
                message: range == .unscheduled ? nil
                    : mine ? "Remove My jobs from the search to see the whole team's jobs." : nil,
                actionTitle: range != .unscheduled && canCreate ? "Create a job" : nil
            ) { showNew = true }
        }
    }

    private func loadHero(_ job: Job) async {
        guard session.can("job.view", feature: "jobs") else { return }
        let generation = session.generation
        do {
            let record = try await api.fieldJob(job.id)
            guard session.generation == generation else { return }
            hero = record
            outbox.learn(record)
        } catch is CancellationError {} catch {
            // Without the server's transitions the band stays a link to the job.
            guard session.generation == generation else { return }
            hero = nil
        }
    }

    /// The lead job's own service location and a number to call. A failed read keeps the last
    /// copy for this job, so the card still shows the address without signal.
    private func loadStop(_ job: Job) async {
        guard session.can("customer.view", feature: "core_crm"),
              let organizationID = session.activeOrganization?.id, let customerID = job.customerId else {
            stop = nil
            return
        }
        let generation = session.generation
        let cached = JobDetailCache.stop(job.id).flatMap {
            $0.organizationID == organizationID && $0.customerID == customerID && $0.locationID == job.locationId ? $0 : nil
        }
        if stop?.jobID != job.id { stop = cached }
        var next = cached ?? NextStopPlace(jobID: job.id, organizationID: organizationID, customerID: customerID, locationID: job.locationId)
        var reached = false
        if let locationID = job.locationId, let places = try? await api.fieldLocations(customerID) {
            reached = true
            let place = places.first { $0.id == locationID && $0.customerId == customerID && $0.organizationId == organizationID }
            next.address = place?.address
            next.coordinates = place?.coordinates
        } else if job.locationId == nil {
            next.address = nil
            next.coordinates = nil
        }
        if let contacts = try? await api.fieldContacts(customerID) {
            reached = true
            let verified = contacts.filter { $0.organizationId == organizationID && $0.customerId == customerID }
            var account: CustomerRecord?
            if NextStopPlace.phone(contacts: verified, account: nil) == nil,
               let record = try? await api.fieldCustomer(customerID), record.organizationId == organizationID, record.id == customerID {
                account = record
            }
            next.phone = NextStopPlace.phone(contacts: verified, account: account)
        }
        guard session.generation == generation, !Task.isCancelled else { return }
        stop = next
        if reached { JobDetailCache.save(stop: next) }
    }

}

/// The Next up card (Paper 18): "Next up · 10:30 AM" in brand text with the drive at the trailing
/// edge ("24 min away"), the job in 22 Bold, "customer · street" in 15, then one row of actions:
/// the blue Navigate pill and the round call and message buttons. The whole card opens the job,
/// where its next step lives (Paper's map: tapping today's job opens Field mode). Under way the
/// label says so ("Now · In progress") and the trailing edge counts the time on site.
private struct ScheduleHero: View {
    let label: String
    let job: Job
    let customer: String
    var pendingStatus: String? = nil
    var place: NextStopPlace? = nil
    /// The job's street from the list's address book, when the stop itself is not loaded.
    var street: String? = nil
    var etaMinutes: Int? = nil
    /// The server's arrival time while on site: the card says "On site 42 min".
    var onSiteSince: Date? = nil
    /// Set when Location is off and the drive time is missing because of it: shows the quiet
    /// "Turn on location" line, and is called when the person dismisses it.
    var locationNotice: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openURL) private var openURL
    @Environment(\.inboxText) private var inboxText

    private var status: String { pendingStatus ?? job.status }
    private var underWay: Bool { ScheduleLead.activeStatuses.contains(status) }
    private var where_: String? { place?.firstLine ?? street }
    /// "Danielle Marlowe · 412 Birchwood Ln".
    private var supporting: String { [customer, where_ ?? ""].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ") }

    /// "Next up · 10:30 AM"; under way "Now · In progress"; a step still on this phone says so.
    private var labelLine: String {
        if pendingStatus != nil { return "\(label) \u{00B7} \(status.statusLabel) \u{00B7} waiting to sync" }
        if underWay { return "\(label) \u{00B7} \(status.statusLabel)" }
        guard let date = JobFiltering.date(job.scheduledFor) else { return label }
        return "\(label) \u{00B7} \(Calendar.current.isDateInToday(date) ? date.clockTime : date.visitLabel())"
    }

    /// "24 min away" while there is a drive time; "On site 42 min" once arrived.
    private func trailing(now: Date) -> String? {
        if let onSiteSince { return JobOnSiteClock.line(arrived: onSiteSince, now: now) }
        if let etaMinutes { return "\(etaMinutes) min away" }
        return nil
    }

    private var text: URL? { JobReach(phone: place?.phone, email: nil).text }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let stacked = typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 16) {
            NavigationLink(value: job) {
                VStack(alignment: .leading, spacing: 6) {
                    TimelineView(.everyMinute) { context in
                        let line = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                           : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
                        line {
                            Text(labelLine).font(Theme.font(13, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(Theme.brandText)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: stacked ? nil : .infinity, alignment: .leading)
                            if let trailing = trailing(now: context.date) {
                                Text(trailing).font(Theme.font(13, weight: .medium)).monospacedDigit()
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(stacked ? nil : 1)
                                    .accessibilityIdentifier(etaMinutes != nil ? "next-stop-eta" : "next-stop-time")
                            }
                        }
                    }
                    Text(job.title.dashKeptWithWordBefore).font(Theme.font(22, weight: .bold)).tracking(-0.44)
                        .foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !supporting.isEmpty {
                        Text(supporting).font(Theme.font(15)).foregroundStyle(Theme.subtle)
                            .multilineTextAlignment(.leading)
                            .lineLimit(stacked ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .jobContextMenu(job, customer: customer)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint("Opens the job")
            .accessibilityIdentifier("next-stop-card")
            // Outside the link, so Open Settings and dismiss never open the job.
            if let locationNotice {
                NextStopLocationNotice(dismiss: locationNotice)
            }
            if place?.directions != nil || place?.call != nil || text != nil {
                // One row: Navigate, then call and message. At accessibility sizes Navigate takes
                // its own line so the word never squeezes.
                let actions = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                      : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
                actions {
                    if let directions = place?.directions {
                        Button { openURL(directions) } label: { PaperPillLabel(title: "Navigate", glyph: .navigate) }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel("Navigate")
                            .accessibilityHint("Opens driving directions in Maps")
                            .accessibilityIdentifier("next-stop-directions")
                    }
                    HStack(spacing: 8) {
                        if let call = place?.call {
                            PaperRoundButton(glyph: .phone, label: "Call \(customer)") { openURL(call) }
                                .accessibilityIdentifier("next-stop-call")
                        }
                        if let text {
                            PaperRoundButton(glyph: .message, label: "Message \(customer)") {
                                inboxText(text, name: customer, openURL: openURL)
                            }
                            .accessibilityIdentifier("next-stop-text")
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: shape)
        .clipShape(shape)
    }

    private var accessibilitySummary: String {
        var parts = [labelLine, job.title, customer]
        if let where_ { parts.append(where_) }
        if let trailing = trailing(now: .now) { parts.append(trailing) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// A list's time column (design.thorbis.com "Time is 7:40. Tabular."): "a.m." / "p.m." shows on
/// the first timed row and wherever the period changes, so the column reads 10:30, 12:15, 1:00.
enum TimeColumn {
    static func showsPeriod(_ jobs: [Job], at index: Int) -> Bool {
        let period = JobFiltering.date(jobs[index].scheduledFor)?.periodMark
        guard let previous = jobs[..<index].last(where: { $0.scheduledFor != nil }) else { return true }
        return JobFiltering.date(previous.scheduledFor)?.periodMark != period
    }
}

extension Date {
    /// The Today column's clock (design.thorbis.com "Time is 7:40"): hours and minutes always, so
    /// 7:40 and 11:15 share a tabular column. The period sits apart (`periodMark`).
    var columnTime: String {
        let uses24 = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") == false
        let parts = Calendar.current.dateComponents([.hour, .minute], from: self)
        let hour24 = parts.hour ?? 0, minute = parts.minute ?? 0
        if uses24 { return String(format: "%02d:%02d", hour24, minute) }
        return String(format: "%d:%02d", hour24 % 12 == 0 ? 12 : hour24 % 12, minute)
    }
    /// "1:00 PM" (Paper: "10:30 AM", "12:15 PM"): the column's clock with its period, for a time
    /// shown on its own (the Next up card, board cards, the map card).
    var clockTime: String { [columnTime, periodMark].compactMap { $0 }.joined(separator: " ") }
    /// "AM" / "PM" as Paper prints them, or nil on a 24-hour clock.
    var periodMark: String? {
        let uses24 = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") == false
        guard !uses24 else { return nil }
        return Calendar.current.component(.hour, from: self) < 12 ? "AM" : "PM"
    }
}

/// A Today row (Paper 18): the time in a 68pt column (14 Medium, the body grey), the job in 16
/// Medium over customer · street (in the warning hue with its word while under way), and the
/// status circle trailing. Rows sit in one card with an inset hairline between them (the caller
/// draws it). Rows without a time offer Schedule in the circle's place, beside the link.
/// VoiceOver reads one item: street, problem, customer, full time, status.
struct TodayRow: View {
    let job: Job
    let customer: String
    var street: String? = nil
    var timeStyle: ScheduleCompactRow.TimeStyle = .time
    var pendingStatus: String? = nil
    /// The assigned tech's name from the roster; nil shows no initials (one tech's own day).
    var assignee: String? = nil
    /// Kept for call sites; Paper 18 prints the period on every row ("12:15 p.m.").
    var showsPeriod = true
    /// Paper 79's Week row: a 78pt time column and one line, "AC not cooling — Marlowe". The
    /// second line and the status circle show only while the visit is under way or waiting to sync.
    var week = false
    var schedule: (() -> Void)? = nil
    /// The row's swipe actions, also offered to VoiceOver as custom actions on the row.
    var swipeActions: [RowSwipeAction] = []
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var column: CGFloat = 68
    @ScaledMetric(relativeTo: .subheadline) private var weekColumn: CGFloat = 78

    /// Where the hairline between two rows starts: past the card's inset and the time column.
    static let dividerInset: CGFloat = 16 + 68
    static let weekDividerInset: CGFloat = 16 + 78

    private var status: String { pendingStatus ?? job.status }
    private var dimmed: Bool { job.status == "completed" }
    private var underWay: Bool { ScheduleLead.activeStatuses.contains(status) }
    /// A Week row says more than its one line only when there is something to say.
    private var quiet: Bool { week && !underWay && pendingStatus == nil && !dimmed }
    private var titleLine: String { week ? "\(job.title) \u{2014} \(customer)" : job.title }
    private var tone: StatusTone { StatusTone(jobStatus: status, hasTime: job.scheduledFor != nil) }

    private var time: (text: String, spoken: String) {
        if timeStyle == .age, let created = JobFiltering.date(job.createdAt) {
            return (ScheduleCompactRow.age(since: created), "Waiting since \(created.formatted(date: .abbreviated, time: .omitted))")
        }
        if let date = JobFiltering.date(job.scheduledFor) { return (date.clockTime, date.tradeTime) }
        return ("—", "No time")
    }

    /// "Petrov · 88 Larch Ave"; under way "In progress · 245 Rosemont Dr"; waiting to sync says so.
    private var detail: String {
        var parts: [String] = []
        if pendingStatus != nil {
            parts.append("\(status.statusLabel) · waiting to sync")
            if street == nil { parts.append(customer) }
        } else if underWay {
            parts.append(status.statusLabel)
            if street == nil { parts.append(customer) }
        } else {
            parts.append(customer)
        }
        if let street { parts.append(street) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            NavigationLink(value: job) { content }
                .buttonStyle(RowPressStyle())
                .jobContextMenu(job, customer: customer)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
                .accessibilityHint("Opens the job")
                .accessibilityIdentifier("today-row-\(job.id)")
                .rowSwipeAccessibility(swipeActions)
            if let schedule {
                ScheduleRowButton(job: job, action: schedule).padding(.trailing, 12)
            }
        }
    }

    private var content: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                             : AnyLayout(HStackLayout(alignment: .center, spacing: 0))
        return layout {
            Text(time.text).font(Theme.font(14, weight: .medium))
                .foregroundStyle(dimmed ? Theme.muted : Theme.subtle)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: stacked ? nil : (week ? weekColumn : column), alignment: .leading)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    // Beside the Schedule button the row is narrow, so the title may take a third line.
                    Text(titleLine.dashKeptWithWordBefore).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                        .foregroundStyle(dimmed ? Theme.subtle : Theme.foreground)
                        .lineLimit(stacked ? nil : (schedule == nil ? 2 : 3))
                        .fixedSize(horizontal: false, vertical: true)
                    if !detail.isEmpty && !quiet {
                        Text(detail).font(Theme.font(14))
                            .foregroundStyle(underWay && pendingStatus == nil ? Theme.warning : Theme.muted)
                            .lineLimit(stacked ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let assignee { PaperInitials(name: assignee, size: 24) }
                if schedule == nil && !quiet {
                    StatusGlyph(tone: tone, label: status.statusLabel, pending: pendingStatus != nil, size: 18)
                }
            }
            .padding(.vertical, 11)
        }
        .padding(.leading, 16).padding(.trailing, schedule == nil ? 16 : 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var spoken: String {
        var parts = [street ?? job.title]
        if street != nil { parts.append(job.title) }
        parts.append(customer)
        parts.append(time.spoken)
        parts.append(status.statusLabel + (pendingStatus != nil ? ", waiting to sync" : ""))
        if let assignee { parts.append("Assigned to \(assignee)") }
        return parts.joined(separator: ", ")
    }
}
/// A Schedule row: the time column, the street (or the job's title), the problem and who, and
/// the status as a word. Rows without a time offer Schedule beside the link instead.
struct ScheduleCompactRow: View {
    /// `.age` is for jobs without a time: the column shows how long the job has been waiting.
    enum TimeStyle { case time, age }
    let job: Job
    let customer: String
    var street: String? = nil
    var timeStyle: TimeStyle = .time
    var pendingStatus: String? = nil
    /// Show "a.m." / "p.m." beside the time (the first row, and wherever the period changes).
    var showsPeriod = true
    /// Set on a row with no time for someone who may schedule: a trailing Schedule button.
    var schedule: (() -> Void)? = nil
    @Environment(\.paperRowInset) private var inset

    private var leading: PaperRowLeading {
        if timeStyle == .age, let created = JobFiltering.date(job.createdAt) {
            return .text(Self.age(since: created), accessibility: "Waiting since \(created.formatted(date: .abbreviated, time: .omitted))")
        }
        if let date = JobFiltering.date(job.scheduledFor) {
            return .clock(date.columnTime, period: showsPeriod ? date.periodMark : nil, accessibility: date.clockTime)
        }
        return .text("No time")
    }

    /// "Today", "2d", "3w": short enough for the leading column.
    nonisolated static func age(since date: Date, now: Date = .now) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date),
                                                   to: Calendar.current.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "Today"
        case 1..<14: return "\(days)d"
        case 14..<120: return "\(days / 7)w"
        default: return "\(days / 30)mo"
        }
    }

    var body: some View {
        // The Schedule button sits beside the row's link, not inside it, so each is its own target.
        HStack(alignment: .center, spacing: 0) {
            NavigationLink(value: job) {
                PaperListRow(leading: leading, title: (street ?? job.title).dashKeptWithWordBefore,
                             subtitle: street != nil ? "\(job.title) · \(customer)".dashKeptWithWordBefore : customer,
                             subtitleLines: 2, titleLines: schedule == nil ? 2 : 3, dimmed: job.status == "completed") {
                    if schedule == nil {
                        StatusWord(jobStatus: pendingStatus ?? job.status, pending: pendingStatus != nil)
                    }
                }
            }
            .buttonStyle(RowPressStyle())
            .jobContextMenu(job, customer: customer)
            if let schedule {
                ScheduleRowButton(job: job, action: schedule).padding(.trailing, inset)
            }
        }
    }
}


/// The Jobs tab's sections (redesign phase 2), in the order a dispatcher reads the board: under
/// way, booked with a time, still needing a time, finished, then anything else (cancelled), so no
/// job disappears. Empty sections are kept here and skipped by the view.
enum JobsListGroups {
    static func groups(_ jobs: [Job]) -> [(title: String, jobs: [Job])] {
        let booked = PaperWorkGroups.scheduled(jobs)
        let draft: Set<String> = ["draft", "unscheduled"]
        let other = PaperWorkGroups.other(jobs).filter { !draft.contains($0.status) }
        return [("In progress", PaperWorkGroups.inProgress(jobs)),
                ("Scheduled", booked.filter { $0.scheduledFor != nil }),
                ("Unscheduled", booked.filter { $0.scheduledFor == nil } + jobs.filter { draft.contains($0.status) }),
                ("Done", PaperWorkGroups.completed(jobs)),
                (other.allSatisfy { $0.status == "canceled" } ? "Cancelled" : "Other", other)]
    }
}

/// Paper 20: every job, grouped by where it stands.
struct JobsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @State private var tab = "Assigned"
    @State private var showDisplay = false
    @State private var scheduling: Job?
    @State private var display = DisplayOptions()
    /// Empty means every status; otherwise only the ticked ones.
    @State private var statusFilter: Set<String> = []
    @State private var showNew = false
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Street lines for the rows (street first), read per customer like Today.
    @StateObject private var addresses = JobAddressBook()
    /// The rows' swipes: what each row has read (allowed moves, a number to call) and the moves sent.
    @StateObject private var swipes = JobRowSwipeBook()
    /// Who each tech is, for the rows' avatars. Never kept on the phone: offline the rows show none.
    @State private var roster: [String: String] = [:]

    /// Paper 20A "Assigned to", past Me: anyone, no one yet, or one tech. Applies off the Assigned tab.
    @State private var who: JobBoardFilter.Who = .anyone
    /// Paper 20A "Date": by the visit's booked time.
    @State private var when: JobBoardFilter.When = .any
    /// Paper 20A "Pick dates": a range of booked days, chosen in the sheet.
    @State private var pickedDates = false
    @State private var dateFrom = Calendar.current.startOfDay(for: .now)
    @State private var dateTo = Calendar.current.startOfDay(for: .now)
    private var activeDates: (from: Date, to: Date)? { pickedDates ? (from: dateFrom, to: dateTo) : nil }

    /// Paper 20B / 20C: the person's saved views for jobs, from the server.
    @StateObject private var savedViews = JobSavedViewsBook()
    @State private var showSaveView = false
    @State private var showSavedViews = false
    /// "View saved as …", shown for a moment after a save.
    @State private var savedViewToast: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whose jobs the board shows: the Assigned tab is always mine.
    private var activeWho: JobBoardFilter.Who { tab == "Assigned" ? .anyone : who }
    /// A filter is on when the sheet narrows the board past its defaults.
    private var filterActive: Bool {
        !statusFilter.isEmpty || !display.showCompleted || display.ordering != .recent || when != .any
            || pickedDates || activeWho != .anyone
    }

    private var jobs: [Job] {
        let assigned = tab == "Assigned" ? (session.user?.id ?? "") : nil
        // Finding a job by name or number is the bar's Search; the board narrows with Filters.
        let board = JobFiltering.board(store.jobs, assignedTo: assigned, search: "",
                                       showCompleted: display.showCompleted, statuses: statusFilter,
                                       ordering: display.ordering)
        return JobBoardFilter.apply(board, who: activeWho, when: when, dates: activeDates)
    }
    /// The tech picked in the sheet, by name; nil when none is picked or the roster has not loaded.
    private var pickedTechName: String? {
        guard case .tech(let userID) = who else { return nil }
        return roster[userID] ?? "One tech"
    }
    private var activeCount: Int { jobs.filter { !["completed", "canceled"].contains($0.status) }.count }
    /// Paused, or booked and past its time: the jobs someone has to look at.
    private var attentionCount: Int { jobs.filter { $0.status == "paused" || isLate($0) }.count }
    /// Paper 20: "18 active · 6 need attention".
    private var subtitle: String {
        attentionCount > 0 ? "\(activeCount) active · \(attentionCount) need\(attentionCount == 1 ? "s" : "") attention" : "\(activeCount) active"
    }
    private var canSchedule: Bool { session.can("job.assign", feature: "jobs") }
    /// What the Filters sheet is doing to the board, as chips in the search field (Paper 20), so a
    /// narrowed list never looks empty by accident; × takes each one off.
    private var filterChips: [PaperFilterChip] {
        var chips: [PaperFilterChip] = []
        // Paper 20: the Assigned tab reads "My jobs" in the field; × shows everyone's.
        if tab == "Assigned" {
            chips.append(PaperFilterChip(id: "mine", title: "My jobs") { withMotion { tab = "All jobs" } })
        } else if who == .unassigned {
            chips.append(PaperFilterChip(id: "who", title: "Unassigned") { withMotion { who = .anyone } })
        } else if let pickedTechName {
            chips.append(PaperFilterChip(id: "who", title: pickedTechName) { withMotion { who = .anyone } })
        }
        let ticked = JobBoardFilter.groups(in: statusFilter)
        if ticked.count == 1, let only = ticked.first {
            chips.append(PaperFilterChip(id: "status", title: only.title) { withMotion { statusFilter = [] } })
        } else if ticked.count > 1 {
            chips.append(PaperFilterChip(id: "status", title: "\(ticked.count) statuses") { withMotion { statusFilter = [] } })
        }
        if pickedDates {
            chips.append(PaperFilterChip(id: "when", title: JobBoardFilter.datesLabel(from: dateFrom, to: dateTo)) {
                withMotion { pickedDates = false }
            })
        } else if when != .any {
            chips.append(PaperFilterChip(id: "when", title: when.label) { withMotion { when = .any } })
        }
        if !display.showCompleted {
            chips.append(PaperFilterChip(id: "completed", title: "Hiding done") { withMotion { display.showCompleted = true } })
        }
        if display.ordering != .recent {
            chips.append(PaperFilterChip(id: "ordering", title: "By \(JobBoardFilter.sortLabel(display.ordering).lowercased())") {
                withMotion { display.ordering = .recent }
            })
        }
        return chips
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Paper 20: the title, the search field holding the active filters as chips and the
                // filter circle, then Assigned / All jobs / Recent segments.
                PaperHeader(title: "Jobs", subtitle: subtitle, showsCreate: true)
                PaperSearchBar(placeholder: "Search", chips: filterChips) {
                    Button { ThorbisKeyboard.dismiss { showDisplay = true } } label: {
                        PaperFilterCircle(active: filterActive)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Filter jobs")
                    .accessibilityValue(filterActive ? "Filtered" : "")
                    .accessibilityIdentifier("header-filter")
                }
                .paperCardMargin()
                // Paper 20B: saved views as chips under the field, then "Save this view".
                // Paper shows one or the other: the view chips (leading with "My jobs", then All jobs
                // and Recent so both stay a tap away) or, with no saved views, the segments.
                if canUseViews && (!viewEntries.isEmpty || canSaveView) {
                    JobSavedViewChips(entries: viewEntries, favorites: savedViews.favorites,
                                      selectedID: selectedViewID, showsSave: canSaveView,
                                      onPick: { pick($0) }, onSave: { showSaveView = true },
                                      onManage: { showSavedViews = true },
                                      builtIn: [(id: "Assigned", title: "My jobs"), (id: "All jobs", title: "All jobs"),
                                                (id: "Recent", title: "Recent")],
                                      selectedBuiltIn: tab,
                                      onBuiltIn: { choice in withMotion { tab = choice } })
                        .padding(.top, 16)
                } else {
                    PaperTabs(options: ["Assigned", "All jobs", "Recent"], selection: $tab)
                        .padding(.top, 16)
                }
                OfflineBanner()
                if let error = store.error { ErrorBanner(message: error) { _ = await store.refresh(api) } }
                if let problem = swipes.problem { ErrorBanner(message: problem) }
                if canUseViews, !session.isOffline, let problem = savedViews.problem {
                    ErrorBanner(message: problem, action: .init(title: "Try again") { await loadSavedViews() })
                }
                LazyVStack(alignment: .leading, spacing: 0) {
                    if store.loading && store.jobs.isEmpty {
                        ListRoomSkeleton(count: 6)
                    } else if tab == "Recent" {
                        group("Recently updated", jobs: Array(jobs.prefix(25)))
                    } else {
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                            self.group(group.title, jobs: group.jobs)
                        }
                    }
                    if MyDayRules.shouldShowEmptyState(isEmpty: jobs.isEmpty, isLoading: store.loading, hasError: store.error != nil) {
                        let canCreate = session.can("job.create", feature: "jobs")
                        ListRoomEmpty(
                            title: filterActive ? "No jobs match these filters." : store.jobs.isEmpty ? "No open jobs."
                                : tab == "Assigned" ? "No jobs assigned to you." : "No open jobs.",
                            message: filterActive ? "Clear the filters to see the whole board."
                                : tab == "Assigned" && !store.jobs.isEmpty ? "All jobs shows the whole board." : nil,
                            actionTitle: canCreate && !filterActive ? "Create a job" : nil,
                            action: { showNew = true }
                        )
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { await store.refresh(api) }
        // An open row closes as soon as the list moves.
        .onScrollPhaseChange { _, phase in if phase != .idle { swipes.rows.close() } }
        // A swiped move: success once the server took it; a lighter tap when it is only saved here.
        .sensoryFeedback(.success, trigger: swipes.confirmed)
        .sensoryFeedback(.impact(weight: .light), trigger: swipes.queued)
        .task(id: "swipes|\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)") {
            swipes.reset(identity: "\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)")
        }
        .background(Theme.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if session.can("job.create", feature: "jobs") && !jobs.isEmpty {
                FloatingCreateButton(title: "New job") { showNew = true }
            }
        }
        .sheet(isPresented: $showNew) { SheetSurface { NewJobSheet() } }
        .sheet(item: $scheduling) { value in SheetSurface { QuickScheduleSheet(jobID: value.id) } }
        // Paper 20A: the filters are a sheet from the bottom, with the count it will show as its commit.
        .sheet(isPresented: $showDisplay) {
            SheetSurface { filterSheet }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // Paper 20C: name the filters on screen and keep them as a view.
        .sheet(isPresented: $showSaveView) {
            SheetSurface {
                JobSavedViewSaveSheet(book: savedViews, choices: currentChoices, roster: roster) { view in
                    withMotion { savedViewToast = "View saved as \u{201C}\(view.label)\u{201D}" }
                }
            }
        }
        .sheet(isPresented: $showSavedViews) {
            SheetSurface {
                JobSavedViewsSheet(book: savedViews, entries: viewEntries, roster: roster, canSaveCurrent: canSaveView,
                                   onApply: { if let choices = $0.choices { apply(choices) } },
                                   onSaveCurrent: { showSaveView = true })
            }
        }
        // Paper 20B: "View saved as …" rises over the list and leaves on its own.
        .overlay(alignment: .bottom) {
            if let savedViewToast {
                ThorbisToast(symbol: "checkmark", message: savedViewToast)
                    .padding(.horizontal, Theme.gutter).padding(.bottom, 84)
                    .transition(ThorbisToast.transition(reduceMotion: reduceMotion))
                    .accessibilityIdentifier("jobviews-toast")
                    .task(id: savedViewToast) {
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled else { return }
                        withMotion { self.savedViewToast = nil }
                    }
            }
        }
        .task(id: "views|\(JobSavedViewsBook.identity(session))|\(session.isOffline)|\(canUseViews)") { await loadSavedViews() }
        .task(id: "roster|\(session.generation)|\(session.isOffline)") {
            guard session.can("job.view", feature: "jobs"), !session.isOffline,
                  let people = try? await api.fieldAssignees() else { return }
            roster = Dictionary(people.map { ($0.userId, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        }
        .task(id: "addr|\(jobs.map { "\($0.id):\($0.locationId ?? "")" }.joined(separator: ","))|\(session.generation)|\(session.isOffline)") {
            guard session.can("customer.view", feature: "core_crm") else { return }
            await addresses.load(jobs, api: api, organizationID: session.activeOrganization?.id,
                                 identity: "\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)")
        }
        #if DEBUG
        .onAppear {
            if PaperPreview.enabled && PaperPreview.screen == "jobs-filters" {
                Task { try? await Task.sleep(for: .seconds(1.5)); showDisplay = true }
            }
        }
        #endif
    }

    private var groups: [(title: String, jobs: [Job])] { JobsListGroups.groups(jobs) }

    // MARK: Saved views (Paper 20B / 20C)

    /// A view is a list of jobs, so it needs the right to see jobs (the server's `jobs` resource).
    private var canUseViews: Bool { session.can("job.view", feature: "jobs") }

    /// The filters on screen as one value: whose jobs (the Assigned tab is mine), then the sheet's.
    private var currentChoices: JobBoardChoices {
        var choices = JobBoardChoices()
        if tab == "Assigned" {
            if let me = session.user?.id { choices.assignee = .user(me) }
        } else {
            switch who {
            case .anyone: choices.assignee = .anyone
            case .unassigned: choices.assignee = .unassigned
            case .tech(let userID): choices.assignee = .user(userID)
            }
        }
        choices.statuses = statusFilter
        choices.hidesDone = !display.showCompleted
        choices.ordering = display.ordering
        choices.days = pickedDates ? JobBoardChoices.Days(from: dateFrom, to: dateTo) : nil
        choices.when = pickedDates ? .any : when
        return choices
    }

    /// Each saved view with how it reads on this phone, favourites first.
    private var viewEntries: [JobSavedViewEntry] {
        savedViews.ordered.map { JobSavedViewEntry(view: $0, reading: JobSavedViewMapping.read($0)) }
    }

    /// The view whose filters are the ones on screen, if any.
    private var selectedViewID: String? {
        let current = currentChoices.canonical
        return viewEntries.first { $0.choices?.canonical == current }?.id
    }

    /// "Save this view" shows once the sheet narrows the board and no view holds these filters yet.
    private var canSaveView: Bool {
        canUseViews && !session.isOffline && savedViews.loaded && filterActive && selectedViewID == nil
    }

    private func loadSavedViews() async {
        guard canUseViews, !session.isOffline else { return }
        await savedViews.load(api: api, identity: JobSavedViewsBook.identity(session))
    }

    /// A chip: show the view, or clear it when it is the one showing. A view this phone cannot
    /// filter by opens the list of views, where its row says why; it is never applied.
    private func pick(_ entry: JobSavedViewEntry) {
        guard let choices = entry.choices else { showSavedViews = true; return }
        if entry.id == selectedViewID {
            withMotion { resetFilters() }
        } else {
            apply(choices)
        }
    }

    /// Puts a view's filters on the board.
    private func apply(_ choices: JobBoardChoices) {
        withMotion {
            switch choices.assignee {
            case .user(let id) where id == session.user?.id: tab = "Assigned"; who = .anyone
            case .user(let id): tab = "All jobs"; who = .tech(id)
            case .unassigned: tab = "All jobs"; who = .unassigned
            case .anyone: tab = "All jobs"; who = .anyone
            }
            // The sheet's chips stand for groups that can hold a status the server does not have
            // ("on_hold" beside "paused"); tick the whole group when the view names all of its own.
            var statuses = choices.statuses
            for group in JobBoardFilter.statusGroups {
                let known = group.statuses.intersection(JobSavedViewMapping.serverStatuses)
                if !known.isEmpty && known.isSubset(of: statuses) { statuses.formUnion(group.statuses) }
            }
            statusFilter = statuses
            display.showCompleted = !choices.hidesDone
            display.ordering = choices.ordering
            when = .any
            if let days = choices.days {
                dateFrom = days.from
                dateTo = days.to
                pickedDates = true
            } else {
                pickedDates = false
            }
        }
    }

    /// Paper 20A: Assigned to, Status, Date and Sort by, as chips on the sheet; Reset clears them
    /// and the commit shows the narrowed board. Job type is left out: a job carries no type.
    private var filterSheet: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text("Filters").font(Theme.font(22, weight: .bold)).tracking(-0.44).foregroundStyle(Theme.foreground)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                        Button { withMotion { resetFilters() } } label: {
                            Text("Reset").font(Theme.font(15, weight: .semibold))
                                .foregroundStyle(Theme.brandText.opacity(filterActive ? 1 : 0.4))
                                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .disabled(!filterActive)
                        .accessibilityLabel("Reset filters")
                        .accessibilityIdentifier("jobs-filter-reset")
                    }
                    .frame(minHeight: 44)
                    filterLabel("Assigned to", first: true)
                    FlowRow(spacing: 8, lineSpacing: 8) {
                        PaperChoiceChip(title: "Me", isOn: tab == "Assigned") { tab = "Assigned"; who = .anyone }
                        PaperChoiceChip(title: "Anyone", isOn: tab != "Assigned" && who == .anyone) { showEveryone(.anyone) }
                        PaperChoiceChip(title: "Unassigned", isOn: tab != "Assigned" && who == .unassigned) { showEveryone(.unassigned) }
                        if !techItems.isEmpty {
                            ThorbisMenu(items: techItems, title: "Pick a tech", accessibilityLabel: "Pick a tech") {
                                PaperChoiceChipLabel(title: activeTechName ?? "Pick a tech", isOn: activeTechName != nil)
                            }
                            .accessibilityValue(activeTechName ?? "")
                        }
                    }
                    filterLabel("Status")
                    FlowRow(spacing: 8, lineSpacing: 8) {
                        ForEach(JobBoardFilter.statusGroups) { group in
                            let on = group.statuses.isSubset(of: statusFilter)
                            PaperChoiceChip(title: group.title, isOn: on) {
                                if on { statusFilter.subtract(group.statuses) } else { statusFilter.formUnion(group.statuses) }
                            }
                        }
                    }
                    filterLabel("Date")
                    FlowRow(spacing: 8, lineSpacing: 8) {
                        ForEach([JobBoardFilter.When.today, .week, .overdue], id: \.self) { option in
                            PaperChoiceChip(title: option.label, isOn: !pickedDates && when == option) {
                                when = !pickedDates && when == option ? .any : option
                                pickedDates = false
                            }
                        }
                        // Paper 20A: "Pick dates" opens a from/to range under the chips.
                        PaperChoiceChip(title: "Pick dates", isOn: pickedDates) {
                            withMotion { pickedDates.toggle() }
                            if pickedDates { when = .any }
                        }
                        .accessibilityIdentifier("jobs-filter-pick-dates")
                    }
                    if pickedDates {
                        VStack(spacing: 0) {
                            DatePicker("From", selection: $dateFrom, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .padding(.horizontal, 16).frame(minHeight: 56)
                                .accessibilityIdentifier("jobs-filter-date-from")
                            WellDivider(leading: 16)
                            DatePicker("To", selection: $dateTo, in: dateFrom..., displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .padding(.horizontal, 16).frame(minHeight: 56)
                                .accessibilityIdentifier("jobs-filter-date-to")
                        }
                        .font(Theme.font(16)).foregroundStyle(Theme.foreground).tint(Theme.brand)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 10)
                        .onChange(of: dateFrom) { _, start in if dateTo < start { dateTo = start } }
                    }
                    filterLabel("Sort by")
                    PaperSheetSegments(options: JobBoardFilter.sortOrder.map { JobBoardFilter.sortLabel($0) },
                                 selection: Binding(get: { JobBoardFilter.sortLabel(display.ordering) },
                                                    set: { label in
                                                        if let ordering = JobBoardFilter.sortOrder.first(where: { JobBoardFilter.sortLabel($0) == label }) {
                                                            display.ordering = ordering
                                                        }
                                                    }))
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 14).padding(.bottom, 20)
            }
            Button { showDisplay = false } label: {
                Text("Show \(jobs.count) job\(jobs.count == 1 ? "" : "s")").inkCommit()
            }
            .buttonStyle(PressStyle())
            .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 12)
            .accessibilityIdentifier("jobs-filter-show")
        }
    }

    /// The picked tech's name while that choice applies (off the Assigned tab).
    private var activeTechName: String? { tab == "Assigned" ? nil : pickedTechName }

    /// The roster as menu rows, by name; empty until it loads (and offline).
    private var techItems: [ThorbisMenuItem] {
        roster.sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }.map { entry in
            ThorbisMenuItem(entry.value, icon: "person", isSelected: activeWho == .tech(entry.key)) {
                showEveryone(.tech(entry.key))
            }
        }
    }

    /// A choice past Me: leave the Assigned tab, then narrow to it.
    private func showEveryone(_ choice: JobBoardFilter.Who) {
        if tab == "Assigned" { tab = "All jobs" }
        who = choice
    }

    private func resetFilters() {
        statusFilter = []
        display = DisplayOptions()
        who = .anyone
        when = .any
        pickedDates = false
    }

    /// Paper 20A: a group's 13 Semibold label, 16 under the group before it and 8 above its chips.
    private func filterLabel(_ title: String, first: Bool = false) -> some View {
        Text(title).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, first ? 10 : 16).padding(.bottom, 8)
    }

    /// "Today, 2:30 p.m.", "No time yet", or nil once the work is finished.
    private func whenLabel(_ job: Job) -> String? {
        guard !["completed", "canceled"].contains(job.status) else { return nil }
        return JobFiltering.date(job.scheduledFor).map { $0.visitLabel() } ?? "No time yet"
    }

    /// A booked visit whose time has passed.
    private func isLate(_ job: Job) -> Bool {
        guard ["scheduled", "dispatched"].contains(job.status), let date = JobFiltering.date(job.scheduledFor) else { return false }
        return date < .now
    }

    /// Paper 20: a group is its 13 Semibold label with the count trailing, 8 above one card of rows,
    /// an inset hairline between rows and 20 between groups. New job is the header's +, or the
    /// floating pill on iPad.
    @ViewBuilder private func group(_ title: String, jobs: [Job]) -> some View {
        if !jobs.isEmpty {
            PaperCardLabel(title: title, count: jobs.count)
                .padding(.top, 20)
            // Row by row in the lazy stack: one card of every job built at once stalls a long list.
            ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                VStack(alignment: .leading, spacing: 0) {
                    if index > 0 { WellDivider(leading: JobCardRow.dividerInset) }
                    jobRow(job)
                }
                .paperRowsCardSlice(first: index == 0, last: index == jobs.count - 1)
            }
        }
    }

    private func jobRow(_ job: Job) -> some View {
        let customer = store.customerName(job.customerId)
        let needsTime = canSchedule && job.scheduledFor == nil && !["completed", "canceled"].contains(job.status)
            && !ScheduleLead.activeStatuses.contains(job.status)
        // The tech by name from the roster, as initials at the trailing edge (Paper 20).
        let assignee = job.assignedToUserId.flatMap { roster[$0] }
        // Under way: the job number; booked: when; finished: the job number.
        let detail = ScheduleLead.activeStatuses.contains(job.status) ? job.shortRef : whenLabel(job) ?? job.shortRef
        // Swipe right: Call, Directions. Swipe left: the next move the server allows.
        return JobSwipeRow(job: job, customer: customer, book: swipes, places: addresses) { actions in
            HStack(spacing: 0) {
                // iPad selects into the detail column beside the list; iPhone pushes.
                PaperSplitLink(id: job.id, value: job) {
                    JobCardRow(job: job, customer: customer, detail: detail,
                               pendingStatus: outbox.pendingStatus(for: job.id), late: isLate(job),
                               assignee: needsTime ? nil : assignee)
                }
                .buttonStyle(RowPressStyle())
                .jobContextMenu(job, customer: customer)
                .accessibilityHint("Opens the job")
                .accessibilityIdentifier("job-row-\(job.id)")
                .rowSwipeAccessibility(actions)
                // No time yet: book it from the row (beside the link, so each is its own target).
                if needsTime {
                    ScheduleRowButton(job: job) { scheduling = job }.padding(.trailing, 12)
                }
            }
            .background(Theme.card)
        }
    }
}

// MARK: - Paper v2 work lists (Schedule, Jobs)

/// Paper 79: the week as seven tiles (64 tall, radius 16): the weekday's letter in 13 Semibold, the
/// date in 17, and a 4pt dot when the day has jobs. Today sits on the brand surface in brand text.
/// A day with jobs jumps the list to its group.
private struct WeekDayStrip: View {
    let days: [Date]
    let counts: [Date: Int]
    let jump: (Date) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                tile(day, count: counts[day] ?? 0, today: Calendar.current.isDateInToday(day))
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func tile(_ day: Date, count: Int, today: Bool) -> some View {
        // Paper 79: Saturday and Sunday read in the muted grey; today on brand at 24%.
        let ink: Color = today ? Theme.brandText : (Calendar.current.isDateInWeekend(day) ? Theme.muted : Theme.foreground)
        let dot: Color = count == 0 ? Color.clear : (today ? Theme.brandText : Theme.muted)
        let ground: Color = today ? Theme.brandTint : Color.clear
        return Button { jump(day) } label: {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(Theme.font(13, weight: .semibold))
                    .foregroundStyle(today ? Theme.brandText : Theme.muted)
                Text(day.formatted(.dateTime.day()))
                    .font(Theme.font(17, weight: today ? .bold : .semibold)).monospacedDigit()
                    .foregroundStyle(ink)
                Circle().fill(dot).frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(ground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(count == 0)
        .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).month(.wide).day())), \(count) job\(count == 1 ? "" : "s")")
        .accessibilityHint(count > 0 ? "Jumps to this day" : "")
        .accessibilityIdentifier("week-day-\(Calendar.current.component(.day, from: day))")
    }
}

/// A job in a Jobs card (Paper 20): the status circle (half-filled under way, an outline when
/// booked, a filled check when done), the job in 16 Medium over "Customer · JOB-2214" or when, and
/// the tech's initials at the trailing edge. Late and waiting-to-sync say so in words.
private struct JobCardRow: View {
    let job: Job
    let customer: String
    /// The job number, or when the visit is.
    let detail: String
    var pendingStatus: String? = nil
    var late = false
    var assignee: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Where the hairline between two rows starts: past the circle, under the words.
    static let dividerInset: CGFloat = 16 + 20 + 12

    private var status: String { pendingStatus ?? job.status }
    private var finished: Bool { ["completed", "canceled"].contains(job.status) }

    private var subtitle: String {
        var parts = [customer]
        if pendingStatus != nil { parts.append("\(status.statusLabel) · waiting to sync") }
        if late { parts.append("Late") }
        parts.append(detail)
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        HStack(alignment: .center, spacing: 12) {
            StatusGlyph(tone: StatusTone(jobStatus: status, hasTime: job.scheduledFor != nil),
                        label: late ? "Late, \(status.statusLabel)" : status.statusLabel,
                        pending: pendingStatus != nil, size: 20)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(job.title.dashKeptWithWordBefore).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                        .foregroundStyle(finished ? Theme.subtle : Theme.foreground)
                        .lineLimit(stacked ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(Theme.font(14))
                        .foregroundStyle(late ? Theme.destructive : Theme.muted)
                        .lineLimit(stacked ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let assignee { PaperInitials(name: assignee) }
            }
            .padding(.vertical, 11)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Paper 19 "Finish setting up": the first steps still open, under the empty board. One card, a
/// row per step this role can do: a green check when the server says it is done, the step's glyph
/// when it is not, and a chevron to the screen that finishes it. "1 of 4 done" trails the label.
/// Nothing is drawn until every step has been read, or once all of them are done.
private struct FinishSetupCard: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @StateObject private var model = BusinessSetupModel()
    /// The steps the server last confirmed done; nil until a full, current read.
    @State private var confirmed: Set<BusinessSetupModel.Step>?
    @State private var addingCustomer = false

    private enum Item: String, Identifiable {
        case company, customer, priceBook, team
        var id: String { rawValue }

        var title: String {
            switch self {
            case .company: "Set up your company"
            case .customer: "Add your first customer"
            case .priceBook: "Build your price book"
            case .team: "Invite your team"
            }
        }

        var symbol: String {
            switch self {
            case .company: "building.2"
            case .customer: "person.badge.plus"
            case .priceBook: "book.closed"
            case .team: "person.2"
            }
        }
    }

    private var items: [Item] {
        let steps = model.steps(session)
        var shown: [Item] = []
        if steps.contains(.details) { shown.append(.company) }
        if session.can("customer.create", feature: "core_crm") { shown.append(.customer) }
        if steps.contains(.services) { shown.append(.priceBook) }
        if steps.contains(.team) { shown.append(.team) }
        return shown
    }

    private func isDone(_ item: Item, confirmed: Set<BusinessSetupModel.Step>) -> Bool {
        switch item {
        case .company: confirmed.contains(.details)
        case .customer: !store.customers.isEmpty
        case .priceBook: confirmed.contains(.services)
        case .team: confirmed.contains(.team)
        }
    }

    var body: some View {
        let items = self.items
        VStack(alignment: .leading, spacing: 0) {
            if let confirmed, !items.isEmpty {
                let done = items.filter { isDone($0, confirmed: confirmed) }.count
                if done < items.count {
                    PaperCardLabel(title: "Finish setting up", countText: "\(done) of \(items.count) done")
                    PaperRowsCard {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { WellDivider(leading: 16 + 24 + 12) }
                            link(item, done: isDone(item, confirmed: confirmed))
                        }
                    }
                }
            }
        }
        .task(id: "\(session.generation)|\(session.isOffline)") {
            await model.refresh(api: api, session: session)
            let current = model.loaded && model.isCurrent(api: api, session: session) && model.unavailable.isEmpty
            confirmed = current ? model.done : nil
        }
        .sheet(isPresented: $addingCustomer) { SheetSurface { NewCustomerSheet() } }
    }

    @ViewBuilder private func link(_ item: Item, done: Bool) -> some View {
        switch item {
        case .company:
            NavigationLink(value: PaperRoute.companyDetails) { row(item, done: done) }.buttonStyle(RowPressStyle())
        case .customer:
            Button { addingCustomer = true } label: { row(item, done: done) }.buttonStyle(RowPressStyle())
        case .priceBook:
            NavigationLink(value: PaperRoute.priceBook) { row(item, done: done) }.buttonStyle(RowPressStyle())
        case .team:
            NavigationLink(value: PaperRoute.team) { row(item, done: done) }.buttonStyle(RowPressStyle())
        }
    }

    /// Paper 19: a 24pt mark, the step in 16 Medium (muted once done) and a chevron, 56 tall.
    private func row(_ item: Item, done: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : item.symbol)
                .font(.system(size: done ? 20 : 17, weight: .medium))
                .foregroundStyle(done ? Theme.statusDone : Theme.subtle)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(item.title).font(Theme.font(16, weight: .medium))
                .foregroundStyle(done ? Theme.muted : Theme.foreground)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted).accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Not done")
        .accessibilityIdentifier("finish-setup-\(item.rawValue)")
    }
}

/// Paper 19: an empty schedule. A 56pt card circle with the calendar, 22 Bold, a 15 muted line and
/// one brand-tinted action.
private struct ScheduleEmptyState: View {
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            PaperIcon(.calendar, size: 24, color: Theme.muted)
                .frame(width: 56, height: 56)
                .background(Theme.card, in: Circle())
                .accessibilityHidden(true)
            Text(title).font(Theme.font(22, weight: .bold)).tracking(-0.44)
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            if let message, !message.isEmpty {
                Text(message).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle {
                Button(action: action) {
                    Text(actionTitle).font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.brandText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 48)
                        .background(Theme.brandSurface, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .padding(.top, 14)
                .accessibilityIdentifier("empty-state-action")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.gutter).padding(.vertical, 48)
        .accessibilityElement(children: .contain)
    }
}
