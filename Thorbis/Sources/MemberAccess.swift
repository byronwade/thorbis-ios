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
    @Environment(\.dismiss) private var dismiss
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

    var body: some View {
        List {
            Section {
                Button { changingRole = true } label: {
                    HStack {
                        Text("Role").foregroundStyle(Theme.foreground)
                        Spacer()
                        Text(member.roleLabel).foregroundStyle(Theme.muted)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.subtle)
                    }
                }
            } header: {
                Text(member.member.email)
            }
            Section {
                ForEach(filtered) { capability in row(capability) }
            } header: {
                Text("Just for \(member.member.displayName.split(separator: " ").first.map(String.init) ?? "them")")
            } footer: {
                Text("Role follows their role. Allow adds it for this person. Never blocks it even if their role allows it.")
            }
            if let error { Section { ListErrorRow(message: error) } }
        }
        .searchable(text: $search, prompt: "Find a permission")
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .overlay(alignment: .top) { if catalog == nil && error == nil { SkeletonRows(count: 6, leading: false).background(Theme.canvas) } }
        .navigationTitle(member.member.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ThorbisToolbarItem(placement: .topBarTrailing) { Button("Save") { Task { await save() } }.disabled(busy || !changed) }
        }
        .sheet(isPresented: $changingRole) { SheetSurface { MemberRoleSheet(member: member) { await onChanged() } } }
        .task { await load() }
    }

    private var filtered: [RoleBuilderCatalog.Capability] {
        (catalog?.capabilities ?? []).filter {
            search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search)
        }
        .sorted { (choices[$0.id] ?? .role) != .role && (choices[$1.id] ?? .role) == .role ? true : $0.label < $1.label }
    }

    @ViewBuilder private func row(_ capability: RoleBuilderCatalog.Capability) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(capability.label).font(Theme.font(15, weight: .medium))
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
