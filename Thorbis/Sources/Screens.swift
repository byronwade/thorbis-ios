import SwiftUI

/// Searchable customer list for the new-job form. Recent customers come first when the
/// search is empty, so the common case is one tap.
struct CustomerPickerSheet: View {
    let selectedID: String
    let canCreate: Bool
    /// Gets what was typed, so the new customer starts with that name.
    let onNew: (String) -> Void
    let onPick: (String) -> Void
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matches: [Customer] {
        let active = store.customers.filter { $0.archived != true }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return active.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
        }
        return active.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if canCreate {
                    Button { onNew(query) } label: {
                        Label(query.isEmpty ? "New customer" : "New customer “\(query)”", systemImage: "person.badge.plus")
                            .font(Theme.font(15, weight: .medium)).frame(minHeight: 44, alignment: .leading)
                    }
                }
                Section(query.isEmpty ? "Recently added" : "\(matches.count) found") {
                    ForEach(matches) { customer in
                        Button { onPick(customer.id) } label: {
                            HStack {
                                Text(customer.name).font(Theme.font(15)).foregroundStyle(Theme.foreground).lineLimit(1)
                                Spacer()
                                if customer.id == selectedID {
                                    Image(systemName: "checkmark").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.brandText)
                                }
                            }
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .accessibilityAddTraits(customer.id == selectedID ? .isSelected : [])
                    }
                }
                if matches.isEmpty {
                    Text(query.isEmpty ? "No customers yet." : "No customer matches “\(query)”.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search customers")
            .navigationTitle("Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ThorbisToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Theme.cardRadius)
    }
}

struct ContactActions: View {
    let phone: String?
    let email: String?
    var body: some View {
        if let phone, !phone.isEmpty {
            let number = phone.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel:" + number) { Link(destination: url) { Label(phone, systemImage: "phone").frame(minHeight: 44) } }
        }
        if let email, let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), let url = URL(string: "mailto:" + encoded) {
            Link(destination: url) { Label(email, systemImage: "envelope").frame(minHeight: 44) }
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

    private var canSave: Bool {
        guard !busy, session.can("customer.edit", feature: "core_crm") else { return false }
        return contact == nil ? draft.makeRequest() != nil : draft.makeUpdateRequest() != nil
    }

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(Theme.border)
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            ZStack {
                Text(contact == nil ? "New contact" : "Edit contact")
                    .font(Theme.font(17, weight: .medium))
                // MA-16: Cancel leading; the one commit is the ink button at the bottom.
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.foreground)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel(contact == nil ? "Cancel new contact" : "Cancel contact changes")
                        .disabled(busy)
                    Spacer()
                }
            }
            .frame(height: 40)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    contactField("Name", placeholder: "Full name", text: $name, field: .name)
                    contactField("Phone", placeholder: "(555) 555-5555", text: $phone, field: .phone)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Role")
                            .font(Theme.font(13, weight: .medium))
                            .foregroundStyle(Theme.muted)
                        FlowRow(spacing: 6, lineSpacing: 0) {
                            ForEach(Self.roles, id: \.self) { option in
                                roleChip(option, selected: !usesCustomRole && role == option) {
                                    role = option
                                    customRole = ""
                                    usesCustomRole = false
                                }
                            }
                        }
                        if usesCustomRole {
                            contactField("Custom role", placeholder: "Enter a role", text: $customRole, field: .customRole)
                                .padding(.top, 2)
                        } else {
                            Button("Enter custom role") {
                                role = ""
                                usesCustomRole = true
                            }
                            .font(Theme.font(12, weight: .medium))
                            .foregroundStyle(Theme.brandText)
                        }
                    }

                    if showsEmail {
                        HStack(alignment: .center, spacing: 8) {
                            contactField("Email", placeholder: "name@example.com", text: $email, field: .email)
                            Button {
                                email = ""
                                showsEmail = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(Theme.font(12, weight: .medium))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 44, height: 46)
                            }
                            .accessibilityLabel("Remove email")
                            .padding(.top, 20)
                        }
                    } else {
                        Button {
                            showsEmail = true
                            focusedField = .email
                        } label: {
                            Text("+ Add email")
                                .font(Theme.font(15, weight: .medium))
                                .foregroundStyle(Theme.brandText)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(busy)

            VStack(spacing: 8) {
                if let error {
                    Text(error)
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { Task { await save() } } label: {
                    Group {
                        if busy { ProgressView().tint(Theme.onInk) }
                        else { Text(contact == nil ? "Save contact" : "Save changes") }
                    }
                    .inkCommit(enabled: canSave)
                }
                .buttonStyle(PressStyle())
                .disabled(!canSave)

                if contact == nil {
                    Text("The first contact is set as primary automatically.")
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .foregroundStyle(Theme.foreground)
        .background(Theme.card)
        .toolbar(.hidden, for: .navigationBar)
        .presentationDetents([.height(600), .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(Theme.cardRadius)
        .presentationBackground(Theme.card)
        .interactiveDismissDisabled(busy)
    }

    private func contactField(_ title: String, placeholder: String, text: Binding<String>, field: ContactField) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.font(13, weight: .medium))
                .foregroundStyle(Theme.muted)
            TextField(placeholder, text: text)
                // design.thorbis.com mobile: input type is at least 16.
                .font(field == .phone ? Theme.monoFont(16) : Theme.font(16))
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
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .stroke(focusedField == field ? Theme.foreground : Theme.border,
                                lineWidth: focusedField == field ? 1.5 : 1)
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

    private func roleChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .medium)) }
                Text(title).font(Theme.font(13, weight: .medium))
            }
            .foregroundStyle(selected ? Theme.onInk : Theme.muted)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(selected ? Theme.ink : Theme.fill, in: Capsule())
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func save() async {
        guard !busy, canSave else { return }
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
        case .fleet: "car"
        case .equipment: "wrench.and.screwdriver"
        case .agreements: "list.bullet.clipboard"
        case .team: "person.badge.plus"
        }
    }

    var moreSubtitle: String {
        switch self {
        case .fleet: "Vehicles, plates and drivers"
        case .equipment: "Units you service, kept on this phone"
        case .agreements: "Service plans, kept on this phone"
        case .team: "People not yet in Thorbis"
        }
    }
}

/// Paper 29 and 65 together: every destination that is not a tab, then account settings.
struct MoreView: View {
    @EnvironmentObject var session: SessionController
    @EnvironmentObject private var layout: MenuLayout
    @EnvironmentObject var api: APIClient
    @State private var showSettings = false

    /// More holds places only. Account, company, payments, menu, appearance, What's new and
    /// sign-out all live in the one Settings.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                workspaceHeader
                // Items placed in the tab bar or hidden in Customize menu are left out here.
                ForEach(MenuItem.Group.allCases, id: \.self) { section in
                    let items = layout.moreItems(in: section, session: session)
                    let local = section == .phone && session.user?.id != nil && session.activeOrganization?.id != nil
                        ? LocalWorkspaceSection.allCases.filter { session.can($0.requiredCapability, feature: $0.requiredFeature) } : []
                    if !items.isEmpty || !local.isEmpty {
                        group(section.rawValue) {
                            ForEach(items) { item in
                                if let route = item.route {
                                    NavigationLink(value: route) { PaperMenuRow(item.title, symbol: item.symbol, subtitle: item.subtitle, tile: item.tint, filled: true) }
                                }
                            }
                            ForEach(local, id: \.self) { section in
                                NavigationLink(value: PaperRoute.local(section)) { PaperMenuRow(section.title, symbol: section.moreSymbol, subtitle: section.moreSubtitle, tile: Theme.markBurnt, filled: true) }
                            }
                        }
                    }
                }
                group("Account") {
                    Button { showSettings = true } label: {
                        PaperMenuRow("Settings", symbol: "gearshape",
                                     subtitle: "Account, company, payments, menu and appearance", tile: Theme.markAccent, filled: true)
                    }
                }
                Text("Thorbis Field \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    .font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity).padding(.top, 28).padding(.bottom, 32)
            }
            .foregroundStyle(Theme.foreground).buttonStyle(RowPressStyle())
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    /// MA-05: the same header as every tab root (30/500 title). Switching business lives in the
    /// bottom bar's menu and New job on the bar's round button, so they are not repeated here.
    private var workspaceHeader: some View {
        PaperHeader(title: "More", subtitle: session.activeOrganization?.name ?? "Workspace")
    }

    /// A titled group of places on one planar card; rows are separated by space, not rules.
    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperGroupHeader(title: title).padding(.top, 14).padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
            PaperCard {
                VStack(alignment: .leading, spacing: 0) { content() }
                    .padding(.vertical, PaperCardMetrics.edge)
            }
        }
        .paperCardMargin()
    }
}
