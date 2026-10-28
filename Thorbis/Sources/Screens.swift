import SwiftUI

struct NewJobSheet: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FieldJobDraft
    @State private var busy = false
    @State private var error: String?
    @State private var createdJobID: String?
    @State private var showNewCustomer = false
    /// Optional time and technician, applied right after the job is created so a new job can be
    /// booked and dispatched in one step instead of three.
    @State private var when: Date?
    @State private var pickingWhen = false
    @State private var tech: FieldAssignee?
    @State private var people: [FieldAssignee] = []
    /// Set once the job exists, so retrying never creates a second job.
    @State private var savedJobID: String?
    @State private var timeSaved = false
    @State private var techSaved = false
    private var canAssign: Bool { session.can("job.assign", feature: "jobs") }

    init(preselected: Customer? = nil) {
        _draft = State(initialValue: FieldJobDraft(customerID: preselected?.id ?? ""))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 38, height: 38).background(Theme.fill, in: Circle()).frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Cancel new job").disabled(busy)
                    Spacer()
                    HStack(spacing: 5) {
                        Text(String((session.activeOrganization?.name ?? "W").prefix(1))).font(Theme.font(9, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 16, height: 16).background(Theme.brand, in: RoundedRectangle(cornerRadius: 5))
                        Text(session.activeOrganization?.name ?? "Workspace").font(Theme.font(13, weight: .medium)).lineLimit(1)
                    }.padding(.horizontal, 12).frame(height: 30).background(Theme.fill, in: Capsule())
                    Spacer()
                    Button { Task { await create() } } label: {
                        Group { if busy { ProgressView().tint(.white) } else { Image(systemName: "arrow.up") } }
                            .foregroundStyle(.white).frame(width: 38, height: 38).background(Theme.brand, in: Circle()).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.accessibilityLabel("Create job")
                        .disabled(busy || !draft.canCreate || !session.can("job.create", feature: "jobs"))
                }.padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 2) {
                            TextField("Job title", text: $draft.title, axis: .vertical)
                                .font(Theme.font(26, weight: .semibold))
                                .tracking(-0.39)
                                .textFieldStyle(.plain)
                                .accessibilityLabel("Job title")
                                .disabled(busy || savedJobID != nil)
                        }
                        .padding(.top, 8)
                        if draft.titleIsTooLong {
                            Text("Job titles can be up to 200 characters.")
                                .font(Theme.font(12))
                                .foregroundStyle(Theme.destructive)
                                .padding(.top, 4)
                        }

                        TextField(
                            text: $draft.notes,
                            prompt: Text("Add description — what's the problem, where, anything the tech should know…")
                                .foregroundStyle(Theme.muted),
                            axis: .vertical
                        ) {
                            Text("Job description")
                        }
                            .font(Theme.font(15))
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(2...6)
                            .textFieldStyle(.plain)
                            .accessibilityLabel("Job description")
                            .padding(.top, 8)
                            .disabled(busy || savedJobID != nil)
                        if draft.notesAreTooLong {
                            Text("Descriptions can be up to 10,000 characters.")
                                .font(Theme.font(12))
                                .foregroundStyle(Theme.destructive)
                                .padding(.top, 4)
                        }

                        // Customer, when and who as pills in one row (a chip is a pill; values stay words).
                        HStack(spacing: 8) {
                            customerPicker
                            if canAssign {
                                Button { pickingWhen = true } label: {
                                    pill(when.map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()) } ?? "When",
                                         symbol: "clock", set: when != nil)
                                }
                                .accessibilityLabel(when == nil ? "Choose a time" : "Time: \(when!.formatted())")
                                .disabled(busy || timeSaved)
                                techPicker
                            }
                        }
                        .padding(.top, 12)

                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(Theme.font(13))
                                .foregroundStyle(Theme.destructive)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 14)
                                .accessibilityIdentifier("new-job-error")
                            if let savedJobID, session.can("job.view", feature: "jobs") {
                                Button("Open the job") { createdJobID = savedJobID }
                                    .font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.brandText)
                                    .frame(minHeight: 44)
                            }
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 8)
                }
                Spacer(minLength: 0)
            }.foregroundStyle(Theme.foreground).background(Theme.background).buttonStyle(.plain)
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $showNewCustomer) {
                    NewCustomerSheet { customer in draft.customerID = customer.id; error = nil }
                }
                .sheet(isPresented: $pickingWhen) {
                    NavigationStack {
                        DatePicker("When", selection: Binding(get: { when ?? Self.nextHour() }, set: { when = $0; timeSaved = false }),
                                   in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.graphical)
                            .padding(.horizontal, 20)
                            .navigationTitle("When")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) { Button("Clear") { when = nil; pickingWhen = false } }
                                ToolbarItem(placement: .topBarTrailing) { Button("Done") { if when == nil { when = Self.nextHour() }; pickingWhen = false } }
                            }
                    }
                    .presentationDetents([.large])
                }
                .navigationDestination(isPresented: createdJobRoute) {
                    if let createdJobID { JobDetailView(jobId: createdJobID) }
                }
        }
    }

    private var customerPicker: some View {
        Menu {
            if session.can("customer.create", feature: "core_crm") {
                Button { showNewCustomer = true } label: { Label("New customer…", systemImage: "person.badge.plus") }
                Divider()
            }
            Button { draft.customerID = "" } label: {
                Label("Choose a customer", systemImage: "person.crop.circle.badge.xmark")
            }
            ForEach(store.customers.filter { $0.archived != true }) { customer in
                Button { draft.customerID = customer.id; error = nil } label: {
                    if customer.id == draft.customerID {
                        Label(customer.name, systemImage: "checkmark")
                    } else {
                        Text(customer.name)
                    }
                }
            }
        } label: {
            Label {
                Text(store.customers.first(where: { $0.id == draft.customerID })?.name ?? "Customer")
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                Image(systemName: "person")
            }
            .font(Theme.font(12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(Theme.fill, in: Capsule())
            .frame(minHeight: 44)
        }
        .accessibilityLabel("Customer: \(store.customers.first(where: { $0.id == draft.customerID })?.name ?? "Choose a customer")")
        // Once the job exists its title, description and customer are fixed; edit them on the job.
        .disabled(busy || savedJobID != nil)
    }

    private var techPicker: some View {
        Menu {
            Button { tech = nil } label: { Label("No technician yet", systemImage: "person.crop.circle.badge.xmark") }
            ForEach(people) { person in
                Button { tech = person; techSaved = false } label: {
                    if person == tech { Label(person.displayName, systemImage: "checkmark") } else { Text(person.displayName) }
                }
            }
        } label: {
            pill(tech?.displayName ?? "Tech", symbol: "person.badge.clock", set: tech != nil)
        }
        .accessibilityLabel("Technician: \(tech?.displayName ?? "none")")
        .disabled(busy || techSaved)
        .task { if people.isEmpty { people = (try? await api.fieldAssignees()) ?? [] } }
    }

    private func pill(_ text: String, symbol: String, set: Bool) -> some View {
        Label { Text(text).lineLimit(1) } icon: { Image(systemName: symbol) }
            .font(Theme.font(12, weight: .medium))
            .foregroundStyle(set ? Theme.foreground : Theme.muted)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(Theme.fill, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    private static func nextHour() -> Date {
        let calendar = Calendar.current
        let next = calendar.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return calendar.date(bySetting: .minute, value: 0, of: next) ?? next
    }

    private var createdJobRoute: Binding<Bool> {
        Binding(
            get: { createdJobID != nil },
            set: { isPresented in
                guard !isPresented, createdJobID != nil else { return }
                createdJobID = nil
                dismiss()
            }
        )
    }

    private func create() async {
        guard !busy, session.can("job.create", feature: "jobs") else { return }
        let sessionGeneration = session.generation
        let organizationID = session.activeOrganization?.id
        error = nil
        busy = true
        defer { busy = false }
        do {
            // A retry after a failed time or tech reuses the job already created, never a second one.
            let jobID: String
            if let savedJobID {
                jobID = savedJobID
            } else {
                guard let request = draft.request else { return }
                jobID = try await api.createFieldJob(request).id
                savedJobID = jobID
            }
            guard session.generation == sessionGeneration,
                  session.activeOrganization?.id == organizationID else { return }
            var failed: [String] = []
            if canAssign, let when, !timeSaved {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                do {
                    _ = try await api.scheduleFieldJob(jobID, request: FieldScheduleRequest(scheduledFor: iso.string(from: when),
                                                                                         timeZone: TimeZone.current.identifier))
                    timeSaved = true
                } catch is CancellationError { return } catch { failed.append("time") }
            }
            if canAssign, let tech, !techSaved {
                do {
                    _ = try await api.assignFieldJob(jobID, request: FieldAssignRequest(userId: tech.userId))
                    techSaved = true
                } catch is CancellationError { return } catch { failed.append("technician") }
            }
            _ = await store.refresh(api)
            guard session.generation == sessionGeneration,
                  session.activeOrganization?.id == organizationID else { return }
            if !failed.isEmpty {
                // Say exactly what didn't save; the arrow retries just that on the same job.
                error = "The job was created, but the \(failed.joined(separator: " and ")) didn't save. Tap the arrow to try again, or open the job to set it there."
                return
            }
            if session.can("job.view", feature: "jobs") {
                createdJobID = jobID
            } else {
                dismiss()
            }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
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
            Link(destination: url) { Label(address, systemImage: "map").frame(minHeight: 44) }
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
                    .font(Theme.font(17, weight: .semibold))
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(Theme.font(13, weight: .semibold))
                            .foregroundStyle(Theme.foreground)
                            .frame(width: 32, height: 32)
                            .background(Theme.fill, in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(contact == nil ? "Cancel new contact" : "Cancel contact changes")
                    .disabled(busy)
                    Spacer()
                    Button("Save") { Task { await save() } }
                        .font(Theme.font(15, weight: .semibold))
                        .foregroundStyle(Theme.brandText)
                        .frame(minHeight: 44)
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
                                    .font(Theme.font(12, weight: .semibold))
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
                                .font(Theme.font(14, weight: .medium))
                                .foregroundStyle(Theme.brandText)
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
                        else { Text(contact == nil ? "Save contact" : "Save changes").font(Theme.font(15, weight: .semibold)) }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.45)

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
        .presentationCornerRadius(20)
        .presentationBackground(Theme.card)
        .interactiveDismissDisabled(busy)
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

/// Paper 29 and 65 together: every destination that is not a tab, then account settings.
struct MoreView: View {
    @AppStorage("thorbis.appearance") private var appearance = "system"
    @EnvironmentObject var session: SessionController
    @EnvironmentObject private var layout: MenuLayout
    @EnvironmentObject var api: APIClient
    @State private var showWorkspaces = false
    @State private var showNewJob = false

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
                                    NavigationLink(value: route) { PaperMenuRow(item.title, symbol: item.symbol, subtitle: item.subtitle, tile: item.tint) }
                                }
                            }
                            ForEach(local, id: \.self) { section in
                                NavigationLink(value: PaperRoute.local(section)) { PaperMenuRow(section.title, symbol: "folder", tile: Theme.markBurnt) }
                            }
                        }
                    }
                }
                group("Account") {
                    NavigationLink(value: PaperRoute.customizeMenu) {
                        PaperMenuRow("Customize menu", symbol: "slider.horizontal.3", subtitle: "Choose your tabs and what shows here", tile: Theme.markAccent)
                    }
                    HStack(spacing: 12) {
                        Text(initials(session.user?.name ?? session.user?.email ?? ""))
                            .font(Theme.font(15, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(Theme.brand, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.user?.name ?? "Account").font(Theme.font(16, weight: .medium))
                            if let email = session.user?.email { Text(email).font(Theme.font(13)).foregroundStyle(Theme.muted) }
                        }
                        Spacer()
                    }
                    .frame(minHeight: 56)
                    .accessibilityElement(children: .combine)
                    PaperMenuRow(title: "Appearance", symbol: "circle.lefthalf.filled") {
                        Picker("Appearance", selection: $appearance) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                        .pickerStyle(.menu).labelsHidden().tint(Theme.muted)
                    }
                    Button { Task { await session.signOut() } } label: {
                        PaperMenuRow(title: "Sign out", symbol: "rectangle.portrait.and.arrow.right", tint: Theme.destructive) { EmptyView() }
                    }
                }
                Text("Thorbis Field \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    .font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity).padding(.top, 28).padding(.bottom, 32)
            }
            .foregroundStyle(Theme.foreground).buttonStyle(.plain)
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showWorkspaces) { WorkspaceSelectionView() }
        .sheet(isPresented: $showNewJob) { NewJobSheet() }
    }

    /// Paper's workspace switcher with the compose action beside it.
    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button { showWorkspaces = true } label: {
                    HStack(spacing: 8) {
                        Image("ThorbisMark").resizable().scaledToFit().padding(3)
                            .frame(width: 24, height: 24).background(Theme.card, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.border))
                            .accessibilityHidden(true)
                        Text(session.activeOrganization?.name ?? "Workspace").font(Theme.font(15, weight: .semibold)).lineLimit(1)
                        if session.organizations.count > 1 {
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.horizontal, 10).frame(minHeight: 44)
                    .background(Theme.card, in: Capsule()).overlay(Capsule().stroke(Theme.border))
                }
                .allowsHitTesting(session.organizations.count > 1)
                .accessibilityLabel("Workspace, \(session.activeOrganization?.name ?? "")")
                Spacer()
                if session.can("job.create", feature: "jobs") {
                    PaperCircleButton(symbol: "square.and.pencil", label: "New job") { showNewJob = true }
                }
            }
            Text("More").font(Theme.font(34, weight: .bold)).tracking(-0.68).padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 4)
    }

    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperGroupHeader(title: title).padding(.top, 14)
            content()
        }
        .padding(.horizontal, Theme.gutter)
    }
}
