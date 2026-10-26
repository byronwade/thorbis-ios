import SwiftUI
import ThorbisCore

/// One step, one action: sign in to an existing workspace. No plan purchase,
/// pricing or sign-up surfaces exist in the Apple binary (ADR-0018).
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showServer = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        email.contains("@") && !password.isEmpty && !busy
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Image("BrandMark")
                            .resizable()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
                            .accessibilityHidden(true)
                        Text("Sign in to Thorbis")
                            .font(.largeTitle.weight(.medium))
                            .foregroundStyle(Theme.ink)
                        Text("Use the email and password for your company's workspace.")
                            .font(.body)
                            .foregroundStyle(Theme.inkSecondary)
                    }

                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        LabeledField(label: "Email") {
                            TextField("you@company.com", text: $email)
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.next)
                                .focused($focus, equals: .email)
                                .onSubmit { focus = .password }
                                .accessibilityIdentifier("email")
                        }
                        LabeledField(label: "Password") {
                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .submitLabel(.go)
                                .focused($focus, equals: .password)
                                .onSubmit { if canSubmit { submit() } }
                                .accessibilityIdentifier("password")
                        }
                        if let error {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.footnote)
                                .foregroundStyle(Theme.danger)
                                .accessibilityIdentifier("sign-in-error")
                        }
                    }

                    CommitButton(title: "Sign in", busy: busy, action: submit)
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("sign-in")

                    if model.environment.isLoopback {
                        Button {
                            Task {
                                do { try await model.useDevIdentity() } catch { self.error = error.localizedDescription }
                            }
                        } label: {
                            Label("Use local dev identity", systemImage: "hammer")
                        }
                        .buttonStyle(.rim)
                    }

                    Text("Need access? Contact your organization administrator, then pull down to check again.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkQuiet)
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showServer = true
                    } label: {
                        Image(systemName: "server.rack")
                            .frame(minWidth: Theme.minimumHit, minHeight: Theme.minimumHit)
                    }
                    .accessibilityLabel("Server: \(model.environment.name)")
                }
            }
            .sheet(isPresented: $showServer) {
                ServerPickerView()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        busy = true
        error = nil
        focus = nil
        Task {
            defer { busy = false }
            do {
                try await model.signIn(email: email, password: password)
            } catch {
                // Keep what was typed; explain next to the fields (HIG-013).
                self.error = error.localizedDescription
            }
        }
    }
}

/// Label persists above the well; the placeholder is only an example (Controls).
struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(Theme.inkSecondary)
            content
                .font(.body)
                .padding(.horizontal, Theme.Space.m)
                .frame(minHeight: Theme.minimumHit)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.rimInteractive))
        }
    }
}

struct ServerPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach([APIEnvironment.production, .local]) { environment in
                        Button {
                            choose(environment)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(environment.name).foregroundStyle(Theme.ink)
                                    Text(environment.baseURL.absoluteString).font(.footnote).foregroundStyle(Theme.inkQuiet)
                                }
                                Spacer()
                                if environment == model.environment {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent).accessibilityLabel("Selected")
                                }
                            }
                        }
                        .sheetRow()
                    }
                } footer: {
                    Text("Changing servers signs you out of the current one.")
                }
                Section("Other server") {
                    TextField("https://thorbis.com/app", text: $custom)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .sheetRow()
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(Theme.danger).sheetRow()
                    }
                    Button("Use this server") {
                        guard let environment = APIEnvironment.custom(custom) else {
                            error = "Enter an https address, or http for a server on this Mac."
                            return
                        }
                        choose(environment)
                    }
                    .disabled(custom.isEmpty)
                    .sheetRow()
                }
            }
            .thorbisList()
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func choose(_ environment: APIEnvironment) {
        Task {
            await model.setEnvironment(environment)
            dismiss()
        }
    }
}

struct OrganizationPickerView: View {
    @Environment(AppModel.self) private var model
    let organizations: [Organization]
    @State private var busy: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if organizations.isEmpty {
                    ContentUnavailableView(
                        "No workspaces",
                        systemImage: "building.2",
                        description: Text("This account isn't a member of any company yet. Contact your organization administrator, then pull down to check again.")
                    )
                    .listRowBackground(Color.clear)
                }
                ForEach(organizations) { organization in
                    Button {
                        busy = organization.id
                        Task {
                            defer { busy = nil }
                            do { try await model.chooseOrganization(organization) } catch { self.error = error.localizedDescription }
                        }
                    } label: {
                        HStack {
                            Avatar(name: organization.name)
                            Text(organization.name).foregroundStyle(Theme.ink)
                            Spacer()
                            if busy == organization.id { ProgressView() }
                        }
                        .frame(minHeight: Theme.minimumHit)
                    }
                    .sheetRow()
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.danger).sheetRow()
                }
            }
            .thorbisList()
            .refreshable { await model.switchOrganization() }
            .navigationTitle("Choose a workspace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sign out") { Task { await model.signOut() } }
                }
            }
        }
    }
}
