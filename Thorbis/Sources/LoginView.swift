import SwiftUI

struct LoginView: View {
    @EnvironmentObject var api: APIClient
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showServer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("T").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                .frame(width: 32, height: 32).background(Theme.brand, in: RoundedRectangle(cornerRadius: 8))
                .padding(.bottom, 20)
            Text("Welcome back").font(.system(size: 28, weight: .bold))
            Text("Log in to your Thorbis workspace").font(.system(size: 15)).foregroundStyle(Theme.muted).padding(.top, 4)

            field("Email") {
                TextField("you@company.com", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
            }.padding(.top, 28)
            field("Password", trailing: "Forgot?") { SecureField("••••••••", text: $password) }.padding(.top, 14)

            if let error { Text(error).font(.system(size: 13)).foregroundStyle(Theme.destructive).padding(.top, 10) }

            PrimaryButton(title: "Log in", busy: busy) { Task { await signIn() } }.padding(.top, 18)

            HStack { line; Text("or continue with").font(.system(size: 12)).foregroundStyle(Theme.muted); line }.padding(.vertical, 18)

            if api.isLoopback {
                Button { api.useDevIdentity() } label: {
                    Label("Local dev identity", systemImage: "hammer").font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                }.foregroundStyle(Theme.foreground)
            }
            Spacer()
            Button { showServer.toggle() } label: {
                Text("API: \(api.baseURL)").font(Theme.mono).foregroundStyle(Theme.muted)
            }.frame(maxWidth: .infinity)
            if showServer {
                TextField("https://api…", text: $api.baseURL).font(Theme.mono).textInputAutocapitalization(.never)
                    .padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 8)).padding(.top, 8)
            }
        }
        .padding(.horizontal, 16).padding(.top, 40).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        busy = true; defer { busy = false }
        do { try await api.signIn(email: email, password: password); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
