import SwiftUI

// The owner's guided setup, one job per screen (design.thorbis.com GuidedFlow). It carries the
// web panel's onboarding wizard (old Thorbis OS: welcome, company, communication, data import,
// services, team, payments, complete) onto what today's API serves:
// - facts:      GET /v1/organization/profile, POST /v1/organization/facts (queued when offline)
// - customers:  POST /v1/customer-imports
// - services:   price book items
// - team:       /v1/organization/invitations
// - get paid:   Stripe hosted onboarding (it, not Thorbis, takes owner ID, SSN, EIN and bank documents)

extension EnvironmentValues {
    /// The setup step a pushed or covered screen belongs to ("Step 2 / 10"), for a screen that
    /// shows it in its own top bar (Paper 09B, the logo crop). Nil outside guided setup.
    @Entry var setupStepLabel: String? = nil
}

enum SetupStep: String, CaseIterable, Identifiable {
    // Paper 08-17 order: welcome, company, communication, import, services, team, payments,
    // operations, ready. Legal details (no Paper screen) follows the company.
    case trade, company, legal, messages, customers, services, team, payments, hours, done
    var id: String { rawValue }

    var title: String {
        switch self {
        case .trade: "Welcome to Thorbis"
        case .company: "Tell us about the business"
        case .legal: "Legal details"
        case .messages: "How customers hear from you"
        case .customers: "Import customers"
        case .services: "Services and pricing"
        case .team: "Invite your team"
        case .payments: "Payments"
        case .hours: "Operations defaults"
        case .done: "You’re ready."
        }
    }

    /// Why we ask (GuidedFlow: reason-for-data on every step).
    var reason: String {
        switch self {
        case .trade: "A few quick answers about your work. Everything can change later."
        case .company: "This shows up on the estimates and invoices your customers see."
        case .legal: "Optional. Payment providers and lenders ask for these, so you only type them once."
        case .messages: "Estimates and invoices are emailed in your company’s name, and replies come back to you."
        case .customers: "Start with your customer list from your old software — or skip and add people as you go."
        case .services: "Add the services and parts you sell with prices — these become line items on estimates and invoices."
        case .team: "We’ll email each person an invite to join with their role. They can accept anytime — this doesn’t block setup."
        case .payments: "Accept customer payments by card. Stripe verifies your identity, business documents and bank account — Thorbis never stores your SSN, EIN or bank details."
        case .hours: "Set your hours, time zone, sales tax and payment terms. Tweak what matters."
        case .done: "Your workspace is live. Anything you skipped can be finished later from More."
        }
    }

    /// How a finished step reads in "Done during setup" (Paper 17).
    var doneTitle: String {
        switch self {
        case .trade: "Your trade"
        case .company: "Business profile"
        case .legal: "Legal details"
        case .messages: "Customer emails"
        case .customers: "Customer import"
        case .services: "Services and pricing"
        case .team: "Team invites"
        case .payments: "Customer payments"
        case .hours: "Hours, tax and terms"
        case .done: ""
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
    @State private var priceItems: [PriceBookListItem] = []
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Hours, tax and terms shows once the server knows those facts.
    private var steps: [SetupStep] {
        SetupStep.steps(session).filter { $0 != .hours || OperatingFacts.offered(facts.profile) }
    }
    private var busy: Bool { advancing || facts.saving || facts.loading || importer.phase == .checking || importer.phase == .importing }
    private var index: Int { steps.firstIndex(of: step) ?? 0 }
    /// Paper's step count, from the steps this person really has: "Step 2 / 10" on a phone
    /// (08-17), "Step 2 of 10" on iPad (T08-T17).
    private var stepLabel: String {
        sizeClass == .regular ? "Step \(index + 1) of \(steps.count)" : "Step \(index + 1) / \(steps.count)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Paper 08-17: the 34 Bold title and its reason, 20 from the edge.
                    VStack(alignment: .leading, spacing: 4) {
                        if step == .done {
                            Image(systemName: "checkmark").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.brand)
                                .frame(width: 48, height: 48)
                                .background(Theme.brandSurface, in: Circle())
                                .padding(.bottom, 8)
                                .accessibilityHidden(true)
                        }
                        Text(step.title).font(Theme.font(34, weight: .bold)).tracking(-0.85)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(step.reason).font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)
                    content.padding(.top, 24)
                    if let stepError { InlineProblem(message: stepError).padding(.horizontal, 4).padding(.top, 14) }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 20).padding(.bottom, 20)
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

    /// Paper 08-17: the back circle, "Step 2 / 10" in the middle, the step's state as a pill, and
    /// a thin brand progress line under them.
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            // One row, so the step count, the pill and Later never overlap at large text.
            HStack(spacing: 8) {
                if index > 0 {
                    Button { withAnimation(.easeOut(duration: 0.2)) { step = steps[index - 1] } } label: {
                        CreamCircleLabel(symbol: "chevron.left")
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Back")
                    .disabled(busy)
                } else {
                    Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                }
                // Phone: 14 Medium in the middle. iPad: 14 SemiBold at the leading edge.
                Text(stepLabel)
                    .font(Theme.font(14, weight: sizeClass == .regular ? .semibold : .medium))
                    .monospacedDigit().foregroundStyle(Theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: sizeClass == .regular ? .leading : .center)
                    .accessibilityHidden(true)
                if !typeSize.isAccessibilitySize { statePill }
                Button { dismiss() } label: {
                    Text(step == .done ? "Close" : "Later")
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
            SetupProgressLine(fraction: Double(index + 1) / Double(max(steps.count, 1)))
                .padding(.horizontal, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(index + 1) of \(steps.count)")
        }
        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 2).padding(.bottom, 4)
        .foregroundStyle(Theme.foreground)
    }

    /// The step's own state, only from real evidence: fields the server refused, values waiting
    /// on this phone, or a step already saved.
    @ViewBuilder private var statePill: some View {
        let toFix = step.facts.filter { facts.fieldErrors[$0] != nil }.count
        if toFix > 0 {
            SetupStatePill(text: "\(toFix) to fix", dot: Theme.statusInProgress, word: Theme.warning, fill: Theme.warningSurface)
        } else if step.facts.contains(where: { facts.queued[$0] != nil }) {
            SetupStatePill(text: "To sync", dot: Theme.statusInProgress, word: Theme.warning, fill: Theme.warningSurface)
        } else if finished.contains(step) && step != .done {
            SetupStatePill(text: "Saved", dot: Theme.statusDone, word: Theme.success, fill: Theme.successSurface)
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Button {
                // Captured at tap time, so a second tap queued behind the first can't advance again.
                let from = step
                Task { await advance(from: from) }
            } label: {
                HStack(spacing: 8) {
                    if facts.saving { ProgressView().tint(.white) }
                    Text(step == .done ? "Start using Thorbis" : "Continue")
                }
                .inkCommit()
            }
            .buttonStyle(PressStyle())
            .disabled(busy)
            .accessibilityIdentifier("setup-continue")
            if index == 0 && step != .done {
                Text("\(max(steps.count - 1, 1)) short steps · answers save when you tap Continue")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            if step == .done {
                Text("You can finish setup later from More.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8).padding(.bottom, 8)
            } else if step.required.isEmpty {
                Button { skip() } label: {
                    Text("Skip for now").font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.subtle)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 12).padding(.bottom, 6)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .trade:
            VStack(alignment: .leading, spacing: 20) {
                tradePicker
                factField("service_areas", "Where you work", placeholder: "Towns, counties or ZIP codes", multiline: true)
                factField("business_description", "About your business", placeholder: "One or two sentences customers will see", multiline: true)
            }
        case .company:
            // Paper 09: logo, name, address, phone; then what the code also keeps (also known as,
            // email, website, mailing address).
            VStack(alignment: .leading, spacing: 16) {
                if facts.profile?.catalog.contains(where: { $0.factKey == "logo" }) == true {
                    // Paper 09B: the logo's crop screen carries this step's count in its top bar
                    // ("Step 2 / 10"; iPad "Step 2 of 10 · Company").
                    CompanyLogoPicker().padding(.bottom, 6)
                        .environment(\.setupStepLabel, sizeClass == .regular ? "\(stepLabel) · Company" : stepLabel)
                }
                factField("legal_name", "Business name", placeholder: "Wade Plumbing & Heating LLC", required: true)
                factField("business_address", "Business address", placeholder: "Street, city, state, ZIP", required: true, multiline: true)
                factField("primary_phone", "Phone", placeholder: "(555) 555-0123", required: true)
                factField("dba_names", "Also known as", placeholder: "The name on your trucks, if different")
                factField("primary_email", "Business email", placeholder: "office@company.com")
                factField("website", "Website", placeholder: "company.com")
                PaperCard {
                    Toggle("Mail goes to the same address", isOn: $mailingSame)
                        .font(Theme.font(16, weight: .medium)).tint(Theme.brand)
                        .padding(.horizontal, PaperCardMetrics.inset)
                        .frame(minHeight: 56)
                }
                if !mailingSame {
                    factField("mailing_address", "Mailing address", placeholder: "Street, city, state, ZIP", multiline: true)
                }
            }
        case .legal:
            VStack(alignment: .leading, spacing: 16) {
                PaperFormField("Business type") {
                    let current = facts.drafts["entity_type"] ?? ""
                    let options = SetupEntityTypes.all + (current.isEmpty || SetupEntityTypes.all.contains(current) ? [] : [current])
                    ThorbisMenu(items: options.map { option in
                        ThorbisMenuItem(option, isSelected: option == current) { draft("entity_type").wrappedValue = option }
                    }, title: "Business type", accessibilityLabel: "Business type") {
                        HStack {
                            Text(current.isEmpty ? "Choose" : current).font(Theme.font(16))
                                .foregroundStyle(current.isEmpty ? Theme.muted : Theme.foreground)
                            Spacer()
                            Image(systemName: "chevron.down").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                        }
                        .fieldWell()
                        .contentShape(Rectangle())
                    }
                }
                factField("formation_jurisdiction", "State where it was formed", placeholder: "Texas")
                PaperSection("Date formed") {
                    Toggle("I know the date", isOn: $hasFormedOn)
                        .font(Theme.font(16, weight: .medium)).tint(Theme.brand)
                        .padding(.horizontal, PaperCardMetrics.inset)
                        .frame(minHeight: 56)
                    if hasFormedOn {
                        WellDivider()
                        HStack {
                            Text("Date").font(Theme.font(16, weight: .medium)).accessibilityHidden(true)
                            Spacer()
                            DatePicker("Date formed", selection: $formedOn, in: ...Date(), displayedComponents: .date)
                                .datePickerStyle(.compact).labelsHidden()
                        }
                        .padding(.horizontal, PaperCardMetrics.inset)
                        .frame(minHeight: 56)
                    }
                }
                note("Owner ID, SSN, EIN, ownership and bank documents are collected by Stripe in Payments, encrypted and never stored in Thorbis.",
                     symbol: "lock")
            }
        case .messages:
            VStack(alignment: .leading, spacing: 16) {
                factField("email_sender_name", "Name on emails", placeholder: "Wade Plumbing")
                factField("email_sender_address", "Replies go to", placeholder: "office@company.com")
                if session.can("organization.settings.edit", feature: "job_booking_notices") {
                    PaperCard {
                        NavigationLink { NoticeSettingsView() } label: {
                            PaperMenuRow("Who hears about jobs", symbol: "bell.badge", subtitle: "Email and in-app alerts for booked, changed and canceled jobs")
                        }
                        .buttonStyle(RowPressStyle())
                    }
                }
            }
        case .hours:
            VStack(alignment: .leading, spacing: 12) {
                OperatingFactsFields(model: facts, week: $week)
                if !facts.queued.isEmpty {
                    Label("Saved on this phone. It syncs when you're back online.", systemImage: "icloud.and.arrow.up")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                }
            }
        case .customers:
            CustomerImportPanel(model: importer) { finished.insert(.customers) }
        case .services:
            // Paper 13: the price book as one card of rows, then the way to add to it.
            VStack(alignment: .leading, spacing: 12) {
                PaperSection("Your price book", count: priceItems.count) {
                    if priceItems.isEmpty {
                        Text("Nothing in your price book yet.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, PaperCardMetrics.inset)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    } else {
                        ForEach(Array(priceItems.prefix(8).enumerated()), id: \.offset) { index, item in
                            if index > 0 { WellDivider(leading: PaperCardMetrics.inset + 38) }
                            // Paper 13: the name, its unit under it, the price at the trailing edge.
                            PaperListRow(leading: .icon("tag"), title: item.description, subtitle: item.unit,
                                         amount: money(item.sellPrice.amount, currency: item.sellPrice.currency))
                        }
                    }
                }
                if priceItems.count > 8 {
                    Text("+ \(priceItems.count - 8) more in your price book").font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                }
                addRow(priceItems.isEmpty ? "Add your first service" : "Add another service") { addingItem = true }
            }
        case .team:
            // Paper 14/14A: who has been invited, then "Add another teammate".
            VStack(alignment: .leading, spacing: 12) {
                if !invites.isEmpty {
                    PaperSection("Invited", count: invites.count) {
                        ForEach(Array(invites.enumerated()), id: \.element.id) { index, invite in
                            if index > 0 { WellDivider() }
                            PaperListRow(title: invite.email, subtitle: "\(invite.roleLabel) · invite sent")
                        }
                    }
                }
                addRow(invites.isEmpty ? "Invite a teammate" : "Add another teammate") { inviting = true }
                note(invites.isEmpty ? "You choose each person’s role when you invite them."
                                     : "Each person gets an email with a link to join — this doesn’t block setup.",
                     symbol: "info.circle")
            }
        case .payments:
            // Paper 15/15A: "Customer payments" with its state, then the way into Stripe.
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Customer payments").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if finished.contains(.payments) {
                        SetupStatePill(text: "Cards on", dot: Theme.statusDone, word: Theme.success, fill: Theme.successSurface)
                    } else {
                        SetupStatePill(text: "Stripe Connect", dot: nil, word: Theme.brandText, fill: Theme.brandSurface)
                    }
                }
                .padding(.horizontal, 4)
                Text(finished.contains(.payments) ? "Card payments are on. Open Stripe to check payouts."
                                                  : "Customers pay invoices by card, and Stripe pays you out to your bank.")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                Button { showStripe = true } label: {
                    RimmedButtonLabel(title: finished.contains(.payments) ? "Manage payouts" : "Set up payouts", symbol: "creditcard")
                }
                .buttonStyle(PressStyle())
                note("Stripe asks for the owner’s name, date of birth, last four of the SSN or an ID photo, the business EIN, and a bank account for payouts.",
                     symbol: "lock")
            }
        case .done:
            doneContent
        }
    }

    /// Paper 17: what got done, then what was skipped, each one tap from finishing.
    private var doneContent: some View {
        let items = steps.filter { $0 != .done }
        let completed = items.filter { !skipped.contains($0) }
        let later = items.filter { skipped.contains($0) }
        return VStack(alignment: .leading, spacing: 20) {
            if !completed.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Done during setup").font(Theme.font(13, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text("\(completed.count) / \(items.count)").font(Theme.font(13)).monospacedDigit()
                    }
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4).padding(.bottom, 8)
                    .accessibilityElement(children: .combine)
                    PaperCard {
                        ForEach(Array(completed.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { WellDivider(leading: PaperCardMetrics.inset + 36) }
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle").font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(Theme.statusDone)
                                    .frame(width: 24)
                                    .accessibilityHidden(true)
                                Text(item.doneTitle).font(Theme.font(16, weight: .medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, PaperCardMetrics.inset)
                            .frame(minHeight: 56)
                            .accessibilityElement(children: .combine)
                            .accessibilityValue("Done")
                        }
                    }
                }
            }
            if !later.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Finish later").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(later) { item in
                                Button { step = item } label: {
                                    Text(item.doneTitle).font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.foreground)
                                        .padding(.horizontal, 14)
                                        .frame(minHeight: 44)
                                        .background(Theme.card, in: Capsule())
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(PressStyle())
                                .accessibilityLabel("Finish \(item.doneTitle)")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Paper's selectable chips: the trade on a card pill, the chosen one in brand.
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
                            if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)) }
                            Text(trade).font(Theme.font(15, weight: .medium))
                        }
                        .foregroundStyle(on ? Theme.brandText : Theme.foreground)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? Theme.brandSurface : Theme.card, in: Capsule())
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

    /// Paper v2: a 13 Semibold label 4 in from its field.
    private func fieldTitle(_ title: String) -> some View {
        Text(title).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 4)
    }

    private func factField(_ key: String, _ title: String, placeholder: String, required: Bool = false, multiline: Bool = false) -> some View {
        PaperFormField(title, note: required ? "Required" : nil, error: facts.fieldErrors[key]) {
            TextField(placeholder, text: draft(key), prompt: .placeholder(placeholder), axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 1...4 : 1...1)
                .textFieldStyle(.plain)
                .font(Theme.font(16))
                .foregroundStyle(Theme.foreground)
                .keyboardType(CompanyFact.keyboard(key))
                .textContentType(CompanyFact.content(key))
                .textInputAutocapitalization(CompanyFact.keyboard(key) == .default ? .words : .never)
                .autocorrectionDisabled(CompanyFact.keyboard(key) != .default)
                .focused($focused, equals: key)
                .fieldWell()
                .accessibilityLabel(title + (required ? ", required" : ""))
        }
    }

    /// Paper 14's quiet info line: a muted glyph and 13pt words, no box.
    private func note(_ text: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            Text(text).font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8).padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Paper 14: "+ Add another teammate", a plain 16 Semibold row with a 44pt target.
    private func addRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).accessibilityHidden(true)
                Text(title).font(Theme.font(16, weight: .semibold))
            }
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
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
        priceItems = page.items.filter { $0.archivedAt == nil }
    }

    private func loadPayments() async {
        if (try? await api.merchantReadiness())?.chargesReady == true { finished.insert(.payments) }
    }
}

/// Paper 08-17's header pill ("Saved", "2 to fix"): a dot and a 13 Semibold word on a tinted capsule.
private struct SetupStatePill: View {
    let text: String
    let dot: Color?
    let word: Color
    let fill: Color

    var body: some View {
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 6, height: 6).accessibilityHidden(true) }
            Text(text).font(Theme.font(13, weight: .semibold)).foregroundStyle(word).lineLimit(1)
        }
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(fill, in: Capsule())
        .fixedSize()
    }
}

/// Paper 08-17's progress: a 4pt card track with the done part in brand blue.
private struct SetupProgressLine: View {
    let fraction: Double

    var body: some View {
        Capsule().fill(Theme.card)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(Theme.brand)
                        .frame(width: proxy.size.width * CGFloat(min(max(fraction, 0), 1)), height: 4)
                }
            }
            .animation(.easeOut(duration: 0.2), value: fraction)
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
