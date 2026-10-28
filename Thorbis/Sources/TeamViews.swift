import SwiftUI

/// `GET /v1/organization/role-members` item (access-control RoleMemberListItem).
struct RoleMember: Codable, Identifiable, Hashable {
    struct Identity: Codable, Hashable {
        struct LegalRole: Codable, Hashable { let id: String; let label: String }
        let memberId: String
        let userId: String
        let displayName: String
        let email: String
        let isLegalOwner: Bool
        let legalMembershipRoles: [LegalRole]
    }
    struct Authority: Codable, Hashable {
        struct Role: Codable, Hashable {
            let name: String
            let description: String?
            var roleId: String? = nil
            var currentRevision: Int? = nil
        }
        struct LegalRole: Codable, Hashable { let label: String }
        let kind: String
        let role: Role?
        let roles: [LegalRole]?
        /// The concurrency version a role change must name.
        var currentAssignmentVersion: Int? = nil
    }
    let member: Identity
    let authority: Authority
    var id: String { member.memberId }

    /// What the office calls this person's access: their custom role, or the built-in one.
    var roleLabel: String {
        if member.isLegalOwner { return "Owner" }
        if authority.kind == "tenant_role", let name = authority.role?.name { return name }
        let labels = (authority.roles?.map(\.label) ?? member.legalMembershipRoles.map(\.label))
        return labels.first ?? "Member"
    }
}

/// One custom role from GET /v1/organization/roles (role plus its current revision).
struct OrganizationRole: Codable, Identifiable, Hashable {
    struct Role: Codable, Hashable { let id: String; let currentRevision: Int }
    struct Revision: Codable, Hashable { let name: String; let description: String? }
    let role: Role
    let revision: Revision
    var id: String { role.id }
}

extension APIClient {
    func organizationRoles() async throws -> [OrganizationRole] {
        let page: Items<OrganizationRole> = try await send("GET", "/v1/organization/roles")
        return page.items.sorted { $0.revision.name.localizedCaseInsensitiveCompare($1.revision.name) == .orderedAscending }
    }

    /// Moves a member onto a custom role. The member comes from the route; the versions make a
    /// change made elsewhere in the meantime fail instead of being overwritten.
    func changeMemberRole(_ member: RoleMember, to role: OrganizationRole, idempotencyKey: String) async throws {
        struct Body: Encodable {
            let desiredRoleId: String
            let expectedVersion: Int
            let expectedRoleRevision: Int
            let idempotencyKey: String
            let reason: String
        }
        let encodedID = member.member.memberId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? member.member.memberId
        let _: EmptyResponse = try await send("POST", "/v1/organization/role-members/\(encodedID)/role",
                                              body: Body(desiredRoleId: role.role.id, expectedVersion: member.authority.currentAssignmentVersion ?? 0,
                                                         expectedRoleRevision: role.role.currentRevision, idempotencyKey: idempotencyKey,
                                                         reason: "Changed in the Thorbis iPhone app"))
    }

    func roleMembers() async throws -> [RoleMember] {
        var items: [RoleMember] = []
        var cursor: String?
        repeat {
            let page: Items<RoleMember> = try await send("GET", "/v1/organization/role-members", cursor: cursor)
            items += page.items
            guard page.nextCursor != cursor else { break }
            cursor = page.nextCursor
        } while cursor != nil && items.count < 2_000
        return items
    }
}

/// Paper 62: everyone in the workspace and the access they have. Changing roles stays on the web for now.
struct TeamView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var members: [RoleMember] = []
    @State private var loading = true
    @State private var error: String?
    @State private var search = ""
    @State private var filter = "All"
    @State private var changing: RoleMember?
    @State private var customRoles: [OrganizationRole] = []
    @State private var naming = false
    @State private var newRoleName = ""
    @State private var editingRoleID: String?
    /// Changing someone's access needs both owner capabilities, the same pair the server checks.
    private var canManage: Bool {
        session.can("organization.permissions.manage") && session.can("organization.members.manage")
    }

    private var roles: [String] { ["All"] + Array(Set(members.map(\.roleLabel))).sorted() }
    private var visible: [RoleMember] {
        members.filter { member in
            (filter == "All" || member.roleLabel == filter) &&
            (search.isEmpty || member.member.displayName.localizedCaseInsensitiveContains(search) || member.member.email.localizedCaseInsensitiveContains(search))
        }
        .sorted { $0.member.displayName.localizedCaseInsensitiveCompare($1.member.displayName) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BUSINESS SETTINGS").font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.muted)
                    Text("Team & permissions").font(Theme.font(26, weight: .semibold)).tracking(-0.39).accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, Theme.gutter).padding(.bottom, 12)
                PaperSearchField(text: $search, prompt: "Search team members")
                if roles.count > 2 { PaperTabs(options: roles, selection: $filter) }
                if let error { ErrorBanner(message: error) }
                if loading && members.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40) }
                VStack(alignment: .leading, spacing: 0) {
                    if !visible.isEmpty { PaperGroupHeader(title: "Members", count: visible.count) }
                    ForEach(visible) { member in
                        Button { if canManage && !member.member.isLegalOwner { changing = member } } label: {
                        HStack(spacing: 12) {
                            Avatar(name: member.member.displayName, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.member.displayName).font(Theme.font(15, weight: .medium)).lineLimit(1)
                                Text(member.member.email).font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(member.roleLabel)
                                .font(Theme.font(12, weight: .medium))
                                .foregroundStyle(member.member.isLegalOwner ? Theme.brandText : Theme.muted)
                                .padding(.horizontal, 9).frame(minHeight: 24)
                                .background(member.member.isLegalOwner ? Theme.brandSurface : Theme.fill, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(canManage && !member.member.isLegalOwner ? "Change role" : "")
                    }
                }
                .padding(.horizontal, Theme.gutter)
                if canManage {
                    VStack(alignment: .leading, spacing: 0) {
                        PaperGroupHeader(title: "Roles", count: customRoles.count) {
                            Button { newRoleName = ""; naming = true } label: {
                                Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .accessibilityLabel("New role")
                        }
                        ForEach(customRoles) { role in
                            Button { editingRoleID = role.id } label: {
                                PaperMenuRow(role.revision.name, symbol: "person.badge.key", subtitle: role.revision.description?.isEmpty == false ? role.revision.description : nil, tile: Theme.markOlive)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.gutter).padding(.top, 16)
                }
                if !loading && visible.isEmpty && error == nil {
                    PaperEmptyState(symbol: "person.2", title: search.isEmpty ? "No team members" : "No matches", message: "Invite people and change roles from Thorbis on the web.")
                }
                Text(canManage ? "Tap a person to change their role. Invite people from Thorbis on the web." : "Invite people and change roles from Thorbis on the web.")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity).padding(.top, 20)
            }
            .padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $changing) { member in
            MemberRoleSheet(member: member) { await load() }
        }
        .navigationDestination(item: $editingRoleID) { id in
            RoleEditorView(roleID: id) { await load() }
        }
        .alert("New role", isPresented: $naming) {
            TextField("Role name", text: $newRoleName)
            Button("Create") { Task { await createRole() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Then choose what this role can do.")
        }
    }

    private func load() async {
        let generation = session.generation
        loading = true
        defer { loading = false }
        do {
            let loaded = try await api.roleMembers()
            guard session.generation == generation else { return }
            members = loaded
            if canManage { customRoles = (try? await api.organizationRoles()) ?? customRoles }
            error = nil
        } catch is CancellationError {} catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
        }
    }
}

extension TeamView {
    fileprivate func createRole() async {
        let trimmed = newRoleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let created = try await api.createOrganizationRole(name: trimmed, description: "", idempotencyKey: UUID().uuidString)
            await load()
            editingRoleID = created.role.id
        } catch { self.error = error.localizedDescription }
    }
}

/// Pick a custom role for one person. Online only; the server rejects a stale change.
struct MemberRoleSheet: View {
    let member: RoleMember
    let onChanged: () async -> Void
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var roles: [OrganizationRole] = []
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var key = UUID().uuidString

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(roles) { role in
                        Button { Task { await choose(role) } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(role.revision.name).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                                    if let detail = role.revision.description, !detail.isEmpty {
                                        Text(detail).font(Theme.font(13)).foregroundStyle(Theme.muted)
                                    }
                                }
                                Spacer()
                                if member.authority.role?.roleId == role.role.id || (member.authority.role?.roleId == nil && member.roleLabel == role.revision.name) {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.brandText)
                                }
                            }
                        }
                        .disabled(busy)
                    }
                } header: {
                    Text(member.member.displayName)
                } footer: {
                    Text(loaded && roles.isEmpty ? "No custom roles yet. Create roles from Thorbis on the web." : "Their access changes as soon as you pick a role.")
                }
                if let error { Section { Text(error).foregroundStyle(Theme.destructive) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .overlay { if !loaded { ProgressView() } }
            .navigationTitle("Change role")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.disabled(busy) } }
            .task {
                do { roles = try await api.organizationRoles() } catch { self.error = error.localizedDescription }
                loaded = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func choose(_ role: OrganizationRole) async {
        busy = true
        defer { busy = false }
        do {
            try await api.changeMemberRole(member, to: role, idempotencyKey: key)
            await onChanged()
            dismiss()
        } catch is CancellationError {
        } catch {
            key = UUID().uuidString
            self.error = error.isConnectivityFailure ? "Changing a role needs a connection." : error.localizedDescription
        }
    }
}
