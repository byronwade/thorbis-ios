import SwiftUI

@MainActor
struct LoginView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showingReset = false
    @FocusState private var focused: FocusField?

    private enum FocusField { case email, password }

    var body: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ThorbisLogoLockup(markSize: 30, wordmarkSize: 19)

                Text("Welcome back")
                    .font(Theme.font(30, weight: .medium))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.foreground)
                    .padding(.top, 20)
                    .accessibilityAddTraits(.isHeader)
                Text("Log in to your Thorbis workspace")
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 6)

                label("Email").padding(.top, 32)
                TextField("you@company.com", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .focused($focused, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
                    .paperField()
                    .padding(.top, 8)

                HStack {
                    label("Password")
                    Spacer()
                    Button("Forgot?") { showingReset = true }
                        .font(Theme.font(13, weight: .medium))
                        .foregroundStyle(Theme.brandText)
                }
                .padding(.top, 16)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.plain)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await signIn() } }
                    .paperField()
                    .padding(.top, 8)

                if let message = error ?? session.error {
                    // MA-15: plain words in body colour; only the mark is tinted.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.destructive)
                        Text(message).foregroundStyle(Theme.foreground)
                    }
                    .font(Theme.font(15))
                    .padding(.top, 12)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("login-error")
                }
                Button { Task { await signIn() } } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView().tint(Theme.onInk) }
                        Text("Log in")
                    }
                    .inkCommit()
                }
                .buttonStyle(PressStyle())
                .disabled(busy)
                .padding(.top, 24)
                .accessibilityIdentifier("login-submit")

                if session.phase == .failed {
                    Button("Retry session") { Task { await session.restore() } }
                        .font(Theme.font(13, weight: .medium))
                        .foregroundStyle(Theme.brandText)
                        .padding(.top, 20)
                }
                Spacer(minLength: 80)
                HStack(spacing: 5) {
                    Text("Need an account?").foregroundStyle(Theme.muted)
                    Text("Ask your workspace administrator.").foregroundStyle(Theme.foreground)
                }
                .font(Theme.font(13))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, sizeClass == .regular ? 72 : 32)
            .frame(maxWidth: 430, minHeight: max(620, geometry.size.height - 32), alignment: .topLeading)
            .frame(maxWidth: .infinity)
        }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showingReset) {
            PasswordResetRequestView(initialEmail: email).environmentObject(api)
        }
    }

    private func label(_ title: String) -> some View {
        Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
    }

    private func signIn() async {
        guard !busy else { return }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !password.isEmpty else {
            error = "Enter your email and password."
            return
        }
        busy = true
        defer { busy = false }
        error = nil
        await session.signIn(email: address, password: password)
    }
}

private extension View {
    func paperField() -> some View {
        font(Theme.font(16))
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 46)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.border, lineWidth: 1))
    }
}

@MainActor
private struct PasswordResetRequestView: View {
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var email: String
    @State private var busy = false
    @State private var outcome: String?
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
                    TextField("you@company.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.plain)
                        .submitLabel(.send)
                        .onSubmit { Task { await requestReset() } }
                        .focused($emailFocused)
                        .paperField()
                        .padding(.top, 8)
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
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Password reset")
            .navigationBarTitleDisplayMode(.inline)
            // MA-16: Cancel leading, the commit trailing in the sheet's bar.
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Send link") { Task { await requestReset() } }
                            .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear { if email.isEmpty { emailFocused = true } }
        }
    }

    private func requestReset() async {
        guard !busy, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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
