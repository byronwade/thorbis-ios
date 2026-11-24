import SwiftUI

// MARK: - Change password (Paper "Setup and account" 67B)
//
// Better Auth `POST /api/auth/change-password` with `{ currentPassword, newPassword,
// revokeOtherSessions }`. The passwords live only in this sheet's state, go straight into that one
// request body, and are cleared when the sheet closes. They are never logged, never put in an
// identifier, an accessibility value or an error message. The length limits are Better Auth's own
// (8 to 128, as the web's password-reset screen says); Better Auth keeps no password history, so
// Paper's "Not one you've used before" and the strength meter are left out.

struct PasswordChangeRequest: Encodable {
    let currentPassword: String
    let newPassword: String
    let revokeOtherSessions: Bool
}

/// Checks and words for Change password, apart from the view so they are unit-tested.
enum PasswordChange {
    /// Better Auth 1.6.26 `minPasswordLength` / `maxPasswordLength` (the server enforces them).
    static let minimumLength = 8
    static let maximumLength = 128

    static func longEnough(_ password: String) -> Bool { password.count >= minimumLength }

    static func bothMatch(_ password: String, _ confirmation: String) -> Bool {
        !password.isEmpty && password == confirmation
    }

    static func currentProblem(_ current: String) -> String? {
        current.isEmpty ? "Enter your current password." : nil
    }

    static func newProblem(_ password: String) -> String? {
        if password.isEmpty { return "Enter a new password." }
        if password.count < minimumLength { return "Use at least \(minimumLength) characters." }
        if password.count > maximumLength { return "Use \(maximumLength) characters or fewer." }
        return nil
    }

    static func confirmProblem(_ password: String, _ confirmation: String) -> String? {
        if confirmation.isEmpty { return "Type the new password again." }
        return password == confirmation ? nil : "The two new passwords don't match."
    }

    /// Better Auth answers `{ code, message }`; APIClient turns that into `Problem(title: code, …)`.
    static func message(code: String?, status: Int?, detail: String?) -> String {
        switch code?.uppercased() {
        case "INVALID_PASSWORD": return "That isn't your current password. Check it and try again."
        case "PASSWORD_TOO_SHORT": return "Use at least \(minimumLength) characters."
        case "PASSWORD_TOO_LONG": return "Use \(maximumLength) characters or fewer."
        case "CREDENTIAL_ACCOUNT_NOT_FOUND": return "This account has no password to change. Ask your company's owner for help."
        default: break
        }
        switch status {
        case 401: return "Your session ended. Sign in again, then change your password."
        case 429: return "Too many tries. Wait a few minutes, then try again."
        default: return detail ?? "Your password wasn't changed. Try again."
        }
    }

    /// What "Forgot?" says after asking for a reset link for the signed-in email.
    static func resetMessage(status: Int?, email: String) -> String {
        switch status {
        case nil: return "We sent a reset link to \(email). It expires in 30 minutes."
        case 404: return "Password reset is unavailable here. Ask your workspace administrator for help."
        case 429: return "Too many requests. Please try again later."
        default: return "We couldn't request a reset link. Please try again."
        }
    }
}

extension APIClient {
    /// `authed: false` like every other `/api/auth/*` call: a wrong current password is said on the
    /// sheet; it must not sign the person out.
    func changePassword(_ request: PasswordChangeRequest) async throws {
        let _: APIClient.EmptyResponse = try await send("POST", "/api/auth/change-password",
                                                        body: request, authed: false)
    }

    func requestPasswordResetLink(email: String) async throws {
        struct Request: Encodable { let email: String }
        let _: APIClient.EmptyResponse = try await send("POST", "/api/auth/request-password-reset",
                                                        body: Request(email: email), authed: false)
    }
}

/// 67B · Change password. Present as a sheet (Cancel, the title and Save in one row).
/// `onChanged` runs after the server accepts the new password, just before the sheet closes.
struct ChangePasswordSheet: View {
    var onChanged: () -> Void = {}
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var signOutOthers = true
    @State private var reveal = false
    @State private var showErrors = false
    @State private var saving = false
    @State private var serverMessage: String?
    @State private var resetBusy = false
    @State private var resetMessage: String?
    @FocusState private var focused: Field?

    private enum Field: Hashable { case current, new, confirm }

    init(onChanged: @escaping () -> Void = {}) {
        self.onChanged = onChanged
    }

    private var hasTyped: Bool { !current.isEmpty || !newPassword.isEmpty || !confirmation.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let serverMessage {
                        ErrorBanner(message: serverMessage, tint: Theme.destructive, outer: 0)
                            .accessibilityIdentifier("change-password-error")
                    }
                    currentCard
                    newCard
                    checklist
                    signOutCard
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 20).padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.sidebar.ignoresSafeArea())
        .thorbisSheetPresentation([.large])
        .interactiveDismissDisabled(saving || hasTyped)
        .onDisappear { clear() }
    }

    // MARK: Header

    private var header: some View {
        PaperTaskBar(title: "Change password", cancelDisabled: saving, cancelIdentifier: "change-password-cancel",
                     commit: ThorbisSheetHeaderAction(title: "Save", busy: saving, identifier: "change-password-save") {
                         Task { await save() }
                     }) { dismiss() }
    }

    // MARK: Cards

    private var currentCard: some View {
        card {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current password").font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .accessibilityHidden(true)
                    SecureField("Current password", text: $current, prompt: .placeholder("Your password"))
                        .font(Theme.font(17, weight: .medium))
                        .textContentType(.password)
                        .submitLabel(.next)
                        .onSubmit { focused = .new }
                        .focused($focused, equals: .current)
                        .onChange(of: current) { _, _ in serverMessage = nil }
                        .accessibilityLabel("Current password")
                        .accessibilityIdentifier("change-password-current")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { Task { await requestReset() } } label: {
                    Group {
                        if resetBusy { ProgressView().controlSize(.small) }
                        else { Text("Forgot?").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.brandText) }
                    }
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(resetBusy || saving)
                .accessibilityLabel("Forgot password?")
                .accessibilityHint("Emails you a reset link")
                .accessibilityIdentifier("change-password-forgot")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            if showErrors, let problem = PasswordChange.currentProblem(current) {
                FieldProblem(message: problem).padding(.horizontal, 16).padding(.bottom, 12)
            }
            if let resetMessage {
                Text(resetMessage).font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.bottom, 12)
                    .accessibilityIdentifier("change-password-reset-message")
            }
        }
    }

    private var newCard: some View {
        card {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New password").font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .accessibilityHidden(true)
                    passwordField("New password", text: $newPassword, field: .new, identifier: "change-password-new")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Typing on a phone in a truck is error-prone; let people check what they typed.
                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye")
                        .font(.system(size: 17)).foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reveal ? "Hide passwords" : "Show passwords")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            if showErrors, let problem = PasswordChange.newProblem(newPassword) {
                FieldProblem(message: problem).padding(.horizontal, 16).padding(.bottom, 12)
            }
            WellDivider(leading: 16)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Confirm new password").font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .accessibilityHidden(true)
                    passwordField("Confirm new password", text: $confirmation, field: .confirm,
                                  identifier: "change-password-confirm")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if PasswordChange.bothMatch(newPassword, confirmation) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.success)
                        .frame(width: 24, height: 24)
                        .background(Theme.successSurface, in: Circle())
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            if showErrors, let problem = PasswordChange.confirmProblem(newPassword, confirmation) {
                FieldProblem(message: problem).padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
    }

    /// Paper's checklist, kept to what the server checks.
    private var checklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            checkRow("At least \(PasswordChange.minimumLength) characters", met: PasswordChange.longEnough(newPassword))
            checkRow("Both passwords match", met: PasswordChange.bothMatch(newPassword, confirmation))
        }
        .padding(.horizontal, 4)
    }

    private var signOutCard: some View {
        card {
            Toggle(isOn: $signOutOthers) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sign out other devices").font(Theme.font(16)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.brand)
            .padding(.horizontal, 16).frame(minHeight: 64)
            .accessibilityIdentifier("change-password-sign-out-others")
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func passwordField(_ label: String, text: Binding<String>, field: Field, identifier: String) -> some View {
        Group {
            if reveal {
                TextField(label, text: text, prompt: .placeholder(label))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } else {
                SecureField(label, text: text, prompt: .placeholder(label))
            }
        }
        .font(Theme.font(17, weight: .medium))
        .textContentType(.newPassword)
        .submitLabel(field == .new ? .next : .done)
        .onSubmit {
            if field == .new { focused = .confirm } else { Task { await save() } }
        }
        .focused($focused, equals: field)
        .onChange(of: text.wrappedValue) { _, _ in serverMessage = nil }
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func checkRow(_ title: String, met: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark" : "circle")
                .font(.system(size: met ? 12 : 8, weight: .bold))
                .foregroundStyle(met ? Theme.success : Theme.muted)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(title).font(Theme.font(14)).foregroundStyle(Theme.subtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(met ? "Done" : "Not yet")
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    // MARK: Actions

    private func save() async {
        guard !saving else { return }
        showErrors = true
        serverMessage = nil
        if PasswordChange.currentProblem(current) != nil { focused = .current; return }
        if PasswordChange.newProblem(newPassword) != nil { focused = .new; return }
        if PasswordChange.confirmProblem(newPassword, confirmation) != nil { focused = .confirm; return }
        focused = nil
        saving = true
        defer { saving = false }
        let organizationID = session.activeOrganization?.id
        do {
            try await api.changePassword(PasswordChangeRequest(currentPassword: current, newPassword: newPassword,
                                                               revokeOtherSessions: signOutOthers))
            clear()
            // Signing out other devices replaces this phone's session with a new one that has no
            // company chosen; choose the same company again so work keeps loading.
            if signOutOthers, let organizationID { await keepCompanyActive(organizationID) }
            onChanged()
            dismiss()
        } catch is CancellationError {
            return
        } catch let problem as Problem {
            serverMessage = PasswordChange.message(code: problem.title, status: problem.status, detail: problem.detail)
        } catch {
            serverMessage = PasswordChange.message(code: nil, status: nil, detail: nil)
        }
    }

    private func requestReset() async {
        guard !resetBusy else { return }
        guard let email = session.user?.email, !email.isEmpty else {
            resetMessage = "Your account has no email to send a reset link to. Ask your company's owner for help."
            return
        }
        resetBusy = true
        defer { resetBusy = false }
        do {
            try await api.requestPasswordResetLink(email: email)
            resetMessage = PasswordChange.resetMessage(status: nil, email: email)
        } catch is CancellationError {
            return
        } catch let problem as Problem {
            resetMessage = PasswordChange.resetMessage(status: problem.status ?? 0, email: email)
        } catch {
            resetMessage = PasswordChange.resetMessage(status: 0, email: email)
        }
    }

    /// Better Auth `POST /api/auth/organization/set-active`, as SessionController.selectOrganization
    /// sends it. If it fails, a full restore finds the session again rather than leaving it half-set.
    private func keepCompanyActive(_ organizationID: String) async {
        struct Selection: Encodable { let organizationId: String }
        do {
            let _: APIClient.EmptyResponse = try await api.send("POST", "/api/auth/organization/set-active",
                                                                body: Selection(organizationId: organizationID),
                                                                authed: false)
            api.forgetRefusedReads()
        } catch {
            await session.restore()
        }
    }

    /// The typed passwords leave memory with the sheet.
    private func clear() {
        current = ""
        newPassword = ""
        confirmation = ""
    }
}
