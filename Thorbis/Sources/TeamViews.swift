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
    @State private var openingInvite: TeamInvitation?
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
                // Paper 55 / 62: a 34 Bold title (owners see "Team and permissions"), one muted line.
                VStack(alignment: .leading, spacing: 2) {
                    // Paper 62: owners see where this lives ("Business settings") above the title;
                    // the counts sit on the section labels below.
                    if canManage {
                        Text("Business settings").font(Theme.font(15)).foregroundStyle(Theme.muted)
                    }
                    Text(canManage ? "Team and permissions" : "Team")
                        .font(Theme.font(34, weight: .bold)).tracking(-0.85)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                    if !canManage || members.isEmpty {
                        Text(teamSubtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 14).padding(.bottom, 14)
                // Paper 62: the role filter is a segment track 16 from the edges; finding someone is
                // the bar's Search below.
                if roles.count > 2 { PaperTabs(options: roles, selection: $filter) }
                if let error { ErrorBanner(message: error) { await load() }.padding(.top, 12) }
                if loading && members.isEmpty { ListRoomSkeleton(count: 6, threeLines: false) }
                if visible.isEmpty && !members.isEmpty {
                    PaperEmptyState(symbol: "magnifyingglass", title: "No one on the team matches",
                                    actionTitle: "Clear search") { search = ""; filter = "All" }
                }
                // Paper 62: the members on one card, an avatar column, inset hairlines between rows.
                if !visible.isEmpty {
                    PaperSection("Members", count: visible.count) {
                        ForEach(visible) { member in
                            if member.id != visible.first?.id { WellDivider(leading: teamRowTextInset) }
                            memberRow(member)
                        }
                    }
                    .paperCardMargin().padding(.top, 22)
                }
                if canInvite && !invitations.isEmpty {
                    PaperSection("Invited", count: invitations.count) {
                        ForEach(invitations) { invitation in
                            if invitation.id != invitations.first?.id { WellDivider(leading: teamRowTextInset) }
                            invitationRow(invitation)
                        }
                    }
                    .paperCardMargin().padding(.top, 22)
                }
                // Paper 61D: each role with what it is for and how many people have it.
                if canManage {
                    PaperSection("Roles", count: customRoles.count) {
                        ForEach(customRoles) { role in
                            Button { editingRoleID = role.id } label: {
                                TeamRoomRow(title: role.revision.name,
                                            detail: role.revision.description?.isEmpty == false ? role.revision.description : nil,
                                            trailingInset: PaperCardMetrics.inset) {
                                    HStack(spacing: 10) {
                                        Text("\(roleCount(role))").font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
                                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Theme.muted).accessibilityHidden(true)
                                    }
                                }
                            }
                            .buttonStyle(RowPressStyle())
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Edit what this role can do")
                            WellDivider()
                        }
                        Button { newRoleName = ""; naming = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus").font(.system(size: 15, weight: .semibold)).accessibilityHidden(true)
                                Text("New role").font(Theme.font(16, weight: .medium))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(Theme.brandText)
                            .padding(.horizontal, PaperCardMetrics.inset)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityLabel("New role")
                    }
                    .paperCardMargin().padding(.top, 22)
                    Text("Tap a role to choose exactly what it can see and change. The number is how many people have it.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.gutter).padding(.top, 12)
                }
                // Only when there is truly no one; a search with no match has its own state above.
                if !loading && members.isEmpty && error == nil {
                    PaperEmptyState(symbol: "person.2", title: "No one on the team",
                                    message: canInvite ? "Bring your techs in. Invite someone." : "Ask an owner to invite your crew.",
                                    actionTitle: canInvite ? "Invite someone" : nil,
                                    action: canInvite ? { inviting = true } as () -> Void : nil)
                }
                Text(canManage ? "Tap a person to change their role or what they can do." : "Ask an owner to change roles.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.gutter).padding(.top, 12)
            }
            .padding(.bottom, 40)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        // Like Invoices and Estimates: the system search field, at the bottom of the screen.
        .searchable(text: $search, prompt: "Search team members")
        .toolbar {
            if canInvite {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    PaperCircleButton(symbol: "person.badge.plus", label: "Invite to team", size: 44, fill: Theme.card) { inviting = true }
                }
            }
        }
        .thorbisDestination(item: $openingInvite) { invitation in
            TeamInviteDetailView(invitation: invitation) { await load() }
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
    /// Paper 62: avatar, name over email, the role word at the trailing edge (the owner in brand
    /// blue), and the row's ••• for the rest.
    @ViewBuilder fileprivate func memberRow(_ member: RoleMember) -> some View {
        let opens = canManage && !member.member.isLegalOwner
        let owner = member.member.isLegalOwner
        HStack(alignment: .center, spacing: 0) {
            Button { if opens { opening = member } } label: {
                TeamRoomRow(title: member.member.displayName, detail: member.member.email,
                            avatar: TeamRosterAvatar(text: initials(member.member.displayName), style: owner ? .owner : .member)) {
                    Text(member.roleLabel)
                        .font(Theme.font(14, weight: owner ? .semibold : .medium))
                        .foregroundStyle(owner ? Theme.brandText : Theme.subtle)
                }
            }
            .buttonStyle(RowPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint(opens ? "Change role" : "")
            // MA-12: the row's actions behind a Thorbis menu, not the stock long-press menu.
            ThorbisMenu(items: memberActions(member), title: member.member.displayName,
                        accessibilityLabel: "Actions for \(member.member.displayName)") {
                // A fixed-size mark inside its 44pt target, so it stays on screen at the largest text.
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .padding(.trailing, 4)
        }
    }

    /// Paper 62 Invited: a dashed initial, the email, when it was sent, and "Pending" in the warning
    /// tone. Tapping opens the invite (62D).
    @ViewBuilder fileprivate func invitationRow(_ invitation: TeamInvitation) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Button { openingInvite = invitation } label: {
                TeamRoomRow(title: invitation.email, detail: TeamInviteCopy.sentLine(invitation),
                            avatar: TeamRosterAvatar(text: String(invitation.email.prefix(1)).uppercased(), style: .invited)) {
                    Text("Pending").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.warning)
                }
            }
            .buttonStyle(RowPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the invite")
            ThorbisMenu(items: [
                ThorbisMenuItem("Cancel invite", role: .destructive) { Task { await cancel(invitation) } }
            ], accessibilityLabel: "Invite actions") {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .padding(.trailing, 4)
        }
    }

    /// How many people are on this custom role now.
    fileprivate func roleCount(_ role: OrganizationRole) -> Int {
        members.filter { $0.authority.role?.roleId == role.role.id }.count
    }

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

/// Where a team row's words start inside its card: the card inset plus the 44pt avatar column, so
/// the hairline between rows starts under the name (Paper 62).
private let teamRowTextInset: CGFloat = PaperCardMetrics.inset + 44

/// Paper 62's leading mark: initials in a 32pt circle inside a 44pt column. The owner sits on the
/// brand surface, an invite is a dashed ring. Decorative; the name beside it is what is read.
private struct TeamRosterAvatar: View {
    enum Style { case owner, member, invited }
    let text: String
    let style: Style

    var body: some View {
        let ink: Color = style == .owner ? Theme.brandText : (style == .invited ? Theme.muted : Theme.subtle)
        let label = Text(text).font(Theme.font(12, weight: .semibold)).foregroundStyle(ink)
            .frame(width: 32, height: 32)
        Group {
            if style == .invited {
                label.overlay(Circle().strokeBorder(Theme.muted, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
            } else {
                label.background(style == .owner ? Theme.brandSurface : Theme.fill, in: Circle())
            }
        }
        .frame(width: 44, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityHidden(true)
    }
}

/// "Invite sent 2 days ago", from when the invitation was created.
private enum TeamInviteCopy {
    static func sentLine(_ invitation: TeamInvitation) -> String {
        guard let sent = JobFiltering.date(invitation.createdAt) else { return invitation.roleLabel }
        return "Invite sent \(sent.formatted(.relative(presentation: .named)))"
    }

    static func day(_ raw: String) -> String? {
        JobFiltering.date(raw).map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
    }
}

/// A row on Team's cards (Paper 62): an optional avatar column, the name (16 Medium), then a quieter
/// line that keeps its end, and a word at the trailing edge. Stacks at accessibility sizes so
/// nothing is cut.
private struct TeamRoomRow<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    var avatar: TeamRosterAvatar? = nil
    /// Tight where a ••• follows the row; the card inset where nothing does.
    var trailingInset: CGFloat = 4
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                             : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        HStack(alignment: .center, spacing: 0) {
            if let avatar { avatar }
            layout {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(Theme.font(16, weight: .medium)).tracking(-0.16).foregroundStyle(Theme.foreground)
                        .lineLimit(stacked && !Self.isAddress(title) ? nil : Self.isAddress(title) ? 1 : 2)
                        .addressFit(Self.isAddress(title))
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .lineLimit(stacked && !Self.isAddress(detail) ? nil : 1).truncationMode(.tail)
                            .addressFit(Self.isAddress(detail))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing.fixedSize(horizontal: !stacked, vertical: true)
            }
        }
        .padding(.leading, PaperCardMetrics.inset).padding(.trailing, trailingInset).padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// An email address breaks mid-word when it wraps, so it stays on one line and shrinks instead.
    static func isAddress(_ text: String) -> Bool { text.contains("@") && !text.contains(" ") }
}

private extension View {
    @ViewBuilder func addressFit(_ isAddress: Bool) -> some View {
        if isAddress { self.minimumScaleFactor(0.6).truncationMode(.middle) } else { self }
    }
}

/// Paper 62D: one invite that hasn't been accepted. What it is for and where it went, and Revoke.
/// Resend and changing an invite's role have no route yet, so they are not offered.
private struct TeamInviteDetailView: View {
    let invitation: TeamInvitation
    let onChanged: () async -> Void
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRevoke = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    // Paper 62D: the title is 28 Bold.
                    Text(invitation.email)
                        .font(Theme.heading()).tracking(-0.56)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 8) {
                        Text("Invite pending").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.warning)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Theme.warningSurface, in: Capsule())
                        Text(TeamInviteCopy.sentLine(invitation)).font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 14).padding(.bottom, 16)
                PaperCard {
                    detailRow("Role", invitation.roleLabel)
                    WellDivider()
                    detailRow("Sent to", invitation.email)
                    if let expires = TeamInviteCopy.day(invitation.expiresAt) {
                        WellDivider()
                        detailRow("Link works until", expires)
                    }
                }
                .paperCardMargin()
                if let error { ErrorBanner(message: error).padding(.top, 12) }
                Button { confirmRevoke = true } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView() }
                        Text("Revoke invite")
                    }
                    .font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(busy)
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 16)
                Text("Revoking turns off the link right away.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.gutter).padding(.top, 8)
            }
            .padding(.bottom, 32)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .thorbisConfirm("Revoke this invite?", message: "\(invitation.email) won't be able to join with this link.",
                        isPresented: $confirmRevoke,
                        actions: [ThorbisConfirmAction("Revoke invite", role: .destructive) { Task { await revoke() } }])
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        PaperDetailRow(label, value: value)
            .padding(.horizontal, PaperCardMetrics.inset)
            .frame(minHeight: 52)
    }

    private func revoke() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await api.cancelInvitation(invitation.id)
            await onChanged()
            dismiss()
        } catch is CancellationError {
        } catch {
            self.error = error.isConnectivityFailure ? "Revoking an invite needs a connection." : error.localizedDescription
        }
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
