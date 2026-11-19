import SwiftUI

/// Paper P3 Pick a record, for customers: a sheet with Cancel, "Choose customer" and New across
/// the top, one search field, then the records on one card. Recent customers come first when the
/// search is empty, so the common case is one tap; while typing, the matched letters read bold
/// and (where the caller allows it) the last row adds what was typed as a new customer.
struct CustomerPickerSheet: View {
    let selectedID: String
    let canCreate: Bool
    /// Gets what was typed, so the new customer starts with that name.
    let onNew: (String) -> Void
    let onPick: (String) -> Void
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searching: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var matches: [Customer] {
        let active = store.customers.filter { $0.archived != true }
        guard !trimmed.isEmpty else {
            return active.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
        }
        return active.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            searchField
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(trimmed.isEmpty ? "Recent" : "Results")
                        .font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(matches) { customer in
                            row(customer)
                            if customer.id != matches.last?.id { WellDivider(leading: 16) }
                        }
                        if matches.isEmpty {
                            Text(trimmed.isEmpty ? "No customers yet." : "No customer matches “\(trimmed)”.")
                                .font(Theme.font(14)).foregroundStyle(Theme.muted)
                                .padding(.horizontal, 16)
                                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        }
                        if canCreate && !trimmed.isEmpty {
                            WellDivider(leading: 16)
                            addRow
                        }
                    }
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.surface)
        .presentationDetents([.large])
        .presentationCornerRadius(28)
    }

    /// Cancel pill, the 17 Semibold title, and New in brand text when the caller can create.
    private var header: some View {
        ZStack {
            Text("Choose customer")
                .font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button { dismiss() } label: {
                    Text("Cancel").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(Theme.card, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                Spacer(minLength: 8)
                if canCreate {
                    Button { onNew(query) } label: {
                        Text("New").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.brandText)
                            .padding(.leading, 18).padding(.trailing, 4).frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("New customer")
                }
            }
        }
    }

    /// 48pt field, radius 14; the rim turns to the focus colour while typing.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            TextField("Search customers", text: $query, prompt: .placeholder("Search customers"))
                .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .focused($searching)
                .submitLabel(.search)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: PaperControl.fieldHeight)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: PaperControl.fieldRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Theme.brandText, lineWidth: searching ? 1.5 : 0))
    }

    /// 40pt initials circle, the name in 16 Medium (matched letters bold), a tick on the chosen one.
    private func row(_ customer: Customer) -> some View {
        let chosen = customer.id == selectedID
        return Button { onPick(customer.id) } label: {
            HStack(spacing: 12) {
                Text(initials(customer.name))
                    .font(Theme.font(14, weight: .semibold))
                    .foregroundStyle(chosen ? Theme.brandText : Theme.subtle)
                    .frame(width: 40, height: 40)
                    .background(chosen ? Theme.brandSurface : Theme.quietFill, in: Circle())
                    .accessibilityHidden(true)
                Text(highlighted(customer.name))
                    .font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if chosen {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.brandText)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(customer.name)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// Paper P3's last row: a brand plus and "Add “Pe” as a new customer".
    private var addRow: some View {
        Button { onNew(query) } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.brandText)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                Text("Add “\(trimmed)” as a new customer")
                    .font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.brandText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    private func highlighted(_ name: String) -> AttributedString {
        var text = AttributedString(name)
        if !trimmed.isEmpty, let range = text.range(of: trimmed, options: .caseInsensitive) {
            text[range].font = Theme.font(16, weight: .bold)
        }
        return text
    }
}

struct ContactActions: View {
    @Environment(\.inboxEmail) private var inboxEmail
    let phone: String?
    let email: String?
    var emailContext: String? = nil
    var body: some View {
        if let phone, !phone.isEmpty {
            let number = phone.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel:" + number) { Link(destination: url) { Label(phone, systemImage: "phone").frame(minHeight: 44) } }
        }
        if let email, let emailContext, let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), let url = URL(string: "mailto:" + encoded) {
            Button { inboxEmail(url, context: emailContext) } label: { Label(email, systemImage: "envelope").frame(minHeight: 44) }
        }
    }
}

struct AddressLink: View {
    let address: String
    var coordinates: FieldCoordinates? = nil
    var body: some View {
        if let url {
            Link(destination: url) { Label(address, systemImage: "map").multilineTextAlignment(.leading).frame(minHeight: 44, alignment: .leading) }
        } else { Text(address) }
    }
    private var url: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        let destination = coordinates.map { "\($0.latitude),\($0.longitude)" } ?? address
        components?.queryItems = [URLQueryItem(name: "q", value: destination)]
        return components?.url
    }
}

/// Turn-by-turn driving directions in Apple Maps to a service location.
enum Directions {
    static func url(address: String, coordinates: FieldCoordinates?) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        let destination = coordinates.map { "\($0.latitude),\($0.longitude)" } ?? address
        components?.queryItems = [URLQueryItem(name: "daddr", value: destination), URLQueryItem(name: "dirflg", value: "d")]
        return components?.url
    }
}

struct CustomerContactSheet: View {
    let customerID: String
    let contact: CustomerContactRecord?
    let onSaved: (CustomerContactRecord) -> Void
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role = ""
    @State private var customRole = ""
    @State private var usesCustomRole = false
    @State private var phone = ""
    @State private var email = ""
    @State private var showsEmail = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focusedField: ContactField?
    /// Said under the name when Save is pressed without one; clears as they type.
    @State private var nameProblem: String?

    private enum ContactField: Hashable { case name, phone, email, customRole }
    private static let roles = ["Homeowner", "Spouse", "Tenant", "Property mgr"]

    init(customerID: String, contact: CustomerContactRecord? = nil, onSaved: @escaping (CustomerContactRecord) -> Void) {
        self.customerID = customerID
        self.contact = contact
        self.onSaved = onSaved
        _name = State(initialValue: contact?.name ?? "")
        _phone = State(initialValue: contact?.phone ?? "")
        _email = State(initialValue: contact?.email ?? "")
        _showsEmail = State(initialValue: contact?.email != nil)
        if let existingRole = contact?.role, !existingRole.isEmpty {
            if Self.roles.contains(existingRole) {
                _role = State(initialValue: existingRole)
                _customRole = State(initialValue: "")
                _usesCustomRole = State(initialValue: false)
            } else {
                _role = State(initialValue: "")
                _customRole = State(initialValue: existingRole)
                _usesCustomRole = State(initialValue: true)
            }
        } else {
            _role = State(initialValue: "")
            _customRole = State(initialValue: "")
            _usesCustomRole = State(initialValue: false)
        }
    }

    private var draft: CustomerContactDraft {
        CustomerContactDraft(
            name: name,
            role: usesCustomRole ? customRole : role,
            email: showsEmail ? email : nil,
            phone: phone
        )
    }

    /// The one reason Save is truly off; a missing name is said under the field when it's pressed.
    private var saveBlockedReason: String? {
        session.can("customer.edit", feature: "core_crm") ? nil : "Your role can't change contacts. Ask your office."
    }

    private var canSave: Bool {
        guard !busy, session.can("customer.edit", feature: "core_crm") else { return false }
        return contact == nil ? draft.makeRequest() != nil : draft.makeUpdateRequest() != nil
    }

    /// Paper 26A "New contact": a back circle and the 22 Bold title, Name and Phone on quiet
    /// 50pt fields (the one being typed in ringed in brand), the role as 40pt chips, "Add email"
    /// on its own card, then the commit and where the contact lands.
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                PaperCircleButton(symbol: "xmark",
                                  label: contact == nil ? "Cancel new contact" : "Cancel contact changes",
                                  size: 44, fill: Theme.quietFill) { dismiss() }
                    .disabled(busy)
                PaperSheetTitle(title: contact == nil ? "New contact" : "Edit contact")
            }
            .padding(.top, 14).padding(.bottom, 4)
            .onChange(of: name) { _, _ in nameProblem = nil }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    contactField("Name", placeholder: "Full name", text: $name, field: .name)
                    if let nameProblem { FieldProblem(message: nameProblem).padding(.top, -8) }
                    contactField("Phone", placeholder: "(555) 555-5555", text: $phone, field: .phone)

                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Role")
                        FlowRow(spacing: 8, lineSpacing: 4) {
                            ForEach(Self.roles, id: \.self) { option in
                                roleChip(option, selected: !usesCustomRole && role == option) {
                                    // A second tap takes the role off again.
                                    role = role == option && !usesCustomRole ? "" : option
                                    customRole = ""
                                    usesCustomRole = false
                                }
                            }
                            // Any other role ("Service manager") is typed in.
                            roleChip("Other", selected: usesCustomRole) {
                                role = ""
                                usesCustomRole.toggle()
                                if usesCustomRole { focusedField = .customRole } else { customRole = "" }
                            }
                        }
                        .padding(.vertical, -2)
                        if usesCustomRole {
                            contactField(nil, placeholder: "Service manager", text: $customRole, field: .customRole)
                        }
                    }

                    if showsEmail {
                        HStack(alignment: .bottom, spacing: 8) {
                            contactField("Email", placeholder: "name@example.com", text: $email, field: .email)
                            PaperCircleButton(symbol: "xmark", label: "Remove email", size: 44, fill: Theme.quietFill) {
                                email = ""
                                showsEmail = false
                            }
                            .padding(.bottom, 3)
                        }
                    } else {
                        Button {
                            showsEmail = true
                            focusedField = .email
                        } label: {
                            HStack(spacing: 10) {
                                PaperIcon(.jobPlus, size: 18, color: Theme.brandText)
                                Text("Add email").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.brandText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.leading, 16).padding(.trailing, 14)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Theme.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(PressStyle())
                        .padding(.top, 2)
                    }
                }
                .padding(.top, 14).padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .disabled(busy)

            VStack(spacing: 10) {
                if let error {
                    Text(error)
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button { Task { await save() } } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView().tint(.white) }
                        Text(contact == nil ? "Save contact" : "Save changes")
                    }
                    .paperButton(.commit, tone: .brand, fills: true)
                    .opacity(saveBlockedReason == nil ? 1 : 0.5)
                }
                .buttonStyle(PressStyle())
                // Never pre-disabled for a blank name (pressing says so under it); off only while
                // saving or when this role can't change contacts, which the sentence below says.
                .disabled(busy || saveBlockedReason != nil)
                .accessibilityIdentifier("contact-save")
                // A disabled commit says why (design.thorbis.com "Disabled needs a reason").
                if !busy, let reason = saveBlockedReason {
                    Text(reason).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else if contact == nil, let account = accountName {
                    // Paper 26A: "Added to Marlowe residence".
                    Text("Added to \(account)")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 4).padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .foregroundStyle(Theme.foreground)
        .toolbar(.hidden, for: .navigationBar)
        .thorbisSheetPresentation([.height(showsEmail || usesCustomRole ? 640 : 560), .large])
        .interactiveDismissDisabled(busy)
    }

    /// The account the contact joins, when this phone knows its name.
    private var accountName: String? {
        let name = store.customerName(customerID)
        return name == "Customer" ? nil : name
    }

    /// Paper 26A's field label: 13 Semibold muted, 4 in from the field's edge.
    private func fieldLabel(_ title: String) -> some View {
        Text(title).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 4)
    }

    private func contactField(_ title: String?, placeholder: String, text: Binding<String>, field: ContactField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { fieldLabel(title) }
            TextField(title ?? "Custom role", text: text, prompt: .placeholder(placeholder))
                // design.thorbis.com mobile: input type is at least 16.
                .font(Theme.font(16))
                .keyboardType(field == .phone ? .phonePad : field == .email ? .emailAddress : .default)
                .textInputAutocapitalization(field == .email || field == .phone ? .never : .words)
                .autocorrectionDisabled()
                .textContentType(field == .name ? .name : field == .phone ? .telephoneNumber : field == .email ? .emailAddress : nil)
                .focused($focusedField, equals: field)
                // MA-16: return moves to the next field; the last one saves.
                .submitLabel(nextField(after: field) == nil ? .done : .next)
                .onSubmit {
                    if let next = nextField(after: field) { focusedField = next } else { Task { await save() } }
                }
                .tint(Theme.brand)
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(Theme.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    if focusedField == field {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.brand, lineWidth: 1.5)
                    }
                }
        }
    }

    private func nextField(after field: ContactField) -> ContactField? {
        switch field {
        case .name: .phone
        case .phone: showsEmail ? .email : nil
        case .customRole: showsEmail ? .email : nil
        case .email: nil
        }
    }

    /// Paper 26A's role chip: the sheet chip (40 tall, 14 Medium on ink at 9%); chosen, a 12pt
    /// tick and 14 Semibold brand text on brand at 24%.
    private func roleChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected { PaperIcon(.contactTick, size: 12, color: Theme.brandText) }
                Text(title).font(Theme.font(14, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.brandText : Theme.foreground)
                    .lineLimit(1)
            }
            .padding(.leading, selected ? 12 : 14).padding(.trailing, 14)
            .frame(minHeight: 40)
            .background(selected ? Theme.brandTint : Theme.quietFill, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func save() async {
        guard !busy else { return }
        guard canSave else {
            if saveBlockedReason == nil {
                nameProblem = "Add the contact's name, like Danielle Marlowe."
                focusedField = .name
            }
            return
        }
        busy = true
        defer { busy = false }
        do {
            let saved: CustomerContactRecord
            if let contact {
                guard let request = draft.makeUpdateRequest() else { return }
                saved = try await api.updateFieldContact(customerID, contact.id, request: request)
            } else {
                guard let request = draft.makeRequest() else { return }
                saved = try await api.createFieldContact(customerID, request: request)
            }
            onSaved(saved)
            dismiss()
        } catch is CancellationError {} catch {
            self.error = error.localizedDescription
        }
    }
}

/// MA-11: each More row says what it is at a glance, so phone-only lists get their own glyph
/// and a one-line subtitle instead of four identical folders.
extension LocalWorkspaceSection {
    var moreSymbol: String {
        switch self {
        // Paper v2 drawer icons: the van, the unit, the plan's shield.
        case .fleet: "box.truck"
        case .equipment: "wrench.and.screwdriver"
        case .agreements: "checkmark.shield"
        case .team: "person.badge.plus"
        }
    }

    var moreSubtitle: String {
        switch self {
        case .fleet: "Vehicles, plates and drivers"
        case .equipment: "Units you service, by customer"
        case .agreements: "Service plans, by customer"
        case .team: "People not yet in Thorbis"
        }
    }
}

/// More (redesign 2026-10-31, after Linear's sidebar): the business on top with its switcher, then
/// every place that is not in the bar as a row with a coloured place mark and a count where the phone
/// already knows one, then Settings (where the menu is arranged). It is the bar's More tab, not a hidden menu.
struct MoreView: View {
    @EnvironmentObject var session: SessionController
    @EnvironmentObject private var layout: MenuLayout
    @EnvironmentObject private var store: Store
    @EnvironmentObject var api: APIClient
    @State private var showSettings = false

    private var pinned: [MenuItem] { layout.visibleTabs(session) }

    /// Every place below the bar's, in the person's menu order, grouped.
    private func places(in group: MenuItem.Group) -> [MenuItem] {
        AppMenuContent.menu(tabs: pinned, hidden: layout.hidden, order: layout.menuOrder,
                            permitted: { $0.permitted(session) })
            .filter { $0.group == group && $0.route != nil }
    }

    private var localSections: [LocalWorkspaceSection] {
        guard session.user?.id != nil, session.activeOrganization?.id != nil else { return [] }
        return LocalWorkspaceSection.allCases.filter { session.can($0.requiredCapability, feature: $0.requiredFeature) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "More", subtitle: "Every place in Thorbis")
                VStack(alignment: .leading, spacing: 20) {
                    businessWell
                    ForEach(MenuItem.Group.allCases, id: \.self) { group in
                        let items = places(in: group)
                        let local = group == .phone ? localSections : []
                        if !items.isEmpty || !local.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                SectionHeader(title: group.rawValue, count: items.count + local.count)
                                Well {
                                    ForEach(Array(items.enumerated()), id: \.element) { index, item in
                                        placeRow(item)
                                        if index < items.count - 1 || !local.isEmpty { WellDivider(leading: 54) }
                                    }
                                    ForEach(Array(local.enumerated()), id: \.element) { index, section in
                                        NavigationLink(value: PaperRoute.local(section)) {
                                            MoreRow(title: section.title, symbol: section.moreSymbol, tint: Theme.markGrey,
                                                    subtitle: section.moreSubtitle)
                                        }
                                        if index < local.count - 1 { WellDivider(leading: 54) }
                                    }
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Account")
                        Well {
                            Button { showSettings = true } label: {
                                MoreRow(title: "Settings", symbol: "gearshape", tint: Theme.markGrey,
                                        subtitle: "Account, company, payments, menu and appearance")
                            }
                        }
                    }
                }
                .paperCardMargin()
                Text("Thorbis Field \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    .font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity).padding(.top, 28).padding(.bottom, 32)
            }
            .foregroundStyle(Theme.foreground).buttonStyle(RowPressStyle())
        }
        .background(Theme.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) { SheetSurface { SettingsView() } }
    }

    /// A place: its route under More (iPad; the sidebar opens Schedule, Jobs and Customers itself).
    @ViewBuilder private func placeRow(_ item: MenuItem) -> some View {
        if let route = item.route {
            NavigationLink(value: route) {
                MoreRow(title: item.title, symbol: item.symbol, tint: item.tint, subtitle: item.subtitle, count: count(item))
            }
        }
    }

    /// Counts the phone already holds; places whose count needs another read show none.
    private func count(_ item: MenuItem) -> Int? {
        switch item {
        case .schedule:
            let today = store.jobs.filter { $0.status != "canceled" && (JobFiltering.date($0.scheduledFor).map { Calendar.current.isDateInToday($0) } ?? false) }
            return today.count
        case .jobs: return store.jobs.filter { !["completed", "canceled"].contains($0.status) }.count
        case .customers: return store.customers.isEmpty ? nil : store.customers.count
        default: return nil
        }
    }

    private var businessName: String { session.activeOrganization?.name ?? "Business" }

    /// Every business this person belongs to, the current one checked, then Add a business.
    private var businessItems: [ThorbisMenuItem] {
        session.organizations.map { organization in
            let current = organization.id == session.activeOrganization?.id
            return ThorbisMenuItem(organization.name, isSelected: current) {
                guard !current else { return }
                Task { await session.selectOrganization(id: organization.id) }
            }
        }
    }

    /// The business and its switcher, like the workspace row on top of Linear's menu.
    private var businessWell: some View {
        Well {
            ThorbisMenu(items: businessItems, title: "Switch business",
                        accessibilityLabel: "\(businessName). Switch business") {
                HStack(spacing: 12) {
                    InitialsAvatar(name: businessName, size: 30)
                        .accessibilityHidden(true)
                    Text(businessName)
                        .font(Theme.font(16, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 10)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("more-business-switcher")
        }
    }
}

/// One place in More: a coloured place mark, the name (and what it holds), a count on the right.
struct MoreRow: View {
    let title: String
    let symbol: String
    var tint: Color = Theme.markGrey
    var subtitle: String? = nil
    var count: Int? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 14) {
            PlaceMark(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                }
            }
            Spacer(minLength: 8)
            if let count {
                Text("\(count)").font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 10)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
