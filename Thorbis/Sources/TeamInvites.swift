import SwiftUI

// Team invitations (GET/POST /v1/organization/invitations, POST .../{id}/cancel).
// Needs organization.members.manage; the invitee accepts from the email on the web.

struct TeamInvitation: Codable, Identifiable, Hashable {
    let id: String
    let email: String
    let role: String
    let status: String
    let createdAt: String
    let expiresAt: String
    var delivery: String? = nil

    static let roles: [(id: String, label: String)] = [
        ("technician", "Technician"), ("apprentice", "Apprentice"), ("dispatcher", "Dispatcher"),
        ("csr", "Customer service"), ("office_manager", "Office manager"), ("accountant", "Accountant"),
        ("admin", "Admin"),
    ]

    /// The server's role ids (packages/permissions ROLE_IDS). An invite sent as "customer_service"
    /// was refused; older rows may still carry it, so it keeps its label.
    var roleLabel: String {
        if role == "customer_service" { return "Customer service" }
        return Self.roles.first { $0.id == role }?.label ?? role.statusLabel
    }
}

private struct InvitationPage: Decodable { let items: [TeamInvitation]; let nextCursor: String? }

extension APIClient {
    func pendingInvitations(requireComplete: Bool = false, whileCurrent: (() -> Bool)? = nil) async throws -> [TeamInvitation] {
        var items: [TeamInvitation] = []
        var cursor: String?
        var seen: Set<String> = []
        var pages = 0
        repeat {
            let page: InvitationPage = try await send("GET", "/v1/organization/invitations",
                                                      queryItems: [URLQueryItem(name: "limit", value: "100")], cursor: cursor, requireFresh: requireComplete)
            guard whileCurrent?() ?? true else {
                throw CancellationError()
            }
            pages += 1
            items += requireComplete ? page.items.filter { $0.status == "pending" } : page.items
            if requireComplete && !items.isEmpty { return items }
            if let next = page.nextCursor, requireComplete {
                guard pages < 500, seen.insert(next).inserted, items.count < 500 else {
                    throw Problem(title: "Incomplete invitations", status: nil, detail: "Could not check every invitation.")
                }
            }
            guard page.nextCursor != cursor else { break }
            // A cursor seen before means the server is going in circles; stop with what we have.
            if let next = page.nextCursor, !requireComplete, !seen.insert(next).inserted { break }
            cursor = page.nextCursor
        } while cursor != nil && items.count < 500 && pages < 500
        return items
    }

    func invite(email: String, role: String) async throws -> TeamInvitation {
        struct Body: Encodable { let email: String; let role: String }
        return try await send("POST", "/v1/organization/invitations", body: Body(email: email, role: role))
    }

    func cancelInvitation(_ id: String) async throws -> TeamInvitation {
        guard let safe = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) else {
            throw Problem(title: "Invalid invitation ID", status: nil, detail: id)
        }
        return try await send("POST", "/v1/organization/invitations/\(safe)/cancel")
    }
}

/// Invite someone by email with a starting role. Admin needs both owner capabilities.
struct InviteMemberSheet: View {
    let onSent: (TeamInvitation) async -> Void
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var role = "technician"
    @State private var busy = false
    @State private var error: String?
    @State private var emailProblem: String?
    @FocusState private var emailFocused: Bool

    private var roles: [(id: String, label: String)] {
        TeamInvitation.roles.filter { $0.id != "admin" || session.can("organization.permissions.manage") }
    }
    private var valid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count <= 254
    }

    private var roleLabel: String {
        RolePickerSheet.name(for: role) ?? roles.first { $0.id == role }?.label ?? role.statusLabel
    }
    @State private var pickingRole = false
    private var companyName: String { session.activeOrganization?.name ?? "your company" }

    private var roleDetail: String? {
        RolePickerSheet.roles.first { $0.serverID == role }?.detail
    }

    /// Paper 62C: Cancel, the title and the blue "Send invite" pill over two cards: who it goes to
    /// (the server invites by email only, so Paper's name and mobile fields are left out), then
    /// the role with what it can do and how the invite is sent. The commit is never pre-disabled.
    var body: some View {
        VStack(spacing: 0) {
            PaperTaskBar(title: "Invite member", cancelDisabled: busy,
                         commit: ThorbisSheetHeaderAction(title: "Send invite", busy: busy, identifier: "team-invite-send") {
                             Task { await press() }
                         }) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TeamCard {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Email").font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
                            TextField("", text: $email, prompt: .placeholder("mike@reyesplumbing.com"))
                                .font(Theme.font(17, weight: .medium))
                                .keyboardType(.emailAddress).textContentType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($emailFocused)
                                .submitLabel(.send)
                                .onSubmit { Task { await press() } }
                                .onChange(of: email) { _, _ in emailProblem = nil }
                                .accessibilityLabel("Email")
                        }
                        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let emailProblem { FieldProblem(message: emailProblem).padding(.horizontal, 4) }
                    TeamCard {
                        // Paper 14B: the role is chosen on its own sheet, each with what it can do.
                        Button { ThorbisKeyboard.dismiss { pickingRole = true } } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Role").font(Theme.font(13)).foregroundStyle(Theme.muted)
                                    Text(roleLabel).font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.foreground)
                                    if let roleDetail {
                                        Text(roleDetail).font(Theme.font(14)).foregroundStyle(Theme.muted)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                PaperIcon(.chevronRight, size: 16, color: Theme.muted).accessibilityHidden(true)
                            }
                            .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityLabel("Role, \(roleLabel)")
                        .accessibilityHint("Chooses the role")
                        .accessibilityIdentifier("team-invite-role")
                        WellDivider(leading: 0)
                        HStack(spacing: 8) {
                            Text("Send invite by").font(Theme.font(16)).foregroundStyle(Theme.foreground)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Email").font(Theme.font(16)).foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, PaperCardMetrics.inset)
                        .frame(minHeight: 56)
                        .accessibilityElement(children: .combine)
                    }
                    Text("They get a link to join \(companyName). It works for 7 days. You can change the role any time.")
                        .font(Theme.font(13)).foregroundStyle(Theme.subtleForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    if let error { ErrorBanner(message: error).padding(.horizontal, -PaperCardMetrics.margin) }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 20).padding(.bottom, 24)
            }
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .presentationDetents([.large])
        .onAppear {
            emailFocused = true
            #if DEBUG
            if PaperPreview.opensSheet("team-role-picker") { emailFocused = false; pickingRole = true }
            #endif
        }
        .sheet(isPresented: $pickingRole) {
            RolePickerSheet(current: role, allowed: Set(roles.map(\.id))) { role = $0 }
        }
        // MA-16: a typed address is not lost to a stray swipe.
        .interactiveDismissDisabled(busy || !email.isEmpty)
    }

    /// Validate on commit: say what's wrong under the email instead of locking Send.
    private func press() async {
        guard valid else {
            emailProblem = email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Add their email, like mike@reyesplumbing.com." : "Check the email address, like mike@reyesplumbing.com."
            return
        }
        await send()
    }

    private func send() async {
        // Return and the bar button both land here; one invite per press.
        guard !busy, valid else { return }
        busy = true
        defer { busy = false }
        do {
            let invitation = try await api.invite(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), role: role)
            await onSent(invitation)
            dismiss()
        } catch is CancellationError {
        } catch let problem as Problem where problem.status == 409 {
            error = "That email already belongs to someone on the team or has an open invite."
        } catch {
            self.error = error.isConnectivityFailure ? "Inviting needs a connection." : error.localizedDescription
        }
    }
}
