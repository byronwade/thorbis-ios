import SwiftUI

// Owner registration and first-run setup, built only on what the server already offers:
// - Account: Better Auth `POST /api/auth/sign-up/email`.
// - Company: Better Auth `POST /api/auth/organization/create` (the creator becomes the owner),
//   then `organization/set-active` like any workspace switch.
// - Company details: `GET /v1/organization/profile` and `POST /v1/organization/facts`, the
//   same facts web Settings › Organization reads (domains/organization FACT_CATALOG).
// - Get paid, services and team reuse Payments setup, the Price Book and team invitations.

/// A URL-safe, unique-enough handle for a new company. Better Auth requires a slug; nobody sees it.
enum CompanySlug {
    static func make(from name: String, suffix: String = randomSuffix()) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        var slug = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                slug.unicodeScalars.append(scalar)
            } else if !slug.isEmpty, !slug.hasSuffix("-") {
                slug += "-"
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        let base = String(slug.prefix(40))
        let trimmed = base.hasSuffix("-") ? String(base.dropLast()) : base
        return (trimmed.isEmpty ? "company" : trimmed) + "-" + suffix
    }

    static func randomSuffix() -> String {
        let letters = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<6).map { _ in letters.randomElement()! })
    }
}

/// The shared look for the account screens: a 46-tall well with a hairline, 16pt type.
private struct AuthField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.font(16))
            .foregroundStyle(Theme.foreground)
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 46)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.border, lineWidth: 1))
    }
}

private extension View {
    func authField() -> some View { modifier(AuthField()) }
}

private func fieldLabel(_ title: String) -> some View {
    Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
}

/// MA-15: plain words in body colour; only the mark is tinted.
struct InlineProblem: View {
    let message: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.destructive)
            Text(message).foregroundStyle(Theme.foreground)
        }
        .font(Theme.font(15))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Create account

/// Step one for a new owner: name, email, password. The company comes next.
struct SignUpView: View {
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email: String
    @State private var password = ""
    @State private var showPassword = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Field?

    private enum Field { case name, email, password }

    init(initialEmail: String = "") { _email = State(initialValue: initialEmail) }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var dirty: Bool { !trimmedName.isEmpty || !password.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Create your account")
                        .font(Theme.font(24, weight: .medium))
                        .accessibilityAddTraits(.isHeader)
                    Text("Next you’ll name your company. It takes about a minute.")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .padding(.top, 6)

                    fieldLabel("Your name").padding(.top, 28)
                    TextField("First and last name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focused, equals: .name)
                        .onSubmit { focused = .email }
                        .authField().padding(.top, 8)

                    fieldLabel("Work email").padding(.top, 16)
                    TextField("you@company.com", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focused, equals: .email)
                        .onSubmit { focused = .password }
                        .authField().padding(.top, 8)

                    fieldLabel("Password").padding(.top, 16)
                    HStack(spacing: 0) {
                        Group {
                            if showPassword {
                                TextField("At least 8 characters", text: $password)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                            } else {
                                SecureField("At least 8 characters", text: $password)
                            }
                        }
                        .textContentType(.newPassword)
                        .submitLabel(.go)
                        .focused($focused, equals: .password)
                        .onSubmit { Task { await create() } }
                        Button { showPassword.toggle(); focused = .password } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye").foregroundStyle(Theme.muted)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                        .padding(.vertical, -10).padding(.trailing, -10)
                    }
                    .authField().padding(.top, 8)

                    if let error {
                        InlineProblem(message: error).padding(.top, 12)
                            .accessibilityIdentifier("signup-error")
                    }
                }
                .padding(20)
                .frame(maxWidth: 430, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .foregroundStyle(Theme.foreground)
            // MA-16: the commit sits in a bottom bar, under the thumb, above the keyboard.
            .safeAreaInset(edge: .bottom) {
                Button { Task { await create() } } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView().tint(Theme.onInk) }
                        Text("Create account")
                    }
                    .inkCommit()
                }
                .buttonStyle(PressStyle())
                .disabled(busy)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .frame(maxWidth: 470)
                .frame(maxWidth: .infinity)
                .background(Theme.background)
                .accessibilityIdentifier("signup-submit")
            }
            .navigationTitle("New account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .interactiveDismissDisabled(dirty || busy)
            .onAppear { focused = .name }
        }
    }

    private func create() async {
        guard !busy else { return }
        guard !trimmedName.isEmpty else { error = "Enter your name."; focused = .name; return }
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            error = "Enter the email you’ll sign in with."; focused = .email; return
        }
        guard password.count >= 8 else { error = "Use at least 8 characters for your password."; focused = .password; return }
        guard password.count <= 128 else { error = "Use 128 characters or fewer for your password."; focused = .password; return }
        busy = true
        defer { busy = false }
        error = nil
        await session.signUp(name: trimmedName, email: trimmedEmail, password: password)
        if session.phase == .failed || session.phase == .signedOut {
            error = Self.message(for: session.error)
        }
    }

    /// Better Auth's codes, in plain words.
    static func message(for raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Your account was not created. Try again." }
        let lower = raw.lowercased()
        if lower.contains("already exists") || lower.contains("user_already_exists") {
            return "That email already has an account. Log in instead, or reset the password."
        }
        if lower.contains("password") && lower.contains("short") { return "Use at least 8 characters for your password." }
        if lower.contains("password") && lower.contains("long") { return "Use 128 characters or fewer for your password." }
        if lower.contains("invalid email") { return "Check the email address." }
        return raw
    }
}

// MARK: - Choose or create a company

/// Shown when the account has no company or more than one, and as the switcher sheet from More.
struct WorkspaceGateView: View {
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false

    var body: some View {
        NavigationStack {
            if session.organizations.isEmpty && session.phase != .ready {
                CreateCompanyForm(firstCompany: true)
            } else {
                List {
                    Section {
                        ForEach(session.organizations) { organization in
                            Button {
                                Task { await session.selectOrganization(id: organization.id); dismiss() }
                            } label: {
                                HStack {
                                    Text(organization.name).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                                    Spacer()
                                    if organization.id == session.activeOrganization?.id {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.brandText)
                                            .accessibilityLabel("Current")
                                    }
                                }
                                .frame(minHeight: 44)
                            }
                        }
                    } header: { Text("Your companies") }
                    Section {
                        NavigationLink { CreateCompanyForm(firstCompany: false) } label: {
                            Label("Create a company", systemImage: "plus").foregroundStyle(Theme.foreground)
                        }
                    } footer: {
                        Text("You’ll own the new company. Your other companies stay as they are.")
                    }
                    if session.phase != .ready {
                        Section {
                            Button("Sign out", role: .destructive) { Task { await session.signOut() } }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .navigationTitle("Choose company")
                .toolbar {
                    if session.phase == .ready {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    }
                }
            }
        }
    }
}

/// Name the company. The account that creates it becomes its owner.
struct CreateCompanyForm: View {
    let firstCompany: Bool
    @EnvironmentObject private var session: SessionController
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?
    @State private var confirmSignOut = false
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if firstCompany {
                    ThorbisLogoLockup(markSize: 30, wordmarkSize: 19)
                    Text(greeting)
                        .font(Theme.font(30, weight: .medium)).tracking(-0.6)
                        .padding(.top, 20)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    Text("New company")
                        .font(Theme.font(24, weight: .medium))
                        .accessibilityAddTraits(.isHeader)
                }
                Text("What’s your company called? Customers see this name on estimates and invoices. You can change it later.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .padding(.top, 6)

                fieldLabel("Company name").padding(.top, 28)
                TextField("Wade Plumbing & Heating", text: $name)
                    .textContentType(.organizationName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit { Task { await create() } }
                    .authField().padding(.top, 8)

                if let error { InlineProblem(message: error).padding(.top, 12) }

                if firstCompany {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Joining a team instead?").font(Theme.font(15, weight: .medium))
                        Text("Ask your company’s owner to invite \(session.user?.email ?? "this email"). Accept the email invite, then check again.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        HStack(spacing: 20) {
                            Button("Check again") { Task { await session.restore() } }
                                .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.brandText)
                                .frame(minHeight: 44)
                            Button("Sign out") { confirmSignOut = true }
                                .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                                .frame(minHeight: 44)
                        }
                    }
                    .padding(.top, 40)
                }
            }
            .padding(20)
            .padding(.top, firstCompany ? 20 : 0)
            .frame(maxWidth: 430, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.foreground)
        .safeAreaInset(edge: .bottom) {
            Button { Task { await create() } } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(Theme.onInk) }
                    Text("Create company")
                }
                .inkCommit()
            }
            .buttonStyle(PressStyle())
            .disabled(busy || trimmed.isEmpty)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .frame(maxWidth: 470)
            .frame(maxWidth: .infinity)
            .background(Theme.background)
            .accessibilityIdentifier("create-company-submit")
        }
        .toolbar(firstCompany ? .hidden : .automatic, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .confirmationDialog("Sign out of Thorbis?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await session.signOut() } }
        }
    }

    private var greeting: String {
        let first = session.user?.name?.split(separator: " ").first.map(String.init)
        return first.map { "Welcome, \($0)" } ?? "Welcome to Thorbis"
    }

    private func create() async {
        guard !busy, !trimmed.isEmpty else { return }
        guard trimmed.count <= 120 else { error = "Use 120 characters or fewer."; return }
        busy = true
        defer { busy = false }
        error = nil
        do {
            try await session.createCompany(name: trimmed)
        } catch is CancellationError {
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "The company was not created. Try again."
        }
    }
}

// MARK: - Company details (organization facts)

struct OrganizationProfile: Decodable, Equatable {
    struct Fact: Decodable, Equatable {
        let factKey: String
        let label: String
        let value: String?

        private enum Keys: String, CodingKey { case factKey, label, value }
        init(factKey: String, label: String, value: String?) {
            self.factKey = factKey; self.label = label; self.value = value
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            factKey = try c.decode(String.self, forKey: .factKey)
            label = try c.decode(String.self, forKey: .label)
            if let text = try? c.decode(String.self, forKey: .value) { value = text }
            else if let number = try? c.decode(Double.self, forKey: .value) { value = String(number) }
            else if let flag = try? c.decode(Bool.self, forKey: .value) { value = String(flag) }
            else { value = nil }
        }
    }
    struct Entry: Decodable, Equatable {
        let factKey: String
        let label: String
        let tier: Int
        let required: Bool
        let confirmed: Bool
    }
    let organizationId: String
    let facts: [Fact]
    let catalog: [Entry]
    let coreReady: Bool
    let missingCore: [String]

    func value(_ key: String) -> String? { facts.first { $0.factKey == key }?.value }
}

extension APIClient {
    func organizationProfile() async throws -> OrganizationProfile {
        try await send("GET", "/v1/organization/profile")
    }

    func confirmOrganizationFact(_ key: String, value: String, actorID: String, organizationID: String) async throws {
        struct Identity: Encodable { let actorId: String; let organizationId: String }
        struct Body: Encodable { let factKey: String; let value: String; let expectedIdentity: Identity }
        let _: EmptyResponse = try await send("POST", "/v1/organization/facts",
                                              body: Body(factKey: key, value: value,
                                                         expectedIdentity: Identity(actorId: actorID, organizationId: organizationID)))
    }
}

/// How each fact reads and types on a phone. The server's catalog decides which facts exist,
/// which are required and their order; unknown keys fall back to the server's label.
enum CompanyFact {
    static func label(_ key: String, fallback: String) -> String {
        switch key {
        case "legal_name": "Business name"
        case "business_address": "Business address"
        case "primary_phone": "Business phone"
        case "primary_email": "Business email"
        case "industry": "Trade"
        case "service_areas": "Where you work"
        case "business_description": "About the business"
        case "email_sender_name": "Name on emails"
        case "email_sender_address": "Reply-to email"
        case "dba_names": "Also known as"
        default: fallback
        }
    }

    static func placeholder(_ key: String) -> String {
        switch key {
        case "legal_name": "Wade Plumbing & Heating LLC"
        case "business_address": "Street, city, state, ZIP"
        case "primary_phone": "(555) 555-0123"
        case "primary_email": "office@company.com"
        case "website": "company.com"
        case "industry": "Plumbing, HVAC, electrical…"
        case "service_areas": "Towns or ZIP codes you cover"
        case "business_description": "One or two sentences"
        case "email_sender_name": "Shown as the sender of estimates and invoices"
        case "email_sender_address": "Where customer replies go"
        case "formation_date": "YYYY-MM-DD"
        case "entity_type": "LLC, S corp, sole proprietor…"
        case "formation_jurisdiction": "State where it was formed"
        default: ""
        }
    }

    static func keyboard(_ key: String) -> UIKeyboardType {
        switch key {
        case "primary_phone": .phonePad
        case "primary_email", "email_sender_address": .emailAddress
        case "website": .URL
        case "formation_date": .numbersAndPunctuation
        default: .default
        }
    }

    static func content(_ key: String) -> UITextContentType? {
        switch key {
        case "legal_name": .organizationName
        case "business_address", "mailing_address": .fullStreetAddress
        case "primary_phone": .telephoneNumber
        case "primary_email", "email_sender_address": .emailAddress
        case "website": .URL
        default: nil
        }
    }

    static func multiline(_ key: String) -> Bool {
        ["business_address", "mailing_address", "business_description", "service_areas"].contains(key)
    }

    /// Group order: what setup needs, what customers see, then the legal paperwork.
    static func group(_ entry: OrganizationProfile.Entry) -> Int {
        if entry.required { return 0 }
        if entry.tier >= 2 || ["dba_names", "mailing_address"].contains(entry.factKey) { return 2 }
        return 1
    }
}

@MainActor
final class CompanyDetailsModel: ObservableObject {
    @Published var profile: OrganizationProfile?
    @Published var drafts: [String: String] = [:]
    @Published var loading = false
    @Published var saving = false
    @Published var loadError: String?
    @Published var fieldErrors: [String: String] = [:]

    func load(api: APIClient) async {
        loading = true
        defer { loading = false }
        do {
            let fresh = try await api.organizationProfile()
            profile = fresh
            loadError = nil
            for entry in fresh.catalog where drafts[entry.factKey] == nil {
                drafts[entry.factKey] = fresh.value(entry.factKey) ?? ""
            }
        } catch is CancellationError {
        } catch let problem as Problem where problem.status == 403 {
            loadError = "Company details need the company settings permission. Ask an owner for access."
        } catch {
            loadError = error.localizedDescription
        }
    }

    func changed(_ key: String) -> Bool {
        let draft = (drafts[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !draft.isEmpty && draft != (profile?.value(key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var dirty: Bool { profile?.catalog.contains { changed($0.factKey) } ?? false }

    /// Confirms each changed fact in turn; a refused one keeps its typed value and says why.
    func save(api: APIClient, session: SessionController) async -> Bool {
        guard let profile, let actor = session.user?.id, let org = session.activeOrganization?.id,
              org.lowercased() == profile.organizationId.lowercased() else {
            loadError = "The open company changed. Close this screen and try again."
            return false
        }
        saving = true
        defer { saving = false }
        fieldErrors = [:]
        var allSaved = true
        for entry in profile.catalog where changed(entry.factKey) {
            let value = (drafts[entry.factKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                try await api.confirmOrganizationFact(entry.factKey, value: value, actorID: actor, organizationID: org)
            } catch is CancellationError {
                return false
            } catch {
                allSaved = false
                fieldErrors[entry.factKey] = error.localizedDescription
            }
        }
        let typed = drafts
        await load(api: api)
        // Keep what failed to save on screen.
        for key in fieldErrors.keys { drafts[key] = typed[key] }
        return allSaved
    }
}

/// Settings › Company: the facts customers and payment providers read, typed once.
struct CompanyDetailsView: View {
    /// Inside setup the screen pops itself after a save.
    var onSaved: (() -> Void)? = nil
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = CompanyDetailsModel()
    @State private var saved = 0
    @State private var showMore = false
    @FocusState private var focused: String?

    private var canEdit: Bool { session.can("organization.settings.edit") }

    var body: some View {
        Group {
            if let profile = model.profile {
                form(profile)
            } else if let error = model.loadError {
                VStack(alignment: .leading, spacing: 12) {
                    InlineProblem(message: error)
                    Button("Try again") { Task { await model.load(api: api) } }
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.brandText)
                        .frame(minHeight: 44)
                }
                .padding(Theme.gutter)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                SkeletonRows(count: 5, leading: false)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .accessibilityLabel("Loading company details")
            }
        }
        .background(Theme.background)
        .navigationTitle("Company details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit, model.profile != nil {
                ToolbarItem(placement: .confirmationAction) {
                    if model.saving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }.disabled(!model.dirty)
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .task { await model.load(api: api) }
    }

    private func form(_ profile: OrganizationProfile) -> some View {
        let entries = profile.catalog
        let needed = entries.filter { CompanyFact.group($0) == 0 }
        let shown = entries.filter { CompanyFact.group($0) == 1 }
        let legal = entries.filter { CompanyFact.group($0) == 2 }
        return Form {
            if !profile.coreReady {
                Section {
                    Text(profile.missingCore.count == 1
                         ? "1 detail is still needed to finish setup."
                         : "\(profile.missingCore.count) details are still needed to finish setup.")
                        .font(Theme.font(15))
                }
            }
            Section {
                ForEach(needed, id: \.factKey) { row($0) }
            } header: { Text("Needed for setup") }
            Section {
                ForEach(shown, id: \.factKey) { row($0) }
            } header: { Text("What customers see") } footer: {
                Text("Name on emails and Reply-to email are used when estimates and invoices are emailed.")
            }
            if !legal.isEmpty {
                Section {
                    DisclosureGroup("Legal details", isExpanded: $showMore) {
                        ForEach(legal, id: \.factKey) { row($0) }
                    }
                    .font(Theme.font(15, weight: .medium))
                } footer: { Text("Optional. Payment providers may ask for these.") }
            }
            Section {
                NavigationLink { CompanyFeaturesView() } label: {
                    Label("Plan and features", systemImage: "square.grid.2x2").foregroundStyle(Theme.foreground)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .disabled(!canEdit)
    }

    @ViewBuilder
    private func row(_ entry: OrganizationProfile.Entry) -> some View {
        let key = entry.factKey
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(CompanyFact.label(key, fallback: entry.label))
                    .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                if entry.required && !entry.confirmed {
                    Text("Needed").font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 8).frame(height: 20)
                        .background(Theme.fill, in: Capsule())
                }
            }
            TextField(CompanyFact.placeholder(key), text: Binding(
                get: { model.drafts[key] ?? "" },
                set: { model.drafts[key] = $0; model.fieldErrors[key] = nil }
            ), axis: CompanyFact.multiline(key) ? .vertical : .horizontal)
            .lineLimit(CompanyFact.multiline(key) ? 1...4 : 1...1)
            .font(Theme.font(15))
            .keyboardType(CompanyFact.keyboard(key))
            .textContentType(CompanyFact.content(key))
            .textInputAutocapitalization(CompanyFact.keyboard(key) == .default ? .sentences : .never)
            .autocorrectionDisabled(CompanyFact.keyboard(key) != .default)
            .focused($focused, equals: key)
            .accessibilityLabel(CompanyFact.label(key, fallback: entry.label))
            if let error = model.fieldErrors[key] {
                InlineProblem(message: error).font(Theme.font(13))
            }
        }
        .padding(.vertical, 4)
    }

    private func save() async {
        focused = nil
        if await model.save(api: api, session: session) {
            saved += 1
            onSaved?()
        }
    }
}

/// What is turned on for this company. Thorbis decides this; the screen only shows it (web Settings › Features).
struct CompanyFeaturesView: View {
    @EnvironmentObject private var session: SessionController

    private static let acronyms: Set<String> = ["api", "crm", "id", "sms"]

    static func label(_ key: String) -> String {
        let words = key.split(separator: "_").map { acronyms.contains(String($0)) ? $0.uppercased() : String($0) }
        guard let first = words.first else { return key }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst()).joined(separator: " ")
    }

    var body: some View {
        let keys = session.features.keys.sorted()
        List {
            Section {
                ForEach(keys, id: \.self) { key in
                    let decision = session.features[key] ?? FeatureDecision(enabled: false, released: false, entitled: false, stage: nil, reason: nil)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.label(key)).font(Theme.font(15, weight: .medium))
                            if !decision.enabled {
                                Text(decision.released ? "Not part of the current plan" : "Not released yet")
                                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer()
                        Text(decision.enabled ? "On" : "Off")
                            .font(Theme.font(13, weight: .medium))
                            .foregroundStyle(decision.enabled ? Theme.success : Theme.muted)
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
            } footer: {
                Text("What is turned on for this company. Thorbis manages this list.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Plan and features")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Set up your business

@MainActor
final class BusinessSetupModel: ObservableObject {
    enum Step: String, CaseIterable, Identifiable {
        case details, payments, services, team
        var id: String { rawValue }

        var title: String {
            switch self {
            case .details: "Add your company details"
            case .payments: "Get paid by card"
            case .services: "Add what you sell"
            case .team: "Invite your team"
            }
        }

        var subtitle: String {
            switch self {
            case .details: "Name, address and phone for estimates and invoices"
            case .payments: "Connect Stripe so customers can pay by card"
            case .services: "Services and parts with prices, for fast estimates"
            case .team: "Technicians and office staff, by email"
            }
        }

        var symbol: String {
            switch self {
            case .details: "building.2"
            case .payments: "creditcard"
            case .services: "book.closed"
            case .team: "person.badge.plus"
            }
        }
    }

    @Published var done: Set<Step> = []
    @Published var loaded = false

    func steps(_ session: SessionController) -> [Step] {
        Step.allCases.filter { step in
            switch step {
            case .details, .payments: session.can("organization.settings.edit")
            case .services: session.can("pricebook.edit", feature: "price_book") || session.can("organization.settings.edit", feature: "price_book")
            case .team: session.can("organization.members.manage")
            }
        }
    }

    /// Each step's state comes from the server; one that cannot be read stays open.
    func refresh(api: APIClient, session: SessionController) async {
        let visible = Set(steps(session))
        var next: Set<Step> = []
        if visible.contains(.details), (try? await api.organizationProfile())?.coreReady == true { next.insert(.details) }
        if visible.contains(.payments), (try? await api.merchantReadiness())?.chargesReady == true { next.insert(.payments) }
        if visible.contains(.services), let page = try? await api.priceBookItems(limit: 1), !page.items.isEmpty { next.insert(.services) }
        if visible.contains(.team) {
            let invited = (try? await api.pendingInvitations()).map { !$0.isEmpty } ?? false
            let teammates = invited ? false : ((try? await api.roleMembers()).map { $0.count > 1 } ?? false)
            if invited || teammates { next.insert(.team) }
        }
        done = next
        loaded = true
    }
}

/// The owner's first-run checklist: four steps, each one tap away, each finished on the server.
struct BusinessSetupView: View {
    /// Presented as a sheet after a company is created; pushed from More otherwise.
    var presented = false
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = BusinessSetupModel()
    @State private var inviting = false
    @State private var guided = false

    var body: some View {
        let steps = model.steps(session)
        let doneCount = steps.filter { model.done.contains($0) }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(presented ? "Set up \(session.activeOrganization?.name ?? "your business")" : "Set up your business")
                    .font(Theme.font(24, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
                Text(model.loaded ? "\(doneCount) of \(steps.count) done. Each step takes a minute or two, and you can come back any time from More."
                                  : "Each step takes a minute or two, and you can come back any time from More.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .padding(.top, 6)
                ProgressView(value: Double(doneCount), total: Double(max(steps.count, 1)))
                    .tint(Theme.success)
                    .padding(.top, 16)
                    .opacity(model.loaded ? 1 : 0)
                    .accessibilityLabel("\(doneCount) of \(steps.count) steps done")

                if session.can("organization.settings.edit") {
                    Button { guided = true } label: {
                        Label(doneCount == 0 ? "Start guided setup" : "Continue guided setup", systemImage: "arrow.right.circle")
                            .font(Theme.font(15, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.border))
                            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
                    }
                    .buttonStyle(PressStyle())
                    .padding(.top, 20)
                    .accessibilityIdentifier("setup-guided")
                }

                VStack(spacing: 0) {
                    ForEach(steps) { step in
                        stepRow(step)
                        if step != steps.last { Divider().padding(.leading, 40) }
                    }
                }
                .padding(.top, 20)
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .safeAreaInset(edge: .bottom) {
            if presented, model.loaded, doneCount == steps.count {
                Button { dismiss() } label: { Text("Start using Thorbis").inkCommit() }
                    .buttonStyle(PressStyle())
                    .padding(.horizontal, Theme.gutter).padding(.vertical, 10)
                    .background(Theme.background)
            }
        }
        .navigationTitle(presented ? "" : "Setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presented {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
            }
        }
        .sheet(isPresented: $inviting, onDismiss: { Task { await model.refresh(api: api, session: session) } }) {
            InviteMemberSheet { _ in }
        }
        .fullScreenCover(isPresented: $guided, onDismiss: { Task { await model.refresh(api: api, session: session) } }) {
            NavigationStack { SetupWizardView() }
        }
        .task { await model.refresh(api: api, session: session) }
        .onAppear { Task { await model.refresh(api: api, session: session) } }
    }

    @ViewBuilder
    private func stepRow(_ step: BusinessSetupModel.Step) -> some View {
        let isDone = model.done.contains(step)
        let label = HStack(alignment: .top, spacing: 14) {
            Image(systemName: isDone ? "checkmark.circle.fill" : step.symbol)
                .font(.system(size: 19))
                .foregroundStyle(isDone ? Theme.success : Theme.muted)
                .frame(width: 26)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).font(Theme.font(15, weight: .medium))
                Text(isDone ? "Done" : step.subtitle).font(Theme.font(13)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isDone ? "Done" : "Not done")

        switch step {
        case .details:
            NavigationLink { CompanyDetailsView() } label: { label }.buttonStyle(RowPressStyle())
        case .payments:
            NavigationLink { PaymentsSetupView() } label: { label }.buttonStyle(RowPressStyle())
        case .services:
            NavigationLink {
                WorkspacePriceBookView(api: api, canList: true,
                                       canViewDetail: session.can("organization.settings.edit", feature: "price_book"))
            } label: { label }.buttonStyle(RowPressStyle())
        case .team:
            Button { inviting = true } label: { label }.buttonStyle(RowPressStyle())
        }
    }
}

/// Opens the setup checklist once, right after this phone created a company.
private struct BusinessSetupPrompt: ViewModifier {
    @EnvironmentObject private var session: SessionController
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .task(id: session.generation) {
                guard session.startBusinessSetup, session.phase == .ready else { return }
                session.startBusinessSetup = false
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, session.can("organization.settings.edit") else { return }
                showing = true
            }
            .fullScreenCover(isPresented: $showing) {
                NavigationStack { SetupWizardView() }
            }
    }
}

extension View {
    func businessSetupPrompt() -> some View { modifier(BusinessSetupPrompt()) }
}

#if DEBUG
/// Screenshot harness for the registration screens (see PaperPreview.onboardingScreen).
struct OnboardingPreview: View {
    let screen: String
    @EnvironmentObject private var session: SessionController

    var body: some View {
        switch screen {
        case "onboard-signup": SignUpView(initialEmail: "")
        case "onboard-company": NavigationStack { CreateCompanyForm(firstCompany: true) }
        default:
            if session.phase == .ready {
                NavigationStack {
                    if screen == "onboard-details" { CompanyDetailsView() }
                    else if screen == "onboard-wizard" { SetupWizardView(start: .company) }
                    else if screen == "onboard-trade" { SetupWizardView(start: .trade) }
                    else { BusinessSetupView(presented: true) }
                }
            } else {
                ProgressView()
            }
        }
    }
}
#endif
