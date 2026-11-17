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
struct MemberAccessView: View {
    let member: RoleMember
    let onChanged: () async -> Void
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var removing: RoleMember?
    @State private var transferring: RoleMember?
    @State private var catalog: RoleBuilderCatalog?
    @State private var snapshot: PermissionOverrideSnapshot?
    @State private var choices: [String: Choice] = [:]
    @State private var scopes: [String: String] = [:]
    @State private var changingRole = false
    @State private var busy = false
    @State private var error: String?
    @State private var search = ""
    @State private var key = UUID().uuidString

    enum Choice: String, CaseIterable { case role = "Role", allow = "Allow", never = "Never" }

    private var changed: Bool {
        guard let snapshot else { return false }
        let original = Self.choices(from: snapshot)
        return original.0 != choices.filter { $0.value != .role } || original.1 != scopes.filter { choices[$0.key] == .allow }
    }

    private var firstName: String { member.member.displayName.split(separator: " ").first.map(String.init) ?? "them" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Paper 62B: a 64pt avatar beside the name (28 Bold) and their role.
                HStack(alignment: .center, spacing: 14) {
                    Text(initials(member.member.displayName))
                        .font(Theme.font(22, weight: .semibold)).foregroundStyle(Theme.brandText)
                        .frame(width: 64, height: 64)
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
                .padding(.horizontal, Theme.gutter).padding(.top, 14).padding(.bottom, 16)

                if let mail = URL(string: "mailto:\(member.member.email)") {
                    Button { openURL(mail) } label: { RimmedButtonLabel(title: "Email", symbol: "envelope") }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Email \(member.member.displayName)")
                        .paperCardMargin().padding(.bottom, 16)
                }

                PaperCard {
                    PaperDetailRow("Email", value: member.member.email)
                        .padding(.horizontal, PaperCardMetrics.inset).frame(minHeight: 52)
                    WellDivider()
                    Button { changingRole = true } label: {
                        HStack(spacing: 8) {
                            Text("Permissions").font(Theme.font(16)).foregroundStyle(Theme.foreground)
                            Spacer(minLength: 8)
                            Text(member.roleLabel).font(Theme.font(16)).foregroundStyle(Theme.muted).lineLimit(1)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.muted).accessibilityHidden(true)
                        }
                        .padding(.horizontal, PaperCardMetrics.inset)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityLabel("Role, \(member.roleLabel)")
                    .accessibilityHint("Change role")
                }
                .paperCardMargin()

                if catalog == nil && error == nil {
                    SkeletonRows(count: 6, leading: false).padding(.top, 20)
                } else if !filtered.isEmpty {
                    PaperSection("Just for \(firstName)", count: nil) {
                        ForEach(filtered) { capability in
                            if capability.id != filtered.first?.id { WellDivider() }
                            row(capability)
                                .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                        }
                    }
                    .paperCardMargin().padding(.top, 20)
                    footnote("Role follows their role. Allow adds it for this person. Never blocks it even if their role allows it.")
                }
                if let error { ErrorBanner(message: error).padding(.top, 12) }

                if OwnershipTransferRules.canOffer(member, session: session) {
                    PaperSection("Ownership", count: nil) {
                        Button { transferring = member } label: {
                            Text("Make \(member.member.displayName) the owner")
                                .font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.brandText)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Theme.brandSurface, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressStyle())
                        .padding(PaperCardMetrics.inset - 4)
                    }
                    .paperCardMargin().padding(.top, 20)
                    footnote("Only the owner can hand ownership over. You stay on as an admin, and they can give it back later.")
                }
                if MemberRemovalRules.canRemove(member, session: session) {
                    PaperSection("Remove", count: nil) {
                        Button { removing = member } label: {
                            Text("Remove from team")
                                .font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.destructive)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Theme.destructiveSurface, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressStyle())
                        .padding(PaperCardMetrics.inset - 4)
                    }
                    .paperCardMargin().padding(.top, 20)
                    footnote("They lose access right away. Their account and past work stay, and you can invite them again.")
                }
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
        .sheet(isPresented: $changingRole) { SheetSurface { MemberRoleSheet(member: member) { await onChanged() } } }
        .transferOwnershipPrompt($transferring, onTransferred: {
            await onChanged()
            dismiss()
        }, onError: { message in error = message })
        .removeMemberPrompt($removing, onRemoved: { _ in
            await onChanged()
            dismiss()
        }, onError: { message in error = message })
        .task { await load() }
    }

    private var filtered: [RoleBuilderCatalog.Capability] {
        (catalog?.capabilities ?? []).filter {
            search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search)
        }
        .sorted { (choices[$0.id] ?? .role) != .role && (choices[$1.id] ?? .role) == .role ? true : $0.label < $1.label }
    }

    /// The quiet sentence under a card (Paper 13 muted, 20 from the edge).
    private func footnote(_ text: String) -> some View {
        Text(text).font(Theme.font(13)).foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.gutter).padding(.top, 10)
    }

    @ViewBuilder private func row(_ capability: RoleBuilderCatalog.Capability) -> some View {
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

    private static func choices(from snapshot: PermissionOverrideSnapshot) -> ([String: Choice], [String: String]) {
        var choices: [String: Choice] = [:]
        var scopes: [String: String] = [:]
        guard snapshot.kind == "active", let policy = snapshot.policy else { return ([:], [:]) }
        for grant in policy.grants where grant.effect != "deny" {
            choices[grant.capability] = .allow
            scopes[grant.capability] = grant.scope
        }
        for capability in policy.userDenies { choices[capability] = .never }
        return (choices, scopes)
    }

    private func load() async {
        do {
            async let catalogRequest = api.roleBuilderCatalog()
            async let snapshotRequest = api.memberOverride(member.member.memberId)
            let (loadedCatalog, loadedSnapshot) = try await (catalogRequest, snapshotRequest)
            catalog = loadedCatalog
            snapshot = loadedSnapshot
            (choices, scopes) = Self.choices(from: loadedSnapshot)
            error = nil
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        guard let snapshot else { return }
        busy = true
        defer { busy = false }
        let grants = choices.filter { $0.value == .allow }.keys.sorted()
            .map { RoleGrant(capability: $0, scope: scopes[$0] ?? "organization") }
        let denies = choices.filter { $0.value == .never }.keys.sorted()
        do {
            try await api.saveMemberOverride(member.member.memberId, grants: grants, denies: denies,
                                             expectedVersion: snapshot.expectedVersion, idempotencyKey: key)
            key = UUID().uuidString
            await onChanged()
            dismiss()
        } catch is CancellationError {
        } catch {
            key = UUID().uuidString
            self.error = error.isConnectivityFailure ? "Changing access needs a connection." : error.localizedDescription
        }
    }
}
