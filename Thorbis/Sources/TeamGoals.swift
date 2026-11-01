import SwiftUI

// Settings › Team goals (design.thorbis.com/team-goals TG-07, TG-15..TG-17). One weekly Sold
// amount per role, an optional amount per person that overrides their role's, and the owner's
// leaderboard switch. Each edit is kept on this phone the moment it is made and sent as a patch
// of only what changed, so it works offline and never undoes a teammate's edit to someone else.

/// `GET`/`POST /v1/organization/team-goals` (Thorbis-TanStack composition/team-goals.ts).
/// Money is integer minor units; nil means no goal.
struct TeamGoalsSettings: Codable, Equatable {
    struct Role: Codable, Equatable, Identifiable {
        let roleKey: String
        let name: String
        var weeklySold: Int?
        let people: Int
        var id: String { roleKey }
    }
    struct Person: Codable, Equatable, Identifiable {
        let userId: String
        let displayName: String
        let roleKey: String?
        let roleName: String
        /// Their own amount when it overrides the role's.
        var override: Int?
        /// The goal that applies: override, else role, else nil.
        var weeklySold: Int?
        var id: String { userId }
    }
    let version: Int
    var leaderboardEnabled: Bool
    var roles: [Role]
    var people: [Person]
    let truncated: Bool
}

/// One change to the goals. A later edit to the same role or person replaces the earlier one.
enum TeamGoalEdit: Codable, Equatable {
    case leaderboard(Bool)
    case role(key: String, weeklySold: Int?)
    case person(userId: String, weeklySold: Int?)

    var key: String {
        switch self {
        case .leaderboard: "leaderboard"
        case .role(let key, _): "role:\(key)"
        case .person(let userId, _): "person:\(userId.lowercased())"
        }
    }

    /// The patch body the server applies: only this change (TG-17).
    var body: TeamGoalsPatch {
        switch self {
        case .leaderboard(let on): TeamGoalsPatch(leaderboardEnabled: on)
        case .role(let key, let amount): TeamGoalsPatch(roleGoals: [.init(roleKey: key, weeklySold: amount)])
        case .person(let userId, let amount): TeamGoalsPatch(personGoals: [.init(userId: userId, weeklySold: amount)])
        }
    }
}

struct TeamGoalsPatch: Encodable, Equatable {
    struct RoleGoal: Encodable, Equatable {
        let roleKey: String
        let weeklySold: Int?
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(roleKey, forKey: .roleKey)
            try container.encode(weeklySold, forKey: .weeklySold) // null clears the goal
        }
        enum CodingKeys: String, CodingKey { case roleKey, weeklySold }
    }
    struct PersonGoal: Encodable, Equatable {
        let userId: String
        let weeklySold: Int?
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(userId, forKey: .userId)
            try container.encode(weeklySold, forKey: .weeklySold)
        }
        enum CodingKeys: String, CodingKey { case userId, weeklySold }
    }
    var leaderboardEnabled: Bool? = nil
    var roleGoals: [RoleGoal]? = nil
    var personGoals: [PersonGoal]? = nil
}

extension TeamGoalsSettings {
    /// The screen with an edit applied, so queued edits show as the owner made them.
    func applying(_ edit: TeamGoalEdit) -> TeamGoalsSettings {
        var next = self
        switch edit {
        case .leaderboard(let on):
            next.leaderboardEnabled = on
        case .role(let key, let amount):
            next.roles = roles.map { var role = $0; if role.roleKey == key { role.weeklySold = amount }; return role }
            next.people = people.map { var person = $0; if person.roleKey == key, person.override == nil { person.weeklySold = amount }; return person }
        case .person(let userId, let amount):
            next.people = people.map { person in
                guard person.userId.lowercased() == userId.lowercased() else { return person }
                var changed = person
                changed.override = amount
                changed.weeklySold = amount ?? roles.first { $0.roleKey == person.roleKey }?.weeklySold
                return changed
            }
        }
        return next
    }
}

extension APIClient {
    func teamGoals() async throws -> TeamGoalsSettings {
        try await send("GET", "/v1/organization/team-goals")
    }

    func saveTeamGoals(_ patch: TeamGoalsPatch) async throws -> TeamGoalsSettings {
        try await send("POST", "/v1/organization/team-goals", body: patch)
    }
}

/// Goal edits kept on this phone until the server accepts them, keyed by actor and company so a
/// sign-out or a company switch never sends another person's edit (OF-01, TG-17).
struct PendingTeamGoalEdits {
    private let defaults: UserDefaults
    private let storageKey = "thorbis.pendingTeamGoalEdits.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func scope(_ actorID: String, _ organizationID: String) -> String {
        "\(actorID.lowercased())|\(organizationID.lowercased())"
    }

    private func load() -> [String: [TeamGoalEdit]] {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode([String: [TeamGoalEdit]].self, from: $0) } ?? [:]
    }

    private func store(_ all: [String: [TeamGoalEdit]]) {
        defaults.set(try? JSONEncoder().encode(all), forKey: storageKey)
    }

    func edits(actorID: String, organizationID: String) -> [TeamGoalEdit] {
        load()[scope(actorID, organizationID)] ?? []
    }

    func put(_ edit: TeamGoalEdit, actorID: String, organizationID: String) {
        var all = load()
        let key = scope(actorID, organizationID)
        var list = (all[key] ?? []).filter { $0.key != edit.key }
        list.append(edit)
        all[key] = list
        store(all)
    }

    /// Removes the edit only while it is still the queued one, so a newer edit stays queued.
    func remove(_ edit: TeamGoalEdit, actorID: String, organizationID: String) {
        var all = load()
        let key = scope(actorID, organizationID)
        let list = (all[key] ?? []).filter { $0 != edit }
        all[key] = list.isEmpty ? nil : list
        store(all)
    }

    func clearAll() { defaults.removeObject(forKey: storageKey) }
}

@MainActor
final class TeamGoalsModel: ObservableObject {
    @Published private(set) var screen: TeamGoalsSettings?
    @Published private(set) var waiting: Set<String> = []
    /// Refusals by edit key, shown on the row that was refused.
    @Published private(set) var refused: [String: String] = [:]
    @Published var loadError: String?
    @Published private(set) var asOf: Date?

    private var confirmed: TeamGoalsSettings?
    private var flushing: Task<Void, Never>?
    private let pending: PendingTeamGoalEdits
    private let cacheKey = "thorbis.teamGoals.lastLoaded.v1"

    init(pending: PendingTeamGoalEdits = .init()) { self.pending = pending }

    private struct Cached: Codable { let organizationID: String; let screen: TeamGoalsSettings; let savedAt: Date }

    private func remember(_ screen: TeamGoalsSettings, organizationID: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(
            Cached(organizationID: organizationID.lowercased(), screen: screen, savedAt: Date())), forKey: cacheKey)
    }

    private func cached(_ organizationID: String) -> Cached? {
        UserDefaults.standard.data(forKey: cacheKey)
            .flatMap { try? JSONDecoder().decode(Cached.self, from: $0) }
            .flatMap { $0.organizationID == organizationID.lowercased() ? $0 : nil }
    }

    /// Sends anything queued, then reads the server. Offline it shows the last screen it loaded
    /// with queued edits applied (TG-14, TG-17).
    func load(api: APIClient, actorID: String?, organizationID: String?) async {
        guard let actorID, let organizationID else { return }
        await flush(api: api, actorID: actorID, organizationID: organizationID)
        do {
            let loaded = try await api.teamGoals()
            confirmed = loaded
            asOf = nil
            loadError = nil
            remember(loaded, organizationID: organizationID)
        } catch is CancellationError {
            return
        } catch let problem as Problem where problem.status == 403 {
            loadError = "Team goals are for people who can see the team's numbers. Ask an owner for access."
            screen = nil
            return
        } catch {
            if confirmed == nil, let cached = cached(organizationID) {
                confirmed = cached.screen
                asOf = cached.savedAt
            } else if confirmed == nil {
                loadError = error.localizedDescription
            }
        }
        rebuild(actorID: actorID, organizationID: organizationID)
    }

    /// Applies an edit on screen at once, keeps it on this phone, then tries to send it.
    func edit(_ edit: TeamGoalEdit, api: APIClient, actorID: String?, organizationID: String?) async {
        guard let actorID, let organizationID else { return }
        refused[edit.key] = nil
        pending.put(edit, actorID: actorID, organizationID: organizationID)
        rebuild(actorID: actorID, organizationID: organizationID)
        await flush(api: api, actorID: actorID, organizationID: organizationID)
    }

    private func rebuild(actorID: String, organizationID: String) {
        let queued = pending.edits(actorID: actorID, organizationID: organizationID)
        waiting = Set(queued.map(\.key))
        screen = confirmed.map { base in queued.reduce(base) { $0.applying($1) } }
    }

    func flush(api: APIClient, actorID: String, organizationID: String) async {
        let previous = flushing
        let run = Task { [weak self] in
            await previous?.value
            await self?.sendQueued(api: api, actorID: actorID, organizationID: organizationID)
        }
        flushing = run
        await run.value
    }

    /// Oldest first. A connection failure keeps the rest queued; a refusal drops that edit, puts
    /// the confirmed value back and says why on its row.
    private func sendQueued(api: APIClient, actorID: String, organizationID: String) async {
        for edit in pending.edits(actorID: actorID, organizationID: organizationID) {
            do {
                let saved = try await api.saveTeamGoals(edit.body)
                pending.remove(edit, actorID: actorID, organizationID: organizationID)
                confirmed = saved
                remember(saved, organizationID: organizationID)
            } catch is CancellationError {
                break
            } catch where error.isTransientServerFailure || error.isConnectivityFailure {
                break
            } catch {
                pending.remove(edit, actorID: actorID, organizationID: organizationID)
                refused[edit.key] = error.localizedDescription
            }
        }
        rebuild(actorID: actorID, organizationID: organizationID)
    }
}

enum TeamGoalsCopy {
    static func amount(_ cents: Int?) -> String {
        cents.map { "\(money($0, currency: "USD")) a week" } ?? "No goal"
    }

    static func person(_ person: TeamGoalsSettings.Person) -> String {
        if let own = person.override { return "Own goal · \(money(own, currency: "USD"))" }
        if let role = person.weeklySold { return "Role goal · \(money(role, currency: "USD"))" }
        return "No goal"
    }
}

/// The goal being edited in the sheet.
private struct GoalTarget: Identifiable {
    enum Kind { case role(TeamGoalsSettings.Role), person(TeamGoalsSettings.Person) }
    let kind: Kind
    var id: String {
        switch kind {
        case .role(let role): "role:\(role.roleKey)"
        case .person(let person): "person:\(person.userId)"
        }
    }
}

struct TeamGoalsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @StateObject private var model = TeamGoalsModel()
    @State private var target: GoalTarget?

    private var actor: String? { session.user?.id }
    private var org: String? { session.activeOrganization?.id }

    var body: some View {
        Form {
            if let error = model.loadError {
                Section { InlineProblem(message: error) }
            }
            if let screen = model.screen {
                Section {
                    Toggle(isOn: Binding(get: { screen.leaderboardEnabled }, set: { on in
                        Task { await model.edit(.leaderboard(on), api: api, actorID: actor, organizationID: org) }
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show leaderboard to the team").font(Theme.font(15))
                            status(for: TeamGoalEdit.leaderboard(true).key,
                                   fallback: screen.leaderboardEnabled ? "Ranked by percent of goal. Nobody sees anyone's dollars." : "Off")
                        }
                    }
                    .tint(Theme.markAccent)
                }
                Section {
                    ForEach(screen.roles) { role in
                        Button { target = GoalTarget(kind: .role(role)) } label: {
                            goalRow(title: role.name, detail: "\(role.people) \(role.people == 1 ? "person" : "people")",
                                    value: TeamGoalsCopy.amount(role.weeklySold), key: TeamGoalEdit.role(key: role.roleKey, weeklySold: nil).key)
                        }
                    }
                } header: { Text("Roles") } footer: {
                    Text("Weekly sold goal. A month's goal is the weekly goal times the weeks in it.")
                }
                Section("People") {
                    ForEach(screen.people) { person in
                        Button { target = GoalTarget(kind: .person(person)) } label: {
                            goalRow(title: person.displayName, detail: person.roleName,
                                    value: TeamGoalsCopy.person(person), key: TeamGoalEdit.person(userId: person.userId, weeklySold: nil).key)
                        }
                    }
                }
                if screen.truncated {
                    Section {
                        Label("Showing the first \(screen.people.count) people. Set a role goal to cover everyone else.",
                              systemImage: "person.3")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                }
                if let asOf = model.asOf {
                    Section {
                        Label("As of \(asOf.formatted(date: .omitted, time: .shortened)). Changes send when you're back online.",
                              systemImage: "icloud.and.arrow.up")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                }
            } else if model.loadError == nil {
                Section { SkeletonRows(count: 4, leading: false, inset: 0) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Team goals")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $target) { target in
            GoalSheet(target: target) { edit in
                Task { await model.edit(edit, api: api, actorID: actor, organizationID: org) }
            }
            .presentationDetents([.medium])
        }
        .task(id: session.isOffline) {
            await model.load(api: api, actorID: actor, organizationID: org)
        }
    }

    @ViewBuilder private func status(for key: String, fallback: String) -> some View {
        if let refusal = model.refused[key] {
            Text(refusal).font(Theme.font(13)).foregroundStyle(Theme.destructive)
        } else if model.waiting.contains(key) {
            Text("Waiting to sync").font(Theme.font(13)).foregroundStyle(Theme.muted)
        } else {
            Text(fallback).font(Theme.font(13)).foregroundStyle(Theme.muted)
        }
    }

    private func goalRow(title: String, detail: String, value: String, key: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                status(for: key, fallback: detail)
            }
            Spacer()
            Text(value).font(Theme.font(15)).monospacedDigit().foregroundStyle(value == "No goal" ? Theme.muted : Theme.foreground)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// One money field in a sheet that names the period (TG-16).
private struct GoalSheet: View {
    let target: GoalTarget
    let save: (TeamGoalEdit) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var problem: String?
    @FocusState private var focused: Bool

    private var title: String {
        switch target.kind {
        case .role(let role): role.name
        case .person(let person): person.displayName
        }
    }

    private var current: Int? {
        switch target.kind {
        case .role(let role): role.weeklySold
        case .person(let person): person.override
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("$").foregroundStyle(Theme.muted)
                        TextField("0", text: $text)
                            .keyboardType(.decimalPad)
                            .font(Theme.monoFont(28, weight: .medium))
                            .focused($focused)
                            .accessibilityLabel("Weekly sold goal")
                    }
                    if let problem { InlineProblem(message: problem).font(Theme.font(13)) }
                } header: { Text("Weekly sold goal") } footer: {
                    Text("A week, Monday to Sunday. Leave it empty for no goal.")
                }
                Section {
                    if case .person(let person) = target.kind, person.override != nil {
                        Button("Use role goal") { finish(nil) }
                    } else if current != nil {
                        Button("Remove goal", role: .destructive) { finish(nil) }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ThorbisToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ThorbisToolbarItem(placement: .confirmationAction, prominent: true) { Button("Save") { submit() } }
            }
            .onAppear {
                if let current { text = NSDecimalNumber(decimal: Decimal(current) / 100).stringValue }
                focused = true
            }
        }
    }

    private func submit() {
        let typed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        if typed.isEmpty { return finish(nil) }
        guard let cents = MoneyInput.cents(typed, maximumCents: 1_000_000_000) else {
            problem = "Type an amount like 10000 or 10000.50, up to $10,000,000."
            return
        }
        finish(cents == 0 ? nil : cents)
    }

    private func finish(_ amount: Int?) {
        switch target.kind {
        case .role(let role): save(.role(key: role.roleKey, weeklySold: amount))
        case .person(let person): save(.person(userId: person.userId, weeklySold: amount))
        }
        dismiss()
    }
}
