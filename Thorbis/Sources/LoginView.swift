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
                Image("ThorbisMark")
                    .resizable().scaledToFit()
                    .frame(width: 40, height: 40)
                    .accessibilityLabel("Thorbis")

                Text("Welcome back")
                    .font(Theme.font(30, weight: .medium))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.foreground)
                    .padding(.top, 24)
                    .accessibilityAddTraits(.isHeader)
                Text("Log in to your Thorbis workspace")
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 6)

                if let sessionProblem {
                    ErrorBanner(message: sessionProblem,
                                symbol: sessionProblem.localizedCaseInsensitiveContains("expired") ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.triangle",
                                action: session.phase == .failed && !sessionProblem.localizedCaseInsensitiveContains("expired")
                                    ? .init(title: String(localized: "Try again")) { await session.restore() } : nil)
                        .padding(.horizontal, -Theme.gutter).padding(.top, 12)
                        .accessibilityIdentifier("login-error")
                }
                if let warning = pendingMedia.cleanupWarning {
                    ErrorBanner(message: warning).padding(.horizontal, -Theme.gutter).padding(.top, 12)
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
                    HStack(alignment: .firstTextBaseline) {
                        Text("Password").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                            .accessibilityHidden(true)
                        Spacer()
                        Button { showingReset = true } label: {
                            Text("Forgot password?").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.brandText)
                                .frame(minHeight: 32).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("login-forgot")
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

                Spacer(minLength: 40)
                // Owners register here; people joining a team accept their email invite first.
                Button { showingSignUp = true } label: {
                    HStack(spacing: 5) {
                        Text("New to Thorbis?").foregroundStyle(Theme.muted)
                        Text("Create an account").foregroundStyle(Theme.brandText)
                    }
                    .font(Theme.font(15, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("login-create-account")
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, sizeClass == .regular ? 72 : 40)
            .padding(.bottom, 8)
            .frame(maxWidth: 430, alignment: .topLeading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.canvas)
        // MA-16: the one commit, under the thumb and above the keyboard.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { Task { await signIn() } } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(Theme.onInk) }
                    Text("Log in")
                }
                .inkCommit()
            }
            .buttonStyle(PressStyle())
            .disabled(busy)
            .accessibilityIdentifier("login-submit")
            .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 10)
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
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 13)).foregroundStyle(Theme.destructive)
                .accessibilityHidden(true)
            Text(message).font(Theme.font(13)).foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
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
private struct PasswordResetRequestView: View {
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var email: String
    @State private var busy = false
    @State private var outcome: String?
    /// Said under the email when Send link is pressed without one; clears as they type.
    @State private var emailProblem: String?
    @FocusState private var emailFocused: Bool

    init(initialEmail: String) { _email = State(initialValue: initialEmail) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Reset your password")
                        .font(Theme.font(24, weight: .medium))
                        .foregroundStyle(Theme.foreground)
                    Text("Enter the email you use for Thorbis. If reset is available for that account, we’ll send a link.")
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 8)
                    Text("Email")
                        .font(Theme.font(13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 32)
                    TextField("Email", text: $email, prompt: .placeholder("you@company.com"))
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.plain)
                        .submitLabel(.send)
                        .onSubmit { Task { await requestReset() } }
                        .focused($emailFocused)
                        .onChange(of: email) { _, _ in emailProblem = nil }
                        .paperField()
                        .padding(.top, 8)
                    if let emailProblem { FieldProblem(message: emailProblem).padding(.top, 6) }
                    if let outcome {
                        Text(outcome)
                            .font(Theme.font(15))
                            .foregroundStyle(Theme.foreground)
                            .padding(.top, 20)
                    }
                }
                .padding(20)
                .frame(maxWidth: 430, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.canvas)
            .navigationTitle("Password reset")
            .navigationBarTitleDisplayMode(.inline)
            // MA-16: Cancel leading, the commit trailing in the sheet's bar.
            .toolbar {
                ThorbisToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ThorbisToolbarItem(placement: .confirmationAction, prominent: true) {
                    if busy {
                        ProgressView()
                    } else {
                        // Not pre-disabled: pressed without an email, it says so under the field.
                        Button("Send link") { Task { await requestReset() } }
                    }
                }
            }
            .onAppear { if email.isEmpty { emailFocused = true } }
        }
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
        struct Request: Encodable { let email: String }
        do {
            let _: APIClient.EmptyResponse = try await api.send(
                "POST", "/api/auth/request-password-reset",
                body: Request(email: email.trimmingCharacters(in: .whitespacesAndNewlines)),
                authed: false
            )
            outcome = "If an account uses that email, we sent a reset link. It expires in 30 minutes."
        } catch let problem as Problem where problem.status == 404 {
            outcome = "Password reset is unavailable here. Ask your workspace administrator for help."
        } catch let problem as Problem where problem.status == 429 {
            outcome = "Too many requests. Please try again later."
        } catch {
            outcome = "We couldn’t request a reset link. Please try again."
        }
    }
}
