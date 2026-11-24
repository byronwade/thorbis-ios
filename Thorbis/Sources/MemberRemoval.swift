import SwiftUI

/// `POST /v1/organization/role-members/{memberId}/remove` (web Team › Remove from team).
/// The person keeps their account and history and can be invited again.
struct MemberRemoval: Decodable, Equatable {
    let memberId: String
    let userId: String
    let removedAt: String
}

extension APIClient {
    func removeMember(_ member: RoleMember, reason: String) async throws -> MemberRemoval {
        struct Body: Encodable { let reason: String }
        let encodedID = try Self.pathSegment(member.member.memberId)
        return try await send("POST", "/v1/organization/role-members/\(encodedID)/remove", body: Body(reason: reason))
    }
}

enum MemberRemovalRules {
    static let defaultReason = "Removed from the team in the Thorbis iPhone app"

    /// Owners and your own membership can't be removed (the server answers 409 for both).
    @MainActor static func canRemove(_ member: RoleMember, session: SessionController) -> Bool {
        session.can("organization.members.manage") && !member.member.isLegalOwner && member.member.userId != session.user?.id
    }

    static func reason(_ typed: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultReason : String(trimmed.prefix(500))
    }

    /// The server's refusals in the office's words.
    static func message(for error: Error, name: String) -> String {
        if error.isConnectivityFailure { return "Removing someone needs a connection." }
        switch (error as? Problem)?.status {
        case 409: return "Owners and your own account can't be removed."
        case 404: return "\(name) is no longer on the team."
        case 403: return "Removing an admin also needs permission to manage access. Ask an owner."
        default: return error.localizedDescription
        }
    }
}

/// Asks first (the person loses access at once), then removes. Used by Team and a person's access screen.
private struct RemoveMemberPrompt: ViewModifier {
    @Binding var member: RoleMember?
    let onRemoved: (RoleMember) async -> Void
    let onError: (String) -> Void
    @EnvironmentObject private var api: APIClient

    func body(content: Content) -> some View {
        // The reason is optional: left empty, `MemberRemovalRules.reason` sends the default.
        content.thorbisConfirm(
            item: $member,
            title: { target in "Remove \(target.member.displayName)?" },
            message: { target in "\(target.member.displayName) loses access to this company right away. Their account and past work stay, and you can invite them again." },
            reason: ThorbisConfirmReason(label: "Reason", placeholder: "Optional",
                                         identifier: "remove-member-reason"),
            actionTitle: "Remove", role: .destructive,
            action: { target, typed in
                Task { await remove(target, typed: typed) }
            }
        )
    }

    private func remove(_ target: RoleMember, typed: String) async {
        do {
            _ = try await api.removeMember(target, reason: MemberRemovalRules.reason(typed))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await onRemoved(target)
        } catch is CancellationError {
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            onError(MemberRemovalRules.message(for: error, name: target.member.displayName))
            if (error as? Problem)?.status == 404 { await onRemoved(target) }
        }
    }
}

extension View {
    func removeMemberPrompt(_ member: Binding<RoleMember?>, onRemoved: @escaping (RoleMember) async -> Void,
                            onError: @escaping (String) -> Void) -> some View {
        modifier(RemoveMemberPrompt(member: member, onRemoved: onRemoved, onError: onError))
    }
}
