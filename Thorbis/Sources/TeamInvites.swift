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
        ("customer_service", "Customer service"), ("office_manager", "Office manager"), ("admin", "Admin"),
    ]

    var roleLabel: String { Self.roles.first { $0.id == role }?.label ?? role.statusLabel }
}

private struct InvitationPage: Decodable { let items: [TeamInvitation]; let nextCursor: String? }

extension APIClient {
    func pendingInvitations() async throws -> [TeamInvitation] {
        var items: [TeamInvitation] = []
        var cursor: String?
        repeat {
            let page: InvitationPage = try await send("GET", "/v1/organization/invitations",
                                                      queryItems: [URLQueryItem(name: "limit", value: "100")], cursor: cursor)
            items += page.items
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
    @FocusState private var emailFocused: Bool

    private var roles: [(id: String, label: String)] {
        TeamInvitation.roles.filter { $0.id != "admin" || session.can("organization.permissions.manage") }
    }
    private var valid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count <= 254
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($emailFocused)
                        .submitLabel(.send)
                        .onSubmit { if valid { Task { await send() } } }
                    Picker("Role", selection: $role) {
                        ForEach(roles, id: \.id) { Text($0.label).tag($0.id) }
                    }
                } footer: {
                    Text("They get an email to join and choose a password. Invites expire after 7 days.")
                }
                if let error { Section { ListErrorRow(message: error) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Invite to team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button("Send invite") { Task { await send() } }.disabled(!valid) }
                }
            }
            .onAppear { emailFocused = true }
        }
        .presentationDetents([.medium, .large])
        // MA-16: a typed address is not lost to a stray swipe.
        .interactiveDismissDisabled(busy || !email.isEmpty)
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
