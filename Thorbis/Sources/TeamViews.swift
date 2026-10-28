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
        struct Role: Codable, Hashable { let name: String; let description: String? }
        struct LegalRole: Codable, Hashable { let label: String }
        let kind: String
        let role: Role?
        let roles: [LegalRole]?
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

extension APIClient {
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
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                if !loading && visible.isEmpty && error == nil {
                    PaperEmptyState(symbol: "person.2", title: search.isEmpty ? "No team members" : "No matches", message: "Invite people and change roles from Thorbis on the web.")
                }
                Text("Invite people and change roles from Thorbis on the web.")
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
    }

    private func load() async {
        let generation = session.generation
        loading = true
        defer { loading = false }
        do {
            let loaded = try await api.roleMembers()
            guard session.generation == generation else { return }
            members = loaded
            error = nil
        } catch is CancellationError {} catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
        }
    }
}
