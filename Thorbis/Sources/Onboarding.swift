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

/// The shared look for the account screens: the form field well (one column, label above).
private struct AuthField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.font(16))
            .foregroundStyle(Theme.foreground)
            .textFieldStyle(.plain)
            .fieldWell()
    }
}

private extension View {
    func authField() -> some View { modifier(AuthField()) }
}

private func fieldLabel(_ title: String) -> some View {
    Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
}

/// MA-15: plain words in body colour; only the mark is tinted. Sits where the field's help
/// text would, never as a toast.
struct InlineProblem: View {
    let message: String
    var body: some View { FieldProblem(message: message) }
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
    /// Which field the error belongs under; nil for the server's answer.
    @State private var errorField: Field?
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
                    StepLabel(step: 1, of: 3).padding(.bottom, 6)
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
                    if let error, errorField == .name { InlineProblem(message: error).padding(.top, 6) }

                    fieldLabel("Work email").padding(.top, 16)
                    TextField("Email", text: $email, prompt: Text(verbatim: "you@company.com").foregroundStyle(Theme.muted))
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focused, equals: .email)
                        .onSubmit { focused = .password }
                        .authField().padding(.top, 8)
                    if let error, errorField == .email { InlineProblem(message: error).padding(.top, 6) }

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

                    if let error, errorField == .password || errorField == nil {
                        InlineProblem(message: error).padding(.top, 6)
                            .accessibilityIdentifier("signup-error")
                    } else {
                        Text("At least 8 characters.").font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.top, 6)
                    }
                }
                .padding(20)
                .frame(maxWidth: 430, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
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
                .background(Theme.canvas)
                .accessibilityIdentifier("signup-submit")
            }
            .navigationTitle("New account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ThorbisToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .interactiveDismissDisabled(dirty || busy)
            .onAppear { focused = .name }
        }
    }

    private func create() async {
        guard !busy else { return }
        guard !trimmedName.isEmpty else { error = "Enter your name."; errorField = .name; focused = .name; return }
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            error = "Enter the email you’ll sign in with."; errorField = .email; focused = .email; return
        }
        guard password.count >= 8 else { error = "Use at least 8 characters for your password."; errorField = .password; focused = .password; return }
        guard password.count <= 128 else { error = "Use 128 characters or fewer for your password."; errorField = .password; focused = .password; return }
        errorField = nil
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
/// The companies sit on one white panel; the open one carries the accent check. Creating a
/// company and signing out stay one tap away.
struct WorkspaceGateView: View {
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var opening: String?
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            if session.organizations.isEmpty && session.phase != .ready {
                CreateCompanyForm(firstCompany: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if session.phase != .ready {
                            VStack(alignment: .leading, spacing: 6) {
                                Image("ThorbisMark").resizable().scaledToFit().frame(width: 36, height: 36)
                                    .accessibilityHidden(true)
                                Text(session.user?.email.map { "You’re logged in as \($0). Pick the company to open." } ?? "Pick the company to open.")
                                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                                    .padding(.top, 10)
                            }
                            .padding(.horizontal, 4)
                        }
                        if let error = session.error, !error.isEmpty {
                            ErrorBanner(message: error).padding(.horizontal, -Theme.gutter).padding(.top, -8)
                        }
                        PaperSection("Your companies", count: session.organizations.count) {
                            ForEach(session.organizations) { organization in
                                let current = organization.id == session.activeOrganization?.id
                                Button {
                                    opening = organization.id
                                    Task { await session.selectOrganization(id: organization.id); opening = nil; dismiss() }
                                } label: {
                                    PaperListRow(leading: .icon("building.2"), title: organization.name) {
                                        if opening == organization.id {
                                            ProgressView().controlSize(.small)
                                        } else if current {
                                            Image(systemName: "checkmark").font(.system(size: 15, weight: .medium))
                                                .foregroundStyle(Theme.brandText)
                                                .accessibilityLabel("Current")
                                        }
                                    }
                                }
                                .buttonStyle(RowPressStyle())
                                .disabled(opening != nil)
                                .accessibilityAddTraits(current ? .isSelected : [])
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            PaperCard {
                                NavigationLink { CreateCompanyForm(firstCompany: false).thorbisBackButton() } label: {
                                    PaperListRow(leading: .icon("plus"), title: "Create a company")
                                }
                                .buttonStyle(RowPressStyle())
                            }
                            Text("You’ll own the new company. Your other companies stay as they are.")
                                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                                .padding(.horizontal, 4)
                        }
                        if session.phase != .ready {
                            Button { confirmSignOut = true } label: {
                                Text("Sign out").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.destructive)
                                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityIdentifier("workspace-sign-out")
                        }
                    }
                    .padding(.horizontal, PaperCardMetrics.margin)
                    .padding(.top, 8).padding(.bottom, 24)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .background(Theme.canvas)
                .navigationTitle("Choose company")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if session.phase == .ready {
                        ThorbisToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    }
                }
                .thorbisConfirm("Sign out of Thorbis?", isPresented: $confirmSignOut,
                                actions: [ThorbisConfirmAction("Sign out", role: .destructive) { Task { await session.signOut() } }])
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
                    StepLabel(step: 2, of: 3)
                    Text(greeting)
                        .font(Theme.font(30, weight: .medium)).tracking(-0.6)
                        .padding(.top, 6)
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
        .background(Theme.canvas)
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
            .background(Theme.canvas)
            .accessibilityIdentifier("create-company-submit")
        }
        .toolbar(firstCompany ? .hidden : .automatic, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .thorbisConfirm("Sign out of Thorbis?", isPresented: $confirmSignOut,
                        actions: [ThorbisConfirmAction("Sign out", role: .destructive) { Task { await session.signOut() } }])
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
    func organizationProfile(requireFresh: Bool = false) async throws -> OrganizationProfile {
        try await send("GET", "/v1/organization/profile", requireFresh: requireFresh)
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
            loadError = error.plainMessage(subject: "company details")
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
                fieldErrors[entry.factKey] = error.plainMessage(subject: "company details")
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
/// One column on the cream ground: each label above its field, the field's problem in place of
/// its help, and one ink Save pinned above the keyboard (it used to sit in the bar).
struct CompanyDetailsView: View {
    /// Inside setup the screen pops itself after a save.
    var onSaved: (() -> Void)? = nil
    /// "Step 3 of 3" when opened from the first-run setup.
    var step: (Int, Int)? = nil
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
                VStack(alignment: .leading, spacing: 0) {
                    ErrorBanner(message: error, symbol: error.hasPrefix("Company details need") ? "lock" : "exclamationmark.triangle",
                                tint: error.hasPrefix("Company details need") ? Theme.muted : Theme.warning,
                                action: error.hasPrefix("Company details need") ? nil
                                    : .init(title: String(localized: "Try again")) { await model.load(api: api) })
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: 20) {
                    SkeletonSection(rows: 3)
                    SkeletonSection(rows: 2)
                }
                .paperCardMargin().padding(.top, 12)
                .frame(maxHeight: .infinity, alignment: .top)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading company details")
            }
        }
        .background(Theme.canvas)
        .navigationTitle("Company details")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if canEdit, model.profile != nil {
                VStack(spacing: 6) {
                    Button { Task { await save() } } label: {
                        HStack(spacing: 8) {
                            if model.saving { ProgressView().tint(Theme.onInk) }
                            Text("Save details")
                        }
                        .inkCommit(enabled: model.dirty && !model.saving)
                    }
                    .buttonStyle(PressStyle())
                    .disabled(!model.dirty || model.saving)
                    .accessibilityIdentifier("company-details-save")
                    .accessibilityHint(model.dirty ? "" : "No changes to save yet.")
                    // A disabled commit says why (design.thorbis.com "Disabled needs a reason").
                    if !model.dirty && !model.saving {
                        Text("No changes to save yet.").font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 10)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
                .background(Theme.canvas)
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
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let step { StepLabel(step: step.0, of: step.1).padding(.bottom, 6) }
                if !profile.coreReady {
                    Text(profile.missingCore.count == 1
                         ? "1 detail is still needed to finish setup."
                         : "\(profile.missingCore.count) details are still needed to finish setup.")
                        .font(Theme.font(15)).foregroundStyle(Theme.foreground)
                        .padding(.bottom, 8)
                }
                if !canEdit {
                    ErrorBanner(message: "Ask an owner for access to edit company details.", symbol: "lock", tint: Theme.muted)
                        .padding(.horizontal, -Theme.gutter).padding(.bottom, 8)
                }
                group("Needed for setup", needed)
                group("What customers see", shown)
                Text("Name on emails and Reply-to email are used when estimates and invoices are emailed.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .padding(.top, 8)
                if !legal.isEmpty {
                    Button { withMotion { showMore.toggle() } } label: {
                        HStack {
                            Text("Legal details").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                            Text("Optional").font(Theme.font(13)).foregroundStyle(Theme.muted)
                            Spacer()
                            Image(systemName: showMore ? "chevron.up" : "chevron.down")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .padding(.top, 20)
                    .accessibilityValue(showMore ? "Shown" : "Hidden")
                    if showMore {
                        VStack(alignment: .leading, spacing: 16) { ForEach(legal, id: \.factKey) { row($0) } }
                            .padding(.top, 4)
                        Text("Payment providers may ask for these.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.top, 8)
                    }
                }
                PaperCard {
                    NavigationLink { CompanyFeaturesView().thorbisBackButton() } label: {
                        PaperListRow(leading: .icon("square.grid.2x2"), title: "Plan and features")
                    }
                    .buttonStyle(RowPressStyle())
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 12).padding(.bottom, 24)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func group(_ title: String, _ entries: [OrganizationProfile.Entry]) -> some View {
        if !entries.isEmpty {
            Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 16).padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 16) { ForEach(entries, id: \.factKey) { row($0) } }
        }
    }

    @ViewBuilder
    private func row(_ entry: OrganizationProfile.Entry) -> some View {
        let key = entry.factKey
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(CompanyFact.label(key, fallback: entry.label))
                    .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                if entry.required && !entry.confirmed {
                    Text("· Needed").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                }
            }
            .accessibilityHidden(true)
            TextField(CompanyFact.placeholder(key), text: Binding(
                get: { model.drafts[key] ?? "" },
                set: { model.drafts[key] = $0; model.fieldErrors[key] = nil }
            ), axis: CompanyFact.multiline(key) ? .vertical : .horizontal)
            .lineLimit(CompanyFact.multiline(key) ? 1...4 : 1...1)
            .textFieldStyle(.plain)
            .font(Theme.font(16))
            .keyboardType(CompanyFact.keyboard(key))
            .textContentType(CompanyFact.content(key))
            .textInputAutocapitalization(CompanyFact.keyboard(key) == .default ? .sentences : .never)
            .autocorrectionDisabled(CompanyFact.keyboard(key) != .default)
            .focused($focused, equals: key)
            .disabled(!canEdit)
            .fieldWell()
            .accessibilityLabel(CompanyFact.label(key, fallback: entry.label) + (entry.required && !entry.confirmed ? ", needed" : ""))
            if let error = model.fieldErrors[key] {
                InlineProblem(message: error)
            }
        }
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
        .background(Theme.canvas)
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
    @Published private(set) var unavailable: Set<Step> = []
    private var refreshID = UUID()
    private struct Scope: Equatable {
        let actor: String
        let organization: String
        let sessionGeneration: UUID
        let authorityRevision: UUID
        let apiGeneration: UUID
        let apiOrigin: String
        let policyVersion: Int?
        let capabilities: Set<String>
        let priceBookEnabled: Bool
        let visible: Set<Step>
    }
    private var resultScope: Scope?

    private func scope(api: APIClient, session: SessionController) -> Scope? {
        guard session.phase == .ready, let actor = session.user?.id,
              let organization = session.activeOrganization?.id else { return nil }
        return Scope(actor: actor, organization: organization, sessionGeneration: session.generation,
                     authorityRevision: session.authorityRevision, apiGeneration: api.requestGeneration,
                     apiOrigin: api.baseURL, policyVersion: session.policyVersion,
                     capabilities: session.capabilities, priceBookEnabled: session.isFeatureOn("price_book"),
                     visible: Set(steps(session)))
    }

    func isCurrent(api: APIClient, session: SessionController) -> Bool {
        guard let resultScope else { return false }
        return resultScope == scope(api: api, session: session)
    }

    func steps(_ session: SessionController) -> [Step] {
        Step.allCases.filter { step in
            switch step {
            case .details, .payments: session.can("organization.settings.edit")
            case .services: session.can("pricebook.edit", feature: "price_book") || session.can("organization.settings.edit", feature: "price_book")
            case .team: session.can("organization.members.manage")
            }
        }
    }

    /// An unsuccessful read is unknown, never evidence that setup is incomplete.
    func refresh(api: APIClient, session: SessionController) async {
        let id = UUID()
        refreshID = id
        guard let binding = scope(api: api, session: session) else {
            done = []; unavailable = []; resultScope = nil; loaded = false
            return
        }
        let visible = binding.visible
        loaded = false
        resultScope = nil
        var next: Set<Step> = []
        var unknown: Set<Step> = []
        func stillCurrent() -> Bool {
            refreshID == id && binding == scope(api: api, session: session) && !Task.isCancelled
        }
        if visible.contains(.details) {
            do {
                let profile = try await api.organizationProfile(requireFresh: true)
                guard stillCurrent() else { return }
                if profile.organizationId != binding.organization { unknown.insert(.details) }
                else if profile.coreReady { next.insert(.details) }
            } catch { unknown.insert(.details) }
            guard stillCurrent() else { return }
        }
        if visible.contains(.payments) {
            do { if try await api.merchantReadiness(requireFresh: true).chargesReady { next.insert(.payments) } }
            catch { unknown.insert(.payments) }
            guard stillCurrent() else { return }
        }
        if visible.contains(.services) {
            do { let page = try await api.priceBookItems(limit: 1, requireFresh: true); if !page.items.isEmpty { next.insert(.services) } }
            catch { unknown.insert(.services) }
            guard stillCurrent() else { return }
        }
        if visible.contains(.team) {
            let invited = try? await api.pendingInvitations(requireComplete: true, whileCurrent: stillCurrent)
            guard stillCurrent() else { return }
            if invited?.isEmpty == false {
                next.insert(.team)
            } else {
                let members = try? await api.roleMembers(requireComplete: true, whileCurrent: stillCurrent)
                guard stillCurrent() else { return }
                if let members, members.count > 1 { next.insert(.team) }
                else if invited == nil || members == nil { unknown.insert(.team) }
            }
        }
        guard stillCurrent() else { return }
        resultScope = binding
        done = next
        unavailable = unknown
        loaded = true
    }

}

/// The owner's first-run checklist: up to four steps (the ones this role can do), each one tap
/// away, each finished on the server. The steps sit on one white panel with their state as a
/// word; the one ink commit is the next step, or "Start using Thorbis" once all are done.
struct BusinessSetupView: View {
    /// Presented as a sheet after a company is created; pushed from More otherwise.
    var presented = false
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = BusinessSetupModel()
    @State private var inviting = false
    @State private var opened: BusinessSetupModel.Step?

    var body: some View {
        let steps = model.steps(session)
        let current = model.loaded && model.isCurrent(api: api, session: session)
        let doneCount = current ? steps.filter { model.done.contains($0) }.count : 0
        let next = current ? steps.first { !model.done.contains($0) } : nil
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if presented { StepLabel(step: 3, of: 3).padding(.bottom, 6) }
                Text(presented ? "Set up \(session.activeOrganization?.name ?? "your business")" : "Set up your business")
                    .font(Theme.font(24, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
                Text(current && model.unavailable.isEmpty ? "\(doneCount) of \(steps.count) done. Each takes a minute or two; you can come back any time from More."
                                  : "Each step takes a minute or two, and you can come back any time from More.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .padding(.top, 6)
                if current && model.unavailable.isEmpty && !steps.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(steps) { step in
                            Capsule().fill(model.done.contains(step) ? Theme.success : Theme.fill).frame(height: 4)
                        }
                    }
                    .padding(.top, 14)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(doneCount) of \(steps.count) steps done")
                }
                if current && !model.unavailable.isEmpty {
                    ErrorBanner(message: "Some steps couldn’t be checked.") {
                        await model.refresh(api: api, session: session)
                    }
                    .padding(.horizontal, -Theme.gutter)
                    .padding(.top, 8)
                }
                PaperSection("Steps", count: nil) {
                    ForEach(steps) { stepRow($0) }
                }
                .padding(.horizontal, PaperCardMetrics.margin - Theme.gutter)
                .padding(.top, 20)
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if current, let next {
                    Button { open(next) } label: { Text(next.title).inkCommit() }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("setup-next-step")
                } else if presented, current, doneCount == steps.count {
                    Button { dismiss() } label: { Text("Start using Thorbis").inkCommit() }
                        .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 10)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .background(Theme.canvas)
        }
        .navigationTitle(presented ? "" : "Setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presented {
                ThorbisToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
            }
        }
        .navigationDestination(item: $opened) { step in
            switch step {
            case .details: CompanyDetailsView(step: presented ? (3, 3) : nil).thorbisBackButton()
            case .payments: PaymentsSetupView().thorbisBackButton()
            case .services:
                WorkspacePriceBookView(api: api, canList: true,
                                       canViewDetail: session.can("organization.settings.edit", feature: "price_book")).thorbisBackButton()
            case .team: EmptyView()
            }
        }
        .sheet(isPresented: $inviting, onDismiss: { Task { await model.refresh(api: api, session: session) } }) { SheetSurface {
            InviteMemberSheet { _ in }
        } }
        .onChange(of: opened) { old, new in
            // Back from a step: read it again, so its word changes to Done.
            if old != nil, new == nil { Task { await model.refresh(api: api, session: session) } }
        }
        .task(id: [session.authorityRevision, api.requestGeneration]) { await model.refresh(api: api, session: session) }
    }

    private func open(_ step: BusinessSetupModel.Step) {
        if step == .team { inviting = true } else { opened = step }
    }

    private func stepRow(_ step: BusinessSetupModel.Step) -> some View {
        let current = model.loaded && model.isCurrent(api: api, session: session)
        let isDone = current && model.done.contains(step)
        let isUnknown = current && model.unavailable.contains(step)
        let word: StatusWord = !current ? StatusWord(text: String(localized: "Checking…"))
            : isDone ? StatusWord(text: String(localized: "Done"), tint: Theme.success)
            : isUnknown ? StatusWord(text: String(localized: "Couldn’t check"), tint: Theme.warning)
            : StatusWord(text: String(localized: "To do"))
        return Button { open(step) } label: {
            PaperListRow(leading: .icon(step.symbol), title: step.title, subtitle: step.subtitle, subtitleLines: 2,
                         dimmed: isDone, status: word)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityValue(!current ? "Checking" : (isDone ? "Done" : (isUnknown ? "Status unavailable" : "Not done")))
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
            .sheet(isPresented: $showing) { SheetSurface {
                NavigationStack { BusinessSetupView(presented: true) }
            } }
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
                    if screen == "onboard-details" { CompanyDetailsView() } else { BusinessSetupView(presented: true) }
                }
            } else {
                ProgressView()
            }
        }
    }
}
#endif
