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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("T")
                    .font(Theme.font(20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.brand, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Thorbis")

                Text("Welcome back")
                    .font(Theme.font(34, weight: .bold))
                    .tracking(-0.68)
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
                        .foregroundStyle(Theme.brand)
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
                    Text(message)
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.destructive)
                        .padding(.top, 12)
                        .accessibilityIdentifier("login-error")
                }
                Button { Task { await signIn() } } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView().tint(.white) }
                        Text("Log in")
                    }
                    .font(Theme.font(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(busy)
                .padding(.top, 24)
                .accessibilityIdentifier("login-submit")

                if session.phase == .failed {
                    Button("Retry session") { Task { await session.restore() } }
                        .font(Theme.font(13, weight: .medium))
                        .foregroundStyle(Theme.brand)
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
            .frame(maxWidth: 430, minHeight: sizeClass == .regular ? 620 : nil, alignment: .topLeading)
            .frame(maxWidth: .infinity)
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
        font(Theme.font(15))
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
    }
}

@MainActor
private struct PasswordResetRequestView: View {
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var email: String
    @State private var busy = false
    @State private var outcome: String?

    init(initialEmail: String) { _email = State(initialValue: initialEmail) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Reset your password")
                        .font(Theme.font(26, weight: .bold))
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
                        .paperField()
                        .padding(.top, 8)
                    if let outcome {
                        Text(outcome)
                            .font(Theme.font(14))
                            .foregroundStyle(Theme.foreground)
                            .padding(.top, 20)
                    }
                    Button { Task { await requestReset() } } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(.white) }
                            Text("Send reset link")
                        }
                        .font(Theme.font(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(busy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.top, 24)
                }
                .padding(20)
                .frame(maxWidth: 430, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Password reset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private func requestReset() async {
        guard !busy else { return }
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
