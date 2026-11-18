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
    @EnvironmentObject private var store: Store
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
    @State private var showingRoles = false
    @State private var showingOwnership = false
    private var canInvite: Bool { session.can("organization.members.manage") }
    /// Changing someone's access needs both owner capabilities, the same pair the server checks.
    private var canManage: Bool {
        session.can("organization.permissions.manage") && session.can("organization.members.manage")
    }

    /// Paper 62: All, then Owner, Office, Technician; any other role follows by name.
    private var roles: [String] {
        let rank = ["Owner": 0, "Office": 1, "Technician": 2]
        let names = Set(members.map(\.roleLabel)).sorted { (rank[$0] ?? 9, $0) < (rank[$1] ?? 9, $1) }
        return ["All"] + names
    }
    /// Paper 55: "Tue, Jul 21 · 5 people". Who is clocked in is not something the app can read
    /// for the whole team, so that part of Paper's line is left out.
    private var teamSubtitle: String {
        if members.isEmpty { return loading ? "Loading…" : "People and what they can do" }
        let date = Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let pending = canInvite && !invitations.isEmpty ? " · \(invitations.count) invited" : ""
        return "\(date) · \(members.count) \(members.count == 1 ? "person" : "people")\(pending)"
    }
    /// Paper 62 lists the owner first, then the office, then the field; names within a role.
    private var visible: [RoleMember] {
        let rank = ["Owner": 0, "Office": 1, "Technician": 2]
        return members.filter { member in
            (filter == "All" || member.roleLabel == filter) &&
            (search.isEmpty || member.member.displayName.localizedCaseInsensitiveContains(search)
                || member.member.email.localizedCaseInsensitiveContains(search)
                || member.roleLabel.localizedCaseInsensitiveContains(search))
        }
        .sorted { left, right in
            let l = rank[left.roleLabel] ?? 9, r = rank[right.roleLabel] ?? 9
            if canManage, l != r { return l < r }
            return left.member.displayName.localizedCaseInsensitiveCompare(right.member.displayName) == .orderedAscending
        }
    }

    /// Paper 55's word at the end of a row, for someone on a job right now: "On site", "Driving".
    /// Anyone else gets no word: the app cannot know they are "In office".
    private func jobWord(_ member: RoleMember) -> StatusWord? {
        let priority = ["in_progress": 0, "arrived": 1, "paused": 2, "en_route": 3]
        guard let job = store.jobs.filter({ $0.assignedToUserId == member.member.userId && priority[$0.status] != nil })
            .min(by: { (priority[$0.status] ?? 9) < (priority[$1.status] ?? 9) }) else { return nil }
        switch job.status {
        case "en_route": return StatusWord(text: "Driving", tint: StatusWord.jobTint("en_route"))
        case "paused": return StatusWord(text: "Paused", tint: StatusWord.jobTint("paused"))
        case "arrived": return StatusWord(text: "On site", tint: StatusWord.jobTint("in_progress"))
        default: return StatusWord(text: "Working", tint: StatusWord.jobTint("in_progress"))
        }
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
                // Paper 55 / 62: the search field under the title; owners then get the role
                // segments (62). Paper 55's Roster / Payroll segments are not drawn: no payroll.
                if !members.isEmpty {
                    DocumentSearchField(text: $search, label: "Search team members")
                    if canManage && roles.count > 2 { PaperTabs(options: roles, selection: $filter).padding(.top, 12) }
                }
                if let error { ErrorBanner(message: error) { await load() }.padding(.top, 12) }
                if loading && members.isEmpty { ListRoomSkeleton(count: 6, threeLines: false) }
                if visible.isEmpty && !members.isEmpty {
                    PaperEmptyState(symbol: "magnifyingglass", title: "No one on the team matches",
                                    actionTitle: "Clear search") { search = ""; filter = "All" }
                }
                // Paper 62: the members on one card, an avatar column, inset hairlines between rows.
                if !visible.isEmpty {
                    PaperSection(canManage ? "Members" : "Full team", count: visible.count) {
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
                // Only when there is truly no one; a search with no match has its own state above.
                if !loading && members.isEmpty && error == nil {
                    PaperEmptyState(symbol: "person.2", title: "No one on the team",
                                    message: canInvite ? "Bring your techs in. Invite someone." : "Ask an owner to invite your crew.",
                                    actionTitle: canInvite ? "Invite someone" : nil,
                                    action: canInvite ? { inviting = true } as () -> Void : nil)
                }
            }
            .padding(.bottom, 40)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        // Paper 62: the invite circle, then ••• for the roles themselves (each role's editor and
        // New role), which used to sit on a card under the members.
        .toolbar {
            if canInvite {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    if canManage {
                        // Paper 62: the person-plus circle on the card tone.
                        PaperCircleButton(symbol: "person.badge.plus", label: "Invite to team", size: 44, fill: Theme.card) { inviting = true }
                    } else {
                        // Paper 55: the blue + circle.
                        Button { inviting = true } label: { CreamCircleLabel(symbol: "plus", ink: true, glyph: .plus) }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel("Invite to team")
                    }
                }
            }
            if canManage {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    ThorbisMenu(items: roleItems, title: "Roles", accessibilityLabel: "Roles") {
                        CreamCircleLabel(symbol: "ellipsis", glyph: .more)
                    }
                    .accessibilityIdentifier("team-roles-menu")
                }
            }
        }
        .thorbisDestination(item: $openingInvite) { invitation in
            TeamInviteDetailView(invitation: invitation) { await load() }
        }
        .sheet(isPresented: $inviting) {
            InviteMemberSheet { sent in
                notice = sent.delivery == "sent" ? "Invite sent to \(sent.email)." : "Invite created for \(sent.email). Email isn't set up yet, so share the link from the web."
                await load()
            }
            // Paper 62C draws the invite as a full page on the app's ground.
            .paperPageGround()
        }
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
            if PaperPreview.opensSheet("team-invite") || PaperPreview.opensSheet("team-role-picker") { inviting = true }
            #endif
            await load()
            #if DEBUG
            // Screenshots of the pushed screens: the first custom role, the first person who is not the owner.
            if PaperPreview.enabled, PaperPreview.screen == "role-editor" { editingRoleID = customRoles.first?.id }
            if PaperPreview.enabled, PaperPreview.screen == "team-roles" { showingRoles = true }
            if PaperPreview.enabled, PaperPreview.screen == "team-ownership" { showingOwnership = true }
            if PaperPreview.enabled, PaperPreview.screen == "team-invite-detail" {
                // Screenshot only: the fixtures carry no pending invite.
                openingInvite = invitations.first ?? TeamInvitation(
                    id: "preview-invite", email: "ana@wadesplumbing.com", role: "apprentice", status: "pending",
                    createdAt: ISO8601DateFormatter().string(from: .now.addingTimeInterval(-86_400)),
                    expiresAt: ISO8601DateFormatter().string(from: .now.addingTimeInterval(6 * 86_400)))
            }
            if PaperPreview.enabled, PaperPreview.screen == "member-offboard" { opening = members.first { !$0.member.isLegalOwner } }
            if PaperPreview.enabled, PaperPreview.screen == "member-access" { opening = members.first { !$0.member.isLegalOwner } }
            #endif
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
        .thorbisDestination(isPresented: $showingOwnership) {
            OwnershipView(members: members) { await load() }
        }
        .thorbisDestination(isPresented: $showingRoles) {
            TeamRolesView(members: members, roles: customRoles) { await load() }
        }
        .thorbisDestination(item: $editingRoleID) { id in
            RoleEditorView(roleID: id, memberCount: customRoles.first { $0.id == id }.map(roleCount)) { await load() }
        }
        .thorbisConfirm("New role", message: "Then choose what this role can do.", isPresented: $naming,
                        reason: ThorbisConfirmReason(label: "Role name", placeholder: "Role name", required: true,
                                                     missingMessage: "Enter a role name.", identifier: "new-role-name"),
                        actionTitle: "Create") { typed in
            newRoleName = typed
            Task { await createRole() }
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
    /// Paper 55 (everyone else): the role under the name, and where they are when on a job.
    /// The row is the control, as in Paper: an owner's tap opens the person (role, permissions,
    /// email, remove); otherwise it opens the person's actions (MA-12: a Thorbis menu).
    @ViewBuilder fileprivate func memberRow(_ member: RoleMember) -> some View {
        let opens = canManage && !member.member.isLegalOwner
        let owner = member.member.isLegalOwner
        let row = TeamRoomRow(title: member.member.displayName, detail: canManage ? member.member.email : member.roleLabel,
                              avatar: TeamRosterAvatar(text: initials(member.member.displayName), style: owner ? .owner : .member),
                              trailingInset: PaperCardMetrics.inset) {
            if canManage {
                Text(member.roleLabel)
                    .font(Theme.font(14, weight: owner ? .semibold : .medium))
                    .foregroundStyle(owner ? Theme.brandText : Theme.subtle)
            } else if let word = jobWord(member) {
                Text(word.text).font(Theme.font(14, weight: .medium)).foregroundStyle(word.tint ?? Theme.subtle)
            }
        }
        if opens {
            Button { opening = member } label: { row }
                .buttonStyle(RowPressStyle())
                .accessibilityElement(children: .combine)
                .accessibilityHint("Change role")
        } else {
            ThorbisMenu(items: memberActions(member), title: member.member.displayName,
                        accessibilityLabel: "\(member.member.displayName), \(member.roleLabel)") { row }
                .accessibilityHint("Shows actions")
        }
    }

    /// Paper 62's •••: the Roles page (Paper 61D, each role into its editor), then New role.
    fileprivate var roleItems: [ThorbisMenuItem] {
        var items = [ThorbisMenuItem("Roles", icon: "person.badge.key", subtitle: "What each role can see and do") { showingRoles = true },
                     ThorbisMenuItem("New role", icon: "plus") { newRoleName = ""; naming = true }]
        // Paper 62A: the owner's page for handing the company over.
        if members.contains(where: { OwnershipTransferRules.canOffer($0, session: session) }) {
            items.append(ThorbisMenuItem("Ownership", icon: "crown", subtitle: "Who owns the company") { showingOwnership = true })
        }
        return items
    }

    /// Paper 62 Invited: a dashed initial, the email, when it was sent, and "Pending" in the warning
    /// tone. Tapping opens the invite (62D).
    @ViewBuilder fileprivate func invitationRow(_ invitation: TeamInvitation) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Button { openingInvite = invitation } label: {
                TeamRoomRow(title: invitation.email, detail: TeamInviteCopy.sentLine(invitation),
                            avatar: TeamRosterAvatar(text: String(invitation.email.prefix(1)).uppercased(), style: .invited),
                            trailingInset: PaperCardMetrics.inset) {
                    Text("Pending").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.warning)
                }
            }
            .buttonStyle(RowPressStyle())
            .accessibilityElement(children: .combine)
            // Paper 62: the row is the control; cancelling is on the invite it opens (62D).
            .accessibilityHint("Opens the invite, where it can be cancelled")
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

    /// Paper 62D: "Sent yesterday". Who sent it is not on the invitation, so the name is left out.
    static func sentShort(_ invitation: TeamInvitation) -> String? {
        JobFiltering.date(invitation.createdAt).map { "Sent \($0.formatted(.relative(presentation: .named)))" }
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
                TeamDetailTitle(title: invitation.email) {
                    HStack(spacing: 8) {
                        Text("Invite pending").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.warning)
                            .padding(.horizontal, 10).frame(minHeight: 24)
                            .background(Theme.warningSurface, in: Capsule())
                        if let sent = TeamInviteCopy.sentShort(invitation) {
                            Text(sent).font(Theme.font(15)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    // Paper 62D: who it is for and how long the link works. Whether the link was
                    // opened is not something the server reports, so the line says what is known.
                    HStack(alignment: .center, spacing: 12) {
                        Text(String(invitation.email.prefix(1)).uppercased())
                            .font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.subtle)
                            .frame(width: 44, height: 44).background(Theme.fill, in: Circle())
                            .dynamicTypeSize(...DynamicTypeSize.large)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Not accepted yet").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                            if let expires = TeamInviteCopy.day(invitation.expiresAt) {
                                Text("Link works until \(expires)").font(Theme.font(14)).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityElement(children: .combine)
                    TeamCard {
                        detailRow("Role", RolePickerSheet.name(for: invitation.role) ?? invitation.roleLabel)
                        WellDivider(leading: 0)
                        detailRow("Sent to", invitation.email)
                    }
                    if let error { ErrorBanner(message: error).padding(.horizontal, -PaperCardMetrics.margin) }
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
                    Text("Revoking turns off the link right away. They won't be told.")
                        .font(Theme.font(13)).foregroundStyle(Theme.subtleForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 16)
            }
            .padding(.bottom, 32)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .thorbisConfirm("Revoke this invite?", message: "\(invitation.email) won't be able to join with this link.",
                        isPresented: $confirmRevoke,
                        actions: [ThorbisConfirmAction("Revoke", role: .destructive) { Task { await revoke() } }])
    }

    /// Paper 62D: the label in ink, its answer in the muted tone, both 16.
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label).font(Theme.font(16)).foregroundStyle(Theme.foreground).fixedSize()
            Text(value).font(Theme.font(16)).foregroundStyle(Theme.muted)
                .lineLimit(1).minimumScaleFactor(0.7).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, PaperCardMetrics.inset)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
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
