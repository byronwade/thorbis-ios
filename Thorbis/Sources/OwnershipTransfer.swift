import SwiftUI

/// `POST /v1/organization/role-members/{memberId}/transfer-ownership` (web Team › member › Ownership).
/// Only the current owner can call it; they stay on as an admin.
struct TransferredOwnership: Decodable, Equatable {
    let previousOwnerMemberId: String
    let newOwnerMemberId: String
    let newOwnerUserId: String
    let transferredAt: String
}

extension APIClient {
    func transferOwnership(to member: RoleMember, reason: String) async throws -> TransferredOwnership {
        struct Body: Encodable { let reason: String }
        let encodedID = member.member.memberId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? member.member.memberId
        return try await send("POST", "/v1/organization/role-members/\(encodedID)/transfer-ownership", body: Body(reason: reason))
    }
}

enum OwnershipTransferRules {
    static let defaultReason = "Handing over the business"

    /// Shown like the web: to whoever can manage access, never for yourself or an existing owner.
    /// The server checks that the caller is the legal owner and answers 403 for everyone else.
    @MainActor static func canOffer(_ member: RoleMember, session: SessionController) -> Bool {
        session.can("organization.permissions.manage") && !member.member.isLegalOwner && member.member.userId != session.user?.id
    }

    static func reason(_ typed: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultReason : String(trimmed.prefix(500))
    }

    static func message(for error: Error, name: String) -> String {
        if error.isConnectivityFailure { return "Handing over ownership needs a connection." }
        switch (error as? Problem)?.status {
        case 403: return "Only the owner can hand over ownership."
        case 409: return "\(name) already owns this company."
        case 404: return "\(name) is no longer on the team."
        default: return error.localizedDescription
        }
    }
}

/// Asks first, since the caller gives up owner access, then transfers and reloads the caller's permissions.
private struct TransferOwnershipPrompt: ViewModifier {
    @Binding var member: RoleMember?
    let onTransferred: () async -> Void
    let onError: (String) -> Void
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var reason = ""

    func body(content: Content) -> some View {
        content.alert(
            member.map { "Make \($0.member.displayName) the owner?" } ?? "Transfer ownership?",
            isPresented: Binding(get: { member != nil }, set: { if !$0 { member = nil; reason = "" } }),
            presenting: member
        ) { target in
            TextField(OwnershipTransferRules.defaultReason, text: $reason)
            Button("Transfer", role: .destructive) {
                let typed = reason
                Task { await transfer(target, typed: typed) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text("\(target.member.displayName) can do everything, including billing and closing the account. You stay on as an admin.")
        }
    }

    private func transfer(_ target: RoleMember, typed: String) async {
        do {
            _ = try await api.transferOwnership(to: target, reason: OwnershipTransferRules.reason(typed))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // Both people's authority changed, the caller's included.
            await session.revalidate()
            await onTransferred()
        } catch is CancellationError {
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            onError(OwnershipTransferRules.message(for: error, name: target.member.displayName))
        }
    }
}

extension View {
    func transferOwnershipPrompt(_ member: Binding<RoleMember?>, onTransferred: @escaping () async -> Void,
                                 onError: @escaping (String) -> Void) -> some View {
        modifier(TransferOwnershipPrompt(member: member, onTransferred: onTransferred, onError: onError))
    }
}
