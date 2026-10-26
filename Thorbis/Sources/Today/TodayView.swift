import SwiftUI
import ThorbisCore

/// The technician's day: what's next, then the agenda by day.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("thorbis.today.scope") private var scope: Scope = .mine

    enum Scope: String, CaseIterable, Identifiable {
        case mine, everyone
        var id: String { rawValue }
        var title: String { self == .mine ? "Mine" : "Everyone" }
    }

    // Until we know who is signed in, "Mine" shows nothing rather than everyone's jobs.
    private var assignee: String? { scope == .mine ? (model.userId ?? "") : nil }
    private var agenda: (days: [AgendaDay], unscheduled: [Job]) { Agenda.build(model.jobs, assignedTo: assignee) }
    private var nextUp: Job? {
        Agenda.nextUp(model.jobs.filter { assignee == nil || $0.assignedToUserId == assignee })
    }

    var body: some View {
        let agenda = agenda
        LoadState(
            isLoading: model.isRefreshing,
            error: model.refreshError,
            isEmpty: model.jobs.isEmpty,
            emptyTitle: "Nothing scheduled",
            emptySymbol: "sun.max",
            emptyMessage: "Jobs assigned to you show up here.",
            retry: { await model.refreshAll() }
        ) {
            List {
                if let error = model.refreshError {
                    InlineError(message: error) { await model.refreshAll() }.sheetRow()
                }
                if let next = nextUp {
                    Section("Next up") {
                        NextUpCard(job: next)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                ForEach(agenda.days) { day in
                    Section(Format.dayTitle(day.day)) {
                        ForEach(day.jobs) { job in
                            NavigationLink(value: Route.job(job.id)) { AgendaRow(job: job) }.sheetRow()
                        }
                    }
                }
                if !agenda.unscheduled.isEmpty {
                    Section("Not on the calendar") {
                        ForEach(agenda.unscheduled) { job in
                            NavigationLink(value: Route.job(job.id)) { JobRow(job: job) }.sheetRow()
                        }
                    }
                }
                if agenda.days.isEmpty, agenda.unscheduled.isEmpty, nextUp == nil {
                    Section {
                        Text(scope == .mine ? "No open jobs are assigned to you." : "No open jobs.")
                            .foregroundStyle(Theme.inkSecondary)
                            .sheetRow()
                    }
                }
            }
            .thorbisList()
        }
        .navigationTitle("Today")
        .refreshable { await model.refreshAll() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Picker("Show", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("today-scope")
            }
            AccountToolbarItem()
        }
    }
}

/// The one job that matters now, with its next step as the commit (Guided profile).
struct NextUpCard: View {
    @Environment(AppModel.self) private var model
    let job: Job
    @State private var busy = false
    @State private var error: String?
    @State private var completed = 0

    private var action: JobAction? {
        JobWorkflow.primaryAction(status: job.status, allowed: job.allowedTransitions ?? JobWorkflow.fallbackTransitions(from: job.status))
    }

    var body: some View {
        SheetCard {
            NavigationLink(value: Route.job(job.id)) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack {
                        StatusBadge(job.status)
                        Spacer()
                        if let at = job.scheduledDate {
                            Text(Format.time(at)).font(.subheadline).monospacedDigit().foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    Text(job.title).font(.title3.weight(.medium)).foregroundStyle(Theme.ink)
                    Text(model.customerName(job.customerId)).font(.body).foregroundStyle(Theme.inkSecondary)
                    if let address = model.customer(job.customerId)?.address {
                        Label(address, systemImage: "mappin").font(.subheadline).foregroundStyle(Theme.inkQuiet)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("next-up")

            if let error { InlineError(message: error) }
            // Completing and resuming need details, so they open on the job itself.
            if let action, action != .complete, action != .resume {
                CommitButton(title: action.title, symbol: action.symbol, busy: busy) { run(action) }
                    .accessibilityIdentifier("next-up-action")
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.xs)
        .sensoryFeedback(.success, trigger: completed)
    }

    private func run(_ action: JobAction) {
        guard case let .progress(target) = action else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                model.store(try await model.api.progress(job.id, to: target))
                completed += 1
            } catch {
                self.error = model.message(for: error)
            }
        }
    }
}

struct AgendaRow: View {
    @Environment(AppModel.self) private var model
    let job: Job

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(job.scheduledDate.map { Format.time($0) } ?? "—")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .frame(minWidth: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                Text(model.customerName(job.customerId)).font(.subheadline).foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: Theme.Space.s)
            StatusBadge(job.status)
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityElement(children: .combine)
    }
}
