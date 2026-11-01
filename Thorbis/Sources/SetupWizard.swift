import SwiftUI

// The owner's guided setup, one job per screen (design.thorbis.com GuidedFlow). It carries the
// web panel's onboarding wizard (old Thorbis OS: welcome, company, communication, data import,
// services, team, payments, complete) onto what today's API serves:
// - facts:      GET /v1/organization/profile, POST /v1/organization/facts (queued when offline)
// - customers:  POST /v1/customer-imports
// - services:   price book items
// - team:       /v1/organization/invitations
// - get paid:   Stripe hosted onboarding (it, not Thorbis, takes owner ID, SSN, EIN and bank documents)

enum SetupStep: String, CaseIterable, Identifiable {
    case trade, company, legal, messages, hours, customers, services, team, payments, done
    var id: String { rawValue }

    var title: String {
        switch self {
        case .trade: "What kind of work do you do?"
        case .company: "Your company"
        case .legal: "Legal details"
        case .messages: "How customers hear from you"
        case .hours: "Hours, tax and terms"
        case .customers: "Bring your customers"
        case .services: "What you sell"
        case .team: "Your team"
        case .payments: "Get paid"
        case .done: "You’re set up"
        }
    }

    /// Why we ask (GuidedFlow: reason-for-data on every step).
    var reason: String {
        switch self {
        case .trade: "Thorbis uses your trade and service area on your profile and to suggest how jobs are set up."
        case .company: "Your name, phone and address go on every estimate and invoice your customers see."
        case .legal: "Optional. Payment providers and lenders ask for these, so you only type them once."
        case .messages: "Estimates and invoices are emailed in your company’s name, and replies come back to you."
        case .hours: "When you’re open, your time zone, and the sales tax and payment terms you usually charge."
        case .customers: "Import your customer list from your old software, so nobody has to be typed in twice."
        case .services: "Add the services and parts you sell with prices, so estimates take seconds."
        case .team: "Invite technicians and office staff. Each person gets an email to join with their role."
        case .payments: "Connect Stripe to take cards and get payouts. Stripe securely verifies your identity, business documents and bank account. Thorbis never stores your SSN, EIN or bank details."
        case .done: "You can change any of this later from More."
        }
    }

    var symbol: String {
        switch self {
        case .trade: "wrench.and.screwdriver"
        case .company: "building.2"
        case .legal: "doc.text"
        case .messages: "envelope"
        case .hours: "clock"
        case .customers: "person.2"
        case .services: "book.closed"
        case .team: "person.badge.plus"
        case .payments: "creditcard"
        case .done: "checkmark.circle"
        }
    }

    /// Fact keys this step confirms, and which of them must be filled to continue.
    var facts: [String] {
        switch self {
        case .trade: ["industry", "service_areas", "business_description"]
        case .company: ["legal_name", "dba_names", "primary_phone", "primary_email", "website", "business_address", "mailing_address"]
        case .legal: ["entity_type", "formation_jurisdiction", "formation_date"]
        case .messages: ["email_sender_name", "email_sender_address"]
        case .hours: OperatingFacts.keys
        default: []
        }
    }

    var required: [String] {
        self == .company ? ["legal_name", "primary_phone", "business_address"] : []
    }

    @MainActor func permitted(_ session: SessionController) -> Bool {
        switch self {
        case .trade, .company, .legal, .messages, .hours, .payments: session.can("organization.settings.edit")
        case .customers: session.can("customer.create", feature: "core_crm") && session.can("customer.edit", feature: "core_crm")
        case .services: session.can("pricebook.edit", feature: "price_book") || session.can("organization.settings.edit", feature: "price_book")
        case .team: session.can("organization.members.manage")
        case .done: true
        }
    }

    @MainActor static func steps(_ session: SessionController) -> [SetupStep] {
        allCases.filter { $0.permitted(session) }
    }
}

/// The trades the web onboarding offered (old Thorbis INDUSTRIES).
enum SetupTrades {
    static let all = ["HVAC", "Plumbing", "Electrical", "Roofing", "Landscaping", "Cleaning", "Pest control",
                      "Appliance repair", "Garage doors", "Locksmith", "General contracting", "Other"]

    static func parse(_ value: String?) -> Set<String> {
        Set((value ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    /// Known trades in list order, then anything typed elsewhere.
    static func join(_ picked: Set<String>) -> String {
        (all.filter(picked.contains) + picked.subtracting(all).sorted()).joined(separator: ", ")
    }
}

enum SetupEntityTypes {
    static let all = ["Sole proprietor", "LLC", "S corporation", "C corporation", "Partnership", "Nonprofit"]
}

/// Where this phone left setup, per company, so Later picks up on the same step.
enum SetupProgress {
    private static func key(_ organizationID: String) -> String { "thorbis.setup.step.\(organizationID)" }

    static func load(_ organizationID: String?, defaults: UserDefaults = .standard) -> SetupStep? {
        guard let organizationID, let raw = defaults.string(forKey: key(organizationID)) else { return nil }
        return SetupStep(rawValue: raw)
    }

    static func save(_ step: SetupStep, organizationID: String?, defaults: UserDefaults = .standard) {
        guard let organizationID else { return }
        defaults.set(step.rawValue, forKey: key(organizationID))
    }

    /// Steps the owner skipped, so the last screen still offers Finish after setup is reopened.
    static func skipped(_ organizationID: String?, defaults: UserDefaults = .standard) -> Set<SetupStep> {
        guard let organizationID else { return [] }
        return Set((defaults.stringArray(forKey: key(organizationID) + ".skipped") ?? []).compactMap(SetupStep.init(rawValue:)))
    }

    static func saveSkipped(_ steps: Set<SetupStep>, organizationID: String?, defaults: UserDefaults = .standard) {
        guard let organizationID else { return }
        defaults.set(steps.map(\.rawValue).sorted(), forKey: key(organizationID) + ".skipped")
    }
}

struct SetupWizardView: View {
    var start: SetupStep? = nil
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @Environment(\.dismiss) private var dismiss
    @StateObject private var facts = CompanyDetailsModel()
    @StateObject private var importer = CustomerImportModel()
    @State private var step: SetupStep = .trade
    @State private var skipped: Set<SetupStep> = []
    @State private var finished: Set<SetupStep> = []
    /// True while Continue is working, so a double tap can't finish two steps.
    @State private var advancing = false
    @State private var priceItems: [String] = []
    @State private var invites: [TeamInvitation] = []
    @State private var addingItem = false
    @State private var inviting = false
    @State private var showStripe = false
    @State private var mailingSame = true
    @State private var formedOn = Date()
    @State private var hasFormedOn = false
    @State private var week = SetupWeek.standard
    @State private var stepError: String?
    @State private var advanced = 0
    @FocusState private var focused: String?

    /// Hours, tax and terms shows once the server knows those facts.
    private var steps: [SetupStep] {
        SetupStep.steps(session).filter { $0 != .hours || OperatingFacts.offered(facts.profile) }
    }
    private var busy: Bool { advancing || facts.saving || facts.loading || importer.phase == .checking || importer.phase == .importing }
    private var index: Int { steps.firstIndex(of: step) ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: step.symbol).font(.system(size: 26)).foregroundStyle(Theme.markAccent)
                    Text(step.title).font(Theme.font(24, weight: .medium)).padding(.top, 12)
                        .accessibilityAddTraits(.isHeader)
                    Text(step.reason).font(Theme.font(15)).foregroundStyle(Theme.muted).padding(.top, 6)
                    content.padding(.top, 24)
                    if let stepError { InlineProblem(message: stepError).padding(.top, 14) }
                }
                .padding(Theme.gutter)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .id(step)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.foreground)
        .safeAreaInset(edge: .bottom) { footer }
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.success, trigger: advanced)
        .sheet(isPresented: $addingItem) {
            PriceBookItemEditor(api: api, existing: nil) { Task { await loadItems() } }
        }
        .sheet(isPresented: $inviting) {
            InviteMemberSheet { invitation in invites.insert(invitation, at: 0) }
        }
        .sheet(isPresented: $showStripe, onDismiss: { Task { await loadPayments() } }) {
            NavigationStack {
                PaymentsSetupView()
                    .toolbar { ThorbisToolbarItem(placement: .confirmationAction, prominent: true) { Button("Done") { showStripe = false } } }
            }
        }
        .task {
            let resume = start ?? SetupProgress.load(session.activeOrganization?.id)
            if let resume, SetupStep.steps(session).contains(resume) { step = resume } else { step = steps.first ?? .done }
            skipped = SetupProgress.skipped(session.activeOrganization?.id)
            await facts.load(api: api)
            if facts.profile != nil { prefill() } else if !step.facts.isEmpty { stepError = facts.loadError }
            // A server without hours, tax and terms yet: go on to the step after it.
            if step == .hours, facts.profile != nil, !steps.contains(.hours) {
                step = SetupStep.allCases.drop { $0 != .hours }.dropFirst().first(where: steps.contains) ?? .done
            }
            await loadPayments()
        }
        .onChange(of: step) { _, next in
            stepError = nil
            SetupProgress.save(next, organizationID: session.activeOrganization?.id)
            Task {
                if next == .services { await loadItems() }
                if next == .team { invites = (try? await api.pendingInvitations()) ?? [] }
            }
        }
    }

    // MARK: Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if index > 0 && step != .done {
                    Button { withAnimation(.easeOut(duration: 0.2)) { step = steps[index - 1] } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Back")
                    .disabled(busy)
                }
                Spacer()
                Text(step == .done ? "" : "Step \(index + 1) of \(steps.count - 1)")
                    .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                Spacer()
                Button(step == .done ? "Close" : "Later") { dismiss() }
                    .font(Theme.font(15, weight: .medium)).frame(minWidth: 44, minHeight: 44)
            }
            ProgressView(value: Double(min(index, steps.count - 1)), total: Double(max(steps.count - 1, 1)))
                .tint(Theme.foreground)
                .accessibilityLabel("Step \(index + 1) of \(steps.count)")
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 4)
        .foregroundStyle(Theme.foreground)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Button {
                // Captured at tap time, so a second tap queued behind the first can't advance again.
                let from = step
                Task { await advance(from: from) }
            } label: {
                HStack(spacing: 8) {
                    if facts.saving { ProgressView().tint(Theme.onInk) }
                    Text(step == .done ? "Start using Thorbis" : "Continue")
                }
                .inkCommit()
            }
            .buttonStyle(PressStyle())
            .disabled(busy)
            .accessibilityIdentifier("setup-continue")
            if step != .done && step.required.isEmpty {
                Button("Skip for now") { skip() }
                    .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(busy)
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 6)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .trade:
            VStack(alignment: .leading, spacing: 18) {
                tradePicker
                factField("service_areas", "Where you work", placeholder: "Towns, counties or ZIP codes", multiline: true)
                factField("business_description", "About your business", placeholder: "One or two sentences customers will see", multiline: true)
            }
        case .company:
            VStack(alignment: .leading, spacing: 16) {
                factField("legal_name", "Business name", placeholder: "Wade Plumbing & Heating LLC", required: true)
                if facts.profile?.catalog.contains(where: { $0.factKey == "logo" }) == true { CompanyLogoPicker() }
                factField("dba_names", "Also known as", placeholder: "The name on your trucks, if different")
                factField("primary_phone", "Business phone", placeholder: "(555) 555-0123", required: true)
                factField("primary_email", "Business email", placeholder: "office@company.com")
                factField("website", "Website", placeholder: "company.com")
                factField("business_address", "Business address", placeholder: "Street, city, state, ZIP", required: true, multiline: true)
                Toggle("Mail goes to the same address", isOn: $mailingSame)
                    .font(Theme.font(15)).tint(Theme.success).frame(minHeight: 44)
                if !mailingSame {
                    factField("mailing_address", "Mailing address", placeholder: "Street, city, state, ZIP", multiline: true)
                }
            }
        case .legal:
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldTitle("Business type")
                    let current = facts.drafts["entity_type"] ?? ""
                    let options = SetupEntityTypes.all + (current.isEmpty || SetupEntityTypes.all.contains(current) ? [] : [current])
                    ThorbisMenu(items: options.map { option in
                        ThorbisMenuItem(option, isSelected: option == current) { draft("entity_type").wrappedValue = option }
                    }, title: "Business type", accessibilityLabel: "Business type") {
                        HStack {
                            Text(current.isEmpty ? "Choose" : current).font(Theme.font(16))
                                .foregroundStyle(current.isEmpty ? Theme.muted : Theme.foreground)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 13)).foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
                    }
                }
                factField("formation_jurisdiction", "State where it was formed", placeholder: "Texas")
                VStack(alignment: .leading, spacing: 6) {
                    fieldTitle("Date formed")
                    Toggle("I know the date", isOn: $hasFormedOn).font(Theme.font(15)).tint(Theme.success).frame(minHeight: 44)
                    if hasFormedOn {
                        DatePicker("Date formed", selection: $formedOn, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact).labelsHidden()
                    }
                }
                note("Owner ID, SSN, EIN, ownership and bank documents are collected by Stripe in Get paid, encrypted and never stored in Thorbis.",
                     symbol: "lock")
            }
        case .messages:
            VStack(alignment: .leading, spacing: 16) {
                factField("email_sender_name", "Name on emails", placeholder: "Wade Plumbing")
                factField("email_sender_address", "Replies go to", placeholder: "office@company.com")
                if session.can("organization.settings.edit", feature: "job_booking_notices") {
                    NavigationLink { NoticeSettingsView() } label: {
                        PaperMenuRow("Who hears about jobs", symbol: "bell.badge", subtitle: "Email and in-app alerts for booked, changed and canceled jobs")
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
        case .hours:
            VStack(alignment: .leading, spacing: 12) {
                OperatingFactsFields(model: facts, week: $week)
                if !facts.queued.isEmpty {
                    Label("Saved on this phone. It syncs when you're back online.", systemImage: "icloud.and.arrow.up")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
            }
        case .customers:
            CustomerImportPanel(model: importer) { finished.insert(.customers) }
        case .services:
            VStack(alignment: .leading, spacing: 12) {
                if priceItems.isEmpty {
                    Text("Nothing in your price book yet.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                } else {
                    ForEach(priceItems.prefix(8), id: \.self) { name in
                        Label(name, systemImage: "checkmark").font(Theme.font(15)).frame(minHeight: 36, alignment: .leading)
                    }
                    if priceItems.count > 8 { Text("and \(priceItems.count - 8) more").font(Theme.font(13)).foregroundStyle(Theme.muted) }
                }
                bordered(priceItems.isEmpty ? "Add your first service" : "Add another", symbol: "plus") { addingItem = true }
            }
        case .team:
            VStack(alignment: .leading, spacing: 12) {
                ForEach(invites) { invite in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(invite.email).font(Theme.font(15, weight: .medium))
                            Text("\(invite.roleLabel) · invite sent").font(Theme.font(13)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                    }
                    .frame(minHeight: 48)
                }
                bordered(invites.isEmpty ? "Invite someone" : "Invite another", symbol: "person.badge.plus") { inviting = true }
            }
        case .payments:
            VStack(alignment: .leading, spacing: 12) {
                if finished.contains(.payments) {
                    Label("Card payments are on.", systemImage: "checkmark.circle.fill")
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.success)
                }
                bordered(finished.contains(.payments) ? "Review payments" : "Set up with Stripe", symbol: "creditcard") { showStripe = true }
                note("Stripe asks for the owner’s name, date of birth, last four of the SSN or an ID photo, the business EIN, and a bank account for payouts.",
                     symbol: "doc.text.magnifyingglass")
            }
        case .done:
            VStack(alignment: .leading, spacing: 0) {
                ForEach(steps.filter { $0 != .done }) { item in
                    HStack(spacing: 12) {
                        Image(systemName: skipped.contains(item) ? "circle" : "checkmark.circle.fill")
                            .foregroundStyle(skipped.contains(item) ? Theme.muted : Theme.success)
                        Text(item.title).font(Theme.font(15))
                        Spacer()
                        if skipped.contains(item) {
                            Button("Finish") { step = item }
                                .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.brandText)
                                .frame(minHeight: 44)
                        }
                    }
                    .frame(minHeight: 48)
                }
            }
        }
    }

    private var tradePicker: some View {
        let picked = SetupTrades.parse(facts.drafts["industry"])
        return VStack(alignment: .leading, spacing: 8) {
            fieldTitle("Your trades")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(SetupTrades.all, id: \.self) { trade in
                    let on = picked.contains(trade)
                    Button {
                        var next = picked
                        if on { next.remove(trade) } else { next.insert(trade) }
                        facts.drafts["industry"] = SetupTrades.join(next)
                    } label: {
                        HStack(spacing: 6) {
                            if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .medium)) }
                            Text(trade).font(Theme.font(15, weight: on ? .medium : .regular))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? Theme.fill : .clear, in: Capsule())
                        .overlay(Capsule().stroke(on ? Theme.foreground : Theme.border))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: facts.drafts["industry"])
        }
    }

    // MARK: Pieces

    private func draft(_ key: String) -> Binding<String> {
        Binding(get: { facts.drafts[key] ?? "" }, set: { facts.drafts[key] = $0; facts.fieldErrors[key] = nil })
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
    }

    private func factField(_ key: String, _ title: String, placeholder: String, required: Bool = false, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                fieldTitle(title)
                if required { Text("Required").font(Theme.font(12)).foregroundStyle(Theme.muted) }
            }
            TextField(placeholder, text: draft(key), axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 1...4 : 1...1)
                .font(Theme.font(16))
                .keyboardType(CompanyFact.keyboard(key))
                .textContentType(CompanyFact.content(key))
                .textInputAutocapitalization(CompanyFact.keyboard(key) == .default ? .words : .never)
                .autocorrectionDisabled(CompanyFact.keyboard(key) != .default)
                .focused($focused, equals: key)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(minHeight: 46)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .stroke(facts.fieldErrors[key] == nil ? Theme.border : Theme.destructive, lineWidth: 1))
            if let error = facts.fieldErrors[key] {
                InlineProblem(message: error).font(Theme.font(13))
            }
        }
    }

    private func note(_ text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Theme.muted)
            Text(text).font(Theme.font(13)).foregroundStyle(Theme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
    }

    private func bordered(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Theme.font(15, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 48)
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.border))
                .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
        }
        .buttonStyle(PressStyle())
        .foregroundStyle(Theme.foreground)
    }

    // MARK: Flow

    /// Fills obvious defaults the owner can still change: the email sender from the company.
    private func prefill() {
        let company = facts.drafts["legal_name"].flatMap { $0.isEmpty ? nil : $0 } ?? session.activeOrganization?.name ?? ""
        if (facts.drafts["legal_name"] ?? "").isEmpty { facts.drafts["legal_name"] = company }
        if (facts.drafts["email_sender_name"] ?? "").isEmpty { facts.drafts["email_sender_name"] = facts.drafts["dba_names"].flatMap { $0.isEmpty ? nil : $0 } ?? company }
        if (facts.drafts["primary_email"] ?? "").isEmpty, let email = session.user?.email { facts.drafts["primary_email"] = email }
        if let raw = facts.profile?.value("formation_date"), let date = SetupDates.parse(raw) { formedOn = date; hasFormedOn = true }
        let mailing = facts.profile?.value("mailing_address") ?? ""
        if let saved = SetupWeek.parse(facts.profile?.value("business_hours")) { week = saved }
        if (facts.drafts["timezone"] ?? "").isEmpty { facts.drafts["timezone"] = TimeZone.current.identifier }
        mailingSame = mailing.isEmpty || mailing == facts.profile?.value("business_address")
    }

    private func advance(from origin: SetupStep) async {
        guard step == origin, !advancing else { return }
        advancing = true
        defer { advancing = false }
        focused = nil
        stepError = nil
        if step == .done { dismiss(); return }
        if !step.facts.isEmpty, facts.profile == nil {
            // The first load failed (offline, say): try again here instead of a dead end.
            await facts.load(api: api)
            guard facts.profile != nil else {
                stepError = facts.loadError ?? "Your company details did not load. Check your connection and tap Continue again."
                return
            }
            prefill()
        }
        if !step.facts.isEmpty {
            if step == .messages, (facts.drafts["email_sender_address"] ?? "").isEmpty, let email = facts.drafts["primary_email"], !email.isEmpty {
                facts.drafts["email_sender_address"] = email
            }
            if step == .company, mailingSame { facts.drafts["mailing_address"] = facts.drafts["business_address"] }
            if step == .legal, hasFormedOn { facts.drafts["formation_date"] = SetupDates.format(formedOn) }
            if step == .hours {
                if let problem = week.problem { stepError = problem; return }
                facts.drafts["business_hours"] = week.json
            }
            let missing = step.required.filter { (facts.drafts[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !missing.isEmpty {
                for key in missing { facts.fieldErrors[key] = "Needed to finish setup." }
                stepError = missing.count == 1 ? "Fill in the field marked above." : "Fill in the \(missing.count) fields marked above."
                return
            }
            guard await facts.save(api: api, session: session, only: Set(step.facts), outbox: outbox) else {
                stepError = facts.loadError ?? "Some details were not saved. Check the fields marked above."
                return
            }
        }
        guard step == origin else { return }
        if step == .customers, importer.phase == .preview || importer.phase == .map {
            stepError = "Import the file first, or tap Skip for now."
            return
        }
        if step == .payments {
            // Only Stripe's own answer finishes Get paid; otherwise it stays open to come back to.
            await loadPayments()
            guard step == origin else { return }
            if !finished.contains(.payments) { skip(); return }
        }
        finished.insert(step)
        skipped.remove(step)
        SetupProgress.saveSkipped(skipped, organizationID: session.activeOrganization?.id)
        advanced += 1
        moveOn()
    }

    private func skip() {
        skipped.insert(step)
        SetupProgress.saveSkipped(skipped, organizationID: session.activeOrganization?.id)
        moveOn()
    }

    private func moveOn() {
        let next = steps.indices.contains(index + 1) ? steps[index + 1] : .done
        withAnimation(.easeOut(duration: 0.2)) { step = next }
    }

    private func loadItems() async {
        guard let page = try? await api.priceBookItems(limit: 50) else { return }
        priceItems = page.items.filter { $0.archivedAt == nil }.map(\.description)
    }

    private func loadPayments() async {
        if (try? await api.merchantReadiness())?.chargesReady == true { finished.insert(.payments) }
    }
}

enum SetupDates {
    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
    static func format(_ date: Date) -> String {
        let local = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", local.year ?? 0, local.month ?? 1, local.day ?? 1)
    }
    static func parse(_ raw: String) -> Date? {
        guard let utc = formatter().date(from: raw) else { return nil }
        let parts = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: utc)
        return Calendar.current.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12))
    }
}
