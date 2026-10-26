import SwiftUI

func statusIcon(_ s: String) -> (String, Color) {
    switch s {
    case "completed": return ("checkmark.circle.fill", Theme.success)
    case "in_progress", "arrived": return ("circle.lefthalf.filled", Theme.warning)
    case "en_route", "dispatched": return ("arrow.right.circle", Theme.brand)
    case "canceled": return ("xmark.circle", Theme.destructive)
    default: return ("circle", Theme.muted)
    }
}

struct ScheduleView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @State private var range: ScheduleRange = .today
    var items: [Job] { JobFiltering.schedule(store.jobs, range: range) }
    var body: some View {
        List {
            Picker("Schedule range", selection: $range) {
                ForEach(ScheduleRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if let error = store.error { ErrorBanner(message: error) }
            if store.loading { ProgressView("Updating schedule…") }
            ForEach(items) { job in
                NavigationLink(value: job) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let date = JobFiltering.date(job.scheduledFor) {
                            Text(date, format: .dateTime.weekday().hour().minute()).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text(job.title).font(.headline)
                        Text(store.customerName(job.customerId))
                        Label(job.status.statusLabel, systemImage: statusIcon(job.status).0).font(.caption).foregroundStyle(statusIcon(job.status).1)
                    }.padding(.vertical, 6)
                }
            }
            if items.isEmpty && !store.loading {
                ContentUnavailableView("No jobs", systemImage: "calendar", description: Text(range == .unscheduled ? "Jobs without a scheduled time appear here." : "No active jobs in this date range."))
            }
        }
        .navigationTitle("Schedule")
        .refreshable { await store.refresh(api) }
    }
}

struct JobsView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @State private var assignedOnly = false
    @State private var search = ""
    @State private var showNew = false
    var items: [Job] { JobFiltering.jobs(store.jobs, assignedTo: assignedOnly ? (session.user?.id ?? "") : nil, search: search) }
    var body: some View {
        List {
            Toggle("Assigned to me", isOn: $assignedOnly)
            if let error = store.error { ErrorBanner(message: error) }
            if store.loading { ProgressView("Updating jobs…") }
            ForEach(items) { job in
                NavigationLink(value: job) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(job.title).font(.headline)
                        Text(store.customerName(job.customerId)).foregroundStyle(.secondary)
                        Label(job.status.statusLabel, systemImage: statusIcon(job.status).0).font(.caption).foregroundStyle(statusIcon(job.status).1)
                    }
                }
            }
            if items.isEmpty && !store.loading { ContentUnavailableView.search(text: search) }
        }
        .navigationTitle("Jobs")
        .searchable(text: $search, prompt: "Title or job reference")
        .refreshable { await store.refresh(api) }
        .toolbar {
            if session.can("job.create", feature: "jobs") {
                Button("New job", systemImage: "plus") { showNew = true }
            }
        }
        .sheet(isPresented: $showNew) { NewJobSheet() }
    }
}

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
            Form {
                TextField("Job title", text: $title)
                Picker("Customer", selection: $customerId) {
                    Text("Choose a customer").tag("")
                    ForEach(store.customers.filter { $0.archived != true }) { Text($0.name).tag($0.id) }
                }
                if let error { Text(error).foregroundStyle(Theme.destructive) }
                Button { Task { await create() } } label: {
                    if busy { ProgressView() } else { Text("Create job") }
                }.disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || customerId.isEmpty || !session.can("job.create", feature: "jobs"))
            }
            .navigationTitle("New job")
            .toolbar { Button("Cancel") { dismiss() }.disabled(busy) }
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

struct JobDetailView: View {
    let jobId: String
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @State private var job: JobRecord?
    @State private var notes: [JobNoteRecord] = []
    @State private var note = ""
    @State private var reason = ""
    @State private var nextAction = ""
    @State private var showPause = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        List {
            if let error { ErrorBanner(message: error) }
            if let job {
                Section("Job") {
                    LabeledContent("Customer", value: store.customerName(job.customerId))
                    LabeledContent("Status", value: job.status.statusLabel)
                    if let date = JobFiltering.date(job.scheduledFor) { LabeledContent("Scheduled", value: date.formatted()) }
                    if let detail = job.notes, !detail.isEmpty { Text(detail) }
                    if let reason = job.pauseReason { LabeledContent("Pause reason", value: reason) }
                    if let next = job.pauseNextAction { LabeledContent("Next action", value: next) }
                }
                if session.can("job.edit", feature: "jobs") || session.can("job.assign", feature: "jobs") {
                    Section("Actions") {
                        ForEach((job.allowedTransitions ?? []).filter { ["scheduled", "dispatched", "en_route", "arrived", "in_progress", "paused"].contains($0) && session.can(["scheduled", "dispatched"].contains($0) ? "job.assign" : "job.edit", feature: "jobs") }, id: \.self) { target in
                            Button(target == "paused" ? "Pause job…" : "Mark \(target.statusLabel.lowercased())") {
                                if target == "paused" { showPause = true }
                                else { Task { await advance(target) } }
                            }.disabled(busy)
                        }
                    }
                }
                Section("Related work") {
                    NavigationLink("Closeout") { JobCloseoutView(jobID: jobId) }
                    NavigationLink("Media") { JobMediaView(jobID: jobId) }
                    NavigationLink("Follow-ups") { JobFollowUpsView(jobID: jobId) }
                    if session.can("job.assign", feature: "jobs") {
                        NavigationLink("Schedule job") { JobScheduleView(job: job) }
                        NavigationLink("Assign job") { JobAssignmentView(jobID: jobId) }
                    }
                    if let estimateID = job.estimateId, session.can("estimate.view", feature: "estimates") {
                        NavigationLink("Estimate") { EstimateDetailView(id: estimateID) }
                    }
                }
                Section("Notes") {
                    ForEach(notes) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.body)
                            if let date = JobFiltering.date(record.createdAt) { Text(date.formatted()).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if notes.isEmpty { Text("No notes yet").foregroundStyle(.secondary) }
                    if session.can("job.note", feature: "jobs") {
                        TextField("Add a note", text: $note, axis: .vertical).lineLimit(3...8)
                        Button("Save note") { Task { await saveNote() } }
                            .disabled(busy || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.utf16.count > 10_000)
                    }
                }
                Section("Record") {
                    Text(job.id).font(.caption.monospaced()).textSelection(.enabled)
                    LabeledContent("Updated", value: JobFiltering.date(job.updatedAt)?.formatted() ?? job.updatedAt)
                }
            } else if error == nil { ProgressView("Loading job…") }
        }
        .navigationTitle(job?.title ?? "Job")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showPause) {
            NavigationStack {
                Form {
                    TextField("Why are you pausing?", text: $reason, axis: .vertical)
                    TextField("What needs to happen next?", text: $nextAction, axis: .vertical)
                    if let error { Text(error).foregroundStyle(Theme.destructive) }
                    Button("Pause job") { Task { await pause() } }
                        .disabled(busy || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.utf16.count > 2000 || nextAction.utf16.count > 2000)
                }.navigationTitle("Pause job")
                    .toolbar { Button("Cancel") { showPause = false }.disabled(busy) }
            }
        }
    }
    private func load() async {
        do {
            job = try await api.fieldJob(jobId)
            notes = try await api.fieldNotes(jobId)
            error = nil
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func advance(_ target: String) async {
        let request: FieldProgressRequest
        switch target {
        case "scheduled": request = .scheduled
        case "dispatched": request = .dispatched
        case "en_route": request = .enRoute()
        case "arrived": request = .arrived()
        case "in_progress":
            if job?.status == "paused", let auditID = job?.pauseCycleAuditId, session.can("job.edit", feature: "job_pause_cycle_resume") {
                request = .resume(expectedPauseAuditId: auditID)
            } else { request = .start }
        default: return
        }
        await progress(request)
    }
    private func pause() async {
        if await progress(.pause(reason: reason.trimmingCharacters(in: .whitespacesAndNewlines), nextAction: nextAction.trimmingCharacters(in: .whitespacesAndNewlines))) {
            showPause = false
            reason = ""
            nextAction = ""
        }
    }
    @discardableResult private func progress(_ request: FieldProgressRequest) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            job = try await api.progressFieldJob(jobId, request: request)
            await store.refresh(api)
            error = nil
            return true
        } catch is CancellationError { return false } catch { self.error = error.localizedDescription; return false }
    }
    private func saveNote() async {
        busy = true
        defer { busy = false }
        do {
            let saved = try await api.addFieldNote(jobId, body: note.trimmingCharacters(in: .whitespacesAndNewlines))
            notes.append(saved)
            note = ""
            error = nil
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct CustomersView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @State private var showNew = false
    @State private var search = ""
    @State private var newName = ""
    @State private var busy = false
    @State private var error: String?
    var items: [Customer] {
        store.customers.filter { $0.archived != true && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        List {
            if let error = error ?? store.error { ErrorBanner(message: error) }
            if store.loading { ProgressView("Updating customers…") }
            ForEach(items) { customer in
                NavigationLink(value: customer) {
                    Label(customer.name, systemImage: "person.crop.circle")
                }
            }
            if items.isEmpty && !store.loading { ContentUnavailableView.search(text: search) }
        }
        .navigationTitle("Customers")
        .searchable(text: $search, prompt: "Customer name")
        .refreshable { await store.refresh(api) }
        .toolbar {
            if session.can("customer.create", feature: "core_crm") {
                Button("New customer", systemImage: "plus") { showNew = true }.disabled(busy)
            }
        }
        .alert("New customer", isPresented: $showNew) {
            TextField("Name", text: $newName)
            Button("Create") { Task { await create() } }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
    }
    private func create() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await api.createCustomer(name: newName.trimmingCharacters(in: .whitespacesAndNewlines))
            newName = ""
            await store.refresh(api)
            error = nil
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct CustomerDetailView: View {
    let customer: Customer
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @State private var record: CustomerRecord?
    @State private var contacts: [CustomerContactRecord] = []
    @State private var locations: [ServiceLocationRecord] = []
    @State private var error: String?
    @State private var showNewJob = false
    @State private var showContact = false
    @State private var showLocation = false
    var jobs: [Job] { store.jobs.filter { $0.customerId == customer.id } }
    var body: some View {
        List {
            if let error { ErrorBanner(message: error) }
            if let record {
                Section("Customer") {
                    ContactActions(phone: record.phone, email: record.email)
                    if let address = record.address { AddressLink(address: address) }
                    if let terms = record.billingTerms { LabeledContent("Billing terms", value: terms) }
                    if let account = record.accountType { LabeledContent("Account", value: account.statusLabel) }
                }
            }
            Section("Contacts") {
                ForEach(contacts) { contact in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(contact.name).font(.headline)
                        if contact.primary { Text("Primary contact").font(.caption).foregroundStyle(.secondary) }
                        if let role = contact.role { Text(role).font(.subheadline) }
                        ContactActions(phone: contact.phone, email: contact.email)
                    }.padding(.vertical, 4)
                }
                if contacts.isEmpty { Text("No contacts").foregroundStyle(.secondary) }
                if session.can("customer.edit", feature: "core_crm") { Button("Add contact") { showContact = true } }
            }
            Section("Locations") {
                ForEach(locations) { location in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(location.label).font(.headline)
                        Text(location.kind.statusLabel).font(.caption).foregroundStyle(.secondary)
                        AddressLink(address: location.address)
                        if let notes = location.notes { Text(notes) }
                        if let parking = location.parking { LabeledContent("Parking", value: parking) }
                        if let dogs = location.dogOnSite { LabeledContent("Dogs on site", value: dogs) }
                    }.padding(.vertical, 4)
                }
                if locations.isEmpty { Text("No locations").foregroundStyle(.secondary) }
                if session.can("customer.edit", feature: "core_crm") { Button("Add location") { showLocation = true } }
            }
            if session.can("job.view", feature: "jobs") {
                Section("Jobs") {
                    ForEach(jobs) { job in NavigationLink(value: job) { Text(job.title) } }
                    if jobs.isEmpty { Text("No jobs").foregroundStyle(.secondary) }
                    if session.can("job.create", feature: "jobs") { Button("New job") { showNewJob = true } }
                }
            }
        }
        .navigationTitle(customer.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showNewJob) { NewJobSheet(preselected: customer) }
        .sheet(isPresented: $showContact, onDismiss: { Task { await load() } }) { CustomerRecordSheet(customerID: customer.id, isLocation: false) }
        .sheet(isPresented: $showLocation, onDismiss: { Task { await load() } }) { CustomerRecordSheet(customerID: customer.id, isLocation: true) }
    }
    private func load() async {
        do {
            record = try await api.fieldCustomer(customer.id)
            contacts = try await api.fieldContacts(customer.id)
            locations = try await api.fieldLocations(customer.id)
            error = nil
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
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var api: APIClient
    @State private var showWorkspaces = false
    var body: some View {
        List {
            Section("Workspace") {
                LabeledContent("Workspace", value: session.activeOrganization?.name ?? "")
                LabeledContent("Signed in", value: session.user?.name ?? session.user?.email ?? "")
                if session.organizations.count > 1 { Button("Switch workspace") { showWorkspaces = true } }
            }
            Section("Work") {
                if session.can("job.view", feature: "jobs") {
                    NavigationLink { ScheduleView() } label: { Label("Schedule", systemImage: "calendar") }
                    NavigationLink { JobsView() } label: { Label("Jobs", systemImage: "briefcase") }
                }
                if session.can("customer.view", feature: "core_crm") {
                    NavigationLink { CustomersView() } label: { Label("Customers", systemImage: "person.2") }
                }
                if session.can("estimate.view", feature: "estimates") {
                    NavigationLink { EstimatesView() } label: { Label("Estimates", systemImage: "doc.text") }
                }
                if session.can("invoice.view", feature: "invoicing") {
                    NavigationLink { InvoicesView() } label: { Label("Invoices", systemImage: "doc.plaintext") }
                }
            }
            Section("Workspace tools") {
                if session.can("job.view", feature: "job_booking_notices") {
                    NavigationLink("Notifications") { WorkspaceNoticesView(api: api, available: true).id(session.generation) }
                }
                if session.can("invoice.view", feature: "invoicing") && session.can("invoice.view", feature: "payments") {
                    NavigationLink("Revenue report") { WorkspaceRevenueView(api: api, available: true).id(session.generation) }
                }
                if session.can("pricebook.view", feature: "price_book") {
                    NavigationLink("Price Book") { WorkspacePriceBookView(api: api, canList: true, canViewDetail: session.can("organization.settings.edit", feature: "price_book")).id(session.generation) }
                }
            }
            if let actorID = session.user?.id, let organizationID = session.activeOrganization?.id {
                Section("On this device") {
                    NavigationLink { InboxLocalDraftView(actorID: actorID, organizationID: organizationID) } label: { Label("Message drafts", systemImage: "bubble.left") }
                    ForEach(LocalWorkspaceSection.allCases, id: \.self) { section in
                        if session.can(section.requiredCapability, feature: section.requiredFeature) {
                            NavigationLink(section.title) { LocalWorkspaceView(section: section, actorID: actorID, organizationID: organizationID) }
                        }
                    }
                }
            }
            Section {
                Button("Sign out", role: .destructive) { Task { await session.signOut() } }
            }
        }
        .navigationTitle("More")
        .sheet(isPresented: $showWorkspaces) { WorkspaceSelectionView() }
    }
}
