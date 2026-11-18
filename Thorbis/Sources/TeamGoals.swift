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

    /// This week's numbers for the people the viewer may see (`GET /v1/reports/scorecard`). Nil
    /// offline or when the read is refused: the page then shows the goals without the standings.
    @State private var card: Scorecard?

    /// Paper 91: "This week · Jul 20 – 26".
    private var weekLine: String {
        let start = ScorecardPeriod.week.range(now: .now).from
        guard let end = Calendar.current.date(byAdding: .day, value: 6, to: start) else { return "This week" }
        let sameMonth = Calendar.current.component(.month, from: start) == Calendar.current.component(.month, from: end)
        let last = sameMonth ? end.formatted(.dateTime.day()) : end.formatted(.dateTime.month(.abbreviated).day())
        return "This week \u{00B7} \(start.formatted(.dateTime.month(.abbreviated).day())) \u{2013} \(last)"
    }

    /// A person on the leaderboard: their goal settings with this week's numbers when known.
    private struct Standing: Identifiable {
        let person: TeamGoalsSettings.Person
        let numbers: Scorecard.Person?
        var id: String { person.userId }
    }

    /// Most sold first; people whose numbers aren't known follow by name.
    private func standings(_ screen: TeamGoalsSettings) -> [Standing] {
        let numbers = Dictionary((card?.people ?? []).map { ($0.userId, $0) }, uniquingKeysWith: { first, _ in first })
        return screen.people.map { Standing(person: $0, numbers: numbers[$0.userId]) }.sorted { first, second in
            let a = first.numbers?.sold ?? -1, b = second.numbers?.sold ?? -1
            if a != b { return a > b }
            return first.person.displayName.localizedStandardCompare(second.person.displayName) == .orderedAscending
        }
    }

    private func whole(_ cents: Int, currency: String) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: currency).precision(.fractionLength(0)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Paper 91: the title in 34 Bold with the week under it.
                PaperHeader(title: "Team goals", subtitle: weekLine)
                    .environment(\.paperMenuButton, false)
                    .environment(\.paperDrawer, nil)

                if let error = model.loadError {
                    InlineProblem(message: error).padding(.horizontal, Theme.gutter).padding(.bottom, 12)
                }
                if let screen = model.screen {
                    VStack(alignment: .leading, spacing: 0) {
                        if let card { hero(card) }
                        // Paper 91's Leaderboard: rank, initials, the name over jobs done and the
                        // goal that applies, and what they sold. A row opens that person's goal.
                        label("Leaderboard", top: card == nil ? 0 : 22)
                        let rows = standings(screen)
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                Button { target = GoalTarget(kind: .person(row.person)) } label: {
                                    standingRow(row, rank: row.numbers?.sold == nil ? nil : index + 1,
                                                divider: index > 0, currency: card?.currency ?? "USD")
                                }
                                .buttonStyle(RowPressStyle())
                                .accessibilityHint("Sets this person's weekly goal")
                            }
                        }
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        if screen.truncated {
                            footnote("Showing the first \(screen.people.count) people. Set a role goal to cover everyone else.")
                        }

                        label("Role goals", top: 22)
                        VStack(spacing: 0) {
                            ForEach(screen.roles) { role in
                                if role.id != screen.roles.first?.id { WellDivider(leading: 16) }
                                Button { target = GoalTarget(kind: .role(role)) } label: {
                                    goalRow(title: role.name, detail: "\(role.people) \(role.people == 1 ? "person" : "people")",
                                            value: TeamGoalsCopy.amount(role.weeklySold), key: TeamGoalEdit.role(key: role.roleKey, weeklySold: nil).key)
                                }
                                .buttonStyle(RowPressStyle())
                            }
                            if !screen.roles.isEmpty { WellDivider(leading: 16) }
                            Toggle(isOn: Binding(get: { screen.leaderboardEnabled }, set: { on in
                                Task { await model.edit(.leaderboard(on), api: api, actorID: actor, organizationID: org) }
                            })) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("Show leaderboard to the team").font(Theme.font(16, weight: .medium)).tracking(-0.16)
                                    status(for: TeamGoalEdit.leaderboard(true).key,
                                           fallback: screen.leaderboardEnabled ? "Ranked by percent of goal. Nobody sees anyone's dollars." : "Off")
                                }
                            }
                            .tint(Theme.brand)
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .frame(minHeight: 56)
                        }
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        footnote("Weekly sold goal. A month's goal is the weekly goal times the weeks in it.")
                        if let asOf = model.asOf {
                            footnote("As of \(asOf.formatted(date: .omitted, time: .shortened)). Changes send when you're back online.")
                        }
                    }
                    .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 6)
                } else if model.loadError == nil {
                    SkeletonRows(count: 4, leading: false)
                }
            }
            .padding(.bottom, 32)
        }
        .task(id: "card|\(session.generation)|\(session.isOffline)") {
            guard !session.isOffline else { return }
            let generation = session.generation
            let value = try? await api.scorecard(.week)
            guard session.generation == generation, !Task.isCancelled else { return }
            if let value { card = value }
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $target) { target in
            GoalSheet(target: target) { edit in
                Task { await model.edit(edit, api: api, actorID: actor, organizationID: org) }
            }
        }
        .task(id: session.isOffline) {
            await model.load(api: api, actorID: actor, organizationID: org)
        }
    }

    @ViewBuilder private func status(for key: String, fallback: String) -> some View {
        if let refusal = model.refused[key] {
            Text(refusal).font(Theme.font(14)).foregroundStyle(Theme.destructive)
        } else if model.waiting.contains(key) {
            Text("Waiting to sync").font(Theme.font(14)).foregroundStyle(Theme.muted)
        } else {
            Text(fallback).font(Theme.font(14)).foregroundStyle(Theme.muted)
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text).font(Theme.font(13)).foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4).padding(.top, 10)
    }

    private func label(_ title: String, top: CGFloat) -> some View {
        Text(title).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 4).padding(.top, top).padding(.bottom, 8)
    }

    /// Paper 91's hero: "Revenue" over the week's sold in 44 Bold with "of $25,000", an 8pt bar,
    /// then "74% of goal" and what is left. The goal is the sum of the goals that apply to the
    /// people counted; without one the card is the figure alone.
    @ViewBuilder private func hero(_ card: Scorecard) -> some View {
        let counted = card.people.filter { $0.sold != nil }
        if !counted.isEmpty {
            let sold = counted.reduce(0) { $0 + ($1.sold ?? 0) }
            let goal = counted.reduce(0) { $0 + ($1.goal ?? 0) }
            let fraction = goal > 0 ? min(1, max(0, Double(sold) / Double(goal))) : 0
            VStack(alignment: .leading, spacing: 4) {
                Text("Revenue").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { heroFigure(sold, goal: goal, currency: card.currency) }
                    VStack(alignment: .leading, spacing: 0) { heroFigure(sold, goal: goal, currency: card.currency) }
                }
                if goal > 0 {
                    GeometryReader { proxy in
                        Capsule().fill(Theme.brand).frame(width: (proxy.size.width * fraction).rounded())
                    }
                    .frame(height: 8)
                    .background(Theme.quietFill, in: Capsule())
                    .padding(.top, 10).padding(.bottom, 6)
                    .accessibilityHidden(true)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(sold * 100 / goal)% of goal").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(sold >= goal ? "Goal met" : "\(whole(goal - sold, currency: card.currency)) to go")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func heroFigure(_ sold: Int, goal: Int, currency: String) -> some View {
        Text(whole(sold, currency: currency)).font(Theme.font(44, weight: .bold)).tracking(-1.32)
            .foregroundStyle(Theme.foreground).lineLimit(1).minimumScaleFactor(0.6)
        if goal > 0 {
            Text("of \(whole(goal, currency: currency))").font(Theme.font(15)).foregroundStyle(Theme.muted)
        }
    }

    /// Paper 91's leaderboard row: the rank in a 16pt slot, 36pt initials, the name in 16 Medium
    /// over one 14 muted line, the week's sold in 16 Semibold. The viewer's own row is tinted.
    private func standingRow(_ row: Standing, rank: Int?, divider: Bool, currency: String) -> some View {
        let me = row.person.userId == (card?.me.userId ?? session.user?.id)
        let jobs = row.numbers.map { "\($0.jobsDone) job\($0.jobsDone == 1 ? "" : "s")" }
        let key = TeamGoalEdit.person(userId: row.person.userId, weeklySold: nil).key
        let goal = row.person.override.map { "Own goal \(whole($0, currency: currency))" }
            ?? row.person.weeklySold.map { "Role goal \(whole($0, currency: currency))" } ?? "No goal"
        let detail = [jobs, goal].compactMap { $0 }.joined(separator: " \u{00B7} ")
        return HStack(alignment: .center, spacing: 12) {
            Text(rank.map(String.init) ?? "").font(Theme.font(15, weight: .semibold))
                .foregroundStyle(me ? Theme.brandText : Theme.muted)
                .frame(width: 16)
            Text(Self.initials(row.person.displayName)).font(Theme.font(13, weight: .semibold))
                .foregroundStyle(me ? Theme.brandText : Theme.foreground)
                .frame(width: 36, height: 36)
                .background(me ? Theme.brandSurface : Theme.quietFill, in: Circle())
                .accessibilityHidden(true)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    (Text(row.person.displayName).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                     + Text(me ? " \u{00B7} You" : "").font(Theme.font(16)).foregroundStyle(Theme.muted))
                        .tracking(-0.16)
                        .fixedSize(horizontal: false, vertical: true)
                    status(for: key, fallback: detail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let sold = row.numbers?.sold {
                    Text(whole(sold, currency: currency)).font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                }
            }
            .padding(.vertical, 11).padding(.trailing, 16)
            .overlay(alignment: .top) { if divider && !me { WellDivider(leading: 0) } }
        }
        .padding(.leading, 16)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(me ? Theme.brand.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private static func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    /// A role's row: the name in 16 Medium, its line under it, the goal at the trailing edge.
    private func goalRow(title: String, detail: String, value: String, key: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.font(16, weight: .medium)).tracking(-0.16).foregroundStyle(Theme.foreground)
                status(for: key, fallback: detail)
            }
            Spacer(minLength: 8)
            Text(value).font(Theme.font(16, weight: .semibold))
                .foregroundStyle(value == "No goal" ? Theme.muted : Theme.foreground)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
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
        // Paper's sheet: the 22 Bold title, one filled money field under its label, the blue pill
        // commit with Cancel under it. No stock form, bar or grouped list.
        ThorbisModalSheet(title: title, closeLabel: "Cancel", onClose: { dismiss() },
                          commitTitle: "Save", commitIdentifier: "team-goal-save", commit: { submit() },
                          onKeyboardDone: { focused = false }) {
            FormField(label: "Weekly sold goal", help: "A week, Monday to Sunday. Leave it empty for no goal.",
                      error: problem) {
                MoneyFieldWell {
                    TextField("", text: $text, prompt: .placeholder("0"))
                        .font(Theme.monoFont(16))
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .onChange(of: text) { _, _ in problem = nil }
                        .accessibilityLabel("Weekly sold goal")
                }
            }
            if case .person(let person) = target.kind, person.override != nil {
                Button { finish(nil) } label: {
                    RimmedButtonLabel(title: "Use role goal", symbol: "arrow.uturn.backward")
                }
                .buttonStyle(PressStyle())
            } else if current != nil {
                Button { finish(nil) } label: {
                    Text("Remove goal").font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.destructive)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .onAppear {
            if let current { text = NSDecimalNumber(decimal: Decimal(current) / 100).stringValue }
            focused = true
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
