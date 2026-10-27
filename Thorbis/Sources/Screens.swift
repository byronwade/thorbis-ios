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
    var body: some View {
        if let url {
            Link(destination: url) { Label(address, systemImage: "map") }
        } else { Text(address) }
    }
    private var url: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: address)]
        return components?.url
    }
}

struct CustomerRecordSheet: View {
    let customerID: String
    let isLocation: Bool
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var kind = "service"
    @State private var primary = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField(isLocation ? "Label" : "Name", text: $name)
                if isLocation {
                    Picker("Type", selection: $kind) { Text("Service").tag("service"); Text("Billing").tag("billing") }
                    TextField("Address", text: $address, axis: .vertical).textContentType(.fullStreetAddress)
                } else {
                    TextField("Email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                    Toggle("Primary contact", isOn: $primary)
                }
                if let error { Text(error).foregroundStyle(Theme.destructive) }
                Button("Save") { Task { await save() } }
                    .disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (isLocation && address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || !session.can("customer.edit", feature: "core_crm"))
                if busy { ProgressView() }
            }.navigationTitle(isLocation ? "New location" : "New contact")
                .toolbar { Button("Cancel") { dismiss() }.disabled(busy) }
        }
    }
    private func save() async {
        busy = true
        defer { busy = false }
        do {
            if isLocation {
                _ = try await api.createFieldLocation(customerID, request: .init(label: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, address: address.trimmingCharacters(in: .whitespacesAndNewlines)))
            } else {
                _ = try await api.createFieldContact(customerID, request: .init(name: name.trimmingCharacters(in: .whitespacesAndNewlines), email: email.isEmpty ? nil : email, phone: phone.isEmpty ? nil : phone, primary: primary))
            }
            dismiss()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
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
