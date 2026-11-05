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

    func roleMembers(requireComplete: Bool = false, whileCurrent: (() -> Bool)? = nil) async throws -> [RoleMember] {
        var items: [RoleMember] = []
        var cursor: String?
        var seen: Set<String> = []
        var pages = 0
        var memberIDs: Set<String> = []
        repeat {
            let page: Items<RoleMember> = try await send("GET", "/v1/organization/role-members", cursor: cursor, requireFresh: requireComplete)
            guard whileCurrent?() ?? true else {
                throw CancellationError()
            }
            pages += 1
            if requireComplete { items += page.items.filter { memberIDs.insert($0.member.memberId).inserted } }
            else { items += page.items }
            if requireComplete && items.count > 1 { return items }
            if let next = page.nextCursor, requireComplete {
                guard pages < 500, seen.insert(next).inserted, items.count < 2_000 else {
                    throw Problem(title: "Incomplete members", status: nil, detail: "Could not check every team member.")
                }
            }
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
    @Environment(\.openURL) private var openURL
    @State private var members: [RoleMember] = []
    @State private var loading = true
    @State private var error: String?
    @State private var search = ""
    @State private var filter = "All"
    @State private var changing: RoleMember?
    @State private var opening: RoleMember?
    @State private var customRoles: [OrganizationRole] = []
    @State private var naming = false
    @State private var newRoleName = ""
    @State private var editingRoleID: String?
    @State private var invitations: [TeamInvitation] = []
    @State private var inviting = false
    @State private var notice: String?
    @State private var removing: RoleMember?
    private var canInvite: Bool { session.can("organization.members.manage") }
    /// Changing someone's access needs both owner capabilities, the same pair the server checks.
    private var canManage: Bool {
        session.can("organization.permissions.manage") && session.can("organization.members.manage")
    }

    private var roles: [String] { ["All"] + Array(Set(members.map(\.roleLabel))).sorted() }
    private var teamSubtitle: String {
        if members.isEmpty { return loading ? "Loading your team…" : "People and what they can do" }
        let pending = canInvite && !invitations.isEmpty ? " · \(invitations.count) invited" : ""
        return "\(members.count) \(members.count == 1 ? "person" : "people")\(pending)"
    }
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
                    // MA-05: large title, one muted subtitle line.
                    Text("Team").font(Theme.font(30, weight: .medium)).tracking(-0.6).accessibilityAddTraits(.isHeader)
                    Text(teamSubtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.gutter).padding(.bottom, 12)
                // v2 List room, like Customers: the role filter is the view bar's text tabs; finding
                // someone is the bar's Search below.
                if roles.count > 2 { ListViewBar(options: roles, selection: $filter) }
                if let error { ErrorBanner(message: error) { await load() } }
                if loading && members.isEmpty { ListRoomSkeleton(count: 6, threeLines: false) }
                if visible.isEmpty && !members.isEmpty {
                    PaperEmptyState(symbol: "magnifyingglass", title: "No one on the team matches",
                                    actionTitle: "Clear search") { search = ""; filter = "All" }
                }
                // Rows on the canvas under a 13 Medium label; space between groups, no lines, no panel.
                if !visible.isEmpty { ListGroupLabel(title: "Members", count: visible.count, first: true) }
                ForEach(visible) { member in
                    let opens = canManage && !member.member.isLegalOwner
                    HStack(alignment: .center, spacing: 0) {
                        Button { if opens { opening = member } } label: {
                            // Role is a plain word at the trailing edge; owner reads by weight, not a tint.
                            TeamRoomRow(title: member.member.displayName, detail: member.member.email) {
                                Text(member.roleLabel)
                                    .font(Theme.font(13, weight: member.member.isLegalOwner ? .medium : .regular))
                                    .foregroundStyle(member.member.isLegalOwner ? Theme.foreground : Theme.muted)
                            }
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(opens ? "Change role" : "")
                        // MA-12: the row's actions behind a Thorbis menu (the Invited rows' •••),
                        // not the stock long-press menu.
                        ThorbisMenu(items: memberActions(member), title: member.member.displayName,
                                    accessibilityLabel: "Actions for \(member.member.displayName)") {
                            // A fixed-size mark inside its 44pt target, so it stays on screen at the largest text.
                            Image(systemName: "ellipsis").font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.muted)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .padding(.trailing, ListRoom.gutter - 14)
                    }
                }
                if canInvite && !invitations.isEmpty {
                    ListGroupLabel(title: "Invited", count: invitations.count)
                    ForEach(invitations) { invitation in
                        HStack(alignment: .center, spacing: 0) {
                            // The email leads, then the role and expiry; "Invited" is the state word that trails.
                            TeamRoomRow(title: invitation.email,
                                        detail: "\(invitation.roleLabel)\(JobFiltering.date(invitation.expiresAt).map { " · expires \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "")") {
                                StatusLabel(tone: .scheduled, word: "Invited", emphasis: .quiet)
                            }
                            .accessibilityElement(children: .combine)
                            ThorbisMenu(items: [
                                ThorbisMenuItem("Cancel invite", role: .destructive) { Task { await cancel(invitation) } }
                            ], accessibilityLabel: "Invite actions") {
                                Image(systemName: "ellipsis").font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.muted)
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .padding(.trailing, ListRoom.gutter - 14)
                        }
                    }
                }
                if canManage {
                    ListGroupLabel(title: "Roles", count: customRoles.count) {
                        Button { newRoleName = ""; naming = true } label: {
                            Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .accessibilityLabel("New role")
                    }
                    ForEach(customRoles) { role in
                        Button { editingRoleID = role.id } label: {
                            TeamRoomRow(title: role.revision.name,
                                        detail: role.revision.description?.isEmpty == false ? role.revision.description : nil,
                                        trailingInset: ListRoom.gutter) { EmptyView() }
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Edit what this role can do")
                    }
                }
                // Only when there is truly no one; a search with no match has its own state above.
                if !loading && members.isEmpty && error == nil {
                    PaperEmptyState(symbol: "person.2", title: "No one on the team",
                                    message: canInvite ? "Bring your techs in. Invite someone." : "Ask an owner to invite your crew.",
                                    actionTitle: canInvite ? "Invite someone" : nil,
                                    action: canInvite ? { inviting = true } as () -> Void : nil)
                }
                Text(canManage ? "Tap a person to change their role or what they can do." : "Ask an owner to change roles.")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity).padding(.top, 20)
            }
            .padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        // Like Invoices and Estimates: the system search field, at the bottom of the screen.
        .searchable(text: $search, prompt: "Search team members")
        .toolbar {
            if canInvite {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    PaperCircleButton(symbol: "person.badge.plus", label: "Invite to team", fill: Theme.card, bordered: true) { inviting = true }
                }
            }
        }
        .sheet(isPresented: $inviting) { SheetSurface {
            InviteMemberSheet { sent in
                notice = sent.delivery == "sent" ? "Invite sent to \(sent.email)." : "Invite created for \(sent.email). Email isn't set up yet, so share the link from the web."
                await load()
            }
        } }
        .safeAreaInset(edge: .top) {
            if let notice {
                Text(notice).font(Theme.font(13)).foregroundStyle(Theme.foreground)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .panelBackground(cornerRadius: Theme.controlRadius)
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
                    .padding(.horizontal, Theme.gutter)
                    .onTapGesture { self.notice = nil }
            }
        }
        .refreshable { await load() }
        .task {
            #if DEBUG
            if PaperPreview.opensSheet("team-invite") { inviting = true }
            #endif
            await load()
        }
        .sheet(item: $changing) { member in SheetSurface {
            MemberRoleSheet(member: member) { await load() }
        } }
        .removeMemberPrompt($removing, onRemoved: { removed in
            notice = "\(removed.member.displayName) was removed from the team."
            await load()
        }, onError: { message in error = message })
        .thorbisDestination(item: $opening) { member in
            MemberAccessView(member: member) { await load() }
        }
        .thorbisDestination(item: $editingRoleID) { id in
            RoleEditorView(roleID: id) { await load() }
        }
        .alert("New role", isPresented: $naming) {
            TextField("Role name", text: $newRoleName, prompt: .placeholder("Role name"))
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
            if canInvite { invitations = (try? await api.pendingInvitations()) ?? invitations }
            error = nil
        } catch is CancellationError {} catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
        }
    }
}

extension TeamView {
    /// What a member's ••• offers: the same four actions the row's long-press used to, under the same checks.
    fileprivate func memberActions(_ member: RoleMember) -> [ThorbisMenuItem] {
        var items = [ThorbisMenuItem("Copy email", icon: "doc.on.doc") { UIPasteboard.general.string = member.member.email }]
        if let mail = URL(string: "mailto:\(member.member.email)") {
            items.append(ThorbisMenuItem("Email", icon: "envelope") { openURL(mail) })
        }
        if canManage && !member.member.isLegalOwner {
            items.append(ThorbisMenuItem("Change role", icon: "person.badge.key") { opening = member })
        }
        if MemberRemovalRules.canRemove(member, session: session) {
            items.append(ThorbisMenuItem("Remove from team", icon: "person.badge.minus", role: .destructive) { removing = member })
        }
        return items
    }

    fileprivate func cancel(_ invitation: TeamInvitation) async {
        do {
            _ = try await api.cancelInvitation(invitation.id)
            invitations.removeAll { $0.id == invitation.id }
        } catch { self.error = error.localizedDescription }
    }

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

/// A row in Team's list room, after `CustomerRoomRow`: the name (15 Medium), then a quieter line
/// that keeps its end ("jorge@acmehvac.com" truncates at the tail, never the middle), and a word at
/// the trailing edge. Stacks at accessibility sizes so nothing is cut.
private struct TeamRoomRow<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    /// Tight where a ••• follows the row; the gutter where nothing does.
    var trailingInset: CGFloat = 4
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                    .lineLimit(stacked ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail).font(Theme.font(14)).foregroundStyle(Theme.subtle)
                        .lineLimit(stacked ? nil : 1).truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing.fixedSize(horizontal: !stacked, vertical: true)
        }
        .padding(.leading, ListRoom.gutter).padding(.trailing, trailingInset).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
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
                if let error { Section { ListErrorRow(message: error) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .overlay(alignment: .top) { if !loaded { SkeletonRows(count: 4, leading: false).background(Theme.canvas) } }
            .navigationTitle("Change role")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ThorbisToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.disabled(busy) } }
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
