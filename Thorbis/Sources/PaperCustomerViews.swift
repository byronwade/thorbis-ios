import SwiftUI
import UIKit

/// Native translation of Paper's Customers and Customer detail artboards.
struct CustomersView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @State private var showNew = false
    @State private var newJobFor: Customer?
    @Environment(\.openURL) private var openURL
    @State private var showSearch = false
    @State private var search = ""
    @State private var newName = ""
    @State private var selectedView = CustomerListScope.recent.rawValue
    @State private var stateFilter = "Any state"
    @State private var records: [CustomerRecord] = []
    @State private var recordsLoading = true
    @State private var loadGeneration = 0
    @State private var busy = false
    @State private var error: String?

    private var scope: CustomerListScope { CustomerListScope(rawValue: selectedView) ?? .recent }
    private var items: [CustomerRecord] {
        scope.customers(from: records).filter { customer in
            let matchesState = stateFilter == "Any state"
                || (stateFilter == "Archived") == customer.archived
            return matchesState && (search.isEmpty || customer.name.localizedCaseInsensitiveContains(search))
        }
    }
    private var activeJobs: Int { store.jobs.filter { !["completed", "canceled"].contains($0.status) }.count }

    /// Paper 47: an alphabetical book, one letter per section. Recent keeps its newest-first
    /// order in one group; letters would re-sort it and break the point of the tab.
    private var sections: [(String, [CustomerRecord])] {
        if scope == .recent { return items.isEmpty ? [] : [("Recently added", items)] }
        let grouped = Dictionary(grouping: items) { customer -> String in
            let letter = customer.name.trimmingCharacters(in: .whitespaces).prefix(1).uppercased()
            return letter.rangeOfCharacter(from: .letters) == nil ? "#" : letter
        }
        return grouped.keys.sorted().map { key in
            (key, (grouped[key] ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    var body: some View {
        let jobGroups = CustomerJobGroups(jobs: store.jobs)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PaperHeader(title: "Customers", subtitle: recordsLoading && records.isEmpty ? "Loading customers…" : "\(records.count) customers · \(activeJobs) active jobs", search: { withMotion { showSearch.toggle() } })
                if showSearch { PaperSearchField(text: $search, prompt: "Customer name") }
                PaperTabs(options: CustomerListScope.allCases.map(\.rawValue), selection: $selectedView)
                if let error = error ?? store.error {
                    ErrorBanner(message: error) { _ = await store.refresh(api); await loadCustomers() }
                }
                if recordsLoading && records.isEmpty { SkeletonRows() }
                ForEach(sections, id: \.0) { letter, customers in
                    Section {
                        ForEach(customers) { customer in
                            customerRow(customer, jobs: jobGroups.jobs(for: customer.id))
                                .padding(.horizontal, Theme.gutter)
                        }
                    } header: {
                        PaperGroupHeader(title: letter).padding(.top, 6)
                            .padding(.horizontal, Theme.gutter)
                    }
                }
                if items.isEmpty && !recordsLoading && error == nil && store.error == nil {
                    if scope == .archived {
                        PaperEmptyState(symbol: "archivebox", title: "No archived customers", message: search.isEmpty ? "Archived customers will appear here." : "Try a different search.")
                    } else if !search.isEmpty {
                        PaperEmptyState.search(search)
                    } else {
                        PaperEmptyState(symbol: "person.2", title: "No customers yet", message: "Customers you add appear here, A to Z.",
                                        actionTitle: session.can("customer.create", feature: "core_crm") ? "Add a customer" : nil,
                                        action: { showNew = true })
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { await store.refresh(api); await loadCustomers() }
        .background(Theme.background).toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if session.can("customer.create", feature: "core_crm") && !items.isEmpty {
                FloatingCreateButton(title: "New customer", disabled: busy) { showNew = true }
            }
        }
        .task(id: store.customers.map(\.id).sorted().joined(separator: "|")) { await loadCustomers() }
        .sheet(isPresented: $showNew) {
            NewCustomerSheet { _ in Task { await loadCustomers() } }
        }
        .sheet(item: $newJobFor) { customer in NewJobSheet(preselected: customer) }
    }
    private func customerRow(_ customer: CustomerRecord, jobs: [Job]) -> some View {
        let now = Date()
        let summaryJob = JobFiltering.customerJobSummary(jobs, customerID: customer.id, now: now)?.job
        let jobCount = jobs.count
        let listCustomer = Customer(id: customer.id, name: customer.name, archived: customer.archived, createdAt: customer.createdAt)
        return NavigationLink(value: listCustomer) {
            HStack(alignment: .center, spacing: 12) {
                Text(initials(customer.name))
                    .font(Theme.font(16, weight: .semibold))
                    .foregroundStyle(customer.archived ? Theme.muted : Theme.brandText)
                    .frame(width: 42, height: 42)
                    .background(customer.archived ? Theme.fill : Theme.brandSurface,
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(customer.name)
                        .font(Theme.font(16, weight: .semibold))
                        .foregroundStyle(customer.archived ? Theme.muted : Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 5) {
                        if let summaryJob, !customer.archived {
                            StatusRing(status: summaryJob.status, size: 12).accessibilityHidden(true)
                        }
                        Text(customer.archived ? "Archived" : rowDetail(jobCount: jobCount, open: summaryJob, now: now))
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8).padding(.vertical, 10)
            .frame(minHeight: 64).contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        // MA-12: the common actions on long-press; each also exists on the customer.
        .contextMenu {
            if let phone = customer.phone.map({ $0.filter { $0.isNumber || $0 == "+" } }), phone.count >= 7 {
                if let call = URL(string: "tel:\(phone)") { Button("Call", systemImage: "phone") { openURL(call) } }
                if let text = URL(string: "sms:\(phone)") { Button("Text", systemImage: "message") { openURL(text) } }
            }
            if let address = customer.address, !address.isEmpty, let maps = Directions.url(address: address, coordinates: nil) {
                Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") { openURL(maps) }
            }
            if !customer.archived && session.can("job.create", feature: "jobs") {
                Button("New job for \(customer.name)", systemImage: "plus") { newJobFor = listCustomer }
            }
            Button("Copy name", systemImage: "doc.on.doc") { UIPasteboard.general.string = customer.name }
        }
        .padding(.horizontal, -8)
    }

    private func rowDetail(jobCount: Int, open: Job?, now: Date) -> String {
        let count = "\(jobCount) \(jobCount == 1 ? "job" : "jobs")"
        guard let open else { return count }
        if let date = JobFiltering.date(open.scheduledFor), ["scheduled", "dispatched"].contains(open.status) {
            if date < now {
                return "\(count) · Past scheduled time · \(open.status.statusLabel) · \(date.visitLabel(now: now))"
            }
            // Same words as the Jobs list ("Today 4:00 PM", "In progress"), so a visit reads alike everywhere.
            return "\(count) · \(open.status.statusLabel) · \(date.visitLabel(now: now))"
        }
        return "\(count) · \(open.status.statusLabel)"
    }

    private func create() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await api.createCustomer(name: newName.trimmingCharacters(in: .whitespacesAndNewlines))
            newName = ""
            await store.refresh(api)
            await loadCustomers()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }

    private func loadCustomers() async {
        guard session.can("customer.view", feature: "core_crm") else { return }
        loadGeneration += 1
        let request = loadGeneration
        recordsLoading = true
        defer { if loadGeneration == request { recordsLoading = false } }
        do {
            let loaded = try await api.fieldCustomers(includeArchived: true)
            guard loadGeneration == request else { return }
            records = loaded
            error = nil
        } catch is CancellationError {
        } catch {
            guard loadGeneration == request else { return }
            self.error = error.localizedDescription
        }
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

/// Identity and authority that authorized a compiled customer record.
struct CustomerRecordsScope: Equatable {
    let actorID: String
    let organizationID: String
    let customerID: String
    let generation: UUID
    let authorityRevision: UUID
    let policyVersion: Int?
    let access: CustomerRecordAccess

    @MainActor func isCurrent(session: SessionController) -> Bool {
        Self.capture(session: session, customerID: customerID) == self
    }

    @MainActor static func capture(session: SessionController, customerID: String) -> CustomerRecordsScope? {
        guard session.can("customer.view", feature: "core_crm"),
              let actorID = session.user?.id, let organizationID = session.activeOrganization?.id else { return nil }
        return CustomerRecordsScope(actorID: actorID, organizationID: organizationID, customerID: customerID,
            generation: session.generation, authorityRevision: session.authorityRevision, policyVersion: session.policyVersion,
            access: CustomerRecordAccess(jobs: session.can("job.view", feature: "jobs"),
                estimates: session.can("estimate.view", feature: "estimates"),
                invoices: session.can("invoice.view", feature: "invoicing")))
    }
}

struct CustomerDetailView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let customer: Customer
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var record: CustomerRecord?
    @State private var contactState = CustomerContactCollectionState()
    @State private var loadGeneration = 0
    @State private var activity: [CustomerHistoryEntry] = []
    @State private var activityCursor: String?
    @State private var activityLoading = false
    @State private var activityError: String?
    @State private var activityLoadGeneration = 0
    @State private var locationState = ServiceLocationCollectionState()
    @State private var error: String?
    @State private var showNewJob = false
    @State private var contactSheet: CustomerContactSheetItem?
    @State private var contactToRemove: CustomerContactRecord?
    @State private var isMutatingContact = false
    @State private var contactMutationError: String?
    @State private var locationSheet: CustomerLocationSheet?
    @State private var locationToRemove: ServiceLocationRecord?
    @State private var isRemovingLocation = false
    @State private var locationError: String?
    @State private var tab = "Overview"
    @State private var records: CustomerJobCompilation?
    @State private var recordsLoading = false
    @State private var recordsError: String?
    @State private var recordsLoadGeneration = 0
    @State private var recordsPublishedScope: CustomerRecordsScope?
    @State private var recordsRequestedScope: CustomerRecordsScope?
    private var recordsScope: CustomerRecordsScope? { CustomerRecordsScope.capture(session: session, customerID: customer.id) }
    @State private var smsConsent: CustomerSmsConsent?
    @State private var smsConsentLoaded = false
    @State private var smsConsentKey = UUID().uuidString
    @State private var smsConsentChoice: Bool?
    @State private var smsConsentError: String?
    @State private var showCustomerMode = false
    @State private var handoff: DeviceHandoff?
    private var jobs: [Job] { store.jobs.filter { $0.customerId == customer.id } }
    private var canEdit: Bool { session.can("customer.edit", feature: "core_crm") }
    private var contacts: [CustomerContactRecord] { contactState.contacts }
    private var contactsLoaded: Bool { contactState.isLoaded }
    private var locations: [ServiceLocationRecord] { locationState.locations }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                customerIdentity
                    .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 16)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { metadataChips }.fixedSize()
                    VStack(alignment: .leading, spacing: 6) { metadataChips }
                }.padding(.horizontal, Theme.gutter).padding(.bottom, 10)
                PaperQuickActions(phone: contacts.first(where: \.primary)?.phone ?? record?.phone,
                                  email: contacts.first(where: \.primary)?.email ?? record?.email,
                                  directions: (locations.first?.address ?? record?.address).flatMap { Directions.url(address: $0, coordinates: locations.first?.coordinates) })
                    .padding(.horizontal, Theme.gutter).padding(.bottom, 14)
                // Next visit sits above everything else: it's why most people open a customer.
                if tab == "Overview" && session.can("job.view", feature: "jobs") {
                    nextVisit.padding(.horizontal, Theme.gutter).padding(.bottom, 8)
                }
                if typeSize.isAccessibilitySize {
                    customerPrimaryActions
                }
                if let error {
                    ErrorBanner(message: error) { await load() }.padding(.horizontal, Theme.gutter).padding(.bottom, 12)
                }
                Section {
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case "Overview":
                        // Details live under Overview so the tabs sit near the top of the page
                        // instead of below a long block the person has to scroll past.
                        if record == nil && error == nil {
                            SkeletonRows(count: 4, leading: false, inset: 0)
                        } else {
                            DisclosureGroup("Customer details") {
                                details
                            }
                            .font(Theme.font(15, weight: .medium))
                            .tint(Theme.foreground)
                            .accessibilityIdentifier("customer-details-disclosure")
                        }
                        CustomerMembershipSection(customerID: customer.id)
                        contactsSection
                        locationsSection
                        CustomerEquipmentSection(customerID: customer.id, locations: locations.filter { $0.kind == "service" })
                    case "Jobs":
                        if session.can("job.view", feature: "jobs") { jobsSection }
                        else { unavailable("Jobs", "You don’t have access to jobs in this workspace.") }
                    case "Records": recordsSection
                    case "Activity": activitySection
                    default: activitySection
                    }
                }.padding(.horizontal, Theme.gutter).padding(.top, 12).padding(.bottom, 24)
                } header: {
                    // Pinned like the job page's tabs.
                    PaperTabs(options: ["Overview", "Jobs", "Records", "Activity"], selection: $tab).background(Theme.background)
                }
            }
        }
        .foregroundStyle(Theme.foreground).background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            let items = customerMenuItems
            if !items.isEmpty {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    ThorbisMenu(items: items, accessibilityLabel: "Customer actions") { PaperCircleLabel(symbol: "ellipsis", fill: Theme.card, bordered: true) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !typeSize.isAccessibilitySize { customerPrimaryActions }
        }
        .deviceHandoffs($handoff)
        .task { await load() }
        .task { await loadSmsConsent() }
        .task(id: recordsScope) {
            if recordsPublishedScope != recordsScope {
                records = nil
                recordsPublishedScope = nil
                recordsError = nil
            }
            if tab == "Records" { await loadRecords() }
        }
        .onAppear {
            RecentItems.shared.record(.customer, id: customer.id, title: customer.name, subtitle: "Customer")
            #if DEBUG
            if PaperPreview.enabled && PaperPreview.screen == "customer-activity" { tab = "Activity" }
            if PaperPreview.enabled && PaperPreview.screen == "customer-records" { tab = "Records" }
            #endif
        }
        .onChange(of: tab) { _, selectedTab in
            if selectedTab == "Activity" { Task { await loadActivity(reset: true) } }
            if selectedTab == "Records" { Task { await loadRecords() } }
        }
        .refreshable {
            await load()
            if tab == "Activity" { await loadActivity(reset: true) }
            if tab == "Records" { await loadRecords() }
        }
        .sheet(isPresented: $showNewJob) { NewJobSheet(preselected: customer) }
        .fullScreenCover(isPresented: $showCustomerMode, onDismiss: { Task { await load(); await loadSmsConsent() } }) {
            CustomerSelfEditView(customerID: customer.id) { showCustomerMode = false }
        }
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
        .thorbisConfirm(item: $locationToRemove,
                        title: { _ in "Remove service location?" },
                        message: { _ in "This removes the location from \(record?.name ?? customer.name)." },
                        actions: { location in
            [ThorbisConfirmAction("Remove \(location.label)", role: .destructive) {
                Task { await removeLocation(location) }
            }]
        })
        .thorbisConfirm(item: $contactToRemove,
                        title: { _ in "Remove customer contact?" },
                        message: { contact in "This removes \(contact.name) from \(record?.name ?? customer.name)." },
                        actions: { contact in
            [ThorbisConfirmAction("Remove \(contact.name)", role: .destructive) {
                Task { await removeContact(contact) }
            }]
        })
    }
    @ViewBuilder private var metadataChips: some View {
        if record?.archived == true { Chip(text: "Archived", icon: "archivebox") }
        if jobs.contains(where: { $0.status == "in_progress" }) { Chip(text: "Job in progress", icon: "circle.lefthalf.filled", tint: Theme.warning, bg: Theme.warningSurface) }
        if session.can("job.view", feature: "jobs") { Chip(text: "\(jobs.count) jobs", icon: "clock") }
        if let type = record?.accountType { Chip(text: type.statusLabel) }
        MemberChip(customerID: customer.id)
    }
    private var customerPrimaryActions: some View {
        let actions = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return actions {
            if canEdit {
                Button { showCustomerMode = true } label: {
                    // Keep the customer handoff clear even when space is tight.
                    Group {
                        if typeSize.isAccessibilitySize {
                            Text("Customer review")
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ViewThatFits(in: .horizontal) {
                                Label("Customer checks details", systemImage: "person.crop.rectangle").fixedSize()
                                Text("Customer review")
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .font(Theme.font(17, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, typeSize.isAccessibilitySize ? 10 : 8)
                    .frame(maxWidth: .infinity, minHeight: Theme.commitHeight)
                    .foregroundStyle(Theme.foreground).background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Show to customer")
                .accessibilityHint("Hands the device to the customer to check and fix their details")
                .accessibilityIdentifier("customer-handoff-action")
            }
            if session.can("job.create", feature: "jobs") {
                Button { showNewJob = true } label: {
                    Label("New job", systemImage: "plus").inkCommit()
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("customer-new-job-action")
            }
        }.padding(.horizontal, 20).padding(.vertical, 10).background(Theme.background)
    }
    private var customerIdentity: some View {
        let name = record?.name ?? customer.name
        let initial = name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() }
        return HStack(alignment: .top, spacing: 14) {
            if !typeSize.isAccessibilitySize, let initial {
                Text(initial)
                    .font(Theme.font(20, weight: .semibold))
                    .foregroundStyle(Theme.brandText)
                    .frame(width: 48, height: 48)
                    .background(Theme.brandSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(Theme.font(26, weight: .semibold)).tracking(-0.4)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let date = JobFiltering.date(record?.createdAt ?? customer.createdAt) {
                    Text("Customer since \(date.formatted(.dateTime.month(.abbreviated).year()))")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let record {
                if let phone = record.phone { detailRow("Phone", value: phone) }
                if let email = record.email {
                    HStack { Text("Email").foregroundStyle(Theme.muted); Spacer(); ContactActions(phone: nil, email: email) }.font(Theme.font(15)).frame(minHeight: 44)
                }
                if let address = record.address {
                    HStack { Text("Address").foregroundStyle(Theme.muted); Spacer(); AddressLink(address: address) }.font(Theme.font(15)).frame(minHeight: 44)
                }
                if let industry = record.industry { detailRow("Industry", value: industry) }
                if let preferred = record.preferredContact { detailRow("Contact preference", value: preferred.statusLabel) }
                if let terms = record.billingTerms { detailRow("Billing terms", value: terms) }
                if smsConsentLoaded { smsConsentRow }
            }
        }
    }
    /// The customer's open job first: what a dispatcher or tech opens a customer to find.
    @ViewBuilder private var nextVisit: some View {
        if let summary = JobFiltering.customerJobSummary(jobs, customerID: customer.id) {
            let job = summary.job
            VStack(alignment: .leading, spacing: 8) {
                PaperGroupHeader(title: summary.openCount > 1 ? "\(summary.heading) · \(summary.openCount) open" : summary.heading)
                NavigationLink(value: job) {
                    HStack(alignment: .top, spacing: 12) {
                        StatusRing(status: job.status).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(job.title).font(Theme.font(16, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                            Text([JobFiltering.date(job.scheduledFor).map { $0.visitLabel() } ?? "No time yet",
                                  job.status.statusLabel].joined(separator: " · "))
                                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 8)
                        PaperDisclosure()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border))
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier("customer-next-visit")
            }
        }
    }

    /// Email and Save to Contacts need no edit rights; the record changes do.
    private var customerMenuItems: [ThorbisMenuItem] {
        var items: [ThorbisMenuItem] = []
        if let record {
            if let mail = MailDraft(recipient: contacts.first(where: \.primary)?.email ?? record.email) {
                items.append(ThorbisMenuItem("Email", icon: "envelope") { handoff = .mail(mail) })
            }
            items.append(ThorbisMenuItem("Save to Contacts", icon: "person.crop.circle.badge.plus") {
                handoff = .contact(ContactCardDraft.make(customer: record))
            })
        }
        guard canEdit else { return items }
        return items + [
            ThorbisMenuItem("Show to customer", icon: "person.crop.rectangle") { showCustomerMode = true },
            ThorbisMenuItem("Add contact", icon: "person.badge.plus", isDisabled: !contactsLoaded) { contactSheet = .add },
            ThorbisMenuItem("Add location", icon: "mappin.and.ellipse") { locationSheet = .add },
        ]
    }

    private func contactMenuItems(_ contact: CustomerContactRecord) -> [ThorbisMenuItem] {
        var items: [ThorbisMenuItem] = []
        if let mail = MailDraft(recipient: contact.email) {
            items.append(ThorbisMenuItem("Email", icon: "envelope") { handoff = .mail(mail) })
        }
        items.append(ThorbisMenuItem("Save to Contacts", icon: "person.crop.circle.badge.plus") {
            handoff = .contact(ContactCardDraft.make(contact: contact, customerName: record?.name ?? customer.name, address: record?.address))
        })
        guard canEdit else { return items }
        items.append(ThorbisMenuItem("Edit contact", icon: "pencil") { contactSheet = .edit(contact) })
        if !contact.primary {
            items.append(ThorbisMenuItem("Make primary", icon: "star", isDisabled: isMutatingContact) {
                Task { await makeContactPrimary(contact) }
            })
        }
        items.append(ThorbisMenuItem("Remove contact", icon: "trash", isDisabled: isMutatingContact, role: .destructive) {
            contactToRemove = contact
        })
        return items
    }

    private func locationMenuItems(_ location: ServiceLocationRecord) -> [ThorbisMenuItem] {
        [ThorbisMenuItem("Edit location", icon: "pencil") { locationSheet = .edit(location) },
         ThorbisMenuItem("Remove location", icon: "trash", role: .destructive) { locationToRemove = location }]
    }

    /// Job texts: what the customer told staff about text messages for their jobs.
    private var smsConsentRow: some View {
        // Captured so dismissing the confirm (which clears smsConsentChoice) can't blank the choice
        // before the action reads it.
        let pendingGrant = smsConsentChoice
        return HStack {
            Text("Job texts").foregroundStyle(Theme.muted)
            Spacer()
            let granted = smsConsent?.decision == "grant"
            if canEdit {
                ThorbisMenu(items: [
                    ThorbisMenuItem("Customer agreed to job texts", icon: "checkmark.message", isDisabled: granted) { smsConsentChoice = true },
                    ThorbisMenuItem("Customer asked to stop texts", icon: "nosign", isDisabled: smsConsent?.decision == "revoke") { smsConsentChoice = false },
                ]) {
                    HStack(spacing: 4) {
                        Text(smsConsentLabel)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.foreground)
                    .frame(minHeight: 44)
                }
            } else {
                Text(smsConsentLabel).foregroundStyle(Theme.foreground)
            }
        }
        .font(Theme.font(15))
        .frame(minHeight: 44)
        .thorbisConfirm(pendingGrant == true ? "Record that the customer agreed to job texts?" : "Record that the customer asked to stop job texts?",
                        message: "Only record what the customer told you themselves.",
                        isPresented: Binding(get: { smsConsentChoice != nil }, set: { if !$0 { smsConsentChoice = nil } }),
                        actions: [ThorbisConfirmAction(pendingGrant == true ? "Customer agreed" : "Customer asked to stop") {
            if let grant = pendingGrant { Task { await recordSmsConsent(grant) } }
        }])
        .overlay(alignment: .bottomTrailing) {
            if let smsConsentError { Text(smsConsentError).font(Theme.font(12)).foregroundStyle(Theme.destructive).offset(y: 14) }
        }
    }

    private var smsConsentLabel: String {
        guard let smsConsent else { return "Not asked" }
        let date = JobFiltering.date(smsConsent.recordedAt).map { " · " + $0.formatted(.dateTime.month(.abbreviated).day()) } ?? ""
        return (smsConsent.decision == "grant" ? "Allowed" : "Stopped") + date
    }

    private func loadSmsConsent() async {
        guard session.can("customer.view", feature: "core_crm") else { return }
        do {
            smsConsent = try await api.customerSmsConsent(customer.id)
            smsConsentLoaded = true
        } catch {
            // An older server or no access: leave the row out rather than show a guess.
        }
    }

    private func recordSmsConsent(_ grant: Bool) async {
        do {
            smsConsent = try await api.recordCustomerSmsConsent(customer.id, grant: grant, expectedVersion: smsConsent?.version,
                                                                idempotencyKey: smsConsentKey)
            smsConsentKey = UUID().uuidString
            smsConsentError = nil
        } catch is CancellationError {
        } catch {
            smsConsentError = error.isConnectivityFailure ? "Needs a connection" : "Couldn't save. Pull to refresh and try again."
        }
    }

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { sectionTitle("Contacts", count: contacts.count); Spacer(); if canEdit { Button { contactSheet = .add } label: { Image(systemName: "plus").frame(width: 44, height: 44, alignment: .trailing).contentShape(Rectangle()) }.accessibilityLabel("Add contact").disabled(!contactsLoaded) } }
            if let contactMutationError {
                Text(contactMutationError).font(Theme.font(13)).foregroundStyle(Theme.destructive)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.destructiveSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .accessibilityIdentifier("contact-mutation-error")
            }
            ForEach(contacts) { contact in
                HStack(spacing: 10) {
                    Avatar(name: contact.name, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(contact.name).font(Theme.font(15, weight: .medium))
                        Text([contact.role, contact.primary ? "Primary" : nil].compactMap { $0 }.joined(separator: " · ")).font(Theme.font(12)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 2)
                    if let phone = contact.phone { CustomerContactIcon(value: phone, isPhone: true) }
                    if let email = contact.email { CustomerContactIcon(value: email, isPhone: false) }
                    ThorbisMenu(items: contactMenuItems(contact),
                                accessibilityLabel: "Contact actions for \(contact.name)") {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44, alignment: .trailing).contentShape(Rectangle())
                    }
                    .disabled(isMutatingContact)
                }.frame(minHeight: 48)
            }
            if contacts.isEmpty { emptyText("No contacts") }
        }
    }
    private var locationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { sectionTitle("Locations", count: locations.count); Spacer(); if canEdit { Button { locationSheet = .add } label: { Image(systemName: "plus").frame(width: 44, height: 44, alignment: .trailing).contentShape(Rectangle()) }.accessibilityLabel("Add location") } }
            if let locationError {
                Text(locationError).font(Theme.font(13)).foregroundStyle(Theme.destructive)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.destructiveSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .accessibilityIdentifier("location-mutation-error")
            }
            ForEach(locations) { location in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(location.label).font(Theme.font(15, weight: .medium)).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                        Spacer(minLength: 4)
                        Text(location.kind.statusLabel).font(Theme.font(12)).foregroundStyle(Theme.muted)
                        if canEdit {
                            ThorbisMenu(items: locationMenuItems(location),
                                        accessibilityLabel: "Options for \(location.label)") {
                                Image(systemName: "ellipsis")
                                    .frame(width: 30, height: 30)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
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
                    .font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
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
            sectionTitle("All jobs", count: jobs.count)
            ForEach(jobs) { job in
                NavigationLink(value: job) {
                    HStack(spacing: 12) {
                        Image(systemName: statusIcon(job.status).0).foregroundStyle(statusIcon(job.status).1).frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.title).font(Theme.font(15, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                            Text(job.status.statusLabel).font(Theme.font(12)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 8)
                        PaperDisclosure()
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(RowPressStyle())
            }
            if jobs.isEmpty { emptyText("No jobs") }
        }
    }
    private var recordsSection: some View {
        let scope = recordsScope
        let visible = scope != nil && recordsPublishedScope == scope ? records : nil
        let visibleError = scope != nil && recordsRequestedScope == scope ? recordsError : nil
        return VStack(alignment: .leading, spacing: 10) {
            if scope == nil {
                emptyText("You don’t have access to this customer’s records.")
            } else {
                if let visibleError {
                    ErrorBanner(message: visible == nil ? "Records did not load. \(visibleError)" : visibleError) {
                        await loadRecords()
                    }.accessibilityIdentifier("customer-records-retry")
                }
                if visible == nil && visibleError == nil {
                    SkeletonRows(count: 4, inset: 0)
                } else if let visible {
                    CustomerRecordsView(compilation: visible, customerID: customer.id) { await loadRecords() }
                        .accessibilityIdentifier("customer-records")
                }
            }
        }
    }

    private func loadRecords() async {
        guard let scope = recordsScope else { return }
        guard !recordsLoading || recordsRequestedScope != scope else { return }
        recordsLoadGeneration += 1
        let request = recordsLoadGeneration
        recordsLoading = true
        recordsRequestedScope = scope
        recordsError = nil
        defer { if recordsLoadGeneration == request { recordsLoading = false } }
        do {
            let compiled = try await CustomerJobCompilationLoader.load(customerID: scope.customerID,
                organizationID: scope.organizationID, api: api, access: scope.access)
            guard !Task.isCancelled, recordsLoadGeneration == request, scope.isCurrent(session: session) else { return }
            records = compiled
            recordsPublishedScope = scope
            recordsError = nil
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, recordsLoadGeneration == request, scope.isCurrent(session: session) else { return }
            recordsError = error.localizedDescription
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Customer activity").font(Theme.font(13, weight: .medium))
                Text("\(activity.count)").font(Theme.font(12))
                if activityCursor != nil { Text("· loaded").font(Theme.font(12)) }
            }.foregroundStyle(Theme.muted).padding(.bottom, 6)
            if !session.can("customer.view", feature: "core_crm") {
                emptyText("You don’t have access to customer activity.")
            } else {
                if let activityError {
                    ErrorBanner(message: activity.isEmpty ? "Activity did not load. \(activityError)" : activityError) {
                        // A failed "load earlier" keeps its cursor, so retry continues the page
                        // instead of throwing away what already loaded.
                        await loadActivity(reset: activityCursor == nil)
                    }
                    .accessibilityIdentifier("customer-activity-retry")
                }
                if activityLoading && activity.isEmpty { SkeletonRows(count: 4, inset: 0) }
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(activity) { event in
                        ActivityLink(destination: ActivityDestinationMapping.customerHistory(event, customerID: customer.id)) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: activitySymbol(for: event.kind))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 30, height: 30)
                                    .background(Theme.fill, in: Circle())
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.summary).font(Theme.font(15, weight: .medium)).lineLimit(3)
                                    Text(activityTimestamp(event.occurredAt)).font(Theme.font(12)).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                            }
                            .padding(.vertical, 9)
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
                        }
                    }
                }
                if activity.isEmpty && !activityLoading && activityError == nil {
                    emptyText("Nothing yet…")
                }
                if activityCursor != nil {
                    Button {
                        Task { await loadActivity(reset: false) }
                    } label: {
                        Text(activityLoading ? "Loading…" : activityError == nil ? "Load earlier activity" : "Retry earlier activity")
                            .font(Theme.font(13, weight: .medium)).frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(activityLoading)
                }
            }
        }
    }

    private func loadActivity(reset: Bool) async {
        guard session.can("customer.view", feature: "core_crm"), !activityLoading else { return }
        if reset {
            activityLoadGeneration += 1
            activityCursor = nil
        } else if activityCursor == nil {
            return
        }
        let request = activityLoadGeneration
        let cursor = reset ? nil : activityCursor
        activityLoading = true
        defer { if activityLoadGeneration == request { activityLoading = false } }
        do {
            let page = try await api.fieldCustomerHistory(customer.id, cursor: cursor)
            guard activityLoadGeneration == request else { return }
            if reset { activity = page.items }
            else {
                let existingIDs = Set(activity.map(\.id))
                activity.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
            }
            activityCursor = page.nextCursor
            activityError = nil
        } catch is CancellationError {
        } catch {
            guard activityLoadGeneration == request else { return }
            activityError = error.localizedDescription
        }
    }

    private func sectionTitle(_ title: String, count: Int? = nil) -> some View {
        HStack(spacing: 6) { Text(title).font(Theme.font(13, weight: .medium)); if let count { Text("\(count)").font(Theme.font(12)) } }.foregroundStyle(Theme.muted).padding(.bottom, 6)
    }
    private func activityTimestamp(_ raw: String) -> String {
        guard let date = JobFiltering.date(raw) else { return raw }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
    private func activitySymbol(for kind: String) -> String {
        switch kind {
        case "estimate": "doc.text"
        case "job": "wrench.and.screwdriver"
        case "invoice": "doc.plaintext"
        case "payment": "dollarsign.circle"
        case "contact": "person.crop.circle"
        case "location": "mappin.and.ellipse"
        default: "clock"
        }
    }
    private func detailRow(_ title: String, value: String) -> some View {
        HStack(spacing: 12) { Text(title).foregroundStyle(Theme.muted); Spacer(minLength: 10); Text(value).multilineTextAlignment(.trailing) }.font(Theme.font(15)).frame(minHeight: 44)
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
                    .frame(width: size, height: size).background(size == 46 ? Theme.card : Theme.fill, in: RoundedRectangle(cornerRadius: size == 46 ? 12 : 15, style: .continuous))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel("\(isPhone ? "Call" : "Email") \(value)")
        }
    }
}
