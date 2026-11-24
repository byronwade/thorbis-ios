import SwiftUI

// Per-person access on top of their role (GET /v1/organization/permission-overrides/current,
// POST /v1/organization/permission-overrides). Online only; saves name the version they replace.

struct PermissionOverrideSnapshot: Decodable {
    struct Policy: Decodable { let grants: [RoleGrant]; let userDenies: [String] }
    let kind: String
    let expectedVersion: Int
    let policy: Policy?
}

extension APIClient {
    func memberOverride(_ memberID: String) async throws -> PermissionOverrideSnapshot {
        try await send("GET", "/v1/organization/permission-overrides/current",
                       queryItems: [URLQueryItem(name: "targetKind", value: "member"), URLQueryItem(name: "targetId", value: memberID)])
    }

    /// Nil grants and denies together revoke the person's extra access.
    func saveMemberOverride(_ memberID: String, grants: [RoleGrant], denies: [String], expectedVersion: Int,
                            idempotencyKey: String) async throws {
        struct Target: Encodable { let kind = "member"; let memberId: String }
        struct Policy: Encodable { let grants: [RoleGrant]; let userDenies: [String] }
        struct Body: Encodable {
            let target: Target
            let policy: Policy?
            let expectedVersion: Int
            let idempotencyKey: String
            let reason: String
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: Keys.self)
                try c.encode(target, forKey: .target)
                try c.encode(policy, forKey: .policy)  // null revokes
                try c.encode(expectedVersion, forKey: .expectedVersion)
                try c.encode(idempotencyKey, forKey: .idempotencyKey)
                try c.encode(reason, forKey: .reason)
            }
            enum Keys: String, CodingKey { case target, policy, expectedVersion, idempotencyKey, reason }
        }
        let empty = grants.isEmpty && denies.isEmpty
        let _: EmptyResponse = try await send("POST", "/v1/organization/permission-overrides",
                                              body: Body(target: Target(memberId: memberID),
                                                         policy: empty ? nil : Policy(grants: grants, userDenies: denies),
                                                         expectedVersion: expectedVersion, idempotencyKey: idempotencyKey,
                                                         reason: "Changed in the Thorbis iPhone app"))
    }
}

/// One person's access: their role, plus anything allowed or never allowed just for them.
/// Paper 62B "Team member": a 60pt avatar beside the name and role, the ways to reach them, their
/// details, and this week's jobs over the Permissions row. Paper's phone, truck, skills, clock-in
/// line and hours have no source in the app, so they are left out. What used to sit under the card
/// (access just for this person, ownership, removal) is in the ••• menu.
struct MemberAccessView: View {
    let member: RoleMember
    let onChanged: () async -> Void
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var transferring: RoleMember?
    @State private var changingRole = false
    @State private var editingAccess = false
    @State private var offboarding = false
    @State private var error: String?

    private var firstName: String { member.member.displayName.split(separator: " ").first.map(String.init) ?? "them" }

    /// Monday to Friday of this week, each with how many of this person's jobs are booked that day.
    private var week: [(day: Date, count: Int)] {
        let calendar = Calendar.current
        guard let start = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        let mine = store.jobs.filter { $0.assignedToUserId == member.member.userId && $0.status != "cancelled" }
            .compactMap { JobFiltering.date($0.scheduledFor) }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            .filter { !calendar.isDateInWeekend($0) }
            .map { day in (day, mine.filter { calendar.isDate($0, inSameDayAs: day) }.count) }
    }

    private var menuItems: [ThorbisMenuItem] {
        var items = [ThorbisMenuItem("Access just for \(firstName)", icon: "person.badge.key",
                                     subtitle: "Allow or block single permissions") { editingAccess = true }]
        if OwnershipTransferRules.canOffer(member, session: session) {
            items.append(ThorbisMenuItem("Make \(firstName) the owner", icon: "crown") { transferring = member })
        }
        if MemberRemovalRules.canRemove(member, session: session) {
            items.append(ThorbisMenuItem("Offboard", icon: "person.badge.minus", role: .destructive) { offboarding = true })
        }
        return items
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    Text(initials(member.member.displayName))
                        .font(Theme.font(20, weight: .semibold)).foregroundStyle(Theme.brandText)
                        .frame(width: 60, height: 60)
                        .background(Theme.brandSurface, in: Circle())
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.member.displayName)
                            .font(Theme.heading()).tracking(-0.56)
                            .lineLimit(2).minimumScaleFactor(0.6)
                            .accessibilityAddTraits(.isHeader)
                        Text(member.roleLabel).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, PaperHeaderMetrics.titleTopUnderBar)

                // Paper 62B: Message and Call on the card tone. The app knows only their email.
                if let mail = URL(string: "mailto:\(member.member.email)") {
                    Button { openURL(mail) } label: {
                        HStack(spacing: 8) {
                            PaperIcon(.teamEnvelope, size: 18, color: Theme.foreground)
                            Text("Email")
                        }
                        .paperButton(.card, tone: .quiet, fills: true)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Email \(member.member.displayName)")
                    .paperCardMargin().padding(.top, 16)
                }

                PaperRowsCard {
                    HStack(alignment: .center, spacing: 0) {
                        Text("Email").font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .frame(width: 80, alignment: .leading)
                        Text(member.member.email).font(Theme.font(16)).foregroundStyle(Theme.foreground)
                            .lineLimit(1).minimumScaleFactor(0.6).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, PaperCardMetrics.inset)
                    .frame(minHeight: 52)
                    .accessibilityElement(children: .combine)
                }
                .padding(.top, 16)

                PaperCardLabel(title: "This week")
                    .padding(.top, 22)
                PaperRowsCard {
                    if !week.isEmpty {
                        HStack(spacing: 0) {
                            ForEach(week, id: \.day) { item in MemberWeekDay(day: item.day, count: item.count) }
                        }
                        .padding(.vertical, 12).padding(.horizontal, 8)
                        WellDivider(leading: 0)
                    }
                    Button { changingRole = true } label: {
                        HStack(spacing: 6) {
                            Text("Permissions").font(Theme.font(16)).foregroundStyle(Theme.foreground)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(member.roleLabel).font(Theme.font(16)).foregroundStyle(Theme.muted).lineLimit(1)
                            PaperChevron()
                        }
                        .padding(.horizontal, PaperCardMetrics.inset)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityLabel("Permissions, \(member.roleLabel)")
                    .accessibilityHint("Change role")
                }
                if let error { ErrorBanner(message: error).padding(.top, 12) }
            }
            .padding(.bottom, 34)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ThorbisToolbarItem(placement: .topBarTrailing) {
                ThorbisMenu(items: menuItems, title: member.member.displayName, accessibilityLabel: "More for \(member.member.displayName)") {
                    CreamCircleLabel(symbol: "ellipsis", glyph: .more)
                }
                .accessibilityIdentifier("member-more")
            }
        }
        .sheet(isPresented: $changingRole) { SheetSurface { MemberRoleSheet(member: member) { await onChanged() } } }
        .sheet(isPresented: $offboarding) {
            MemberOffboardSheet(member: member) {
                await onChanged()
                dismiss()
            }
        }
        .thorbisDestination(isPresented: $editingAccess) {
            MemberOverridesView(member: member, onChanged: onChanged)
        }
        .transferOwnershipPrompt($transferring, onTransferred: {
            await onChanged()
            dismiss()
        }, onError: { message in error = message })
        .task {
            #if DEBUG
            if PaperPreview.enabled, PaperPreview.screen == "member-offboard" { offboarding = true }
            #endif
        }
    }
}

extension PaperGlyph {
    /// An envelope in Paper's 20-box line weight, beside "Email" where Paper 62B draws Message and Call.
    static let teamEnvelope = PaperGlyph(box: 20, [.rect(3, 4.5, 14, 11, rx: 2, 1.6), .stroke("M3.5 6l6.5 5 6.5-5", 1.6)])
}

/// One day of Paper 62B's week strip: the day (12 Semibold), the count (17 Semibold) and "jobs";
/// today sits on the brand surface.
private struct MemberWeekDay: View {
    let day: Date
    let count: Int

    var body: some View {
        let today = Calendar.current.isDateInToday(day)
        let ink = today ? Theme.brandText : Theme.foreground
        VStack(spacing: 2) {
            Text(today ? "TODAY" : day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(Theme.font(12, weight: .semibold)).foregroundStyle(today ? Theme.brandText : Theme.muted)
            Text("\(count)").font(Theme.font(17, weight: .semibold)).foregroundStyle(ink)
            Text(count == 1 ? "job" : "jobs").font(Theme.font(12)).foregroundStyle(today ? Theme.brandText : Theme.subtleForeground)
        }
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        .background(today ? Theme.brandSurface : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(today ? "Today" : day.formatted(.dateTime.weekday(.wide))), \(count) \(count == 1 ? "job" : "jobs")")
    }
}

/// What the phone may change in one person's extra access, and what a save sends. A save replaces
/// the whole policy, and the phone shows only Role / Allow / Never with a scope, so a permission
/// set on the web (a block, a limit, or more than one grant) is shown locked and sent back exactly
/// as it was loaded. The phone never removes or weakens what it cannot show.
enum MemberOverrideRules {
    enum Choice: String, CaseIterable { case role = "Role", allow = "Allow", never = "Never" }

    /// In place of Role / Allow / Never for a permission set on the web.
    static let lockedNote = "Has a limit or a block set on the web. Change it there."

    /// The loaded policy, split into what the phone edits and what it keeps as it is.
    struct Loaded {
        var choices: [String: Choice] = [:]
        var scopes: [String: String] = [:]
        /// Permissions set on the web: shown locked, never in `choices`.
        var locked: Set<String> = []
        /// Their grants, in the order loaded, and their denies, sent back unchanged.
        var keptGrants: [RoleGrant] = []
        var keptDenies: [String] = []
    }

    /// Permissions with a grant whose effect is deny, a grant with a limit, or more than one grant.
    static func lockedCapabilities(_ policy: PermissionOverrideSnapshot.Policy) -> Set<String> {
        var counts: [String: Int] = [:]
        for grant in policy.grants { counts[grant.capability, default: 0] += 1 }
        return Set(policy.grants.filter { grant in
            grant.effect == "deny" || !(grant.conditions ?? [:]).isEmpty || (counts[grant.capability] ?? 0) > 1
        }.map(\.capability))
    }

    /// An expired or absent override starts empty and keeps nothing.
    static func load(_ snapshot: PermissionOverrideSnapshot) -> Loaded {
        guard snapshot.kind == "active", let policy = snapshot.policy else { return Loaded() }
        var loaded = Loaded(locked: lockedCapabilities(policy))
        for grant in policy.grants {
            if loaded.locked.contains(grant.capability) {
                loaded.keptGrants.append(grant)
            } else {
                loaded.choices[grant.capability] = .allow
                loaded.scopes[grant.capability] = grant.scope
            }
        }
        for capability in policy.userDenies {
            if loaded.locked.contains(capability) { loaded.keptDenies.append(capability) } else { loaded.choices[capability] = .never }
        }
        return loaded
    }

    /// Whether the editable choices differ from what was loaded. Kept permissions never count.
    static func changed(choices: [String: Choice], scopes: [String: String], from loaded: Loaded) -> Bool {
        let now = choices.filter { $0.value != .role && !loaded.locked.contains($0.key) }
        return loaded.choices != now
            || loaded.scopes.filter { loaded.choices[$0.key] == .allow } != scopes.filter { now[$0.key] == .allow }
    }

    /// The complete policy to send: the kept grants then each Allow, and the kept denies with each
    /// Never. Both empty means revoke.
    static func policy(choices: [String: Choice], scopes: [String: String], loaded: Loaded) -> (grants: [RoleGrant], denies: [String]) {
        let editable = choices.filter { !loaded.locked.contains($0.key) }
        let allows = editable.filter { $0.value == .allow }.keys.sorted()
            .map { RoleGrant(capability: $0, scope: scopes[$0] ?? "organization") }
        let nevers = editable.filter { $0.value == .never }.keys.sorted()
        return (loaded.keptGrants + allows, (loaded.keptDenies + nevers).sorted())
    }

    /// The change a retry key belongs to: every grant (capability, scope, effect, limits in key
    /// order), every deny and the version replaced.
    static func changeKey(grants: [RoleGrant], denies: [String], expectedVersion: Int) -> String {
        let grantText = grants.map { grant in
            let limits = (grant.conditions ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";")
            return "\(grant.capability)@\(grant.scope)#\(grant.effect ?? "")[\(limits)]"
        }
        return (grantText + ["|"] + denies + ["|\(expectedVersion)"]).joined(separator: ",")
    }
}

/// Access for one person on top of their role: Role follows the role, Allow adds, Never blocks.
/// Reached from the person's ••• ("Access just for Ramon"). A permission set on the web is shown
/// locked and kept as it is (`MemberOverrideRules`).
struct MemberOverridesView: View {
    let member: RoleMember
    let onChanged: () async -> Void
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var catalog: RoleBuilderCatalog?
    @State private var snapshot: PermissionOverrideSnapshot?
    @State private var loaded = MemberOverrideRules.Loaded()
    @State private var choices: [String: Choice] = [:]
    @State private var scopes: [String: String] = [:]
    @State private var busy = false
    @State private var error: String?
    @State private var search = ""
    @State private var key = RetryKey<String>()

    typealias Choice = MemberOverrideRules.Choice

    private var changed: Bool {
        guard snapshot != nil else { return false }
        return MemberOverrideRules.changed(choices: choices, scopes: scopes, from: loaded)
    }

    private var firstName: String { member.member.displayName.split(separator: " ").first.map(String.init) ?? "them" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TeamDetailTitle(title: "Just for \(firstName)", subtitle: "\(member.roleLabel) · on top of their role")
                if catalog == nil && error == nil {
                    SkeletonRows(count: 6, leading: false).padding(.top, 16)
                } else if !filtered.isEmpty {
                    PaperRowsCard {
                        ForEach(filtered) { capability in
                            if capability.id != filtered.first?.id { WellDivider(leading: PaperCardMetrics.inset) }
                            row(capability)
                                .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                        }
                    }
                    .padding(.top, 16)
                    footnote("Role follows their role. Allow adds it for this person. Never blocks it even if their role allows it.")
                }
                if let error { ErrorBanner(message: error).padding(.top, 12) }
            }
            .padding(.bottom, 32)
        }
        .foregroundStyle(Theme.foreground)
        .searchable(text: $search, prompt: "Find a permission")
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ThorbisToolbarItem(placement: .topBarTrailing) { Button("Save") { Task { await save() } }.disabled(busy || !changed) }
        }
        .task { await load() }
    }

    private var filtered: [RoleBuilderCatalog.Capability] {
        (catalog?.capabilities ?? []).filter {
            search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search)
        }
        // Anything set for this person comes first: a choice made here, or a permission set on the web.
        .sorted { first, second in
            let firstSet = isSet(first.id), secondSet = isSet(second.id)
            return firstSet != secondSet ? firstSet : first.label < second.label
        }
    }

    private func isSet(_ capability: String) -> Bool {
        (choices[capability] ?? .role) != .role || loaded.locked.contains(capability)
    }

    /// The quiet sentence under a card (Paper 13 muted, 20 from the edge).
    private func footnote(_ text: String) -> some View {
        Text(text).font(Theme.font(13)).foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.gutter).padding(.top, 10)
    }

    @ViewBuilder private func row(_ capability: RoleBuilderCatalog.Capability) -> some View {
        if loaded.locked.contains(capability.id) {
            // Set on the web with a limit or a block the phone can't show, so it is not changed here.
            VStack(alignment: .leading, spacing: 2) {
                Text(capability.label).font(Theme.font(16, weight: .medium))
                Text(MemberOverrideRules.lockedNote).font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("member-override-locked-\(capability.id)")
        } else {
            editableRow(capability)
        }
    }

    @ViewBuilder private func editableRow(_ capability: RoleBuilderCatalog.Capability) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(capability.label).font(Theme.font(16, weight: .medium))
            ThorbisSegmented(options: Choice.allCases.map { ($0, $0.rawValue) },
                             selection: Binding(get: { choices[capability.id] ?? .role }, set: { value in
                choices[capability.id] = value
                if value == .allow, scopes[capability.id] == nil { scopes[capability.id] = capability.allowedScopes.first?.id ?? "organization" }
            }))
            if choices[capability.id] == .allow, capability.allowedScopes.count > 1 {
                ThorbisSelect(options: capability.allowedScopes.map { ($0.id, $0.label) },
                              selection: Binding(get: { scopes[capability.id] ?? "" }, set: { scopes[capability.id] = $0 }),
                              label: "Whose")
            }
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        do {
            async let catalogRequest = api.roleBuilderCatalog()
            async let snapshotRequest = api.memberOverride(member.member.memberId)
            let (loadedCatalog, loadedSnapshot) = try await (catalogRequest, snapshotRequest)
            catalog = loadedCatalog
            snapshot = loadedSnapshot
            loaded = MemberOverrideRules.load(loadedSnapshot)
            choices = loaded.choices
            scopes = loaded.scopes
            error = nil
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        guard let snapshot else { return }
        busy = true
        defer { busy = false }
        let (grants, denies) = MemberOverrideRules.policy(choices: choices, scopes: scopes, loaded: loaded)
        let change = MemberOverrideRules.changeKey(grants: grants, denies: denies, expectedVersion: snapshot.expectedVersion)
        do {
            try await api.saveMemberOverride(member.member.memberId, grants: grants, denies: denies,
                                             expectedVersion: snapshot.expectedVersion, idempotencyKey: key.key(for: change))
            key.settle(after: nil)
            await onChanged()
            dismiss()
        } catch is CancellationError {
        } catch {
            key.settle(after: error)
            self.error = error.isConnectivityFailure ? "Changing access needs a connection." : error.localizedDescription
        }
    }
}
