import SwiftUI
import UIKit

// MARK: - Account and data (Paper v2: 67 Account and data, 68 Delete account — confirm)
//
// App Store rule 5.1.1(v): an app that lets people sign up lets them start deleting the account in
// the app. The request goes to the canonical API (POST /v1/account-lifecycle/deletion-requests);
// the phone holds no deletion rules of its own. The server requires a recent re-authentication
// proof for the request; until it issues one, it refuses and the sheet says so plainly.

/// GET /v1/account-lifecycle/deletion-requests/current. Only the fields the screen shows.
struct AccountDeletionStatus: Decodable, Equatable {
    struct Request: Decodable, Equatable {
        let id: String
        let status: String?
        let requestedAt: String?
    }
    let request: Request?
}

struct AccountDeletionRequestBody: Encodable {
    let reauthenticationId: String
    let reason = "self_service_account_deletion"
}

extension APIClient {
    /// The person's open deletion request, if any. A missing route or no request reads as none.
    func currentAccountDeletion() async -> AccountDeletionStatus? {
        try? await send("GET", "/v1/account-lifecycle/deletion-requests/current") as AccountDeletionStatus
    }

    func requestAccountDeletion(reauthenticationID: String) async throws -> AccountDeletionStatus.Request {
        try await send("POST", "/v1/account-lifecycle/deletion-requests",
                       body: AccountDeletionRequestBody(reauthenticationId: reauthenticationID))
    }
}

/// What the confirm sheet says after the server answers. Pure, so the words are unit-tested.
enum AccountDeletionOutcome: Equatable {
    case requested
    /// The server wants a fresh sign-in check it cannot take from the phone yet.
    case needsSignInCheck
    case failed(String)

    init(status: Int?, detail: String?) {
        switch status {
        case 409: self = .needsSignInCheck
        default: self = .failed(detail ?? "Your account wasn't deleted. Try again.")
        }
    }

    var message: String? {
        switch self {
        case .requested: nil
        case .needsSignInCheck:
            "Deleting needs a fresh sign-in check that isn't switched on for your account yet. Nothing was deleted. Ask your company's owner, or try again later."
        case .failed(let text): text
        }
    }

    /// The word a person types to confirm, in any case, without spaces around it.
    static func confirms(_ typed: String) -> Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DELETE"
    }
}

/// 67 · Account and data: the person, their data, and the danger zone at the foot.
struct AccountAndDataView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.openURL) private var openURL
    @State private var confirming = false
    @State private var editingProfile = false
    @State private var changingPassword = false
    @State private var status: AccountDeletionStatus?

    private var name: String { session.user?.name ?? session.user?.email ?? "Account" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AccountPageTitle(title: "Account and data")

                AccountGroup(title: "Your account") {
                    Button { editingProfile = true } label: {
                        AccountPersonRow(name: name, email: session.user?.name == nil ? nil : session.user?.email)
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Edit your name")
                    .accessibilityIdentifier("account-edit-profile")
                    WellDivider(leading: AccountRow<EmptyView>.dividerInset)
                    Button { changingPassword = true } label: {
                        AccountRow(glyph: .acctKey, title: "Change password")
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityIdentifier("account-change-password")
                }
                .padding(.top, 20)

                // Paper 67 also draws Two-step verification and Download my data; the server has
                // neither yet, so they are left out rather than shown as dead rows.
                AccountGroup(title: "Your data") {
                    NavigationLink { PrivacyPermissionsView().thorbisBackButton() } label: {
                        AccountRow(glyph: .acctPerson, title: "Privacy and permissions", subtitle: "What we collect and why")
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityIdentifier("account-privacy")
                }
                .padding(.top, 22)

                VStack(alignment: .leading, spacing: 0) {
                    label("Danger zone")
                    if let request = status?.request {
                        Text(pendingWords(request))
                            .font(Theme.font(14)).foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4).padding(.bottom, 14)
                            .accessibilityIdentifier("account-deletion-pending")
                    } else {
                        Text("Deleting your account permanently removes your login and personal details. Job and invoice records your company must keep for tax stay with the business.")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4).padding(.bottom, 14)
                        Button { confirming = true } label: {
                            HStack(spacing: 8) {
                                PaperIcon(.acctTrash, size: 15, color: Theme.destructive)
                                Text("Delete my account")
                            }
                            .paperButton(.card, tone: .dangerQuiet, fills: true)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityHint("Asks you to confirm before anything is deleted")
                        .accessibilityIdentifier("account-delete")
                    }
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, 16).padding(.bottom, 32)
        }
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.foreground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { status = await api.currentAccountDeletion() }
        .sheet(isPresented: $editingProfile) {
            EditProfileSheet(name: session.user?.name ?? "", onSaved: { saved in session.applySavedName(saved) })
        }
        .sheet(isPresented: $changingPassword) {
            ChangePasswordSheet(onChanged: {})
        }
        .sheet(isPresented: $confirming) {
            DeleteAccountSheet(name: name, company: session.activeOrganization?.name ?? "your company") { request in
                status = AccountDeletionStatus(request: request)
            }
        }
    }

    private func pendingWords(_ request: AccountDeletionStatus.Request) -> String {
        "You asked to delete this account. The request is being processed."
    }

    private func label(_ text: String) -> some View {
        PaperSectionLabel(title: text)
    }
}

/// 68 · Delete account — confirm: what goes, what the business keeps, type DELETE, then
/// Keep my account or Delete my account.
struct DeleteAccountSheet: View {
    let name: String
    let company: String
    let onRequested: (AccountDeletionStatus.Request) -> Void
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var busy = false
    @State private var outcome: AccountDeletionOutcome?
    @State private var missingWord = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Delete account?")
                    .font(Theme.font(22, weight: .bold)).tracking(-0.44)
                    .accessibilityAddTraits(.isHeader)
                Text("This removes \(name) from \(company). Your company keeps what the law requires; everything personal goes.")
                    .font(Theme.font(15)).foregroundStyle(Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                Text("Deleted").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .padding(.top, 18).padding(.bottom, 6)
                ForEach(["Your login and password", "Name, phone, email, photo", "Saved signature and preferences"], id: \.self) { item in
                    HStack(spacing: 0) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                            .frame(width: 26, alignment: .leading).accessibilityHidden(true)
                        Text(item).font(Theme.font(16, weight: .medium))
                    }
                    .frame(minHeight: 34)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Kept by the business").font(Theme.font(15, weight: .semibold))
                    Text("Completed jobs, invoices and payments stay with \(company) — tax law requires them. Your name becomes \"Former team member\" on those records.")
                        .font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 14).padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .combine)
                .padding(.top, 14)

                Text("Type DELETE to confirm").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .padding(.top, 18).padding(.bottom, 8)
                TextField("Type DELETE", text: $typed, prompt: .placeholder("DELETE"))
                    .font(Theme.font(16, weight: .medium)).tracking(0.64)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .focused($fieldFocused)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel("Type DELETE to confirm")
                    .accessibilityIdentifier("account-delete-confirm-field")
                if missingWord {
                    Text("Type DELETE in the box to confirm.").font(Theme.font(13)).foregroundStyle(Theme.destructive)
                        .padding(.top, 6)
                }
                if let message = outcome?.message {
                    Text(message).font(Theme.font(14)).foregroundStyle(Theme.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .accessibilityIdentifier("account-delete-outcome")
                }

                HStack(spacing: 10) {
                    Button { dismiss() } label: {
                        Text("Keep my account").paperButton(.commit, tone: .quiet, fills: true)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("account-delete-keep")
                    Button { Task { await submit() } } label: {
                        HStack(spacing: 6) {
                            if busy { ProgressView().tint(.white) }
                            Text("Delete my account")
                        }
                        .paperButton(.commit, tone: .danger, fills: true)
                    }
                    .buttonStyle(PressStyle())
                    .disabled(busy)
                    .accessibilityIdentifier("account-delete-commit")
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Theme.foreground)
        .thorbisSheetPresentation([.large])
    }

    private func submit() async {
        guard AccountDeletionOutcome.confirms(typed) else { missingWord = true; fieldFocused = true; return }
        missingWord = false
        // The server binds deletion to a recent sign-in check (account-lifecycle reauthentication,
        // BYR-446/449). Until it can issue that proof to the phone, the phone sends nothing — never
        // a made-up proof — and says plainly that nothing was deleted.
        guard let proof = AccountReauthenticationProof.current else {
            outcome = .needsSignInCheck
            return
        }
        busy = true
        defer { busy = false }
        do {
            let request = try await api.requestAccountDeletion(reauthenticationID: proof)
            outcome = .requested
            onRequested(request)
            dismiss()
        } catch let problem as Problem {
            outcome = AccountDeletionOutcome(status: problem.status, detail: problem.detail)
        } catch is CancellationError {
            return
        } catch {
            outcome = .failed("Your account wasn't deleted. Check your connection and try again.")
        }
    }
}

/// Where a fresh sign-in check's proof id will come from once the server issues one. There is no
/// route for it yet, so there is never a proof and the deletion request is not sent.
enum AccountReauthenticationProof {
    static var current: String? { nil }
}
