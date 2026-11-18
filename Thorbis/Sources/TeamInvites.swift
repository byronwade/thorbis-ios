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
            cursor = page.nextCursor
        } while cursor != nil && items.count < 500
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

    /// Paper 62C: one card holding the address and the role (each label small above its answer),
    /// then a quiet note on what happens next. The commit is never pre-disabled.
    var body: some View {
        ThorbisModalSheet(title: "Invite member", onClose: busy ? nil : { dismiss() },
                          commitTitle: "Send invite", commitSymbol: "paperplane", busy: busy,
                          commitIdentifier: "team-invite-send", commit: { Task { await press() } }) {
            VStack(alignment: .leading, spacing: 8) {
                ThorbisSheetGroup {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Email").font(Theme.font(13)).foregroundStyle(Theme.muted).accessibilityHidden(true)
                        TextField("", text: $email, prompt: .placeholder("mike@reyesplumbing.com"))
                            .font(Theme.font(17, weight: .semibold))
                            .keyboardType(.emailAddress).textContentType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($emailFocused)
                            .submitLabel(.send)
                            .onSubmit { Task { await press() } }
                            .onChange(of: email) { _, _ in emailProblem = nil }
                            .accessibilityLabel("Email")
                    }
                    .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    ThorbisSheetDivider()
                    // Paper 14B: the role is chosen on its own sheet, each with what it can do.
                    Button { ThorbisKeyboard.dismiss { pickingRole = true } } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Role").font(Theme.font(13)).foregroundStyle(Theme.muted)
                                Text(roleLabel).font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
                            }
                            Spacer(minLength: 8)
                            PaperIcon(.chevronRight, size: 16, color: Theme.muted).accessibilityHidden(true)
                        }
                        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityLabel("Role, \(roleLabel)")
                    .accessibilityHint("Chooses the role")
                    .accessibilityIdentifier("team-invite-role")
                }
                if let emailProblem { FieldProblem(message: emailProblem).padding(.horizontal, 4) }
                Text("They get an email to join \(companyName) and choose a password. It works for 7 days. You can change the role any time.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            if let error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter) }
        }
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
