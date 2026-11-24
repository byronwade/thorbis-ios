import SwiftUI
import UIKit

// MARK: - Account and data (Paper v2: 67 Account and data, 68 Delete account — confirm)
//
// App Store rule 5.1.1(v): an app that lets people sign up lets them start deleting the account in
// the app. The phone holds no deletion rules of its own. It first proves it is still the account's
// owner (POST /v1/account-lifecycle/reauthentications with the password, which is sent once and
// never kept), then sends the request with that proof (POST /v1/account-lifecycle/deletion-requests).

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

/// The server's answer to a fresh sign-in check: an id the deletion request carries once.
struct AccountReauthentication: Decodable, Equatable {
    let reauthenticationId: String
}

extension APIClient {
    /// The person's open deletion request, if any. A missing route or no request reads as none.
    func currentAccountDeletion() async -> AccountDeletionStatus? {
        try? await send("GET", "/v1/account-lifecycle/deletion-requests/current") as AccountDeletionStatus
    }

    /// Proves the person holding the phone knows the account's password, just before deleting.
    func reauthenticateAccount(password: String) async throws -> AccountReauthentication {
        struct Body: Encodable { let password: String }
        return try await send("POST", "/v1/account-lifecycle/reauthentications", body: Body(password: password))
    }

    func requestAccountDeletion(reauthenticationID: String) async throws -> AccountDeletionStatus.Request {
        try await send("POST", "/v1/account-lifecycle/deletion-requests",
                       body: AccountDeletionRequestBody(reauthenticationId: reauthenticationID))
    }
}

/// What the confirm sheet says after the server answers. Pure, so the words are unit-tested.
enum AccountDeletionOutcome: Equatable {
    case requested
    case wrongPassword
    case tooManyTries
    /// The server cannot take deletion requests yet (the sign-in check or the rules for what is
    /// kept are not switched on).
    case notAvailable
    case failed(String)

    /// The sign-in check's refusal (POST /v1/account-lifecycle/reauthentications).
    /// 409 `reauthentication_rejected` is a wrong password; any other 409 or a missing route means
    /// the server cannot check passwords yet; 401 means the sign-in itself ran out.
    init(signInCheck status: Int?, code: String? = nil) {
        switch (status, code) {
        case (409, "reauthentication_rejected"), (400, _), (422, _): self = .wrongPassword
        case (429, _): self = .tooManyTries
        case (401, _): self = .failed("You've been signed out. Nothing was deleted. Sign in again, then try again.")
        case (404, _), (409, _), (501, _): self = .notAvailable
        default: self = .failed("Thorbis couldn't check your password. Nothing was deleted. Try again.")
        }
    }

    /// The deletion request's refusal (POST /v1/account-lifecycle/deletion-requests).
    /// 409 `reauthentication_required` means the password check ran out or was already used.
    init(status: Int?, detail: String?, code: String? = nil) {
        switch (status, code) {
        case (409, "reauthentication_required"):
            self = .failed("Thorbis needs to check your password again. Nothing was deleted. Try again.")
        case (429, _): self = .tooManyTries
        case (401, _): self = .failed("You've been signed out. Nothing was deleted. Sign in again, then try again.")
        case (404, _), (409, _): self = .notAvailable
        default: self = .failed(detail ?? "Your account wasn't deleted. Try again.")
        }
    }

    var message: String? {
        switch self {
        case .requested: nil
        case .wrongPassword: "That password isn't right. Nothing was deleted."
        case .tooManyTries: "Too many tries. Nothing was deleted. Wait a few minutes, then try again."
        case .notAvailable:
            "Thorbis can't take deletion requests in the app yet. Nothing was deleted. Try again later."
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
                    NavigationLink { PrivacyPermissionsView(payments: PushNotifications.receivesPaymentAlerts(session)).thorbisBackButton() } label: {
                        AccountRow(glyph: .acctPerson, title: "Privacy and permissions", subtitle: "What we collect and why")
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityIdentifier("account-privacy")
                    WellDivider(leading: AccountRow<EmptyView>.dividerInset)
                    Button { openURL(LegalLinks.privacy) } label: {
                        AccountRow(symbol: "hand.raised", title: "Privacy policy", subtitle: "Opens thorbis.com")
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityIdentifier("account-privacy-policy")
                    WellDivider(leading: AccountRow<EmptyView>.dividerInset)
                    Button { openURL(LegalLinks.terms) } label: {
                        AccountRow(symbol: "doc.text", title: "Terms of service", subtitle: "Opens thorbis.com")
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityIdentifier("account-terms")
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
                        Text("Deleting your account removes your login and personal details. Job and invoice records belong to your company and stay with it.")
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
    @State private var password = ""
    @State private var missingPassword = false
    @State private var busy = false
    @State private var outcome: AccountDeletionOutcome?
    @State private var missingWord = false
    @FocusState private var fieldFocused: Bool
    @FocusState private var passwordFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Delete account?")
                    .font(Theme.font(22, weight: .bold)).tracking(-0.44)
                    .accessibilityAddTraits(.isHeader)
                Text("This asks Thorbis to delete \(name)\u{2019}s account and remove it from \(company). The business keeps its own records.")
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
                    Text("Jobs, invoices, payments, notes and photos belong to \(company) and stay with it.")
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
                Text("Your password").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .padding(.top, 18).padding(.bottom, 8)
                    .accessibilityHidden(true)
                SecureField("Your password", text: $password, prompt: .placeholder("Password"))
                    .font(Theme.font(16, weight: .medium))
                    .textContentType(.password)
                    .submitLabel(.done)
                    .focused($passwordFocused)
                    .onChange(of: password) { _, _ in missingPassword = false; outcome = nil }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel("Your password")
                    .accessibilityHint("Checks that it is you before the account is deleted")
                    .accessibilityIdentifier("account-delete-password")
                if missingPassword {
                    Text("Enter your password to confirm it's you.").font(Theme.font(13)).foregroundStyle(Theme.destructive)
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
        .onDisappear { password = "" }
    }

    private func submit() async {
        guard AccountDeletionOutcome.confirms(typed) else { missingWord = true; fieldFocused = true; return }
        missingWord = false
        guard !password.isEmpty else { missingPassword = true; passwordFocused = true; return }
        busy = true
        defer { busy = false }
        // First the sign-in check. The password goes to the server once and is not kept here.
        let proof: AccountReauthentication
        do {
            proof = try await api.reauthenticateAccount(password: password)
        } catch let problem as Problem {
            outcome = AccountDeletionOutcome(signInCheck: problem.status, code: problem.code)
            if outcome == .wrongPassword { password = ""; passwordFocused = true }
            return
        } catch is CancellationError {
            return
        } catch {
            outcome = .failed("Nothing was deleted. Check your connection and try again.")
            return
        }
        do {
            let request = try await api.requestAccountDeletion(reauthenticationID: proof.reauthenticationId)
            password = ""
            outcome = .requested
            onRequested(request)
            dismiss()
        } catch let problem as Problem {
            outcome = AccountDeletionOutcome(status: problem.status, detail: problem.detail, code: problem.code)
            password = ""
        } catch is CancellationError {
            return
        } catch {
            outcome = .failed("Your account wasn't deleted. Check your connection and try again.")
        }
    }
}
