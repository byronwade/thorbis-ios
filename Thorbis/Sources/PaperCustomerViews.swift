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

struct CustomerDetailView: View {
    let customer: Customer
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var record: CustomerRecord?
    @State private var contacts: [CustomerContactRecord] = []
    @State private var locations: [ServiceLocationRecord] = []
    @State private var error: String?
    @State private var showNewJob = false
    @State private var showContact = false
    @State private var showLocation = false
    @State private var tab = "Overview"
    private var jobs: [Job] { store.jobs.filter { $0.customerId == customer.id } }
    private var canEdit: Bool { session.can("customer.edit", feature: "core_crm") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: 38, height: 38).background(Theme.fill, in: Circle()) }.accessibilityLabel("Back")
                    Spacer()
                    if canEdit {
                        Menu {
                            Button("Add contact", systemImage: "person.badge.plus") { showContact = true }
                            Button("Add location", systemImage: "mappin.and.ellipse") { showLocation = true }
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
        .sheet(isPresented: $showContact, onDismiss: { Task { await load() } }) { CustomerRecordSheet(customerID: customer.id, isLocation: false) }
        .sheet(isPresented: $showLocation, onDismiss: { Task { await load() } }) { CustomerRecordSheet(customerID: customer.id, isLocation: true) }
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
            HStack { sectionTitle("Contacts", count: contacts.count); Spacer(); if canEdit { Button { showContact = true } label: { Image(systemName: "plus").frame(width: 30, height: 30) }.accessibilityLabel("Add contact") } }
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
                }.frame(minHeight: 48)
            }
            if contacts.isEmpty { emptyText("No contacts") }
        }
    }
    private var locationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { sectionTitle("Locations", count: locations.count); Spacer(); if canEdit { Button { showLocation = true } label: { Image(systemName: "plus").frame(width: 30, height: 30) }.accessibilityLabel("Add location") } }
            ForEach(locations) { location in
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(location.label).font(Theme.font(14, weight: .medium)); Spacer(); Text(location.kind.statusLabel).font(Theme.font(12)).foregroundStyle(Theme.muted) }
                    AddressLink(address: location.address).font(Theme.font(13))
                    if let notes = location.notes { Text(notes).font(Theme.font(13)) }
                    if let parking = location.parking { detailRow("Parking", value: parking) }
                    if let dogs = location.dogOnSite { detailRow("Dogs on site", value: dogs) }
                }.padding(.vertical, 5)
            }
            if locations.isEmpty { emptyText("No locations") }
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
        do {
            record = try await api.fieldCustomer(customer.id)
            contacts = try await api.fieldContacts(customer.id)
            locations = try await api.fieldLocations(customer.id)
            error = nil
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
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
