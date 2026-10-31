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
    @State private var newName = ""
    @State private var selectedView = CustomerListScope.recent.rawValue
    @State private var stateFilter = "Any state"
    @State private var records: [CustomerRecord] = []
    @State private var recordsLoading = true
    @State private var loadGeneration = 0
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var scope: CustomerListScope { CustomerListScope(rawValue: selectedView) ?? .recent }
    private var items: [CustomerRecord] {
        scope.customers(from: records).filter { customer in
            let matchesState = stateFilter == "Any state"
                || (stateFilter == "Archived") == customer.archived
            return matchesState
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
                // Finding a customer is the bar's Search; Recent / All / Archived narrow the book.
                PaperHeader(title: "Customers", subtitle: recordsLoading && records.isEmpty ? "Loading customers…" : "\(records.count) customers · \(activeJobs) active jobs", showsCreate: true)
                PaperTabs(options: CustomerListScope.allCases.map(\.rawValue), selection: $selectedView, textTabs: true)
                if let error = error ?? store.error {
                    ErrorBanner(message: error) { _ = await store.refresh(api); await loadCustomers() }
                }
                if recordsLoading && records.isEmpty { SkeletonRows() }
                // Grouped wells (redesign phase 2): a semibold header with its count over one well,
                // each row its own lazy slice so a long book stays lazy.
                ForEach(sections, id: \.0) { letter, customers in
                    WellSection(title: letter, count: customers.count, data: customers,
                                dividerInset: CustomerListRowContent.dividerInset) { customer in
                        customerRow(customer, jobs: jobGroups.jobs(for: customer.id))
                    }
                }
                .paperCardMargin()
                if items.isEmpty && !recordsLoading && error == nil && store.error == nil {
                    if scope == .archived {
                        PaperEmptyState(symbol: "archivebox", title: "No archived customers")
                    } else {
                        PaperEmptyState(symbol: "person.2", title: "No customers yet",
                                        actionTitle: session.can("customer.create", feature: "core_crm") ? "Add a customer" : nil,
                                        action: { showNew = true })
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { await store.refresh(api); await SavedCopies.$liveOnly.withValue(true) { await loadCustomers() } }
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
        // iPad selects into the detail column beside the list; iPhone pushes.
        return PaperSplitLink(id: customer.id, value: listCustomer) {
            // Redesign phase 2: initials, the name, where and how to reach them, how many jobs and
            // when the open visit is, and the open job's state as a glyph and word.
            CustomerListRowContent(name: customer.name, detail: rowDetail(customer),
                                   meta: rowMeta(jobCount: jobCount, open: summaryJob, now: now),
                                   status: summaryJob.map { job in
                                       isLate(job, now: now) ? (StatusTone.attention, "Late")
                                           : (StatusTone(jobStatus: job.status, hasTime: job.scheduledFor != nil), job.status.statusLabel)
                                   },
                                   archived: customer.archived)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("customer-row-\(customer.id)")
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
    }

    /// A booked visit whose time has passed: one word ("Late") instead of "Past scheduled time · Scheduled".
    private func isLate(_ job: Job, now: Date) -> Bool {
        guard ["scheduled", "dispatched"].contains(job.status), let date = JobFiltering.date(job.scheduledFor) else { return false }
        return date < now
    }

    /// Where and how to reach them: the street, then the phone.
    private func rowDetail(_ customer: CustomerRecord) -> String? {
        let street = customer.address.flatMap { NextStopPlace(jobID: "", organizationID: "", customerID: "", address: $0).firstLine }
        let parts = [street, customer.phone].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The job count, then when the open visit is. Same words as Jobs ("Today 4 p.m.").
    private func rowMeta(jobCount: Int, open: Job?, now: Date) -> String {
        var parts = ["\(jobCount) \(jobCount == 1 ? "job" : "jobs")"]
        if let open, let date = JobFiltering.date(open.scheduledFor), ["scheduled", "dispatched"].contains(open.status) {
            parts.append(date.visitLabel(now: now))
        }
        return parts.joined(separator: " · ")
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

    /// Member pricing for the subtitle ("Member, 15% off").
    @State private var pricing: MemberPricing?
    /// The customer's jobs as GET /v1/jobs?customerId returns them: the notes line for Jobs.
    @State private var jobRecords: [JobRecord] = []
    @State private var showAllPast = false
    @Environment(\.openURL) private var openURL

    /// Overview | Jobs · N | Money: the page's one selector row.
    private var jobsLabel: String { session.can("job.view", feature: "jobs") ? "Jobs · \(jobs.count)" : "Jobs" }
    private var tabBinding: Binding<String> {
        Binding(get: { tab == "Jobs" ? jobsLabel : tab }, set: { tab = $0.hasPrefix("Jobs") ? "Jobs" : $0 })
    }
    private var primaryPhone: String? { contacts.first(where: \.primary)?.phone ?? record?.phone }
    private var primaryEmail: String? { contacts.first(where: \.primary)?.email ?? record?.email }
    private var directionsURL: URL? {
        (locations.first?.address ?? record?.address).flatMap { Directions.url(address: $0, coordinates: locations.first?.coordinates) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                OfflineBanner().padding(.horizontal, -Theme.gutter)
                SavedCopyNote(savedAt: api.savedCopyDate("/v1/customers/\(customer.id)")).padding(.horizontal, -Theme.gutter)
                customerIdentity
                actionCircles
                PaperTabs(options: ["Overview", jobsLabel, "Money"], selection: tabBinding, textTabs: true)
                    .padding(.horizontal, -Theme.gutter)
                if let error {
                    ErrorBanner(message: error) { await load() }
                }
                switch tab {
                case "Jobs":
                    if session.can("job.view", feature: "jobs") { jobsSection }
                    else { unavailable("Jobs", "You don’t have access to jobs in this workspace.") }
                case "Money": moneySection
                default: overview
                }
                // At accessibility sizes a pinned New job would cover half the screen, so it
                // follows the content instead (as on the customer presentation).
                if typeSize.isAccessibilitySize { customerPrimaryActions.padding(.horizontal, -Theme.gutter) }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 4).padding(.bottom, 24)
            // Redesign phase 2: every section here is a semibold header over a grouped well.
            .environment(\.paperGroupedWells, true)
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
                    ThorbisMenu(items: items, accessibilityLabel: "Customer actions") { PaperCircleLabel(symbol: "ellipsis", fill: Theme.fill, bordered: true) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { if !typeSize.isAccessibilitySize { customerPrimaryActions } }
        .deviceHandoffs($handoff)
        .task { await load() }
        .task { await loadSmsConsent() }
        .task(id: customer.id) { pricing = try? await api.memberPricing(customer.id) }
        .task { await loadActivity(reset: true) }
        .task(id: recordsScope) {
            if recordsPublishedScope != recordsScope {
                records = nil
                recordsPublishedScope = nil
                recordsError = nil
            }
            if tab != "Overview" { await loadRecords() }
        }
        .onAppear {
            RecentItems.shared.record(.customer, id: customer.id, title: customer.name, subtitle: "Customer")
            #if DEBUG
            if PaperPreview.enabled && ["customer-records", "customer-jobs"].contains(PaperPreview.screen) { tab = "Jobs" }
            if PaperPreview.enabled && PaperPreview.screen == "customer-money" { tab = "Money" }
            #endif
        }
        .onChange(of: tab, initial: true) { _, selectedTab in
            if selectedTab != "Overview" { Task { await loadRecords() } }
            if selectedTab == "Jobs" { Task { await loadJobRecords() } }
        }
        .refreshable {
            await SavedCopies.$liveOnly.withValue(true) {
                await load()
                await loadActivity(reset: true)
                if tab != "Overview" { await loadRecords() }
                if tab == "Jobs" { await loadJobRecords() }
            }
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

    /// Details always open (address first), the open job, membership, contacts, places, equipment,
    /// then the customer's activity.
    @ViewBuilder private var overview: some View {
        if record == nil && error == nil {
            PaperCard { SkeletonRows(count: 3, leading: false, inset: PaperCardMetrics.inset) }
        } else {
            details
        }
        if session.can("job.view", feature: "jobs") { nextVisit }
        CustomerMembershipSection(customerID: customer.id)
        contactsSection
        locationsSection
        CustomerEquipmentSection(customerID: customer.id, locations: locations.filter { $0.kind == "service" })
        activitySection
    }

    /// Call, Text, Email and Directions as labelled quiet circles; only the ones this customer has.
    @ViewBuilder private var actionCircles: some View {
        let dialable = primaryPhone.map { $0.filter { $0.isNumber || $0 == "+" } }.flatMap { $0.count >= 7 ? $0 : nil }
        let mail = MailDraft(recipient: primaryEmail)
        if dialable != nil || mail != nil || directionsURL != nil {
            let count = (dialable != nil ? 2 : 0) + (mail != nil ? 1 : 0) + (directionsURL != nil ? 1 : 0)
            // At accessibility sizes two across, like the job's reach circles: a sideways-scrolling row
            // cut "Directions" off the edge, so the last action was easy to miss with large text.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .top),
                                     count: typeSize.isAccessibilitySize ? min(2, count) : count), spacing: 12) {
                actionCircleItems(dialable: dialable, mail: mail)
            }
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder private func actionCircleItems(dialable: String?, mail: MailDraft?) -> some View {
        if let dialable, let call = URL(string: "tel:\(dialable)"), let text = URL(string: "sms:\(dialable)") {
            PaperLabeledCircle(symbol: "phone", title: "Call") { openURL(call) }
            PaperLabeledCircle(symbol: "message", title: "Text") { openURL(text) }
        }
        if let mail { PaperLabeledCircle(symbol: "envelope", title: "Email") { handoff = .mail(mail) } }
        if let directionsURL {
            PaperLabeledCircle(symbol: "arrow.triangle.turn.up.right.diamond", title: "Directions",
                               accessibilityLabel: "Directions in Maps") { openURL(directionsURL) }
        }
    }

    /// New job: the page's one ink commit, pinned at the bottom.
    @ViewBuilder private var customerPrimaryActions: some View {
        if session.can("job.create", feature: "jobs") {
            Button { showNewJob = true } label: {
                Label("New job", systemImage: "plus").inkCommit()
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("customer-new-job-action")
            .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 8).background(Theme.background)
        }
    }

    /// Redesign phase 2 (after Linear's project overview): the customer's initials, the name in
    /// 30 semibold, then a row of property chips for what the record says about them. The chips wrap,
    /// so nothing is cut at accessibility sizes.
    private var customerIdentity: some View {
        let name = record?.name ?? customer.name
        return VStack(alignment: .leading, spacing: 10) {
            // The name is the page's heading; the circle repeats it, so VoiceOver skips the circle.
            InitialsAvatar(name: name, size: 52).accessibilityHidden(true)
            Text(name)
                .font(Theme.font(30, weight: .semibold)).tracking(-0.5)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            let chips = identityChips
            if !chips.isEmpty {
                FlowRow(spacing: 6, lineSpacing: 6) {
                    ForEach(chips, id: \.text) { chip in
                        PropertyChip(chip.text, symbol: chip.symbol, tint: chip.tint, textColor: chip.textColor, action: chip.action)
                            .accessibilityHint(chip.action == nil ? "" : "Shows the customer's jobs")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(chips.map(\.text).joined(separator: ", "))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Since when, membership, how many jobs (opens Jobs), the account type and archived: each only
    /// when the record or the server says so. There is no balance here: the customer's open balance
    /// only exists once the records compilation loads, on Jobs and Money.
    private var identityChips: [(text: String, symbol: String?, tint: Color, textColor: Color, action: (() -> Void)?)] {
        var chips: [(text: String, symbol: String?, tint: Color, textColor: Color, action: (() -> Void)?)] = []
        if record?.archived ?? customer.archived ?? false {
            chips.append(("Archived", "archivebox", Theme.fill, Theme.foreground, nil))
        }
        if let pricing, pricing.isMember {
            chips.append((pricing.discountPercent > 0 ? "Member, \(pricing.discountPercent)% off" : "Member", "star.fill",
                          Theme.statusInvoicedSurface, Theme.statusInvoicedText, nil))
        }
        if session.can("job.view", feature: "jobs") {
            let open = jobs.filter { !["completed", "canceled"].contains($0.status) }.count
            let text = open > 0 ? "\(jobs.count) \(jobs.count == 1 ? "job" : "jobs") · \(open) open" : "\(jobs.count) \(jobs.count == 1 ? "job" : "jobs")"
            chips.append((text, "briefcase", Theme.fill, Theme.foreground, { tab = "Jobs" }))
        }
        if let type = record?.accountType { chips.append((type.statusLabel, "house", Theme.fill, Theme.foreground, nil)) }
        if let date = JobFiltering.date(record?.createdAt ?? customer.createdAt) {
            chips.append(("Since \(date.formatted(.dateTime.year()))", "calendar", Theme.fill, Theme.foreground, nil))
        }
        return chips
    }

    /// Always open, on one panel: address first, then phone and email, then the rest (F18).
    @ViewBuilder private var details: some View {
        if let record {
            PaperCard {
                VStack(alignment: .leading, spacing: 0) {
                    if let address = record.address, !address.isEmpty {
                        detailLine("Address") { AddressLink(address: address) }
                    }
                    if let phone = record.phone, !phone.isEmpty {
                        detailLine("Phone") { ContactActions(phone: phone, email: nil) }
                    }
                    if let email = record.email, !email.isEmpty {
                        detailLine("Email") { ContactActions(phone: nil, email: email) }
                    }
                    if let type = record.accountType { detailLine("Account") { Text(type.statusLabel) } }
                    if let industry = record.industry { detailLine("Industry") { Text(industry) } }
                    if let preferred = record.preferredContact { detailLine("Contact preference") { Text(preferred.statusLabel) } }
                    if let terms = record.billingTerms { detailLine("Billing terms") { Text(terms) } }
                    if smsConsentLoaded { smsConsentRow.padding(.horizontal, PaperCardMetrics.inset) }
                }
                .padding(.vertical, PaperCardMetrics.edge)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("customer-details")
        }
    }
    /// A muted label left, its value right; a long value wraps under the label.
    private func detailLine<V: View>(_ title: String, @ViewBuilder value: () -> V) -> some View {
        PaperDetailRow(label: title) { value().labelStyle(.titleOnly).tint(Theme.foreground) }
            .padding(.horizontal, PaperCardMetrics.inset)
    }
    /// The customer's open job: what a dispatcher or tech opens a customer to find.
    @ViewBuilder private var nextVisit: some View {
        if let summary = JobFiltering.customerJobSummary(jobs, customerID: customer.id) {
            let job = summary.job
            // One heading and one word: "Open job", and "Late" when a booked visit's time has passed
            // (never "Past scheduled time" above a row that says "Scheduled").
            let late = ["scheduled", "dispatched"].contains(job.status) && (JobFiltering.date(job.scheduledFor).map { $0 < .now } ?? false)
            PaperSection(summary.openCount > 1 ? "Open jobs" : "Open job", count: summary.openCount > 1 ? summary.openCount : nil) {
                NavigationLink(value: job) {
                    // The status glyph, the problem, then where, when and who (the page is the customer).
                    JobListRowContent(job: job, place: street(for: job.locationId),
                                      when: JobFiltering.date(job.scheduledFor).map { $0.visitLabel() } ?? "No time yet",
                                      late: late, assigneeWord: tech(job.assignedToUserId), titleLines: 3)
                }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier("customer-next-visit")
            }
        }
    }

    private func street(for locationID: String?) -> String? {
        guard let locationID, let place = locations.first(where: { $0.id == locationID }) else { return nil }
        return NextStopPlace(jobID: "", organizationID: "", customerID: "", address: place.address).firstLine
    }

    /// Only the signed-in person can be named; other techs need the assignee roster (backend gap).
    private func tech(_ userID: String?) -> String? {
        guard let userID, userID == session.user?.id else { return nil }
        return "You"
    }

    /// Save to Contacts, Customer view and the record changes. Email is a circle on the page.
    private var customerMenuItems: [ThorbisMenuItem] {
        var items: [ThorbisMenuItem] = []
        if let record {
            items.append(ThorbisMenuItem("Save to Contacts", icon: "person.crop.circle.badge.plus") {
                handoff = .contact(ContactCardDraft.make(customer: record))
            })
        }
        guard canEdit else { return items }
        return items + [
            // Customer view: hands the phone to the customer to check and fix their details.
            ThorbisMenuItem("Customer view", icon: "person.crop.rectangle",
                            subtitle: "Hand the phone over to check their details") { showCustomerMode = true },
            ThorbisMenuItem("Add contact", icon: "person.badge.plus", isDisabled: !contactsLoaded) { contactSheet = .add },
            ThorbisMenuItem("Add location", icon: "mappin.and.ellipse") { locationSheet = .add },
        ]
    }

    private func contactMenuItems(_ contact: CustomerContactRecord) -> [ThorbisMenuItem] {
        var items: [ThorbisMenuItem] = []
        if let phone = contact.phone.map({ $0.filter { $0.isNumber || $0 == "+" } }), phone.count >= 7 {
            if let call = URL(string: "tel:\(phone)") { items.append(ThorbisMenuItem("Call", icon: "phone") { openURL(call) }) }
            if let text = URL(string: "sms:\(phone)") { items.append(ThorbisMenuItem("Text", icon: "message") { openURL(text) }) }
        }
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
                // The menu below says "Job texts" itself, so VoiceOver doesn't stop on the label alone.
                .accessibilityHidden(canEdit)
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
                    // A real 44pt target: the frame alone left VoiceOver and the hit test on the
                    // ~18pt words, so the shape covers the whole box for both, with room either side.
                    .padding(.leading, 12)
                    .frame(minHeight: 44)
                    .contentShape([.interaction, .accessibility], Rectangle())
                }
                .frame(minHeight: 44)
                .contentShape([.interaction, .accessibility], Rectangle())
                .accessibilityLabel("Job texts")
                .accessibilityValue(smsConsentLabel)
                .accessibilityHint("Record what the customer said about job texts")
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

    /// A section's quiet + beside its label.
    private func addButton(_ label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.foreground)
                .frame(width: 44, height: 44, alignment: .trailing).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
        .disabled(disabled)
    }

    private func mutationError(_ message: String, id: String) -> some View {
        Text(message).font(Theme.font(13)).foregroundStyle(Theme.destructive)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.destructiveSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .accessibilityIdentifier(id)
    }

    /// Contacts on one panel: name, role and number, "Primary" as a word; Call, Text, Email and
    /// the edits are in the row's ••• menu.
    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaperSection(title: "Contacts", count: contacts.isEmpty ? nil : contacts.count) {
                if contacts.isEmpty {
                    emptyText("No contacts").padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(contacts.enumerated()), id: \.element.id) { index, contact in
                            if index > 0 { WellDivider(leading: PaperCardMetrics.inset + 28 + 12) }
                            HStack(spacing: 0) {
                                InitialsAvatar(name: contact.name, size: 28)
                                    .padding(.leading, PaperCardMetrics.inset)
                                    .accessibilityHidden(true)
                                PaperListRow(title: contact.name,
                                             subtitle: [contact.role, contact.phone ?? contact.email].compactMap { $0 }.joined(separator: " · ")) {
                                    if contact.primary { StatusWord(text: "Primary") }
                                }
                                .environment(\.paperRowInset, 12)
                                // Name, "Primary", role and number as one VoiceOver stop; ••• stays its own.
                                .accessibilityElement(children: .combine)
                                ThorbisMenu(items: contactMenuItems(contact),
                                            accessibilityLabel: "Contact actions for \(contact.name)") {
                                    Image(systemName: "ellipsis").foregroundStyle(Theme.muted)
                                        .frame(width: 44, height: 44).contentShape(Rectangle())
                                }
                                .disabled(isMutatingContact)
                                .padding(.trailing, 4)
                            }
                        }
                    }
                    .padding(.vertical, PaperCardMetrics.edge)
                }
            } accessory: {
                if canEdit { addButton("Add contact", disabled: !contactsLoaded) { contactSheet = .add } }
            }
            if let contactMutationError { mutationError(contactMutationError, id: "contact-mutation-error") }
        }
    }

    /// Service and billing places: label, address (opens Maps), then the site notes.
    private var locationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaperSection(title: "Locations", count: locations.isEmpty ? nil : locations.count) {
                if locations.isEmpty {
                    emptyText("No locations").padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(locations.enumerated()), id: \.element.id) { index, location in
                            if index > 0 { WellDivider(leading: PaperCardMetrics.inset + 26 + 12) }
                            HStack(alignment: .top, spacing: 12) {
                                PlaceMark(symbol: location.kind == "billing" ? "building.2" : "house",
                                          tint: location.kind == "billing" ? Theme.markTeal : Theme.markAccent)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(location.label).font(Theme.font(16, weight: .medium))
                                            .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                                        Spacer(minLength: 4)
                                        StatusWord(text: location.kind.statusLabel)
                                    }
                                    .accessibilityElement(children: .combine)
                                    AddressLink(address: location.address, coordinates: location.coordinates)
                                        .labelStyle(.titleOnly).font(Theme.font(15)).tint(Theme.foreground)
                                    if let notes = location.notes { Text(notes).font(Theme.font(15)).foregroundStyle(Theme.muted) }
                                    if let parking = location.parking { detailRow("Parking", value: parking) }
                                    // A hazard on site reads in the warning tint, with its own glyph.
                                    if let dogs = location.dogOnSite { hazardRow("Dogs on site", value: dogs) }
                                    Text(location.coordinates.map { String(format: "Map pin %.4f, %.4f", $0.latitude, $0.longitude) } ?? "No map pin")
                                        .font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                                }
                                if canEdit {
                                    ThorbisMenu(items: locationMenuItems(location),
                                                accessibilityLabel: "Options for \(location.label)") {
                                        Image(systemName: "ellipsis").foregroundStyle(Theme.muted)
                                            .frame(width: 44, height: 44).contentShape(Rectangle())
                                    }
                                }
                            }
                            .padding(.leading, PaperCardMetrics.inset).padding(.trailing, canEdit ? 4 : PaperCardMetrics.inset)
                            .padding(.vertical, 10)
                        }
                    }
                    .padding(.vertical, PaperCardMetrics.edge)
                }
            } accessory: {
                if canEdit { addButton("Add location") { locationSheet = .add } }
            }
            if let locationError { mutationError(locationError, id: "location-mutation-error") }
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
    /// The records compiled for this customer, once they belong to the current identity.
    private var visibleRecords: CustomerJobCompilation? {
        let scope = recordsScope
        return scope != nil && recordsPublishedScope == scope ? records : nil
    }

    /// CustomerJobs.dc.html: open jobs, then past jobs with a date column, the job's notes and a
    /// meta line (tech · photos · paid). Then the jobs' photos, notes, documents and activity.
    private var jobsSection: some View {
        let ordered = CustomerJobOrder.sorted(jobs)
        let open = ordered.filter { !["completed", "canceled"].contains($0.status) }
        let past = ordered.filter { ["completed", "canceled"].contains($0.status) }
        // CustomerJobs.dc.html: four past jobs, then "Show N older jobs" (nothing is dropped).
        let shownPast = showAllPast ? past : Array(past.prefix(4))
        return VStack(alignment: .leading, spacing: 18) {
            if !open.isEmpty {
                PaperSection("Open", count: open.count) {
                    VStack(spacing: 0) {
                        ForEach(Array(open.enumerated()), id: \.element.id) { index, job in
                            if index > 0 { WellDivider(leading: JobListRowContent.dividerInset) }
                            customerJobRow(job, open: true)
                        }
                    }
                }
            }
            if !past.isEmpty {
                VStack(spacing: 0) {
                    PaperSection("Past", count: past.count) {
                        VStack(spacing: 0) {
                            ForEach(Array(shownPast.enumerated()), id: \.element.id) { index, job in
                                if index > 0 { WellDivider() }
                                customerJobRow(job, open: false)
                            }
                        }
                    }
                    if past.count > shownPast.count {
                        Button { withMotion { showAllPast = true } } label: {
                            Text("Show \(past.count - shownPast.count) older job\(past.count - shownPast.count == 1 ? "" : "s")")
                                .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .padding(.top, 4)
                    }
                }
            }
            if jobs.isEmpty { emptyText("No jobs yet") }
            recordsParts([.photos, .notes, .documents, .activity])
        }
    }

    private func customerJobRow(_ job: Job, open: Bool) -> some View {
        let full = jobRecords.first { $0.id == job.id }
        return NavigationLink(value: job) {
            if open {
                // Open work: the status glyph, the problem, where, when and who.
                JobListRowContent(job: job, place: street(for: job.locationId),
                                  when: JobFiltering.date(job.scheduledFor).map { $0.visitLabel() } ?? "No time yet",
                                  assigneeWord: tech(job.assignedToUserId))
            } else {
                // History (PR #199): the date column, the job's notes folding with "More", then tech · photos · paid.
                PaperListRow(leading: .text(shortDate(job, record: full)), title: job.title,
                             subtitle: summary(job, record: full), meta: meta(job),
                             subtitleLines: 3, expandsSubtitle: true) {
                    if job.status == "canceled" { StatusWord(jobStatus: job.status) }
                }
            }
        }
        .buttonStyle(RowPressStyle())
        .accessibilityHint("Opens the job")
    }

    /// "Today", "Tomorrow", "Apr 14", or "Oct 2, 2025" outside this year.
    private func shortDate(_ job: Job, record: JobRecord?) -> String {
        let raw = ["completed", "canceled"].contains(job.status)
            ? (record?.completedAt ?? record?.canceledAt ?? job.scheduledFor ?? job.updatedAt)
            : job.scheduledFor
        guard let date = JobFiltering.date(raw) else { return "No time" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// The job's own notes (what was found or done), else its latest note.
    private func summary(_ job: Job, record: JobRecord?) -> String? {
        if let notes = record?.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty { return notes }
        let latest = visibleRecords?.notes.first { $0.jobID == job.id }?.items.max { $0.createdAt < $1.createdAt }
        return latest?.body
    }

    /// Tech · N photos · $X paid: only what the server returns for this job.
    private func meta(_ job: Job) -> String? {
        var parts: [String] = []
        if let tech = tech(job.assignedToUserId) { parts.append(tech) }
        if let photos = visibleRecords?.photos.first(where: { $0.jobID == job.id })?.count, photos > 0 {
            parts.append("\(photos) photo\(photos == 1 ? "" : "s")")
        }
        if let invoices = visibleRecords?.invoices.first(where: { $0.jobID == job.id })?.items {
            let paid = invoices.filter { $0.amountPaid > 0 && $0.status != "void" }
            if let currency = paid.first?.currency, paid.allSatisfy({ $0.currency == currency }) {
                parts.append("\(money(paid.reduce(0) { $0 + $1.amountPaid }, currency: currency)) paid")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Money: the customer's estimates and invoices, on and off jobs.
    private var moneySection: some View { recordsParts([.estimates, .invoices]) }

    private func recordsParts(_ parts: Set<CustomerRecordsPart>) -> some View {
        let scope = recordsScope
        let visible = visibleRecords
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
                    SkeletonRows(count: 3, inset: 0)
                } else if let visible {
                    CustomerRecordsView(compilation: visible, customerID: customer.id, retryMedia: { await loadRecords() }, parts: parts)
                        .accessibilityIdentifier("customer-records")
                }
            }
        }
    }

    private func loadJobRecords() async {
        guard session.can("job.view", feature: "jobs"), let organizationID = session.activeOrganization?.id else { return }
        let generation = session.generation
        guard let loaded = try? await api.fieldJobs(customerID: customer.id), session.generation == generation else { return }
        jobRecords = loaded.filter { $0.customerId == customer.id && $0.organizationId == organizationID }
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


    /// The customer's activity at the foot of Overview: what happened, when, newest first.
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !session.can("customer.view", feature: "core_crm") {
                PaperSection("Activity") {
                    emptyText("You don’t have access to customer activity.").padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 6)
                }
            } else {
                if let activityError {
                    ErrorBanner(message: activity.isEmpty ? "Activity did not load. \(activityError)" : activityError) {
                        // A failed "load earlier" keeps its cursor, so retry continues the page
                        // instead of throwing away what already loaded.
                        await loadActivity(reset: activityCursor == nil)
                    }
                    .accessibilityIdentifier("customer-activity-retry")
                }
                PaperSection("Activity", count: activity.isEmpty ? nil : activity.count) {
                    if activityLoading && activity.isEmpty {
                        SkeletonRows(count: 3, leading: false, inset: PaperCardMetrics.inset)
                    } else if activity.isEmpty {
                        emptyText(activityError == nil ? "Nothing yet" : "Not loaded").padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 6)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(activity) { event in
                                ActivityLink(destination: ActivityDestinationMapping.customerHistory(event, customerID: customer.id)) {
                                    PaperListRow(title: event.summary, subtitle: activityTimestamp(event.occurredAt), subtitleLines: 1)
                                }
                            }
                        }
                        .padding(.vertical, PaperCardMetrics.edge)
                    }
                }
                .accessibilityIdentifier("customer-activity")
                if activityCursor != nil {
                    Button {
                        Task { await loadActivity(reset: false) }
                    } label: {
                        Text(activityLoading ? "Loading…" : activityError == nil ? "Load earlier activity" : "Retry earlier activity")
                            .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                            .frame(maxWidth: .infinity, minHeight: 44)
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
        return ActivityStamp.abbreviated.localizedString(for: date, relativeTo: .now)
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
        // A short value sits beside its label; a long one (or large text) goes under it, so words
        // never break mid-word in a narrow right-aligned column.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).foregroundStyle(Theme.muted).fixedSize()
                Spacer(minLength: 10)
                Text(value).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Theme.muted)
                Text(value).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6)
        }
        .font(Theme.font(15)).frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
    /// A site hazard (dogs on site): the warning tint on its own surface, so it can't be missed.
    private func hazardRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(13, weight: .semibold))
                Text(value).font(Theme.font(15)).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Theme.warning)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning, \(title): \(value)")
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

/// A customer's jobs in reading order: open ones by visit time (unscheduled last), then closed ones newest first.
enum CustomerJobOrder {
    static func sorted(_ jobs: [Job]) -> [Job] {
        let closed: Set<String> = ["completed", "canceled"]
        let open = jobs.filter { !closed.contains($0.status) }.sorted {
            (JobFiltering.date($0.scheduledFor) ?? .distantFuture, $0.id) < (JobFiltering.date($1.scheduledFor) ?? .distantFuture, $1.id)
        }
        let done = jobs.filter { closed.contains($0.status) }.sorted {
            (JobFiltering.date($0.scheduledFor) ?? .distantPast, $0.id) > (JobFiltering.date($1.scheduledFor) ?? .distantPast, $1.id)
        }
        return open + done
    }
}

/// Made once: the customer's activity list formats a stamp per row on every render.
@MainActor private enum ActivityStamp {
    static let abbreviated: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
