import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: SessionController
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            Text("T").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                .frame(width: 32, height: 32).background(Theme.brand, in: RoundedRectangle(cornerRadius: 8))
                .padding(.bottom, 20)
            Text("Welcome back").font(.system(size: 28, weight: .bold))
            Text("Log in to your Thorbis workspace").font(.system(size: 15)).foregroundStyle(Theme.muted).padding(.top, 4)

            field("Email") {
                TextField("you@company.com", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled().textContentType(.username)
            }.padding(.top, 28)
            field("Password") { SecureField("Password", text: $password).textContentType(.password) }.padding(.top, 14)

            if let error = error ?? session.error { Text(error).font(.system(size: 13)).foregroundStyle(Theme.destructive).padding(.top, 10) }

            PrimaryButton(title: "Log in", busy: busy) { Task { await signIn() } }.padding(.top, 18)

            if session.phase == .failed {
                Button("Retry session") { Task { await session.restore() } }
                    .font(.system(size: 14, weight: .medium))
                    .padding(.top, 16)
            }

        }
        .padding(24)
        .frame(maxWidth: 460, alignment: .leading)
        .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
    }

    var line: some View { Rectangle().fill(Theme.border).frame(height: 1) }

    func field<C: View>(_ label: String, trailing: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(label).font(.system(size: 13)).foregroundStyle(Theme.muted); Spacer()
                if let trailing { Text(trailing).font(.system(size: 13)).foregroundStyle(Theme.brand) } }
            content().font(.system(size: 15)).padding(.horizontal, 12).frame(height: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
        }
    }

    func signIn() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !password.isEmpty else {
            error = "Enter your email and password."
            return
        }
        error = nil
        await session.signIn(email: address, password: password)
    }
}
