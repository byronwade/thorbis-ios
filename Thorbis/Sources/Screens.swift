import SwiftUI

struct NewJobSheet: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @Environment(\.dismiss) var dismiss
    var preselected: Customer? = nil
    @State private var title = ""
    @State private var customerId = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 38, height: 38).background(Theme.fill, in: Circle()) }.accessibilityLabel("Cancel new job").disabled(busy)
                    Spacer()
                    HStack(spacing: 5) {
                        Text(String((session.activeOrganization?.name ?? "W").prefix(1))).font(Theme.font(9, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 16, height: 16).background(Theme.brand, in: RoundedRectangle(cornerRadius: 5))
                        Text(session.activeOrganization?.name ?? "Workspace").font(Theme.font(13, weight: .medium)).lineLimit(1)
                    }.padding(.horizontal, 12).frame(height: 30).background(Theme.fill, in: Capsule())
                    Spacer()
                    Button { Task { await create() } } label: {
                        Group { if busy { ProgressView().tint(.white) } else { Image(systemName: "arrow.up") } }
                            .foregroundStyle(.white).frame(width: 38, height: 38).background(Theme.brand, in: Circle())
                    }.accessibilityLabel("Create job")
                        .disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || customerId.isEmpty || !session.can("job.create", feature: "jobs"))
                }.padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Job title", text: $title, axis: .vertical).font(Theme.font(26, weight: .semibold)).tracking(-0.39).textFieldStyle(.plain)
                            .accessibilityLabel("Job title")
                        Menu {
                            Picker("Customer", selection: $customerId) {
                                Text("Choose a customer").tag("")
                                ForEach(store.customers.filter { $0.archived != true }) { Text($0.name).tag($0.id) }
                            }
                        } label: {
                            Label(store.customers.first(where: { $0.id == customerId })?.name ?? "Customer", systemImage: "person")
                                .font(Theme.font(12, weight: .medium)).padding(.horizontal, 10).frame(minHeight: 28)
                                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8))
                        }.padding(.vertical, 10)
                        if let error { Text(error).font(Theme.font(13)).foregroundStyle(Theme.destructive) }
                    }.padding(.horizontal, 20).padding(.vertical, 8)
                }
                Spacer(minLength: 0)
            }.foregroundStyle(Theme.foreground).background(Theme.background).buttonStyle(.plain)
                .toolbar(.hidden, for: .navigationBar)
                .onAppear { customerId = preselected?.id ?? "" }
        }
    }
    private func create() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await api.createJob(customerId: customerId, title: title.trimmingCharacters(in: .whitespacesAndNewlines))
            await store.refresh(api)
            dismiss()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct ContactActions: View {
    let phone: String?
    let email: String?
    var body: some View {
        if let phone, !phone.isEmpty {
            let number = phone.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel:" + number) { Link(destination: url) { Label(phone, systemImage: "phone") } }
        }
        if let email, let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), let url = URL(string: "mailto:" + encoded) {
            Link(destination: url) { Label(email, systemImage: "envelope") }
        }
    }
}

struct AddressLink: View {
    let address: String
    var coordinates: FieldCoordinates? = nil
    var body: some View {
        if let url {
            Link(destination: url) { Label(address, systemImage: "map") }
        } else { Text(address) }
    }
    private var url: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        let destination = coordinates.map { "\($0.latitude),\($0.longitude)" } ?? address
        components?.queryItems = [URLQueryItem(name: "q", value: destination)]
        return components?.url
    }
}

struct CustomerContactSheet: View {
    let customerID: String
    let onCreated: (CustomerContactRecord) -> Void
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
    private let roles = ["Homeowner", "Spouse", "Tenant", "Property mgr"]

    private var request: FieldContactCreate? {
        CustomerContactDraft(
            name: name,
            role: usesCustomRole ? customRole : role,
            email: showsEmail ? email : nil,
            phone: phone
        ).makeRequest()
    }

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(Theme.border)
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            ZStack {
                Text("New contact")
                    .font(Theme.font(17, weight: .semibold))
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(Theme.font(13, weight: .semibold))
                            .foregroundStyle(Theme.foreground)
                            .frame(width: 32, height: 32)
                            .background(Theme.fill, in: Circle())
                    }
                    .accessibilityLabel("Cancel new contact")
                    .disabled(busy)
                    Spacer()
                    Button("Save") { Task { await save() } }
                        .font(Theme.font(15, weight: .semibold))
                        .foregroundStyle(Theme.brand)
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.45)
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
                        HStack(spacing: 6) {
                            ForEach(roles, id: \.self) { option in
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
                            .foregroundStyle(Theme.brand)
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
                                    .font(Theme.font(12, weight: .semibold))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 32, height: 46)
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
                                .font(Theme.font(14, weight: .medium))
                                .foregroundStyle(Theme.brand)
                                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
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
                        if busy { ProgressView().tint(.white) }
                        else { Text("Save contact").font(Theme.font(15, weight: .semibold)) }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.45)

                Text("The first contact is set as primary automatically.")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .foregroundStyle(Theme.foreground)
        .background(Theme.card)
        .toolbar(.hidden, for: .navigationBar)
        .presentationDetents([.height(600), .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
        .presentationBackground(Theme.card)
        .interactiveDismissDisabled(busy)
    }

    private var canSave: Bool {
        request != nil && !busy && session.can("customer.edit", feature: "core_crm")
    }

    private func contactField(_ title: String, placeholder: String, text: Binding<String>, field: ContactField) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.font(13, weight: .medium))
                .foregroundStyle(Theme.muted)
            TextField(placeholder, text: text)
                .font(field == .phone ? Theme.monoFont(14) : Theme.font(15))
                .keyboardType(field == .phone ? .phonePad : field == .email ? .emailAddress : .default)
                .textInputAutocapitalization(field == .email || field == .phone ? .never : .words)
                .autocorrectionDisabled()
                .focused($focusedField, equals: field)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(focusedField == field ? Theme.brand : Theme.border,
                                lineWidth: focusedField == field ? 1.5 : 1)
                }
        }
    }

    private func roleChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if selected { Image(systemName: "checkmark").font(Theme.font(10, weight: .semibold)) }
                Text(title).font(Theme.font(13, weight: selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? Color.white : Theme.muted)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(selected ? Theme.brand : Theme.fill, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func save() async {
        guard !busy, let request else { return }
        busy = true
        defer { busy = false }
        do {
            let contact = try await api.createFieldContact(customerID, request: request)
            onCreated(contact)
            dismiss()
        } catch is CancellationError {} catch {
            self.error = error.localizedDescription
        }
    }
}

struct MoreView: View {
    @AppStorage("thorbis.appearance") private var appearance = "system"
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var api: APIClient
    @State private var showWorkspaces = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                settingsGroup("Account") {
                    HStack(spacing: 12) {
                        Avatar(name: session.user?.name ?? "", size: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.user?.name ?? "Account").font(Theme.font(15, weight: .medium))
                            if let email = session.user?.email { Text(email).font(Theme.font(13)).foregroundStyle(Theme.muted) }
                        }
                        Spacer()
                    }.frame(minHeight: 54)
                    LabeledContent("Workspace", value: session.activeOrganization?.name ?? "")
                    if session.organizations.count > 1 { Button("Switch workspace") { showWorkspaces = true }.frame(minHeight: 46) }
                }
                settingsGroup("Work") {
                    if session.can("estimate.view", feature: "estimates") { NavigationLink { EstimatesView() } label: { settingsRow("Estimates", icon: "doc.text") } }
                    if session.can("invoice.view", feature: "invoicing") { NavigationLink { InvoicesView() } label: { settingsRow("Invoices", icon: "doc.plaintext") } }
                    if session.can("job.view", feature: "job_booking_notices") { NavigationLink { WorkspaceNoticesView(api: api, available: true).id(session.generation) } label: { settingsRow("Notifications", icon: "bell") } }
                    if session.can("invoice.view", feature: "invoicing") && session.can("invoice.view", feature: "payments") { NavigationLink { WorkspaceRevenueView(api: api, available: true).id(session.generation) } label: { settingsRow("Revenue report", icon: "chart.bar") } }
                    if session.can("pricebook.view", feature: "price_book") { NavigationLink { WorkspacePriceBookView(api: api, canList: true, canViewDetail: session.can("organization.settings.edit", feature: "price_book")).id(session.generation) } label: { settingsRow("Price book", icon: "book.closed") } }
                }
                if let actorID = session.user?.id, let organizationID = session.activeOrganization?.id {
                    settingsGroup("On this device") {
                        NavigationLink { InboxLocalDraftView(actorID: actorID, organizationID: organizationID) } label: { settingsRow("Message drafts", icon: "bubble.left") }
                        ForEach(LocalWorkspaceSection.allCases, id: \.self) { section in
                            if session.can(section.requiredCapability, feature: section.requiredFeature) { NavigationLink { LocalWorkspaceView(section: section, actorID: actorID, organizationID: organizationID) } label: { settingsRow(section.title, icon: "folder") } }
                        }
                    }
                }
                settingsGroup("App") {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.menu)
                    .frame(minHeight: 44)

                    Button { Task { await session.signOut() } } label: {
                        HStack(spacing: 12) { Image(systemName: "rectangle.portrait.and.arrow.right").frame(width: 20); Text("Sign out"); Spacer() }.foregroundStyle(Theme.destructive).frame(minHeight: 46)
                    }
                }
                Text("Thorbis \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    .font(Theme.monoFont(12)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.top, 16).padding(.bottom, 28)
            }.font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground).buttonStyle(.plain)
        }.background(Theme.background).navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showWorkspaces) { WorkspaceSelectionView() }
    }
    private func settingsGroup<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted).padding(.vertical, 10)
            content()
        }.padding(.horizontal, 20)
    }
    private func settingsRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).frame(width: 20).foregroundStyle(Theme.muted)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
        }.frame(minHeight: 46).contentShape(Rectangle())
    }
}
