import SwiftUI
import ThorbisCore

struct CustomersView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var showArchived = false
    @State private var creating = false

    private var sections: [DirectorySection] {
        let needle = query.trimmed.lowercased()
        let digits = needle.filter(\.isNumber)
        let matches = needle.isEmpty ? model.customers : model.customers.filter { customer in
            if customer.name.lowercased().contains(needle) { return true }
            if !digits.isEmpty, customer.phone?.filter(\.isNumber).contains(digits) == true { return true }
            if customer.email?.lowercased().contains(needle) == true { return true }
            return customer.address?.lowercased().contains(needle) == true
        }
        return Directory.sections(matches, includeArchived: showArchived)
    }

    var body: some View {
        let sections = sections
        LoadState(
            isLoading: model.isRefreshing,
            error: model.refreshError,
            isEmpty: model.customers.isEmpty,
            emptyTitle: "No customers yet",
            emptySymbol: "person.2",
            emptyMessage: "Add your first customer to start booking jobs.",
            retry: { await model.refreshAll() }
        ) {
            List {
                ForEach(sections) { section in
                    Section(section.letter) {
                        ForEach(section.customers) { customer in
                            NavigationLink(value: Route.customer(customer.id)) { CustomerRow(customer: customer) }.sheetRow()
                        }
                    }
                }
                if sections.isEmpty {
                    Text("No customers match “\(query)”.").foregroundStyle(Theme.inkSecondary).sheetRow()
                }
            }
            .thorbisList()
        }
        .navigationTitle("Customers")
        .searchable(text: $query, prompt: "Name, phone, email or address")
        .refreshable { await model.refreshAll() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Toggle(isOn: $showArchived) {
                    Label("Show archived", systemImage: showArchived ? "archivebox.fill" : "archivebox")
                }
                .toggleStyle(.button)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: { Label("New customer", systemImage: "plus") }
            }
            AccountToolbarItem()
        }
        .sheet(isPresented: $creating) { NewCustomerView() }
    }
}

struct CustomerRow: View {
    let customer: Customer

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Avatar(name: customer.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(customer.name).font(.body.weight(.medium)).foregroundStyle(customer.isArchived ? Theme.inkQuiet : Theme.ink)
                if let line = customer.address ?? customer.phone ?? customer.email {
                    Text(line).font(.subheadline).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if customer.isArchived { StatusBadge(text: "Archived", symbol: "archivebox") }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct CustomerDetailView: View {
    @Environment(AppModel.self) private var model
    let customerId: String
    @State private var customer: Customer?
    @State private var contacts: [CustomerContact] = []
    @State private var locations: [ServiceLocation] = []
    @State private var error: String?
    @State private var addingContact = false
    @State private var addingLocation = false
    @State private var creatingJob = false

    private var current: Customer? { customer ?? model.customer(customerId) }
    private var jobs: [Job] { model.jobs.filter { $0.customerId == customerId }.sorted { $0.updatedAt > $1.updatedAt } }
    private var estimates: [Estimate] { model.estimates.filter { $0.customerId == customerId } }
    private var invoices: [Invoice] { model.invoices.filter { $0.customerId == customerId } }

    var body: some View {
        Group {
            if let customer = current {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            Text(customer.name).font(.title2.weight(.medium)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                            if let type = customer.accountType {
                                Text(type.capitalized).font(.subheadline).foregroundStyle(Theme.inkSecondary)
                            }
                        }
                        .sheetRow()
                        ContactActions(phone: customer.phone, email: customer.email).sheetRow()
                    }
                    if let error { Section { InlineError(message: error) { await load() }.sheetRow() } }

                    Section("Details") {
                        if let phone = customer.phone { DetailRow(label: "Phone", value: phone, symbol: "phone").sheetRow() }
                        if let email = customer.email { DetailRow(label: "Email", value: email, symbol: "envelope").sheetRow() }
                        if let address = customer.address { DetailRow(label: "Address", value: address, symbol: "house").sheetRow() }
                        if let preferred = customer.preferredContact {
                            DetailRow(label: "Prefers", value: OutboundLink.preference(preferred), symbol: "hand.raised").sheetRow()
                        }
                        if let terms = Format.billingTerms(customer.billingTerms) {
                            DetailRow(label: "Terms", value: terms, symbol: "calendar.badge.clock").sheetRow()
                        }
                    }

                    Section {
                        ForEach(locations) { location in
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                HStack {
                                    Text(location.label).font(.body.weight(.medium))
                                    if location.kind == .billing { StatusBadge(text: "Billing") }
                                }
                                Button {
                                    Task { _ = await OutboundLink.directions(to: location.address, name: customer.name) }
                                } label: {
                                    Label(location.address, systemImage: "mappin.and.ellipse").font(.subheadline)
                                }
                                ForEach(location.accessNotes) { item in
                                    Text("\(item.label): \(item.value)").font(.footnote).foregroundStyle(Theme.inkSecondary)
                                }
                            }
                            .padding(.vertical, 2)
                            .sheetRow()
                        }
                        Button { addingLocation = true } label: { Label("Add location", systemImage: "plus") }.sheetRow()
                    } header: {
                        Text("Locations")
                    }

                    Section {
                        ForEach(contacts) { contact in
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                HStack {
                                    Text(contact.name).font(.body.weight(.medium))
                                    if contact.primary { StatusBadge(text: "Primary") }
                                }
                                if let role = contact.role { Text(role).font(.subheadline).foregroundStyle(Theme.inkSecondary) }
                                ContactActions(phone: contact.phone, email: contact.email)
                            }
                            .padding(.vertical, 2)
                            .sheetRow()
                        }
                        Button { addingContact = true } label: { Label("Add contact", systemImage: "plus") }.sheetRow()
                    } header: {
                        Text("Contacts")
                    }

                    Section {
                        ForEach(jobs) { job in
                            NavigationLink(value: Route.job(job.id)) { JobRow(job: job) }.sheetRow()
                        }
                        Button { creatingJob = true } label: { Label("New job", systemImage: "plus") }.sheetRow()
                    } header: {
                        Text("Jobs")
                    }

                    if !estimates.isEmpty {
                        Section("Estimates") {
                            ForEach(estimates) { estimate in
                                NavigationLink(value: Route.estimate(estimate.id)) { EstimateRow(estimate: estimate) }.sheetRow()
                            }
                        }
                    }
                    if !invoices.isEmpty {
                        Section("Invoices") {
                            ForEach(invoices) { invoice in
                                NavigationLink(value: Route.invoice(invoice.id)) { InvoiceRow(invoice: invoice) }.sheetRow()
                            }
                        }
                    }
                }
                .thorbisList()
            } else if let error {
                ContentUnavailableView("Couldn't open this customer", systemImage: "person.crop.circle.badge.exclamationmark", description: Text(error))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.canvas)
        .navigationTitle(current?.name ?? "Customer")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: customerId) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $addingContact) {
            AddContactSheet(customerId: customerId) { contacts.append($0) }
        }
        .sheet(isPresented: $addingLocation) {
            AddLocationSheet(customerId: customerId) { locations.append($0) }
        }
        .sheet(isPresented: $creatingJob) {
            NewJobView(customerId: customerId)
        }
    }

    private func load() async {
        do {
            async let customer = model.api.customer(customerId)
            async let contacts = model.api.contacts(customer: customerId)
            async let locations = model.api.locations(customer: customerId)
            let fresh = try await customer
            self.customer = fresh
            model.store(fresh)
            // Keep what was already shown when a child list fails, and say so.
            var failed: [String] = []
            do { self.contacts = try await contacts } catch { failed.append("contacts") }
            do { self.locations = try await locations } catch { failed.append("locations") }
            error = failed.isEmpty ? nil : "Couldn't load \(failed.joined(separator: " or ")). Showing what was loaded before."
        } catch {
            self.error = model.message(for: error)
        }
    }
}

extension OutboundLink {
    static func preference(_ method: ContactMethod) -> String {
        switch method {
        case .phone: "Phone call"
        case .sms: "Text message"
        case .email: "Email"
        }
    }
}
