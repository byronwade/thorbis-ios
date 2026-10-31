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
            parts.append("\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())), \(date.tradeTime)")
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

    private var range: ScheduleRange {
        switch tab {
        case "Week": .week
        case "Unscheduled": .unscheduled
        case "Map": .today
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

    /// One selector row: Today | Week | Map. Unscheduled lives in the header's filter circle,
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
                            filterActive: tab == "Unscheduled" || (showsScope && scope == .everyone && WorkRole(session).schedulesOwnDay))
                OfflineBanner()
                PaperTabs(options: ["Today", "Week", "Map"], selection: segment)
                    .padding(.bottom, 12)
                if let error = store.error { ErrorBanner(message: error) { _ = await store.refresh(api) } }
                if let progressError { ErrorBanner(message: progressError) }
                if store.loading && store.jobs.isEmpty {
                    SkeletonRows()
                } else if jobs.isEmpty {
                    emptyState
                    if range == .today { doneToday.paperCardMargin().padding(.top, 4) }
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
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNew) { NewJobSheet() }
        .sheet(item: $scheduling) { QuickScheduleSheet(jobID: $0.id) }
        .sensoryFeedback(.success, trigger: committed)
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
        }
        #endif
    }

    private var title: String {
        switch range {
        case .today: "Today"
        case .week: "This week"
        case .unscheduled: "Unscheduled"
        }
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

    @ViewBuilder private var dayContent: some View {
        if let first = leadJob {
            let isActive = ScheduleLead.activeStatuses.contains(first.status)
            let isToday = range == .today
            let booked = ["scheduled", "dispatched"].contains(first.status)
            let place = isToday ? stop.flatMap { $0.jobID == first.id ? $0 : nil } : nil
            let driving = ["scheduled", "dispatched", "en_route"].contains(outbox.pendingStatus(for: first.id) ?? first.status)
            VStack(alignment: .leading, spacing: 18) {
                PaperGroupHeader(title: range == .unscheduled ? "Needs a time" : isActive ? "Now" : isToday && booked ? "Next stop" : "Next up")
                    .padding(.horizontal, 4).padding(.bottom, -14)
                ScheduleHero(job: first, customer: store.customerName(first.customerId), pendingStatus: outbox.pendingStatus(for: first.id),
                             nextStop: isToday, place: place, street: addresses.street(first),
                             etaMinutes: place != nil && driving ? eta.minutes : nil) { commit(for: first) }
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
                let rest = jobs.filter { $0.id != first.id }
                if !rest.isEmpty {
                    PaperSection(range == .today ? (isActive ? "Also today" : "Later today") : range == .unscheduled ? "Also waiting" : "More jobs",
                                 count: rest.count) {
                        jobRows(rest, leading: range == .unscheduled ? .age : .time)
                    }
                }
                if isToday { doneToday }
            }
            .paperCardMargin()
        }
    }

    /// Finished visits today as one row; it opens in place to list them.
    @ViewBuilder private var doneToday: some View {
        let done = todayVisits.filter { $0.status == "completed" }
        if !done.isEmpty {
            PaperCard {
                Button { withMotion(.easeOut(duration: 0.2)) { showDone.toggle() } } label: {
                    HStack(spacing: 8) {
                        Text("Done today").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        Spacer(minLength: 8)
                        StatusWord(text: "\(done.count) finished", tint: Theme.success)
                    }
                    .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityValue(showDone ? "Showing" : "Hidden")
                .accessibilityHint(showDone ? "Hides the finished visits" : "Lists the finished visits")
                .accessibilityIdentifier("schedule-done-today")
                if showDone {
                    jobRows(done.sorted { (JobFiltering.date($0.scheduledFor) ?? .distantPast) < (JobFiltering.date($1.scheduledFor) ?? .distantPast) },
                            leading: .time)
                }
            }
        }
    }

    /// Rows on one panel: time column, street first, problem · customer, status word.
    @ViewBuilder private func jobRows(_ list: [Job], leading: ScheduleCompactRow.TimeStyle) -> some View {
        ForEach(list) { job in
            ScheduleCompactRow(job: job, customer: store.customerName(job.customerId), street: addresses.street(job),
                               timeStyle: leading, pendingStatus: outbox.pendingStatus(for: job.id),
                               schedule: job.scheduledFor == nil && canSchedule ? { scheduling = job } : nil)
        }
        .padding(.vertical, PaperCardMetrics.edge)
    }

    /// One section per day with a count.
    @ViewBuilder private var weekContent: some View {
        let calendar = Calendar.current
        let days = Dictionary(grouping: jobs) { calendar.startOfDay(for: JobFiltering.date($0.scheduledFor) ?? .now) }
        VStack(alignment: .leading, spacing: 18) {
            ForEach(days.keys.sorted(), id: \.self) { day in
                let dayJobs = days[day] ?? []
                PaperSection(dayTitle(day), count: dayJobs.count) { jobRows(dayJobs, leading: .time) }
            }
        }
        .paperCardMargin()
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
            title: boardEmpty ? "Nothing on the board yet" : range == .unscheduled ? "Everything has a time" : "No jobs \(mine ? "for you " : "")\(range == .today ? "left today" : "this week")",
            message: boardEmpty ? "Your workspace is live. New jobs will land here."
                : range == .unscheduled ? "Jobs without a scheduled time appear here."
                : mine ? "Choose Everyone in the filter to see the whole team's jobs." : "Try another range, or check Jobs for everything open.",
            actionTitle: boardEmpty && session.can("job.create", feature: "jobs") ? "Create your first job" : nil,
            action: { showNew = true }
        )
        .padding(.top, 24)
    }

    /// The next field step for the Next up job, in lifecycle order.
    private func nextStep(for job: Job) -> String? {
        guard session.can("job.edit", feature: "jobs") else { return nil }
        let allowed: [String]
        let status: String
        if let queued = outbox.pendingStatus(for: job.id) {
            // Already queued a step: only offer what the server allowed from that status before.
            status = queued
            allowed = outbox.offlineSteps(from: queued)
        } else if let hero, hero.id == job.id {
            status = hero.status
            allowed = hero.allowedTransitions ?? []
        } else if session.isOffline {
            status = job.status
            allowed = outbox.offlineSteps(from: job.status)
        } else {
            return nil
        }
        // Only ever forward: a job already in progress never offers "Mark arrived" again.
        let order = ["scheduled": 0, "dispatched": 0, "en_route": 1, "arrived": 2, "in_progress": 3, "paused": 3]
        let current = order[status] ?? 0
        return ["en_route", "arrived", "in_progress"].first {
            allowed.contains($0) && (order[$0] ?? 0) > current && !(status == "paused" && $0 == "in_progress")
        }
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
                commitLabel("Mark arrived", symbol: "mappin.and.ellipse", busy: busyJobID == job.id)
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
            }
        }
    }

    /// MA-08: Next up's one commit is ink and 50 tall; pending keeps the words and swaps the mark.
    private func commitLabel(_ title: String, symbol: String, busy: Bool) -> some View {
        HStack(spacing: 7) {
            if busy { ProgressView().tint(Theme.onInk) } else { Image(systemName: symbol) }
            Text(title)
        }
        .inkCommit()
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
        if session.isOffline || !outbox.pending.filter({ $0.jobID == job.id }).isEmpty {
            queue(job, request)
            return
        }
        busyJobID = job.id
        defer { busyJobID = nil }
        do {
            _ = try await api.progressFieldJob(job.id, request: request)
            committed += 1
            await loadHero(job)
            progressError = nil
            if await store.refresh(api) == .failed {
                progressError = "Saved. The latest schedule could not be refreshed."
            }
        } catch is CancellationError {
        } catch {
            if error.isConnectivityFailure { queue(job, request) } else { progressError = error.localizedDescription }
        }
    }

    /// No signal: save the step on the phone; it is sent in order when signal returns.
    private func queue(_ job: Job, _ request: FieldProgressRequest) {
        guard let payload = OutboxEntry.ProgressPayload(jobID: job.id, request: request) else {
            progressError = "That change needs a connection."
            return
        }
        outbox.enqueue(.progress(payload), policyVersion: session.policyVersion ?? 0)
        committed += 1
        progressError = nil
        if !session.isOffline {
            Task {
                await outbox.drain(api: api, useCommandEndpoint: session.isFeatureOn("offline_sync"))
                await store.refresh(api)
            }
        }
    }
}

/// The lead card (Main.dc.html "Next stop"): the time and drive on one line with the status word,
/// then the street large, then the problem and who, then one ink commit with Directions and Call
/// as quiet circles beside it. Away from Today it is "Next up" with the visit's date instead.
private struct ScheduleHero<Commit: View>: View {
    let job: Job
    let customer: String
    var pendingStatus: String? = nil
    var nextStop = false
    var place: NextStopPlace? = nil
    /// The job's street from the list's address book, when the stop itself is not loaded.
    var street: String? = nil
    var etaMinutes: Int? = nil
    @ViewBuilder var commit: () -> Commit
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openURL) private var openURL

    /// Street first; without an address the job's own title leads.
    private var headline: String { place?.firstLine ?? street ?? job.title }
    private var hasStreet: Bool { place?.firstLine != nil || street != nil }
    private var supporting: String { hasStreet ? "\(job.title) · \(customer)" : customer }

    private var when: String {
        guard let date = JobFiltering.date(job.scheduledFor) else { return "No time yet" }
        var text = nextStop ? date.tradeTime : date.visitLabel()
        if let etaMinutes { text += " · \(etaMinutes) min drive" }
        return text
    }

    var body: some View {
        PaperCard(padding: 16) {
            NavigationLink(value: job) {
                VStack(alignment: .leading, spacing: 12) {
                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                                                              : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                    layout {
                        Text(when).font(Theme.font(15, weight: .medium)).monospacedDigit()
                            .foregroundStyle(job.scheduledFor == nil ? Theme.muted : Theme.foreground)
                            .accessibilityIdentifier(etaMinutes != nil ? "next-stop-eta" : "next-stop-time")
                        // Only beside the time: stacked, a spacer would open a gap under it.
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                        StatusWord(jobStatus: pendingStatus ?? job.status, pending: pendingStatus != nil)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(headline).font(Theme.font(24, weight: .medium)).tracking(-0.3)
                            .foregroundStyle(Theme.foreground)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(supporting).font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.leading)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
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
            .accessibilityIdentifier(nextStop ? "next-stop-card" : "schedule-hero")
            // At accessibility sizes the commit takes the full width and the circles sit under it,
            // so its words are never squeezed into a column beside two 50pt circles.
            let actions = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                                                       : AnyLayout(HStackLayout(spacing: 10))
            actions {
                commit().frame(maxWidth: .infinity)
                HStack(spacing: 10) { circles }
            }
            .padding(.top, 16)
        }
    }

    @ViewBuilder private var circles: some View {
        if nextStop, let directions = place?.directions {
            PaperCircleButton(symbol: "arrow.triangle.turn.up.right.diamond", label: "Directions", size: Theme.commitHeight,
                              bordered: true) { openURL(directions) }
                .accessibilityHint("Opens driving directions in Maps")
                .accessibilityIdentifier("next-stop-directions")
        }
        if nextStop, let call = place?.call {
            PaperCircleButton(symbol: "phone", label: "Call \(customer)", size: Theme.commitHeight, bordered: true) { openURL(call) }
                .accessibilityIdentifier("next-stop-call")
        }
    }

    private var accessibilitySummary: String {
        var parts = [headline, job.title == headline ? nil : job.title, customer].compactMap { $0 }
        parts.append(when)
        parts.append((pendingStatus ?? job.status).statusLabel + (pendingStatus != nil ? ", waiting to sync" : ""))
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
    /// Set on a row with no time for someone who may schedule: a trailing Schedule button.
    var schedule: (() -> Void)? = nil
    @Environment(\.paperRowInset) private var inset

    private var leading: PaperRowLeading {
        if timeStyle == .age, let created = JobFiltering.date(job.createdAt) {
            return .text(Self.age(since: created), accessibility: "Waiting since \(created.formatted(date: .abbreviated, time: .omitted))")
        }
        if let date = JobFiltering.date(job.scheduledFor) { return .text(date.tradeTime) }
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


/// Paper 20: every job, grouped by where it stands.
struct JobsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @State private var tab = "Assigned"
    @State private var showDisplay = false
    @State private var scheduling: Job?
    @State private var display = DisplayOptions()
    /// Empty means every status; otherwise only the ticked ones.
    @State private var statusFilter: Set<String> = []
    @State private var showNew = false
    @Environment(\.dynamicTypeSize) private var typeSize

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
                PaperHeader(title: "Jobs", subtitle: subtitle, filter: { showDisplay = true }, filterActive: filterActive)
                OfflineBanner()
                PaperTabs(options: ["Assigned", "All jobs", "Recent"], selection: $tab)
                    .padding(.bottom, filterActive ? 0 : 8)
                if filterActive { filterBar }
                if let error = store.error { ErrorBanner(message: error) { _ = await store.refresh(api) } }
                VStack(alignment: .leading, spacing: 18) {
                    if store.loading && store.jobs.isEmpty {
                        SkeletonRows().padding(.horizontal, -PaperCardMetrics.margin)
                    } else if tab == "Recent" {
                        group("Recently updated", jobs: Array(jobs.prefix(25)), first: true)
                    } else {
                        let groups = [("In progress", PaperWorkGroups.inProgress(jobs)), ("Scheduled", PaperWorkGroups.scheduled(jobs)),
                                      ("Done", PaperWorkGroups.completed(jobs)), ("Other", PaperWorkGroups.other(jobs))]
                        let lead = groups.first { !$0.1.isEmpty }?.0
                        ForEach(groups, id: \.0) { title, members in group(title, jobs: members, first: title == lead) }
                    }
                    if MyDayRules.shouldShowEmptyState(isEmpty: jobs.isEmpty, isLoading: store.loading, hasError: store.error != nil) {
                        PaperEmptyState(
                            symbol: "briefcase",
                            title: filterActive ? "No jobs match these filters" : tab == "Assigned" ? "Nothing assigned to you" : "No jobs yet",
                            message: filterActive ? "Clear the filters to see the whole board." : tab == "Assigned" ? "Jobs dispatched to you appear here. All jobs shows the whole board." : "New jobs appear here as soon as they are created.",
                            actionTitle: session.can("job.create", feature: "jobs") && !filterActive ? "New job" : nil,
                            action: { showNew = true }
                        )
                    }
                }
                .paperCardMargin().padding(.top, 4)
            }
            .padding(.bottom, 24)
        }
        .refreshable { await store.refresh(api) }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if session.can("job.create", feature: "jobs") && !jobs.isEmpty {
                FloatingCreateButton(title: "New job") { showNew = true }
            }
        }
        .sheet(isPresented: $showNew) { NewJobSheet() }
        .sheet(isPresented: $showDisplay) { displaySheet }
        .sheet(item: $scheduling) { QuickScheduleSheet(jobID: $0.id) }
        #if DEBUG
        .onAppear { if PaperPreview.enabled && PaperPreview.screen == "jobs-filters" { showDisplay = true } }
        #endif
    }

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

    /// Ordering, completed work and status: the real ways to narrow the board.
    private var displaySheet: some View {
        ThorbisSheetScaffold(title: "Filters", onClose: { showDisplay = false }) {
            ThorbisSheetGroup {
                ThorbisSheetRow(label: "Ordering", value: display.ordering.label,
                                options: DisplayOptions.Ordering.allCases.map(\.label)) { picked in
                    display.ordering = DisplayOptions.Ordering.allCases.first { $0.label == picked } ?? .recent
                }
                ThorbisSheetDivider()
                ThorbisSheetToggleRow(label: "Show completed", isOn: $display.showCompleted)
            }

            HStack {
                Text("Status").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if filterActive {
                    Button("Reset") { statusFilter = []; display = DisplayOptions() }
                        .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                        .frame(minHeight: 44)
                }
            }
            ThorbisChipGroup(data: statusChips, id: \.self,
                             isOn: { statusFilter.contains($0) },
                             label: { $0.statusLabel }) { status in
                if statusFilter.contains(status) { statusFilter.remove(status) } else { statusFilter.insert(status) }
            }
        }
    }

    /// Who, then when, then "You" when it is yours on a shared board. The status is the row's
    /// word on the right; the job number lives on the job, in search and on long-press.
    private func detail(_ job: Job, customer: String) -> String {
        var parts = [customer]
        if let date = JobFiltering.date(job.scheduledFor), !["completed", "canceled"].contains(job.status) {
            parts.append(date.visitLabel())
        } else if job.scheduledFor == nil, !["completed", "canceled"].contains(job.status) {
            parts.append("No time yet")
        }
        if tab != "Assigned" && job.assignedToUserId != nil && job.assignedToUserId == session.user?.id { parts.append("You") }
        return parts.joined(separator: " · ")
    }

    /// A titled panel of job rows; New job is the bar's +, or the floating pill on iPad.
    @ViewBuilder private func group(_ title: String, jobs: [Job], first: Bool = false) -> some View {
        if !jobs.isEmpty {
            PaperSection(title, count: jobs.count) {
                PaperCardList(data: jobs) { job in
                    let customer = store.customerName(job.customerId)
                    let needsTime = canSchedule && job.scheduledFor == nil && !["completed", "canceled"].contains(job.status)
                        && !ScheduleLead.activeStatuses.contains(job.status)
                    HStack(spacing: 0) {
                        // iPad selects into the detail column beside the list; iPhone pushes.
                        PaperSplitLink(id: job.id, value: job) {
                            // MA-11: what, then who and when, the status as a word.
                            PaperListRow(title: job.title, subtitle: detail(job, customer: customer),
                                         dimmed: job.status == "completed") {
                                if !needsTime { StatusWord(jobStatus: job.status) }
                            }
                        }
                        .buttonStyle(RowPressStyle())
                        .jobContextMenu(job, customer: customer)
                        // No time yet: book it from the row (beside the link, so each is its own target).
                        if needsTime {
                            ScheduleRowButton(job: job) { scheduling = job }.padding(.trailing, PaperCardMetrics.inset)
                        }
                    }
                }
            }
        }
    }
}
