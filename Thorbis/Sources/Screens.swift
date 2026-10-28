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
    @State private var pickingCustomer = false
    @State private var newCustomerName = ""
    @State private var wantsNewCustomer = false
    @FocusState private var titleFocused: Bool
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
                        Image("ThorbisMark").resizable().scaledToFit().frame(width: 16, height: 16).accessibilityHidden(true)
                        Text(session.activeOrganization?.name ?? "Workspace").font(Theme.font(13, weight: .medium)).lineLimit(1)
                    }.padding(.horizontal, 12).frame(height: 30).background(Theme.fill, in: Capsule())
                    Spacer()
                    // Balances the close button so the workspace pill stays centred.
                    Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                }.padding(.horizontal, Theme.gutter).padding(.top, 6).padding(.bottom, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 2) {
                            TextField("Job title", text: $draft.title, axis: .vertical)
                                .font(Theme.font(24, weight: .medium))
                                .tracking(-0.39)
                                .textFieldStyle(.plain)
                                .accessibilityLabel("Job title")
                                .focused($titleFocused)
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

                        // Customer, when and who as pills that wrap on narrow phones (a chip is a pill;
                        // values stay words).
                        FlowRow(spacing: 8, lineSpacing: 8) {
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
                                    .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.brandText)
                                    .frame(minHeight: 44)
                            }
                        }
                    }.padding(.horizontal, Theme.gutter).padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                Spacer(minLength: 0)
            }.foregroundStyle(Theme.foreground).background(Theme.background).buttonStyle(.plain)
                // MA-12: the form finishes where the thumb is. The commit rides above the keyboard.
                .safeAreaInset(edge: .bottom) {
                    Button { Task { await create() } } label: {
                        Group {
                            if busy { ProgressView().tint(Theme.onInk) }
                            else { Text(savedJobID == nil ? "Create job" : "Try again") }
                        }
                        .inkCommit(enabled: draft.canCreate)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(savedJobID == nil ? "Create job" : "Try saving again")
                    .disabled(busy || !draft.canCreate || !session.can("job.create", feature: "jobs"))
                    .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 10)
                    .background(Theme.background)
                }
                .onAppear { if draft.title.isEmpty { titleFocused = true } }
                .toolbar(.hidden, for: .navigationBar)
                // The new-customer sheet opens once the picker has finished closing; presenting
                // both in one pass would drop the second sheet.
                .sheet(isPresented: $pickingCustomer, onDismiss: {
                    if wantsNewCustomer { wantsNewCustomer = false; showNewCustomer = true }
                }) {
                    CustomerPickerSheet(selectedID: draft.customerID,
                                        canCreate: session.can("customer.create", feature: "core_crm"),
                                        onNew: { typed in newCustomerName = typed; wantsNewCustomer = true; pickingCustomer = false }) { id in
                        draft.customerID = id; error = nil; pickingCustomer = false
                    }
                }
                .sheet(isPresented: $showNewCustomer) {
                    NewCustomerSheet(initialName: newCustomerName) { customer in draft.customerID = customer.id; error = nil }
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
                .navigationDestination(for: Customer.self) { CustomerDetailView(customer: $0) }
                .navigationDestination(for: Job.self) { JobDetailView(jobId: $0.id) }
        }
        // A swipe never throws away a typed title (MA-16).
        .interactiveDismissDisabled(busy || (savedJobID == nil && !draft.title.isEmpty))
    }

    private var customerPicker: some View {
        // A menu can't search; with hundreds of customers the picker is a searchable sheet.
        Button { pickingCustomer = true } label: {
            pill(store.customers.first(where: { $0.id == draft.customerID })?.name ?? "Customer",
                 symbol: "person", set: !draft.customerID.isEmpty)
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
        Label { Text(text).lineLimit(1).truncationMode(.tail) } icon: { Image(systemName: symbol) }
            .font(Theme.font(13, weight: .medium))
            .foregroundStyle(set ? Theme.foreground : Theme.muted)
            .padding(.horizontal, 12)
            .frame(height: Theme.chipHeight + 4)
            .frame(maxWidth: 240)
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
                error = "The job was created, but the \(failed.joined(separator: " and ")) didn't save. Tap Try again, or open the job to set it there."
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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
        case .agreements: "signature"
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
    @AppStorage("thorbis.appearance") private var appearance = "system"
    @EnvironmentObject var session: SessionController
    @EnvironmentObject private var layout: MenuLayout
    @EnvironmentObject var api: APIClient
    @EnvironmentObject private var outbox: FieldOutbox
    @State private var showWorkspaces = false
    @State private var showNewJob = false
    @State private var confirmSignOut = false


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
                                NavigationLink(value: PaperRoute.local(section)) { PaperMenuRow(section.title, symbol: section.moreSymbol, subtitle: section.moreSubtitle, tile: Theme.markBurnt) }
                            }
                        }
                    }
                }
                group("Account") {
                    if session.can("organization.settings.edit") {
                        NavigationLink(value: PaperRoute.payments) {
                            PaperMenuRow("Payments", symbol: "creditcard", subtitle: "Stripe setup, card payments and payouts", tile: Theme.markForest)
                        }
                    }
                    NavigationLink(value: PaperRoute.customizeMenu) {
                        PaperMenuRow("Customize menu", symbol: "slider.horizontal.3", subtitle: "Choose your tabs and what shows here", tile: Theme.markAccent)
                    }
                    HStack(spacing: 12) {
                        Text(initials(session.user?.name ?? session.user?.email ?? ""))
                            .font(Theme.font(15, weight: .medium)).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(Theme.brandText, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.user?.name ?? "Account").font(Theme.font(15, weight: .medium))
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
                    Button { confirmSignOut = true } label: {
                        PaperMenuRow(title: "Sign out", symbol: "rectangle.portrait.and.arrow.right", tint: Theme.destructive) { EmptyView() }
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
        .sheet(isPresented: $showWorkspaces) { WorkspaceSelectionView() }
        .sheet(isPresented: $showNewJob) { NewJobSheet() }
        .confirmationDialog("Sign out of Thorbis?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await session.signOut() } }
        } message: {
            Text(outbox.signOutWarning)
        }
    }

    /// MA-05: the same header as every tab root (menu button, 30/500 title). Switching
    /// workspace and New job live in the side menu, so they are not repeated here.
    private var workspaceHeader: some View {
        PaperHeader(title: "More", subtitle: session.activeOrganization?.name ?? "Workspace")
    }

    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperGroupHeader(title: title).padding(.top, 14)
            content()
        }
        .padding(.horizontal, Theme.gutter)
    }
}
