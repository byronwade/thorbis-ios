import SwiftUI

/// Better Auth's sign-in answers, in plain words that name the way out.
enum LoginCopy {
    static func message(for raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "You weren’t logged in. Try again." }
        let lower = raw.lowercased()
        if lower.contains("invalid email or password") || lower.contains("invalid_email_or_password")
            || lower.contains("invalid password") || lower.contains("user not found") {
            return "That email and password don’t match. Check them, or reset your password."
        }
        if lower.contains("not verified") || lower.contains("email_not_verified") {
            return "Confirm your email first. Open the link we sent, then log in."
        }
        if lower.contains("banned") || lower.contains("disabled") {
            return "This account can’t log in. Ask your office for help."
        }
        return raw
    }
}

/// Sign in (2026-10-31): the shield on the cream ground, two fields with their labels above,
/// one ink "Log in" pinned under the thumb. A wrong password is said under the password field;
/// an ended session or a failed restore is said once at the top with its way out.
@MainActor
struct LoginView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var pendingMedia: PendingMediaStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var emailError: String?
    @State private var passwordError: String?
    /// Set once this screen has tried to log in, so the session's error belongs to that try.
    @State private var attempted: Bool

    /// `attempted` starts true only for screenshot fixtures of a refused try.
    init(attempted: Bool = false) { _attempted = State(initialValue: attempted) }
    @State private var showingReset = false
    @State private var showingSignUp = false
    @State private var showingInvite = false
    @State private var showPassword = false
    @FocusState private var focused: FocusField?

    private enum FocusField { case email, password }

    /// The session ended or could not be restored before anyone typed here.
    private var sessionProblem: String? {
        guard !attempted, let message = session.error, !message.isEmpty else { return nil }
        return message
    }

    /// The server's answer to this screen's own try, under the password.
    private var signInProblem: String? {
        guard attempted, !busy, let message = session.error, !message.isEmpty else { return nil }
        return LoginCopy.message(for: message)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Paper 04: the 44pt mark, then the 34 Bold title 20 under it, 20 from the edge.
                VStack(alignment: .leading, spacing: 0) {
                    AccountBrandTile()

                    Text("Welcome back")
                        .font(Theme.font(34, weight: .bold))
                        .tracking(-0.85)
                        .foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 20)
                        .accessibilityAddTraits(.isHeader)
                    Text("Log in to your Thorbis workspace")
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 4)

                if let sessionProblem {
                    ErrorBanner(message: sessionProblem,
                                symbol: sessionProblem.localizedCaseInsensitiveContains("expired") ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.triangle",
                                action: session.phase == .failed && !sessionProblem.localizedCaseInsensitiveContains("expired")
                                    ? .init(title: String(localized: "Try again")) { await session.restore() } : nil)
                        .padding(.horizontal, -PaperCardMetrics.margin).padding(.top, 12)
                        .accessibilityIdentifier("login-error")
                }
                if let warning = pendingMedia.cleanupWarning {
                    ErrorBanner(message: warning).padding(.horizontal, -PaperCardMetrics.margin).padding(.top, 12)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("login-media-cleanup-warning")
                }

                PaperFormField("Email") {
                    TextField("Email", text: $email, prompt: .placeholder("you@company.com"))
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.plain)
                        .focused($focused, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }
                        .onChange(of: email) { _, _ in emailError = nil }
                        .font(Theme.font(16))
                        .fieldWell()
                        .accessibilityLabel("Email")
                    if let emailError { FieldProblem(message: emailError) }
                }
                .padding(.top, 28)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center) {
                        Text("Password").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                            .padding(.leading, 4)
                            .accessibilityHidden(true)
                        Spacer()
                        Button { showingReset = true } label: {
                            Text("Forgot?").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                                .padding(.leading, 12).padding(.trailing, 4)
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Forgot password?")
                        .accessibilityIdentifier("login-forgot")
                        // A full 44pt target without pushing the field down.
                        .padding(.vertical, -14)
                    }
                    HStack(spacing: 0) {
                        Group {
                            if showPassword {
                                TextField("Password", text: $password, prompt: .placeholder("Password"))
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                            } else {
                                SecureField("Password", text: $password, prompt: .placeholder("Password"))
                            }
                        }
                        .textContentType(.password)
                        .textFieldStyle(.plain)
                        .font(Theme.font(16))
                        .focused($focused, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await signIn() } }
                        .onChange(of: password) { _, _ in passwordError = nil }
                        .accessibilityLabel("Password")
                        // Typing a password on a phone in a truck is error-prone; let people check it.
                        Button { showPassword.toggle(); focused = .password } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye").foregroundStyle(Theme.muted)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                        // Full 44pt target without making this field taller than Email.
                        .padding(.vertical, -10).padding(.trailing, -6)
                    }
                    .fieldWell()
                    if let message = passwordError ?? signInProblem {
                        FieldProblem(message: message).accessibilityIdentifier("login-error")
                    }
                }
                .padding(.top, 16)

                // Paper 04: Log in sits 24 under the password, not pinned to the bottom edge.
                Button { Task { await signIn() } } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView().tint(.white) }
                        Text("Log in")
                    }
                    .inkCommit()
                }
                .buttonStyle(PressStyle())
                .disabled(busy)
                .accessibilityIdentifier("login-submit")
                .padding(.top, 24)
            }
            // Paper: fields and commits 16 from the edge; the title block adds 4 to sit at 20.
            .padding(.horizontal, PaperCardMetrics.margin)
            .padding(.top, sizeClass == .regular ? 72 : 32)
            .padding(.bottom, 8)
            .frame(maxWidth: 430, alignment: .topLeading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.canvas)
        // Paper 04: only the way to sign up (and the invite link) sits at the bottom edge.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                // Owners register here; people joining a team accept their email invite first.
                Button { showingSignUp = true } label: {
                    HStack(spacing: 5) {
                        Text("Don’t have an account?").font(Theme.font(14)).foregroundStyle(Theme.muted)
                        Text("Sign up").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.brandText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("login-create-account")
                // Paper 05A: someone invited to a team pastes the invite link they were sent.
                Button { showingInvite = true } label: {
                    Text("Have an invite link?").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.brandText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("login-invite-link")
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 8).padding(.bottom, 4)
            .frame(maxWidth: 470)
            .frame(maxWidth: .infinity)
            .background(Theme.canvas)
        }
        .sheet(isPresented: $showingSignUp) { SheetSurface {
            SignUpView(initialEmail: email)
        } }
        .sheet(isPresented: $showingReset) { SheetSurface {
            PasswordResetRequestView(initialEmail: email).environmentObject(api)
        } }
        .sheet(isPresented: $showingInvite) { SheetSurface {
            InvitationLinkEntry { id in
                showingInvite = false
                PendingInvitation.shared.id = id
            }
        } }
    }

    private func signIn() async {
        guard !busy else { return }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        emailError = nil
        passwordError = nil
        guard !address.isEmpty else { emailError = "Enter your work email."; focused = .email; return }
        guard address.contains("@") else { emailError = "That doesn’t look like an email. Check it and try again."; focused = .email; return }
        guard !password.isEmpty else { passwordError = "Enter your password."; focused = .password; return }
        busy = true
        defer { busy = false }
        attempted = true
        await session.signIn(email: address, password: password)
    }
}

/// An error in place of a field's help text: the words in body colour, only the mark tinted.
struct FieldProblem: View {
    let message: String

    var body: some View {
        // Paper 09A "Error text": 13/18 in the red text colour, 4 in from the field's edge, no mark.
        HStack(spacing: 0) {
            Text(message).font(Theme.font(13)).foregroundStyle(Theme.destructive)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
        .accessibilityIdentifier("field-problem")
    }
}

private extension View {
    func paperField() -> some View {
        font(Theme.font(16))
            .foregroundStyle(Theme.foreground)
            .fieldWell()
    }
}

@MainActor
struct PasswordResetRequestView: View {
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var email: String
    @State private var busy = false
    /// A refusal or failure, said under the field.
    @State private var outcome: String?
    /// The request went through: the screen becomes "Check your email" (Paper 07).
    @State private var sent: Bool
    /// A second link went out from the sent state, so Resend visibly did something.
    @State private var resent = false
    /// Said under the email when Send link is pressed without one; clears as they type.
    @State private var emailProblem: String?
    @FocusState private var emailFocused: Bool

    /// `sent` starts true only for screenshot fixtures of Paper 07.
    init(initialEmail: String, sent: Bool = false) {
        _email = State(initialValue: initialEmail)
        _sent = State(initialValue: sent)
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if sent { sentContent } else { requestContent }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 16).padding(.bottom, 20)
                .frame(maxWidth: 430, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Paper 06/07: the 44pt back circle at the leading edge.
                ThorbisToolbarItem(placement: .topBarLeading) { ThorbisBackButton() }
            }
            // Paper 06/07: only the way back to log in sits at the bottom edge.
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .onAppear { if email.isEmpty { emailFocused = true } }
        }
    }

    /// Paper 06: the lock tile, the title, the email and Send reset link.
    @ViewBuilder private var requestContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ResetMarkTile(symbol: "lock")
            Text("Forgot password?")
                .font(Theme.font(34, weight: .bold)).tracking(-0.85)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
                .accessibilityAddTraits(.isHeader)
            Text("No worries — enter your email and we’ll send a reset link.")
                .font(Theme.font(15))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(.horizontal, 4)
        PaperFormField("Email") {
            TextField("Email", text: $email, prompt: .placeholder("you@company.com"))
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .submitLabel(.send)
                .onSubmit { Task { await requestReset() } }
                .focused($emailFocused)
                .onChange(of: email) { _, _ in emailProblem = nil; outcome = nil }
                .paperField()
                .accessibilityLabel("Email")
            if let emailProblem { FieldProblem(message: emailProblem) }
            if let outcome { FieldProblem(message: outcome) }
        }
        .padding(.top, 28)
        // Paper 06: the commit sits 16 under the field. Not pre-disabled: pressed without an
        // email, it says so under the field.
        Button { Task { await requestReset() } } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) }
                Text("Send reset link")
            }
            .inkCommit()
        }
        .buttonStyle(PressStyle())
        .disabled(busy)
        .padding(.top, 16)
    }

    /// Paper 07: what was sent and where, a way to send it again.
    @ViewBuilder private var sentContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ResetMarkTile(symbol: "envelope")
            Text("Check your email")
                .font(Theme.font(34, weight: .bold)).tracking(-0.85)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
                .accessibilityAddTraits(.isHeader)
            // The server never says whether the account exists, so neither does this.
            Text("If an account uses the address below, we sent a reset link. It expires in 30 minutes.")
                .font(Theme.font(15))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(.horizontal, 4)
        Text(trimmedEmail)
            .font(Theme.font(14, weight: .medium))
            .foregroundStyle(Theme.foreground)
            .lineLimit(1).truncationMode(.middle)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Theme.card, in: Capsule())
            .padding(.top, 18)
        if let outcome {
            FieldProblem(message: outcome).padding(.top, 12)
        } else if resent {
            Text("Sent again.").font(Theme.font(13)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4).padding(.top, 10)
        }
        // Paper 07: the one blue pill opens the phone's mail app, 24 under the address.
        Button { openURL(URL(string: "message://")!) } label: { Text("Open mail app").inkCommit() }
            .buttonStyle(PressStyle())
            .padding(.top, 24)
            .accessibilityIdentifier("reset-open-mail")
        Button { Task { await requestReset() } } label: {
            HStack(spacing: 5) {
                Text("Didn’t get it?").font(Theme.font(14)).foregroundStyle(Theme.muted)
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Resend email").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.brandText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .padding(.top, 8)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Button { dismiss() } label: {
                HStack(spacing: 5) {
                    if !sent { Text("Remember your password?").font(Theme.font(14)).foregroundStyle(Theme.muted) }
                    Text(sent ? "Back to log in" : "Log in").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.brandText)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 8).padding(.bottom, 4)
        .frame(maxWidth: 470)
        .frame(maxWidth: .infinity)
        .background(Theme.canvas)
    }

    private func requestReset() async {
        guard !busy else { return }
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            emailProblem = "Add the email you use for Thorbis, like you@company.com."
            emailFocused = true
            return
        }
        busy = true
        defer { busy = false }
        outcome = nil
        struct Request: Encodable { let email: String }
        do {
            let _: APIClient.EmptyResponse = try await api.send(
                "POST", "/api/auth/request-password-reset",
                body: Request(email: email.trimmingCharacters(in: .whitespacesAndNewlines)),
                authed: false
            )
            emailFocused = false
            resent = sent
            sent = true
        } catch let problem as Problem where problem.status == 404 {
            outcome = "Password reset is unavailable here. Ask your workspace administrator for help."
        } catch let problem as Problem where problem.status == 429 {
            outcome = "Too many requests. Please try again later."
        } catch {
            outcome = "We couldn’t request a reset link. Please try again."
        }
    }
}

/// Paper 06/07: the 44pt brand-tinted tile that leads the reset screens (a lock, then an envelope).
private struct ResetMarkTile: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Theme.brand)
            .frame(width: 44, height: 44)
            .background(Theme.brandSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}
