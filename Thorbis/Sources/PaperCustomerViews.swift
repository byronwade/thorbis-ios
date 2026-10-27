import SwiftUI

/// Native translation of Paper's Customers and Customer detail artboards.
struct CustomersView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @State private var showNew = false
    @State private var showSearch = false
    @State private var search = ""
    @State private var newName = ""
    @State private var busy = false
    @State private var error: String?

    private var items: [Customer] {
        store.customers.filter { $0.archived != true && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var groups: [String] { Array(Set(items.map { String($0.name.prefix(1)).uppercased() })).sorted() }
    private var activeJobs: Int { store.jobs.filter { !["completed", "canceled"].contains($0.status) }.count }

    var body: some View {
        VStack(spacing: 0) {
            PaperHeader(title: "Customers", icon: "person.2", subtitle: "\(items.count) customers · \(activeJobs) active jobs", search: { showSearch.toggle() })
            if showSearch { PaperSearchField(text: $search, prompt: "Customer name") }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let error = error ?? store.error { ErrorBanner(message: error) }
                    if store.loading { ProgressView("Updating customers…").padding() }
                    ForEach(groups, id: \.self) { letter in
                        let customers = items.filter { String($0.name.prefix(1)).uppercased() == letter }
                        HStack {
                            Text(letter).font(Theme.font(13, weight: .medium))
                            Spacer()
                            Text("\(customers.count)").font(Theme.monoFont(12))
                        }.foregroundStyle(Theme.muted).padding(.top, 14).padding(.bottom, 4)
                        ForEach(customers) { customer in
                            NavigationLink(value: customer) {
                                HStack(spacing: 12) {
                                    Avatar(name: customer.name, size: 24)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(customer.name).font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                                        let count = store.jobs.filter { $0.customerId == customer.id }.count
                                        Text("\(count) \(count == 1 ? "job" : "jobs")").font(Theme.font(13)).foregroundStyle(Theme.muted)
                                    }
                                    Spacer(minLength: 0)
                                    if let job = store.jobs.first(where: { $0.customerId == customer.id && !["completed", "canceled"].contains($0.status) }) {
                                        Image(systemName: statusIcon(job.status).0).foregroundStyle(statusIcon(job.status).1).frame(width: 16)
                                    }
                                }.frame(minHeight: 48).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    if items.isEmpty && !store.loading { ContentUnavailableView.search(text: search) }
                    if session.can("customer.create", feature: "core_crm") {
                        Button("New customer", systemImage: "plus") { showNew = true }
                            .font(Theme.font(13, weight: .medium)).padding(.top, 20).disabled(busy)
                    }
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
            }.refreshable { await store.refresh(api) }
        }
        .background(Theme.background).toolbar(.hidden, for: .navigationBar)
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

private enum CustomerLocationSheet: Identifiable {
    case add
    case edit(ServiceLocationRecord)

    var id: String {
        switch self {
        case .add: "new-location"
        case .edit(let location): location.id
        }
    }

    var location: ServiceLocationRecord? {
        if case .edit(let location) = self { return location }
        return nil
    }
}

private enum CustomerContactSheetItem: Identifiable {
    case add
    case edit(CustomerContactRecord)

    var id: String {
        switch self {
        case .add: "new-contact"
        case .edit(let contact): contact.id
        }
    }

    var contact: CustomerContactRecord? {
        if case .edit(let contact) = self { return contact }
        return nil
    }
}

struct CustomerDetailView: View {
    let customer: Customer
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var record: CustomerRecord?
    @State private var contactState = CustomerContactCollectionState()
    @State private var loadGeneration = 0
    @State private var locationState = ServiceLocationCollectionState()
    @State private var error: String?
    @State private var showNewJob = false
    @State private var contactSheet: CustomerContactSheetItem?
    @State private var contactToRemove: CustomerContactRecord?
    @State private var showRemoveContactConfirmation = false
    @State private var isMutatingContact = false
    @State private var contactMutationError: String?
    @State private var locationSheet: CustomerLocationSheet?
    @State private var locationToRemove: ServiceLocationRecord?
    @State private var showRemoveLocationConfirmation = false
    @State private var isRemovingLocation = false
    @State private var locationError: String?
    @State private var tab = "Overview"
    private var jobs: [Job] { store.jobs.filter { $0.customerId == customer.id } }
    private var canEdit: Bool { session.can("customer.edit", feature: "core_crm") }
    private var contacts: [CustomerContactRecord] { contactState.contacts }
    private var contactsLoaded: Bool { contactState.isLoaded }
    private var locations: [ServiceLocationRecord] { locationState.locations }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: 38, height: 38).background(Theme.fill, in: Circle()) }.accessibilityLabel("Back")
                    Spacer()
                    if canEdit {
                        Menu {
                            Button("Add contact", systemImage: "person.badge.plus") { contactSheet = .add }
                                .disabled(!contactsLoaded)
                            Button("Add location", systemImage: "mappin.and.ellipse") { locationSheet = .add }
                        } label: { Image(systemName: "ellipsis").frame(width: 38, height: 38).background(Theme.fill, in: Circle()) }.accessibilityLabel("Customer actions")
                    }
                }.foregroundStyle(Theme.foreground).padding(.horizontal, 20).frame(height: 54)
                VStack(alignment: .leading, spacing: 6) {
                    if let date = JobFiltering.date(record?.createdAt ?? customer.createdAt) {
                        Text("Customer since \(date.formatted(.dateTime.month(.abbreviated).year()))").font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.muted)
                    }
                    Text(record?.name ?? customer.name).font(Theme.font(26, weight: .semibold)).tracking(-0.39)
                }.padding(.horizontal, 20).padding(.bottom, 12)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { metadataChips }.fixedSize()
                    VStack(alignment: .leading, spacing: 6) { metadataChips }
                }.padding(.horizontal, 20).padding(.bottom, 14)
                if let error { ErrorBanner(message: error) }
                if record == nil && error == nil { ProgressView("Loading customer…").padding(20) }
                details
                PaperTabs(options: ["Overview", "Jobs", "Billing", "Media", "Activity"], selection: $tab)
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case "Overview":
                        contactsSection
                        locationsSection
                        if session.can("job.view", feature: "jobs") { jobsSection }
                        unavailable("Notes", "Customer notes are not available in this workspace connection.")
                        unavailable("Activity", "Customer activity is not available in this workspace connection.")
                    case "Jobs":
                        if session.can("job.view", feature: "jobs") { jobsSection }
                        else { unavailable("Jobs", "You don’t have access to jobs in this workspace.") }
                    case "Billing":
                        if let terms = record?.billingTerms { detailRow("Billing terms", value: terms) }
                        unavailable("Billing", "Customer balances and billing history are not available here.")
                    case "Media": unavailable("Media", "Open a customer job to view its media.")
                    default: unavailable("Activity", "Customer activity is not available in this workspace connection.")
                    }
                }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
            }
        }
        .foregroundStyle(Theme.foreground).background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                if session.can("job.create", feature: "jobs") {
                    Button { showNewJob = true } label: {
                        Label("New job", systemImage: "plus").font(Theme.font(15, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 46).foregroundStyle(.white).background(Theme.brand, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                if let phone = record?.phone { CustomerContactIcon(value: phone, isPhone: true, size: 46) }
            }.padding(.horizontal, 20).padding(.vertical, 10).background(Theme.background)
        }
        .task { await load() }.refreshable { await load() }
        .sheet(isPresented: $showNewJob) { NewJobSheet(preselected: customer) }
        .sheet(item: $contactSheet, onDismiss: { Task { await load() } }) { item in
            CustomerContactSheet(customerID: customer.id, contact: item.contact) { contact in
                contactState.save(contact)
                contactMutationError = nil
                error = nil
            }
        }
        .sheet(item: $locationSheet) { item in
            ServiceLocationSheet(customerID: customer.id, location: item.location) { saved in
                locationState.save(saved)
                locationError = nil
            }
        }
        .confirmationDialog(
            "Remove service location?",
            isPresented: $showRemoveLocationConfirmation,
            titleVisibility: .visible,
            presenting: locationToRemove
        ) { location in
            Button("Remove \(location.label)", role: .destructive) {
                Task { await removeLocation(location) }
            }
            Button("Cancel", role: .cancel) { locationToRemove = nil }
        } message: { location in
            Text("This removes the location from \(record?.name ?? customer.name).")
        }
        .confirmationDialog(
            "Remove customer contact?",
            isPresented: $showRemoveContactConfirmation,
            titleVisibility: .visible,
            presenting: contactToRemove
        ) { contact in
            Button("Remove \(contact.name)", role: .destructive) {
                Task { await removeContact(contact) }
            }
            Button("Cancel", role: .cancel) { contactToRemove = nil }
        } message: { contact in
            Text("This removes \(contact.name) from \(record?.name ?? customer.name).")
        }
    }
    @ViewBuilder private var metadataChips: some View {
        if jobs.contains(where: { $0.status == "in_progress" }) { Chip(text: "Job in progress", icon: "circle.lefthalf.filled", tint: Theme.warning, bg: Theme.warningSurface) }
        if session.can("job.view", feature: "jobs") { Chip(text: "\(jobs.count) jobs", icon: "clock") }
        if let type = record?.accountType { Chip(text: type.statusLabel) }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Details")
            if let record {
                if let phone = record.phone { detailRow("Phone", value: phone) }
                if let email = record.email {
                    HStack { Text("Email").foregroundStyle(Theme.muted); Spacer(); ContactActions(phone: nil, email: email) }.font(Theme.font(14)).frame(minHeight: 42)
                }
                if let address = record.address {
                    HStack { Text("Address").foregroundStyle(Theme.muted); Spacer(); AddressLink(address: address) }.font(Theme.font(14)).frame(minHeight: 42)
                }
                if let industry = record.industry { detailRow("Industry", value: industry) }
                if let preferred = record.preferredContact { detailRow("Contact preference", value: preferred.statusLabel) }
            }
        }.padding(.horizontal, 20).padding(.bottom, 18)
    }
    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { sectionTitle("Contacts", count: contacts.count); Spacer(); if canEdit { Button { contactSheet = .add } label: { Image(systemName: "plus").frame(width: 30, height: 30) }.accessibilityLabel("Add contact").disabled(!contactsLoaded) } }
            if let contactMutationError {
                Text(contactMutationError).font(Theme.font(13)).foregroundStyle(Theme.destructive)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.destructiveSurface, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityIdentifier("contact-mutation-error")
            }
            ForEach(contacts) { contact in
                HStack(spacing: 10) {
                    Avatar(name: contact.name, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(contact.name).font(Theme.font(14, weight: .medium))
                        Text([contact.role, contact.primary ? "Primary" : nil].compactMap { $0 }.joined(separator: " · ")).font(Theme.font(12)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 2)
                    if let phone = contact.phone { CustomerContactIcon(value: phone, isPhone: true) }
                    if let email = contact.email { CustomerContactIcon(value: email, isPhone: false) }
                    if canEdit {
                        Menu {
                            Button("Edit contact", systemImage: "pencil") { contactSheet = .edit(contact) }
                            if !contact.primary {
                                Button("Make primary", systemImage: "star") { Task { await makeContactPrimary(contact) } }
                                    .disabled(isMutatingContact)
                            }
                            Button("Remove contact", systemImage: "trash", role: .destructive) {
                                contactToRemove = contact
                                showRemoveContactConfirmation = true
                            }.disabled(isMutatingContact)
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 30, height: 32)
                        }
                        .accessibilityLabel("Contact actions for \(contact.name)")
                        .disabled(isMutatingContact)
                    }
                }.frame(minHeight: 48)
            }
            if contacts.isEmpty { emptyText("No contacts") }
        }
    }
    private var locationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { sectionTitle("Locations", count: locations.count); Spacer(); if canEdit { Button { locationSheet = .add } label: { Image(systemName: "plus").frame(width: 30, height: 30) }.accessibilityLabel("Add location") } }
            if let locationError {
                Text(locationError).font(Theme.font(13)).foregroundStyle(Theme.destructive)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.destructiveSurface, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityIdentifier("location-mutation-error")
            }
            ForEach(locations) { location in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(location.label).font(Theme.font(14, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(location.kind.statusLabel).font(Theme.font(12)).foregroundStyle(Theme.muted)
                        if canEdit {
                            Menu {
                                Button("Edit location", systemImage: "pencil") { locationSheet = .edit(location) }
                                Button("Remove location", systemImage: "trash", role: .destructive) {
                                    locationToRemove = location
                                    showRemoveLocationConfirmation = true
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .frame(width: 30, height: 30)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Options for \(location.label)")
                        }
                    }
                    AddressLink(address: location.address, coordinates: location.coordinates).font(Theme.font(13))
                    if let notes = location.notes { Text(notes).font(Theme.font(13)) }
                    if let parking = location.parking { detailRow("Parking", value: parking) }
                    if let dogs = location.dogOnSite { detailRow("Dogs on site", value: dogs) }
                    HStack(spacing: 5) {
                        Image(systemName: location.coordinates == nil ? "mappin.slash" : "mappin.and.ellipse")
                        Text(location.coordinates.map { String(format: "%.4f, %.4f", $0.latitude, $0.longitude) } ?? "No map pin")
                    }
                    .font(Theme.monoFont(11)).foregroundStyle(Theme.muted)
                }.padding(.vertical, 5)
            }
            if locations.isEmpty { emptyText("No locations") }
        }
    }

    private func removeLocation(_ location: ServiceLocationRecord) async {
        guard canEdit, !isRemovingLocation else { return }
        isRemovingLocation = true
        defer {
            isRemovingLocation = false
            locationToRemove = nil
        }
        do {
            try await api.removeFieldLocation(customer.id, location.id)
            locationState.remove(id: location.id)
            locationError = nil
        } catch is CancellationError {
        } catch {
            locationError = error.localizedDescription
        }
    }

    private func makeContactPrimary(_ contact: CustomerContactRecord) async {
        guard canEdit, !isMutatingContact, !contact.primary else { return }
        isMutatingContact = true
        defer { isMutatingContact = false }
        do {
            let updated = try await api.updateFieldContact(customer.id, contact.id, request: .init(primary: true))
            contactState.save(updated)
            contactMutationError = nil
        } catch is CancellationError {
        } catch {
            contactMutationError = error.localizedDescription
        }
    }

    private func removeContact(_ contact: CustomerContactRecord) async {
        guard canEdit, !isMutatingContact else { return }
        isMutatingContact = true
        defer {
            isMutatingContact = false
            contactToRemove = nil
        }
        do {
            try await api.removeFieldContact(customer.id, contact.id)
            contactState.remove(id: contact.id)
            contactMutationError = nil
        } catch is CancellationError {
        } catch {
            contactMutationError = error.localizedDescription
        }
    }
    private var jobsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionTitle("Job history", count: jobs.count)
            ForEach(jobs) { job in
                NavigationLink(value: job) {
                    HStack(spacing: 12) {
                        Image(systemName: statusIcon(job.status).0).foregroundStyle(statusIcon(job.status).1).frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.title).font(Theme.font(15, weight: .medium)).lineLimit(1)
                            Text(job.status.statusLabel).font(Theme.font(12)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if jobs.isEmpty { emptyText("No jobs") }
        }
    }
    private func sectionTitle(_ title: String, count: Int? = nil) -> some View {
        HStack(spacing: 6) { Text(title).font(Theme.font(13, weight: .medium)); if let count { Text("\(count)").font(Theme.font(12)) } }.foregroundStyle(Theme.muted).padding(.bottom, 6)
    }
    private func detailRow(_ title: String, value: String) -> some View {
        HStack(spacing: 12) { Text(title).foregroundStyle(Theme.muted); Spacer(minLength: 10); Text(value).multilineTextAlignment(.trailing) }.font(Theme.font(14)).frame(minHeight: 42)
    }
    private func emptyText(_ text: String) -> some View { Text(text).font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.vertical, 6) }
    private func unavailable(_ title: String, _ message: String) -> some View { VStack(alignment: .leading, spacing: 6) { sectionTitle(title); emptyText(message) } }
    private func load() async {
        loadGeneration += 1
        let requestGeneration = loadGeneration
        let locationRequestGeneration = locationState.beginLoad()
        let contactRequestGeneration = contactState.beginLoading()
        do {
            let loadedRecord = try await api.fieldCustomer(customer.id)
            guard loadGeneration == requestGeneration else { return }
            record = loadedRecord
            let loadedContacts = try await api.fieldContacts(customer.id)
            guard loadGeneration == requestGeneration else { return }
            contactState.receive(loadedContacts, generation: contactRequestGeneration)
            let loadedLocations = try await api.fieldLocations(customer.id)
            guard loadGeneration == requestGeneration else { return }
            if locationState.receive(loadedLocations, generation: locationRequestGeneration) {
                locationError = nil
            }
            error = nil
        } catch is CancellationError {} catch {
            guard loadGeneration == requestGeneration else { return }
            self.error = error.localizedDescription
        }
    }
}

private struct CustomerContactIcon: View {
    let value: String
    let isPhone: Bool
    var size: CGFloat = 30
    private var url: URL? {
        let address = isPhone ? value.filter { $0.isNumber || $0 == "+" } : value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard !address.isEmpty else { return nil }
        return URL(string: (isPhone ? "tel:" : "mailto:") + address)
    }
    var body: some View {
        if let url {
            Link(destination: url) {
                Image(systemName: isPhone ? "phone" : "envelope").font(Theme.font(size == 46 ? 17 : 13)).foregroundStyle(Theme.foreground)
                    .frame(width: size, height: size).background(size == 46 ? Theme.card : Theme.fill, in: RoundedRectangle(cornerRadius: size == 46 ? 12 : 15))
            }.accessibilityLabel("\(isPhone ? "Call" : "Email") \(value)")
        }
    }
}
