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

/// Paper 18 / 79: the technician's day. "Next up" carries the one commit that
/// moves the job forward (On my way), so the old Arrive tab lives here now.
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
    @State private var busyJobID: String?
    @State private var progressError: String?
    /// The Next up job as GET /v1/jobs/{id} returns it: list items carry no allowed transitions,
    /// so the hero's commit is read from the server rather than guessed from status.
    @State private var hero: JobRecord?
    @State private var committed = 0
    /// Today's lead job's own address and number, read live or from the last copy.
    @State private var stop: NextStopPlace?
    @StateObject private var eta = NextStopETA()
    /// Street lines for the rows (street first, design 2026-10-30).
    @StateObject private var addresses = JobAddressBook()
    /// "Done today" opens in place to list the finished visits.
    @State private var showDone = false
    /// The Next stop card's "Turn on location" line, once dismissed, stays away this launch.
    @State private var locationNoticeDismissed = NextStopLocationNotice.dismissedThisLaunch
    /// Who each tech is, for the rows' avatars. Never kept on the phone: offline the rows show none
    /// rather than guess.
    @State private var roster: [String: String] = [:]
    /// Today as stop cards or the list; empty until the person picks (the role decides).
    @AppStorage(TodayLayoutMode.storageKey) private var storedTodayLayout = ""
    /// The stop card showing, by job id; its next step is the one loaded for the commit.
    @State private var cardFocus: String?
    @StateObject private var cardPlaces = StopCardPlaces()
    /// The rows' swipes: what each row has read (allowed moves, a number to call) and the moves sent.
    @StateObject private var swipes = JobRowSwipeBook()

    private var range: ScheduleRange {
        switch tab {
        case "Week": .week
        case "Unscheduled": .unscheduled
        case "Map", "Board": .today
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
        JobFiltering.schedule(store.jobs, range: range, assignedTo: scope.assignee(session.user?.id, range: range))
    }
    private var canSchedule: Bool { session.can("job.assign", feature: "jobs") }

    /// Board is the dispatcher's view of every tech's day, so only roles that assign see it.
    private var tabOptions: [String] { canSchedule ? ["Today", "Week", "Board", "Map"] : ["Today", "Week", "Map"] }

    /// One selector row: Today | Week | (Board) | Map. Unscheduled lives in the header's filter circle,
    /// so while it shows no segment is chosen and tapping one goes back.
    private var segment: Binding<String> {
        Binding(get: { tab == "Unscheduled" ? "" : tab }, set: { tab = $0 })
    }

    /// Whose jobs and the Unscheduled queue: the secondary filters behind the header circle.
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
        items.append(ThorbisMenuItem("Unscheduled", icon: "calendar.badge.exclamationmark",
                                     subtitle: "Jobs that still need a time", isSelected: tab == "Unscheduled") {
            tab = tab == "Unscheduled" ? "Today" : "Unscheduled"
        })
        return items
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: title, subtitle: subtitle, filterMenu: filterItems,
                            filterActive: tab == "Unscheduled" || (showsScope && scope == .everyone && WorkRole(session).schedulesOwnDay),
                            showsCreate: true)
                OfflineBanner()
                HStack(alignment: .center, spacing: 0) {
                    PaperTabs(options: tabOptions, selection: segment, textTabs: true)
                    if tab == "Today" {
                        TodayLayoutToggle(mode: todayLayout) { storedTodayLayout = todayLayout.toggled.rawValue }
                            .padding(.trailing, Theme.gutter - 4)
                    }
                }
                .padding(.bottom, 8)
                if let error = store.error { ErrorBanner(message: error) { _ = await store.refresh(api) } }
                if let progressError { ErrorBanner(message: progressError) }
                if let problem = swipes.problem { ErrorBanner(message: problem) }
                if store.loading && store.jobs.isEmpty {
                    SkeletonList(count: 4, leading: true).paperCardMargin()
                } else if tab == "Board" && canSchedule {
                    DispatchBoardView()
                } else if jobs.isEmpty {
                    // Every stop done: the cards still show the day, opening on the last one.
                    if showsStopCards { stopCards(lead: nil) } else { emptyState }
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
        }
        .refreshable { await store.refresh(api) }
        // An open row closes as soon as the list moves.
        .onScrollPhaseChange { _, phase in if phase != .idle { swipes.rows.close() } }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNew) { NewJobSheet() }
        .sheet(item: $scheduling) { QuickScheduleSheet(jobID: $0.id) }
        .sensoryFeedback(.success, trigger: committed)
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
            if PaperPreview.enabled && PaperPreview.screen == "dispatch-board" { tab = "Board" }
            // Previews start from the role's layout each launch, so a capture or UI test never inherits a toggle.
            if PaperPreview.enabled && !TodayStopCardsPreview.resetThisLaunch {
                TodayStopCardsPreview.resetThisLaunch = true
                storedTodayLayout = ""
            }
        }
        #endif
    }

    private var title: String {
        if tab == "Board" { return "Board" }
        return switch range {
        case .today: "Today"
        case .week: "This week"
        case .unscheduled: "Unscheduled"
        }
    }

    private var subtitle: String {
        if tab == "Board" {
            let today = store.jobs.filter { $0.status != "canceled" && (JobFiltering.date($0.scheduledFor).map { Calendar.current.isDateInToday($0) } ?? false) }
            let waiting = JobFiltering.schedule(store.jobs, range: .unscheduled).count
            return "Today · \(today.count) booked · \(waiting) unscheduled"
        }
        let count = jobs.count
        let who = showsScope && scope == .mine ? "Your jobs" : "Everyone"
        return switch range {
        case .today: NextStopDay.subtitle(jobs: todayVisits, lead: leadJob)
        case .week: "\(who) · \(count) job\(count == 1 ? "" : "s")"
        case .unscheduled: "\(count) job\(count == 1 ? "" : "s") need a time · everyone's"
        }
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

    /// Cards or the list on Today; office and owners start on the list, technicians on cards.
    private var todayLayout: TodayLayoutMode {
        #if DEBUG
        if storedTodayLayout.isEmpty, let forced = TodayStopCardsPreview.forced { return forced }
        #endif
        return TodayLayoutMode.resolve(stored: storedTodayLayout, schedulesOwnDay: WorkRole(session).schedulesOwnDay)
    }

    /// Today's stops in pager order: done ones to the left, then the day by time.
    private var cardStops: [Job] {
        TodayStopOrder.ordered(todayVisits) { outbox.pendingStatus(for: $0.id) ?? $0.status }
    }

    private var showsStopCards: Bool { tab == "Today" && todayLayout == .cards && !todayVisits.isEmpty }

    @ViewBuilder private var dayContent: some View {
        if showsStopCards, let first = leadJob {
            // The card replaces the Now panel; the rest of the day stays below as the list.
            let rest = jobs.filter { $0.id != first.id }
            VStack(alignment: .leading, spacing: 0) {
                stopCards(lead: first)
                if ScheduleLead.activeStatuses.contains(first.status), let next = rest.first {
                    section("Up next", [next], leading: .time)
                    if rest.count > 1 { section("Later today", Array(rest.dropFirst()), leading: .time) }
                } else if !rest.isEmpty {
                    section("Later today", rest, leading: .time)
                }
                doneToday
            }
        } else if let first = leadJob {
            let isActive = ScheduleLead.activeStatuses.contains(first.status)
            let isToday = range == .today
            let booked = ["scheduled", "dispatched"].contains(first.status)
            let place = isToday ? stop.flatMap { $0.jobID == first.id ? $0 : nil } : nil
            let driving = ["scheduled", "dispatched", "en_route"].contains(outbox.pendingStatus(for: first.id) ?? first.status)
            // Today hides finished visits from the open list; they sit under Done.
            let rest = jobs.filter { $0.id != first.id && !(isToday && $0.status == "completed") }
            // v2 List room (as Jobs, Customers, Search): labels and rows on the canvas at the gutter;
            // only the Now job sits on a panel.
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ListGroupLabel(title: range == .unscheduled ? "Needs a time" : isActive ? "Now" : isToday && booked ? "Next stop" : "Next up",
                                   first: true)
                    ScheduleHero(job: first, customer: store.customerName(first.customerId), pendingStatus: outbox.pendingStatus(for: first.id),
                                 nextStop: isToday, place: place, street: addresses.street(first),
                                 etaMinutes: place != nil && driving ? eta.minutes : nil,
                                 onSiteSince: onSiteSince(first),
                                 locationNotice: place?.coordinates != nil && driving && !session.isOffline && eta.locationOff && !locationNoticeDismissed
                                    ? { NextStopLocationNotice.dismissedThisLaunch = true
                                        withMotion(.easeOut(duration: 0.2)) { locationNoticeDismissed = true } } : nil) { commit(for: first) }
                        .task(id: "\(first.id)|\(first.status)|\(first.updatedAt ?? "")") { await loadHero(first) }
                        .task(id: "stop|\(first.id)|\(first.customerId ?? "")|\(first.locationId ?? "")|\(session.generation)|\(session.isOffline)") {
                            guard isToday else { return }
                            await loadStop(first)
                        }
                        .task(id: "eta|\(place?.jobID ?? "")|\(place?.coordinates.map { "\($0.latitude),\($0.longitude)" } ?? "")|\(driving)") {
                            guard let place else { return }
                            await eta.update(to: place.coordinates, key: "\(place.jobID)|\(place.locationID ?? "")",
                                             enabled: driving && !session.isOffline)
                        }
                        .paperCardMargin()
                        .padding(.top, 4)
                }
                if isToday && isActive, let next = rest.first {
                    // On a job now: the stop after it, then the rest of the day.
                    section("Up next", [next], leading: .time)
                    if rest.count > 1 { section("Later today", Array(rest.dropFirst()), leading: .time) }
                } else if !rest.isEmpty {
                    section(range == .today ? "Later today" : range == .unscheduled ? "Also waiting" : "More jobs",
                            rest, leading: range == .unscheduled ? .age : .time)
                }
                if isToday { doneToday }
            }
        }
    }

    /// The pager of today's stops. The card showing loads its job's next step (the commit), its
    /// place and drive time, as the Now panel does for the lead job.
    private func stopCards(lead: Job?) -> some View {
        let stops = cardStops
        let shown = stops.first { $0.id == cardFocus } ?? lead ?? stops.last
        let place = shown.flatMap { job in stop.flatMap { $0.jobID == job.id ? $0 : nil } }
        let driving = shown.map { ["scheduled", "dispatched", "en_route"].contains(outbox.pendingStatus(for: $0.id) ?? $0.status) } ?? false
        let canCustomerView = session.can("estimate.view", feature: "estimates") || session.can("invoice.view", feature: "invoicing")
            || session.can("customer.edit", feature: "core_crm")
        return TodayStopCards(
            stops: stops, focus: $cardFocus,
            customer: { store.customerName($0.customerId) },
            street: { addresses.street($0) },
            place: { job in job.id == place?.jobID ? place : cardPlaces.place(job) },
            access: { cardPlaces.access[$0.id] },
            pendingStatus: { outbox.pendingStatus(for: $0.id) },
            // Drive time only for the stop the tech drives to next (the Now panel's rule), never a later one.
            etaMinutes: { job in job.id == place?.jobID && job.id == lead?.id && driving ? eta.minutes : nil },
            onSiteSince: { onSiteSince($0) },
            locationNotice: { job in
                job.id == place?.jobID && place?.coordinates != nil && driving && !session.isOffline && eta.locationOff && !locationNoticeDismissed
                    ? { NextStopLocationNotice.dismissedThisLaunch = true
                        withMotion(.easeOut(duration: 0.2)) { locationNoticeDismissed = true } } : nil
            },
            canOpenCustomerView: canCustomerView
        ) { commit(for: $0) }
        .padding(.top, 4)
        .onAppear { placeCards(stops) }
        .onChange(of: stops.map(\.id)) { _, _ in placeCards(stops) }
        .task(id: "card|\(shown?.id ?? "")|\(shown?.status ?? "")|\(shown?.updatedAt ?? "")") {
            if let shown { await loadHero(shown) }
        }
        .task(id: "cardstop|\(shown?.id ?? "")|\(shown?.customerId ?? "")|\(shown?.locationId ?? "")|\(session.generation)|\(session.isOffline)") {
            if let shown { await loadStop(shown) }
        }
        .task(id: "cardeta|\(place?.jobID ?? "")|\(place?.coordinates.map { "\($0.latitude),\($0.longitude)" } ?? "")|\(driving)") {
            guard let place else { return }
            await eta.update(to: place.coordinates, key: "\(place.jobID)|\(place.locationID ?? "")", enabled: driving && !session.isOffline)
        }
        .task(id: "cardplaces|\(shown?.id ?? "")|\(stops.map(\.id).joined(separator: ","))|\(session.generation)|\(session.isOffline)") {
            // The card showing and its neighbours, so the circles are there before a swipe lands.
            guard let at = stops.firstIndex(where: { $0.id == shown?.id }) else { return }
            let near = [at, at + 1, at - 1].filter(stops.indices.contains).map { stops[$0] }
            await cardPlaces.load(near, api: api, organizationID: session.activeOrganization?.id,
                                  canView: session.can("customer.view", feature: "core_crm"),
                                  identity: "\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)")
        }
    }

    /// Opens the pager on the stop under way, else the next booked one; only on first show or when
    /// the day's stops change, so a refresh or a step never moves the card under the person's thumb.
    private func placeCards(_ stops: [Job]) {
        if let cardFocus, stops.contains(where: { $0.id == cardFocus }) { return }
        var start = TodayStopOrder.startIndex(stops) { outbox.pendingStatus(for: $0.id) ?? $0.status }
        #if DEBUG
        if let forced = TodayStopCardsPreview.startIndex, stops.indices.contains(forced) { start = forced }
        #endif
        cardFocus = start.map { stops[$0].id }
    }

    /// When the tech reached the lead job, from the server's own arrival (or start) time. Nil when the
    /// record has not loaded or carries neither, so the card never guesses a duration.
    private func onSiteSince(_ job: Job) -> Date? {
        guard let hero, hero.id == job.id, ["arrived", "in_progress", "paused"].contains(outbox.pendingStatus(for: job.id) ?? job.status)
        else { return nil }
        return JobFiltering.date(hero.arrivedAt) ?? JobFiltering.date(hero.startedAt)
    }

    /// A group: the list room's 13 Medium label with its count, then the rows on the page (v2: no
    /// panel, no line; tight inside the group, generous between groups).
    private func section(_ title: String, _ list: [Job], leading: ScheduleCompactRow.TimeStyle, first: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ListGroupLabel(title: title, count: list.count, first: first)
            VStack(alignment: .leading, spacing: 0) { jobRows(list, leading: leading) }
        }
    }

    /// Finished visits today, counted in the header; the list opens in place.
    @ViewBuilder private var doneToday: some View {
        let done = todayVisits.filter { $0.status == "completed" }
        if !done.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ListGroupLabel(title: "Done", count: done.count) {
                    Button { withMotion(.easeOut(duration: 0.2)) { showDone.toggle() } } label: {
                        Text(showDone ? "Hide" : "Show")
                            .font(Theme.font(15, weight: .medium))
                            .foregroundStyle(Theme.brandText)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Done today, \(done.count) finished")
                    .accessibilityValue(showDone ? "Showing" : "Hidden")
                    .accessibilityHint(showDone ? "Hides the finished visits" : "Lists the finished visits")
                    .accessibilityIdentifier("schedule-done-today")
                }
                if showDone {
                    VStack(alignment: .leading, spacing: 0) {
                        jobRows(done.sorted { (JobFiltering.date($0.scheduledFor) ?? .distantPast) < (JobFiltering.date($1.scheduledFor) ?? .distantPast) },
                                leading: .time)
                    }
                }
            }
        }
    }

    /// The rows: time column, street first, problem · customer, the status word trailing. The tech's
    /// avatar shows only where it tells something (on one tech's day it would repeat on every row).
    /// "a.m." / "p.m." shows under the time on the first row and wherever the period changes.
    @ViewBuilder private func jobRows(_ list: [Job], leading: ScheduleCompactRow.TimeStyle) -> some View {
        // Who, only where it varies: on everyone's jobs with more than one tech in the group.
        let everyone = !(showsScope && scope == .mine) && Set(list.compactMap(\.assignedToUserId)).count > 1
        ForEach(Array(list.enumerated()), id: \.element.id) { index, job in
            let period = JobFiltering.date(job.scheduledFor)?.periodMark
            let previous = index > 0 ? JobFiltering.date(list[index - 1].scheduledFor)?.periodMark : nil
            let customer = store.customerName(job.customerId)
            // Swipe right: Call, Directions. Swipe left: the next move the server allows.
            JobSwipeRow(job: job, customer: customer, book: swipes, places: addresses) { actions in
                TodayRow(job: job, customer: customer, street: addresses.street(job),
                         timeStyle: leading, pendingStatus: outbox.pendingStatus(for: job.id),
                         assignee: everyone ? job.assignedToUserId.flatMap { roster[$0] } : nil,
                         showsPeriod: index == 0 || period != previous,
                         schedule: job.scheduledFor == nil && canSchedule ? { scheduling = job } : nil,
                         swipeActions: actions)
            }
        }
    }

    /// One section per day with a count.
    @ViewBuilder private var weekContent: some View {
        let calendar = Calendar.current
        let days = Dictionary(grouping: jobs) { calendar.startOfDay(for: JobFiltering.date($0.scheduledFor) ?? .now) }
        let sorted = days.keys.sorted()
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sorted, id: \.self) { day in
                let dayJobs = days[day] ?? []
                section(dayTitle(day), dayJobs, leading: .time, first: day == sorted.first)
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let label = day.formatted(.dateTime.weekday(.abbreviated).day())
        if Calendar.current.isDateInToday(day) { return "\(label) · Today" }
        if Calendar.current.isDateInTomorrow(day) { return "\(label) · Tomorrow" }
        return label
    }

    @ViewBuilder private var emptyState: some View {
        let boardEmpty = store.jobs.isEmpty
        let mine = showsScope && scope == .mine
        PaperEmptyState(
            symbol: "calendar",
            // design.thorbis.com States: empty names the one action ("No jobs today. Create a job.").
            title: range == .unscheduled ? "Every job has a time" : "No jobs \(mine ? "for you " : "")\(range == .today ? (todayVisits.isEmpty ? "today" : "left today") : "this week")",
            message: range == .unscheduled ? nil
                : mine && !boardEmpty ? "Choose Everyone in the filter to see the whole team's jobs." : nil,
            actionTitle: range != .unscheduled && session.can("job.create", feature: "jobs") ? "Create a job" : nil,
            tint: Theme.markAccent, prominent: true,
            action: { showNew = true }
        )
        .padding(.top, 24)
    }

    /// The next field step for the Next up job, in lifecycle order (the same rule as the rows' swipe).
    private func nextStep(for job: Job) -> String? {
        JobMoves.next(listedStatus: job.status,
                      served: hero.flatMap { $0.id == job.id ? ($0.status, $0.allowedTransitions ?? []) : nil },
                      queued: outbox.pendingStatus(for: job.id), isOffline: session.isOffline,
                      learned: outbox.offlineSteps(from:), canEdit: session.can("job.edit", feature: "jobs"))
    }

    @ViewBuilder private func commit(for job: Job) -> some View {
        if job.scheduledFor == nil, canSchedule, !ScheduleLead.activeStatuses.contains(job.status) {
            // Needs a time: booking it is the one next step, straight to the schedule sheet.
            Button { scheduling = job } label: {
                commitLabel("Schedule", symbol: "calendar.badge.plus", busy: false)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Schedule \(job.title)")
            .accessibilityHint("Choose a day and arrival window")
            .accessibilityIdentifier("schedule-row-\(job.id)")
        } else {
            stepCommit(for: job)
        }
    }

    @ViewBuilder private func stepCommit(for job: Job) -> some View {
        switch nextStep(for: job) {
        case "en_route":
            ThorbisMenu(
                items: [ThorbisMenuItem("On my way", icon: "location.fill") {
                    Task { await progress(job, .enRoute(etaMinutes: nil)) }
                }] + ([15, 30, 45, 60] as [Int]).map { minutes in
                    ThorbisMenuItem("ETA \(minutes) min", icon: "clock") {
                        Task { await progress(job, .enRoute(etaMinutes: minutes)) }
                    }
                },
                title: "On my way",
                accessibilityLabel: "On my way"
            ) { commitLabel("On my way", symbol: "location.fill", busy: busyJobID == job.id) }
            .disabled(busyJobID != nil)
            .accessibilityHint("Tells the office and customer you are driving to this job")
        case "arrived":
            Button { Task { await progress(job, .arrived()) } } label: {
                commitLabel("Arrive", symbol: "mappin.and.ellipse", busy: busyJobID == job.id)
            }
            .buttonStyle(PressStyle()).disabled(busyJobID != nil)
        case "in_progress":
            Button { Task { await progress(job, .start) } } label: {
                commitLabel("Start work", symbol: "wrench.and.screwdriver", busy: busyJobID == job.id)
            }
            .buttonStyle(PressStyle()).disabled(busyJobID != nil)
        default:
            // On the job already: the next thing is wrapping it up, so that is the commit.
            if (outbox.pendingStatus(for: job.id) ?? job.status) == "in_progress", session.can("job.edit", feature: "jobs") {
                NavigationLink { JobCloseoutView(jobID: job.id).thorbisBackButton() } label: {
                    commitLabel("Wrap up", symbol: "checkmark.seal", busy: false)
                }
                .buttonStyle(PressStyle())
                .accessibilityHint("Opens the closeout checklist for this job")
                // The link inherits a "Selected" trait inside the schedule's list; it is an action, not a choice.
                .accessibilityRemoveTraits(.isSelected)
            }
        }
    }

    /// MA-08: the panel's one commit is the ink commit (radius 10, a 1px rim, press sinks);
    /// pending keeps the words and swaps the mark.
    private func commitLabel(_ title: String, symbol: String, busy: Bool) -> some View {
        HStack(spacing: 7) {
            if busy { ProgressView().tint(Theme.onInk) } else { Image(systemName: symbol).font(.system(size: 14, weight: .medium)) }
            Text(title)
        }
        .inkCommit(height: 44)
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

    private func progress(_ job: Job, _ request: FieldProgressRequest) async {
        guard busyJobID == nil else { return }
        if !session.isOffline && outbox.pending.filter({ $0.jobID == job.id }).isEmpty { busyJobID = job.id }
        defer { busyJobID = nil }
        switch await JobProgressRun.run(jobID: job.id, request: request, api: api, store: store,
                                        session: session, outbox: outbox) {
        case .sent(let refreshed):
            committed += 1
            await loadHero(job)
            progressError = refreshed ? nil : "Saved. The latest schedule could not be refreshed."
        case .queued:
            committed += 1
            progressError = nil
        case .refused(let message):
            progressError = message
        case .cancelled:
            break
        }
    }
}

/// The Now panel (v2, design.thorbis.com "Today" and Linear's calm): one panel with the street,
/// the problem and who, the status as a word with its mark ("On site 42 min" once the arrival is
/// known) and the time, then one row of actions: the ink commit (On my way, Arrive, Wrap up...)
/// and quiet circles for Directions and Call. No side rail, no chip row. Away from Today it is
/// "Next up" with the visit's date instead.
private struct ScheduleHero<Commit: View>: View {
    let job: Job
    let customer: String
    var pendingStatus: String? = nil
    var nextStop = false
    var place: NextStopPlace? = nil
    /// The job's street from the list's address book, when the stop itself is not loaded.
    var street: String? = nil
    var etaMinutes: Int? = nil
    /// The server's arrival time while on site: the panel says "On site 42 min".
    var onSiteSince: Date? = nil
    /// Set when Location is off and the drive time is missing because of it: shows the quiet
    /// "Turn on location" line, and is called when the person dismisses it.
    var locationNotice: (() -> Void)? = nil
    @ViewBuilder var commit: () -> Commit
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openURL) private var openURL

    /// Street first; without an address the job's own title leads.
    private var headline: String { place?.firstLine ?? street ?? job.title }
    private var hasStreet: Bool { place?.firstLine != nil || street != nil }
    private var supporting: String { hasStreet ? "\(job.title) · \(customer)" : customer }
    private var status: String { pendingStatus ?? job.status }
    private var tone: StatusTone { StatusTone(jobStatus: status, hasTime: job.scheduledFor != nil) }

    private var when: String {
        guard let date = JobFiltering.date(job.scheduledFor) else { return "No time yet" }
        var text = nextStop ? date.clockTime : date.visitLabel()
        if let etaMinutes { text += " · \(etaMinutes) min drive" }
        return text
    }

    private func statusWord(now: Date) -> String {
        if pendingStatus != nil { return "\(status.statusLabel) · waiting to sync" }
        if let onSiteSince { return JobOnSiteClock.line(arrived: onSiteSince, now: now) }
        return status.statusLabel
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: job) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline).font(Theme.font(20, weight: .medium)).tracking(-0.2)
                        .foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(supporting).font(Theme.font(14)).foregroundStyle(Theme.subtle)
                        .multilineTextAlignment(.leading)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                                              : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                    layout {
                        // v2: the status is a word; its small mark sits beside it in the hue.
                        TimelineView(.everyMinute) { context in
                            StatusLabel(tone: tone, word: statusWord(now: context.date), pending: pendingStatus != nil)
                        }
                        Text(when).font(Theme.font(13, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(etaMinutes != nil ? "next-stop-eta" : "next-stop-time")
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .jobContextMenu(job, customer: customer)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint("Opens the job")
            .accessibilityIdentifier(nextStop ? "next-stop-card" : "schedule-hero")
            // Outside the link, so Open Settings and dismiss never open the job.
            if nextStop, let locationNotice {
                NextStopLocationNotice(dismiss: locationNotice).padding(.top, 12)
            }
            // One row: the commit, then the quiet circles. At accessibility sizes the circles go
            // under the commit so its words never squeeze.
            let actions = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                                       : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            actions {
                commit()
                if hasCircles {
                    HStack(spacing: 8) { circles }
                }
            }
            .padding(.top, 16)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // v2: no coloured side rail; "you are here" is the status word and its mark (D-018).
        .background(Theme.well, in: shape)
    }

    private var hasCircles: Bool { nextStop && (place?.directions != nil || place?.call != nil) }

    @ViewBuilder private var circles: some View {
        if nextStop, let directions = place?.directions {
            PaperCircleButton(symbol: "arrow.triangle.turn.up.right.diamond", label: "Directions", size: 44,
                              fill: Theme.fill) { openURL(directions) }
                .accessibilityHint("Opens driving directions in Maps")
                .accessibilityIdentifier("next-stop-directions")
        }
        if nextStop, let call = place?.call {
            PaperCircleButton(symbol: "phone", label: "Call \(customer)", size: 44, fill: Theme.fill) { openURL(call) }
                .accessibilityIdentifier("next-stop-call")
        }
    }

    private var accessibilitySummary: String {
        var parts = [headline, job.title == headline ? nil : job.title, customer].compactMap { $0 }
        parts.append(when)
        parts.append(statusWord(now: .now))
        return parts.joined(separator: ", ")
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
    /// "1:00 p.m.": the column's clock with its period, for a time shown on its own (the Now panel,
    /// board cards, the map card), so a screen never mixes "1 p.m." with "2:30".
    var clockTime: String { [columnTime, periodMark].compactMap { $0 }.joined(separator: " ") }
    /// "a.m." / "p.m.", or nil on a 24-hour clock.
    var periodMark: String? {
        let uses24 = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") == false
        guard !uses24 else { return nil }
        return Calendar.current.component(.hour, from: self) < 12 ? "a.m." : "p.m."
    }
}

/// A Today row (v2, design.thorbis.com "The street leads. Time is a column. Status is a word."):
/// the time in a tabular column, the street (or the job's title) over the problem and who, and the
/// status word with its small mark at the trailing edge. Rows sit on the page, no panel or line:
/// space does the pause. The period ("a.m.") shows under the time only where it changes, so the
/// column reads 7:40, 8:15, 9:00. Rows without a time offer Schedule beside the link instead.
/// VoiceOver reads one item: street, problem, customer, full time, status.
struct TodayRow: View {
    let job: Job
    let customer: String
    var street: String? = nil
    var timeStyle: ScheduleCompactRow.TimeStyle = .time
    var pendingStatus: String? = nil
    /// The assigned tech's name from the roster; nil shows no avatar (one tech's own day).
    var assignee: String? = nil
    /// Show "a.m." / "p.m." under the time (the first row, and wherever the period changes).
    var showsPeriod = true
    var schedule: (() -> Void)? = nil
    /// The row's swipe actions, also offered to VoiceOver as custom actions on the row.
    var swipeActions: [RowSwipeAction] = []
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var column: CGFloat = 50

    /// Kept so older call sites compile; rows have no line between them.
    static let dividerInset: CGFloat = 0

    private var status: String { pendingStatus ?? job.status }
    private var dimmed: Bool { job.status == "completed" }

    private var time: (text: String, period: String?, spoken: String) {
        if timeStyle == .age, let created = JobFiltering.date(job.createdAt) {
            return (ScheduleCompactRow.age(since: created), nil, "Waiting since \(created.formatted(date: .abbreviated, time: .omitted))")
        }
        if let date = JobFiltering.date(job.scheduledFor) { return (date.columnTime, date.periodMark, date.tradeTime) }
        return ("—", nil, "No time")
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
                ScheduleRowButton(job: job, action: schedule).padding(.trailing, ListRoom.gutter)
            }
        }
    }

    /// The time column, then the list room's own job row (`JobRoomRow`: street, problem · customer,
    /// who where it varies, the status word trailing), so Today reads like Jobs and Search.
    private var content: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 0) {
                Text(time.text).font(Theme.font(13, weight: .medium)).monospacedDigit()
                    .foregroundStyle(dimmed ? Theme.muted : Theme.foreground)
                if let period = time.period, showsPeriod, !stacked {
                    Text(period).font(Theme.font(12)).foregroundStyle(Theme.muted)
                }
            }
            .frame(width: stacked ? nil : column, alignment: .leading)
            .padding(.top, stacked ? 10 : 0)
            JobRoomRow(job: job, street: street, customer: customer, who: assignee, pendingStatus: pendingStatus,
                       showsStatus: schedule == nil, inset: 0)
        }
        .padding(.horizontal, ListRoom.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                PaperListRow(leading: leading, title: street ?? job.title,
                             subtitle: street != nil ? "\(job.title) · \(customer)" : customer,
                             subtitleLines: 2, dimmed: job.status == "completed") {
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

    /// Statuses offered as filter chips, in lifecycle order.
    private let statusChips = ["scheduled", "dispatched", "en_route", "arrived", "in_progress", "paused", "completed", "canceled"]
    /// A filter is on when the sheet narrows the board past its defaults.
    private var filterActive: Bool { !statusFilter.isEmpty || !display.showCompleted || display.ordering != .recent }

    private var jobs: [Job] {
        let assigned = tab == "Assigned" ? (session.user?.id ?? "") : nil
        // Finding a job by name or number is the bar's Search; the board narrows with Filters.
        return JobFiltering.board(store.jobs, assignedTo: assigned, search: "",
                                  showCompleted: display.showCompleted, statuses: statusFilter,
                                  ordering: display.ordering)
    }
    private var activeCount: Int { jobs.filter { !["completed", "canceled"].contains($0.status) }.count }
    private var attentionCount: Int { jobs.filter { $0.status == "paused" }.count }
    private var subtitle: String {
        attentionCount > 0 ? "\(activeCount) active · \(attentionCount) paused" : "\(activeCount) active"
    }
    private var canSchedule: Bool { session.can("job.assign", feature: "jobs") }
    /// What the Filters sheet is doing to the board, in words, so a narrowed list never looks empty by accident.
    private var filterSummary: String {
        var parts: [String] = []
        if !statusFilter.isEmpty {
            parts.append(statusChips.filter { statusFilter.contains($0) }.map(\.statusLabel).joined(separator: ", "))
        }
        if !display.showCompleted { parts.append("Hiding completed") }
        if display.ordering != .recent { parts.append("By \(display.ordering.label.lowercased())") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // v2 List room: the title, then the view bar (text tabs and the filter circle).
                PaperHeader(title: "Jobs", subtitle: subtitle, showsCreate: true)
                OfflineBanner()
                ListViewBar(options: ["Assigned", "All jobs", "Recent"], selection: $tab, filterLabel: "Filter jobs",
                            filterActive: filterActive, showFilter: $showDisplay) { filterPopover }
                if filterActive { filterBar }
                if let error = store.error { ErrorBanner(message: error) { _ = await store.refresh(api) } }
                if let problem = swipes.problem { ErrorBanner(message: problem) }
                LazyVStack(alignment: .leading, spacing: 0) {
                    if store.loading && store.jobs.isEmpty {
                        ListRoomSkeleton(count: 6)
                    } else if tab == "Recent" {
                        group("Recently updated", jobs: Array(jobs.prefix(25)), first: true)
                    } else {
                        ForEach(Array(groups.enumerated()), id: \.element.title) { index, group in
                            self.group(group.title, jobs: group.jobs, first: index == 0)
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
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if session.can("job.create", feature: "jobs") && !jobs.isEmpty {
                FloatingCreateButton(title: "New job") { showNew = true }
            }
        }
        .sheet(isPresented: $showNew) { NewJobSheet() }
        .sheet(item: $scheduling) { QuickScheduleSheet(jobID: $0.id) }
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

    /// The active filters in one quiet line under the tabs, with a way back to the whole board.
    private var filterBar: some View {
        HStack(spacing: 8) {
            Button { showDisplay = true } label: {
                Label(filterSummary, systemImage: "line.3.horizontal.decrease")
                    .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Filtered: \(filterSummary)")
            .accessibilityHint("Opens the filters")
            Button { withMotion { statusFilter = []; display = DisplayOptions() } } label: {
                Text("Clear").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Clear filters")
        }
        .padding(.horizontal, Theme.gutter)
    }

    /// Ordering, completed work and status: the real ways to narrow the board, in a popover from the
    /// view bar's filter circle (design.thorbis.com Places: a popover is one local choice).
    private var filterPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Filters").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    if filterActive {
                        Button { withMotion { statusFilter = []; display = DisplayOptions() } } label: {
                            Text("Reset").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Reset filters")
                    }
                }
                .frame(minHeight: 32)
                Text("Ordering").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                    .padding(.top, 8).accessibilityAddTraits(.isHeader)
                ForEach(DisplayOptions.Ordering.allCases) { ordering in
                    Button { display.ordering = ordering } label: {
                        HStack {
                            Text(ordering.label).font(Theme.font(16)).foregroundStyle(Theme.foreground)
                            Spacer(minLength: 8)
                            if display.ordering == ordering {
                                Image(systemName: "checkmark").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.foreground)
                            }
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(display.ordering == ordering ? .isSelected : [])
                }
                Toggle(isOn: $display.showCompleted) {
                    Text("Show completed").font(Theme.font(16)).foregroundStyle(Theme.foreground)
                }
                .tint(Theme.brand)
                .frame(minHeight: 48)
                .padding(.top, 8)
                Text("Status").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                    .padding(.top, 16).padding(.bottom, 8).accessibilityAddTraits(.isHeader)
                ThorbisChipGroup(data: statusChips, id: \.self,
                                 isOn: { statusFilter.contains($0) },
                                 label: { $0.statusLabel }) { status in
                    if statusFilter.contains(status) { statusFilter.remove(status) } else { statusFilter.insert(status) }
                }
            }
            .padding(16)
        }
        .frame(maxHeight: 520)
        .background(Theme.card)
    }

    /// When the visit is ("Today 4 p.m."), "No time yet", or nothing once the work is finished.
    private func when(_ job: Job) -> String? {
        guard !["completed", "canceled"].contains(job.status) else { return nil }
        return JobFiltering.date(job.scheduledFor).map { $0.visitLabel() } ?? "No time yet"
    }

    /// A booked visit whose time has passed.
    private func isLate(_ job: Job) -> Bool {
        guard ["scheduled", "dispatched"].contains(job.status), let date = JobFiltering.date(job.scheduledFor) else { return false }
        return date < .now
    }

    /// Grouped by status on the canvas (v2 List room): a 13 Medium label with its count, then the
    /// rows: street, problem · customer, when and who, and the status word trailing. Space between
    /// groups, no lines. New job is the header's +, or the floating pill on iPad.
    @ViewBuilder private func group(_ title: String, jobs: [Job], first: Bool) -> some View {
        if !jobs.isEmpty {
            ListGroupLabel(title: title, count: jobs.count, first: first)
            ForEach(jobs) { job in jobRow(job) }
        }
    }

    private func jobRow(_ job: Job) -> some View {
        let customer = store.customerName(job.customerId)
        let needsTime = canSchedule && job.scheduledFor == nil && !["completed", "canceled"].contains(job.status)
            && !ScheduleLead.activeStatuses.contains(job.status)
        let mine = job.assignedToUserId != nil && job.assignedToUserId == session.user?.id
        let assignee = job.assignedToUserId.flatMap { roster[$0] }
        // The tech by name from the roster; "You" only where the roster can't name you, on a shared board.
        let who = assignee ?? (tab != "Assigned" && mine ? "You" : nil)
        // Swipe right: Call, Directions. Swipe left: the next move the server allows.
        return JobSwipeRow(job: job, customer: customer, book: swipes, places: addresses) { actions in
            HStack(spacing: 0) {
                // iPad selects into the detail column beside the list; iPhone pushes.
                PaperSplitLink(id: job.id, value: job) {
                    JobRoomRow(job: job, street: addresses.street(job), customer: customer, when: when(job),
                               who: needsTime ? nil : who,
                               pendingStatus: outbox.pendingStatus(for: job.id),
                               late: isLate(job), showsStatus: !needsTime)
                }
                .buttonStyle(RowPressStyle())
                .jobContextMenu(job, customer: customer)
                .accessibilityHint("Opens the job")
                .accessibilityIdentifier("job-row-\(job.id)")
                .rowSwipeAccessibility(actions)
                // No time yet: book it from the row (beside the link, so each is its own target). The
                // group's label already says Unscheduled.
                if needsTime {
                    ScheduleRowButton(job: job) { scheduling = job }.padding(.trailing, ListRoom.gutter - 4)
                }
            }
        }
    }
}
