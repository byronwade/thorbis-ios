import SwiftUI
import UIKit

enum CustomerJobHistory {
    static let initialCount = 4
    static func nextCount(total: Int, visible: Int) -> Int {
        min(25, max(0, total - visible))
    }
    static func firstByID<Record, ID: Hashable>(_ records: [Record], id: KeyPath<Record, ID>) -> [ID: Record] {
        records.reduce(into: [:]) { result, record in
            let key = record[keyPath: id]
            if result[key] == nil { result[key] = record }
        }
    }
}

/// Native translation of Paper's Customers and Customer detail artboards.
struct CustomersView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @State private var showNew = false
    @State private var newJobFor: Customer?
    @Environment(\.openURL) private var openURL
    @Environment(\.inboxText) private var inboxText
    @Environment(\.inboxEmail) private var inboxEmail
    @State private var newName = ""
    /// Paper 47 opens on the alphabetical book; Recent and Archived sit behind the filter circle.
    @State private var selectedView = CustomerListScope.all.rawValue
    @State private var stateFilter = "Any state"
    /// Narrows the book by name, street or phone where the shell has no Search to hand over to.
    @State private var query = ""
    @State private var records: [CustomerRecord] = []
    @State private var recordsLoading = true
    @State private var loadGeneration = 0
    @State private var busy = false
    @State private var error: String?
    /// Paper 48H "Archived customers", pushed from the filter circle.
    @State private var showArchived = false
    #if DEBUG
    @State private var previewImport = false
    #endif
    /// Paper 48B "Archive customer" for the row that was swiped or long-pressed.
    @State private var archiveTarget: CustomerRecord?
    /// Paper 47: one row open at a time; scrolling closes it.
    @StateObject private var swipes = RowSwipeState()
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The header's + (set by the phone shell). Without it (iPad) the floating New customer stays.
    @Environment(\.paperCreate) private var headerCreate
    /// The phone shell's Search; the field hands over to it ("Search or ask").
    @Environment(\.paperSearch) private var openSearch

    private var scope: CustomerListScope { CustomerListScope(rawValue: selectedView) ?? .recent }
    private var items: [CustomerRecord] {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Archived customers live on their own page (Paper 48H), not in the book.
        return scope.customers(from: active).filter { customer in
            let matchesState = stateFilter == "Any state"
                || (stateFilter == "Archived") == customer.archived
            let matchesQuery = words.isEmpty
                || [customer.name, customer.address, customer.phone].contains { $0?.localizedCaseInsensitiveContains(words) == true }
            return matchesState && matchesQuery
        }
    }
    /// The book: everyone who is not archived.
    private var active: [CustomerRecord] { records.filter { !$0.archived } }
    private var canArchive: Bool { session.can("customer.archive", feature: "core_crm") }
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
                PaperHeader(title: "Customers", subtitle: recordsLoading && records.isEmpty ? "Loading…" : "\(PaperCount.text(active.count)) \(active.count == 1 ? "customer" : "customers") · \(PaperCount.text(activeJobs)) active \(activeJobs == 1 ? "job" : "jobs")", showsCreate: true)
                // Paper 47: "Search or ask" on the card, the book's filter circle inside it.
                searchBar
                if let error = error ?? store.error {
                    ErrorBanner(message: error) { _ = await store.refresh(api); await loadCustomers() }
                        .padding(.top, 12)
                }
                if recordsLoading && records.isEmpty { ListRoomSkeleton(count: 7, threeLines: false).padding(.top, 12) }
                // Paper 47: a letter label (13 Semibold, count trailing) over one card per letter;
                // Recent keeps its newest-first order in one group.
                ForEach(Array(sections.enumerated()), id: \.element.0) { index, section in
                    // 22 under the search field, then 16 between a card and the next letter.
                    PaperCardLabel(title: section.0, count: section.1.count)
                        .padding(.top, index == 0 ? 22 : 16)
                    // Clipped to the card, so a swiped row's Archive cell keeps the card's corners.
                    // Row by row in the lazy stack: one card of every customer built at once stalls
                    // a large book.
                    ForEach(Array(section.1.enumerated()), id: \.element.id) { rowIndex, customer in
                        VStack(alignment: .leading, spacing: 0) {
                            if rowIndex > 0 { WellDivider(leading: typeSize.isAccessibilitySize ? 16 : 60) }
                            customerRow(customer, jobs: jobGroups.jobs(for: customer.id))
                        }
                        .paperRowsCardSlice(first: rowIndex == 0, last: rowIndex == section.1.count - 1)
                    }
                }
                if items.isEmpty && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !recordsLoading {
                    ListRoomEmpty(symbol: "magnifyingglass", title: "No customers match", message: "Try a name, street or phone number.")
                } else if items.isEmpty && !recordsLoading && error == nil && store.error == nil {
                    if scope == .archived {
                        ListRoomEmpty(glyph: .person, title: "No archived customers", message: "Customers you archive move here.")
                    } else {
                        ListRoomEmpty(glyph: .people, title: "No customers yet",
                                      actionTitle: session.can("customer.create", feature: "core_crm") ? "Add a customer" : nil,
                                      action: { showNew = true })
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { await store.refresh(api); await SavedCopies.$liveOnly.withValue(true) { await loadCustomers() } }
        .onScrollPhaseChange { _, phase in if phase != .idle { swipes.close() } }
        .background(Theme.canvas).toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            // Paper 47 creates from the header's +; where there is none (iPad) the floating one stays.
            if headerCreate == nil && session.can("customer.create", feature: "core_crm") && !items.isEmpty {
                FloatingCreateButton(title: "New customer", disabled: busy) { showNew = true }
            }
        }
        .task(id: store.customers.map(\.id).sorted().joined(separator: "|")) { await loadCustomers() }
        .sheet(isPresented: $showNew) { SheetSurface {
            NewCustomerSheet(onCreated: { _ in Task { await loadCustomers() } }, offersBooking: true)
        } }
        .sheet(item: $newJobFor) { customer in SheetSurface { NewJobSheet(preselected: customer) } }
        #if DEBUG
        // `--paper-preview-sheet customers-archived | customers-import`: opens 48H or 97 for a capture.
        .thorbisDestination(isPresented: $previewImport) { CustomerImportView() }
        .task {
            guard PaperPreview.enabled else { return }
            if PaperPreview.opensSheet("customers-archived") { try? await Task.sleep(for: .milliseconds(1200)); showArchived = true }
            if PaperPreview.opensSheet("customers-import") { previewImport = true }
        }
        #endif
        .thorbisDestination(isPresented: $showArchived) {
            ArchivedCustomersView(customers: records) { _ in
                _ = await store.refresh(api)
                await SavedCopies.$liveOnly.withValue(true) { await loadCustomers() }
            }
        }
        .thorbisDestination(item: $archiveTarget) { target in
            ArchiveCustomerView(customerID: target.id, customerName: target.name) { _ in
                _ = await store.refresh(api)
                await SavedCopies.$liveOnly.withValue(true) { await loadCustomers() }
            }
        }
    }
    private func customerRow(_ customer: CustomerRecord, jobs: [Job]) -> some View {
        let now = Date()
        let summaryJob = JobFiltering.customerJobSummary(jobs, customerID: customer.id, now: now)?.job
        let jobCount = jobs.count
        let listCustomer = Customer(id: customer.id, name: customer.name, archived: customer.archived, createdAt: customer.createdAt)
        let late = summaryJob.map { isLate($0, now: now) } ?? false
        // Paper 47: a trailing swipe offers Archive, which opens Archive customer (48B) for a reason.
        var swipe: [RowSwipeAction] = []
        if canArchive && !customer.archived {
            swipe.append(RowSwipeAction(id: "row-swipe-archive-\(customer.id)", title: "Archive", symbol: "archivebox",
                                        spokenName: "Archive \(customer.name)") {
                swipes.close()
                archiveTarget = customer
            })
        }
        let swipeActions = swipe
        return RowSwipeContainer(id: customer.id, trailing: swipeActions, state: swipes) {
        // iPad selects into the detail column beside the list; iPhone pushes.
        PaperSplitLink(id: customer.id, value: listCustomer) {
            // Paper 47: initials, the name over the street, the open job's status mark trailing.
            // VoiceOver still hears the status, when the visit is, and how many jobs.
            CustomerBookRow(name: customer.name, street: rowStreet(customer),
                            tone: summaryJob.map { job in
                                late ? StatusTone.attention : StatusTone(jobStatus: job.status, hasTime: job.scheduledFor != nil)
                            },
                            spoken: summaryJob.map { job in
                                (late ? "Late, " : "") + job.status.statusLabel + (visitWhen(job, now: now).map { ", \($0)" } ?? "")
                            },
                            jobs: "\(jobCount) \(jobCount == 1 ? "job" : "jobs")",
                            archived: customer.archived)
        }
        .buttonStyle(RowPressStyle())
        .background(ThorbisPanelStyle())
        .accessibilityIdentifier("customer-row-\(customer.id)")
        .rowSwipeAccessibility(swipeActions)
        // MA-12: the common actions on long-press; each also exists on the customer.
        .contextMenu {
            if let phone = customer.phone.map({ $0.filter { $0.isNumber || $0 == "+" } }), phone.count >= 7 {
                if let call = URL(string: "tel:\(phone)") { Button("Call", systemImage: "phone") { openURL(call) } }
                if let text = URL(string: "sms:\(phone)") { Button("Text", systemImage: "message") { inboxText(text, name: customer.name, openURL: openURL) } }
            }
            if let address = customer.address, !address.isEmpty, let maps = Directions.url(address: address, coordinates: nil) {
                Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") { openURL(maps) }
            }
            if !customer.archived && session.can("job.create", feature: "jobs") {
                Button("New job for \(customer.name)", systemImage: "plus") { newJobFor = listCustomer }
            }
            Button("Copy name", systemImage: "doc.on.doc") { UIPasteboard.general.string = customer.name }
            if canArchive && !customer.archived {
                Button("Archive customer", systemImage: "archivebox", role: .destructive) { archiveTarget = customer }
            }
        }
        }
    }

    /// A booked visit whose time has passed: one word ("Late") instead of "Past scheduled time · Scheduled".
    private func isLate(_ job: Job, now: Date) -> Bool {
        guard ["scheduled", "dispatched"].contains(job.status), let date = JobFiltering.date(job.scheduledFor) else { return false }
        return date < now
    }

    /// Paper 47: the street under the name; the phone when there is no street.
    private func rowStreet(_ customer: CustomerRecord) -> String? {
        let street = customer.address.flatMap { NextStopPlace(jobID: "", organizationID: "", customerID: "", address: $0).firstLine }
        return [street, customer.phone].compactMap { $0?.isEmpty == false ? $0 : nil }.first
    }

    /// "Search or ask" on the card (46 tall, radius 14) with the book's filter circle inside it.
    /// On the phone it hands over to Search; elsewhere it narrows this book.
    @ViewBuilder private var searchBar: some View {
        if openSearch != nil {
            PaperSearchBar(placeholder: "Search or ask", chips: scopeChips) { filterMenu }
                .paperCardMargin()
        } else {
            localSearchBar
        }
    }

    /// Recent is the one thing that narrows the book; it shows in the field as a chip.
    private var scopeChips: [PaperFilterChip] {
        scope == .all ? [] : [PaperFilterChip(id: "scope", title: scope.rawValue) { selectedView = CustomerListScope.all.rawValue }]
    }

    private var filterMenu: some View {
        ThorbisMenu(items: filterItems, title: "Show", accessibilityLabel: "Filter customers") {
            PaperFilterCircle(active: scope != .all)
        }
        .accessibilityValue(scope.rawValue)
        .accessibilityIdentifier("header-filter")
    }

    /// Where the shell has no Search (iPad), the field narrows this book itself.
    private var localSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField("Search customers", text: $query, prompt: .placeholder("Search customers"))
                .font(Theme.font(16)).foregroundStyle(Theme.foreground)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .frame(minHeight: 46)
                .accessibilityIdentifier("customers-search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Clear search")
            }
            filterMenu
        }
        .padding(.leading, 12).padding(.trailing, 4)
        .frame(minHeight: 46)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, PaperCardMetrics.margin)
    }

    /// Recent and All customers narrow this book; archived customers have their own page
    /// (Paper 48H), with Restore on each row.
    private var filterItems: [ThorbisMenuItem] {
        var menu: [ThorbisMenuItem] = []
        for option in [CustomerListScope.recent, CustomerListScope.all] {
            menu.append(ThorbisMenuItem(option.rawValue, isSelected: option == scope) { selectedView = option.rawValue })
        }
        menu.append(ThorbisMenuItem("Archived customers", icon: "archivebox") { showArchived = true })
        return menu
    }

    /// When the open visit is, in the same words as Jobs ("Today 4 p.m."), for booked work only.
    private func visitWhen(_ job: Job, now: Date) -> String? {
        guard ["scheduled", "dispatched"].contains(job.status), let date = JobFiltering.date(job.scheduledFor) else { return nil }
        return date.visitLabel(now: now)
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

/// Paper 47's row: 32pt initials in a 44 column, the name (16 Medium) over the street (14 muted),
/// and the open job's status mark (18) trailing; an empty 18pt slot keeps the column when there is none.
private struct CustomerBookRow: View {
    let name: String
    var street: String? = nil
    var tone: StatusTone? = nil
    /// What VoiceOver says for the mark: the status word and when the visit is.
    var spoken: String? = nil
    /// "3 jobs": read by VoiceOver when there is no open job to name.
    var jobs: String? = nil
    var archived = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        HStack(alignment: .center, spacing: 0) {
            // At accessibility sizes the initials give their width back to the name.
            if !stacked {
                CustomerInitials(name: name).frame(width: 44, alignment: .leading)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(Theme.font(16, weight: .medium)).tracking(-0.16)
                        .foregroundStyle(archived ? Theme.muted : Theme.foreground)
                        .lineLimit(stacked ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let street, !street.isEmpty {
                        Text(street).font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .lineLimit(stacked ? nil : 1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .padding(.trailing, 16).padding(.vertical, 11)
        }
        .padding(.leading, 16)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityWords)
    }

    @ViewBuilder private var trailing: some View {
        if archived {
            Text("Archived").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted).fixedSize()
        } else if let tone {
            StatusGlyph(tone: tone, label: spoken ?? "", size: 18)
        } else {
            Color.clear.frame(width: 18, height: 18)
        }
    }

    private var accessibilityWords: String {
        let status = archived ? "Archived" : (tone != nil ? spoken : jobs)
        return [name, street, status].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Initials on a quiet fill (Paper 47): 12 Semibold in the secondary ink, 32pt circle.
private struct CustomerInitials: View {
    let name: String

    var body: some View {
        Text(Self.initials(name))
            .font(Theme.font(11, weight: .semibold)).foregroundStyle(Theme.subtle)
            .frame(width: 32, height: 32)
            .background(Theme.quietFill, in: Circle())
            .dynamicTypeSize(...DynamicTypeSize.large)
            .accessibilityHidden(true)
    }

    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" }).filter { $0.first?.isLetter == true }
        return words.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

/// Paper 48N's hub rows, each a page about the customer.
private enum CustomerHubPart: String, Hashable, Identifiable {
    case jobs, comms, property, equipment, membership, money, notes
    /// Not hub rows: what Customer actions opens (contacts, details and preferences; the timeline),
    /// and the Media segment of the tabbed page.
    case details, activity, media

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jobs: "Jobs"
        case .comms: "Texts and calls"
        case .notes: "Notes"
        case .property: "Property"
        case .equipment: "Equipment"
        case .membership: "Membership"
        case .money: "Money"
        case .details: "Contacts and details"
        case .activity: "Activity"
        case .media: "Media"
        }
    }

    /// Paper 48D–48G: the segment a page opens on. Jobs, Billing, Media and Activity share one
    /// tabbed page; `tab` also drives the loaders. Every other page has no segment.
    var tab: String {
        switch self {
        case .jobs: "Jobs"
        case .money: "Billing"
        case .media: "Media"
        case .activity: "Activity"
        default: "Overview"
        }
    }

    var isTabbed: Bool { tab != "Overview" }
}

private struct CustomerHubRow: Identifiable {
    let part: CustomerHubPart
    let subtitle: String?
    var id: CustomerHubPart { part }
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
struct CustomerRecordsScope: Equatable, Sendable {
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
    @ObservedObject private var favorites = ScopedRecordFavorites.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    let customer: Customer
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: SessionController
    @EnvironmentObject private var customerView: JobEstimateHandoffPresenter
    @EnvironmentObject private var legacyHandoff: LegacyCustomerPresenter
    @StateObject private var customerWindowAnchor = CustomerWindowAnchor()
    @Environment(\.dismiss) private var dismiss
    @State private var record: CustomerRecord?
    @State private var contactState = CustomerContactCollectionState()
    @State private var loadGeneration = 0
    @State private var activity: [CustomerHistoryEntry] = []
    @State private var activityCursor: String?
    @State private var activityLoading = false
    @State private var activityError: String?
    @State private var activityLoadGeneration = 0
    /// Paper 48G's chips over the timeline: All, Visits, Payments.
    @State private var activityFilter = "All"
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
    /// The records the open hub page needs: "Jobs" and "Money" load the compiled records.
    @State private var tab = "Overview"
    /// Paper 48N: the hub row whose page is pushed ("Everything for Danielle").
    @State private var openPart: CustomerHubPart?
    /// A job opened from the Jobs page. That page is pushed by state, where a value link never opens.
    @State private var openedJob: Job?
    /// An invoice or estimate opened from the Billing segment.
    @State private var openedRoute: PaperRoute?
    /// Paper 85: the customer's one active plan (its page pins "Book covered visit"), the plan
    /// being cancelled (85B), and a count that makes the page read the plan again.
    @State private var plan: MembershipRecord?
    @State private var cancellingPlan: MembershipRecord?
    @State private var planReload = 0
    /// Billing lists five invoices until "See all".
    @State private var showsAllInvoices = false
    /// DEBUG previews open a hub page once.
    @State private var previewOpened = false
    @State private var showRecentlyArchived = false
    @State private var records: CustomerJobCompilation?
    @State private var recordsLoading = false
    @State private var recordsError: String?
    @State private var recordsLoadGeneration = 0
    @State private var recordsPublishedScope: CustomerRecordsScope?
    @State private var recordsRequestedScope: CustomerRecordsScope?
    // Money is compiled independently so slow job media never blocks financial records.
    @State private var moneyRecords: CustomerJobCompilation?
    @State private var moneyRecordsLoading = false
    @State private var moneyRecordsError: String?
    @State private var moneyRecordsLoadGeneration = 0
    @State private var moneyRecordsPublishedScope: CustomerRecordsScope?
    @State private var moneyRecordsRequestedScope: CustomerRecordsScope?
    private var recordsScope: CustomerRecordsScope? { CustomerRecordsScope.capture(session: session, customerID: customer.id) }
    @State private var smsConsent: CustomerSmsConsent?
    @State private var smsConsentLoaded = false
    /// Web parity: the customer's "Email job updates" switch. Nil until it loads (or on an older server).
    @State private var jobEmails: Bool?
    @State private var jobEmailsSaving = false
    @State private var jobEmailsError: String?
    @State private var smsConsentKey = UUID().uuidString
    @State private var smsConsentChoice: Bool?
    @State private var smsConsentError: String?
    @State private var showEditCustomer = false
    /// Paper 48B "Archive customer", pushed from Customer actions or from Edit customer.
    @State private var showArchive = false
    @State private var archiveAfterEdit = false
    @State private var restoring = false
    @State private var handoff: DeviceHandoff?
    private var jobs: [Job] { store.jobs.filter { $0.customerId == customer.id } }
    private var canEdit: Bool { session.can("customer.edit", feature: "core_crm") }
    private var canArchive: Bool { session.can("customer.archive", feature: "core_crm") }
    private var isArchived: Bool { record?.archived ?? customer.archived ?? false }
    private var contacts: [CustomerContactRecord] { contactState.contacts }
    private var contactsLoaded: Bool { contactState.isLoaded }
    private var locations: [ServiceLocationRecord] { locationState.locations }

    /// Member pricing for the hub's Membership row ("Comfort Club · 15% off").
    @State private var pricing: MemberPricing?
    /// The customer's equipment for the hub's row ("Equipment · 2", then what it is). Nil until
    /// it loads, or when this person can't read it.
    @State private var equipment: [EquipmentRecord]?
    /// The customer's jobs as GET /v1/jobs?customerId returns them: the notes line for Jobs.
    @State private var jobRecords: [JobRecord] = []
    @State private var visiblePastCount = CustomerJobHistory.initialCount
    /// Paper 48N "Texts and calls": the business's call log and this phone's drafts, for this customer.
    @StateObject private var comms = CustomerCommsModel()
    /// Paper 48N "Notes": what this workspace wrote about the customer on this phone.
    @StateObject private var phoneNotes = CustomerNotesModel()
    @Environment(\.openURL) private var openURL
    @Environment(\.inboxText) private var inboxText
    @Environment(\.inboxEmail) private var inboxEmail

    private var primaryPhone: String? { contacts.first(where: \.primary)?.phone ?? record?.phone }
    private var primaryEmail: String? { contacts.first(where: \.primary)?.email ?? record?.email }
    /// Every number and address on file: the account's own and each contact's.
    private var customerNumbers: [String] { ([record?.phone] + contacts.map(\.phone)).compactMap { $0 }.filter { !$0.isEmpty } }
    private var customerEmails: [String] { ([record?.email] + contacts.map(\.email)).compactMap { $0 }.filter { !$0.isEmpty } }
    private var callsAvailable: Bool { CallLogRules.available(session) }
    /// This customer's calls in the business's call log, newest first.
    private var customerCalls: [BookingCallRecord] {
        callsAvailable ? CustomerComms.calls(comms.calls, customerID: customer.id, numbers: customerNumbers) : []
    }
    private var commsEntries: [CustomerCommsEntry] {
        CustomerComms.entries(calls: customerCalls,
                              threads: CustomerComms.threads(comms.threads, numbers: customerNumbers, emails: customerEmails))
    }
    private var directionsURL: URL? {
        (locations.first?.address ?? record?.address).flatMap { Directions.url(address: $0, coordinates: locations.first?.coordinates) }
    }

    var body: some View {
        ScrollViewReader { reader in
        ScrollView {
            // Paper 48N: the name, one line of facts, New job with Call and Text, then one card that
            // leads to everything about the customer. Cards sit 16 from the edge, titles 20.
            VStack(alignment: .leading, spacing: 0) {
                OfflineBanner().padding(.horizontal, -PaperCardMetrics.margin)
                SavedCopyNote(savedAt: api.savedCopyDate("/v1/customers/\(customer.id)")).padding(.horizontal, -PaperCardMetrics.margin)
                customerIdentity
                actionRow.padding(.top, 16)
                if let error {
                    ErrorBanner(message: error) { await load() }.padding(.top, 16)
                }
                hub.padding(.top, 20)
                Color.clear.frame(height: 1).id("customer-end")
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 24)
        }
        #if DEBUG
        // `--paper-preview-scroll center|bottom`: the lower sections, once they have loaded.
        .task {
            guard let anchor = PaperPreview.scrollAnchor, anchor != .top else { return }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(nil) { reader.scrollTo(anchor == .bottom ? "customer-end" : "customer-contacts", anchor: anchor == .bottom ? .bottom : .top) }
        }
        #endif
        }
        .foregroundStyle(Theme.foreground).background(Theme.canvas)
        .background(CustomerWindowAnchorView(anchor: customerWindowAnchor))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            let items = customerMenuItems
            if !items.isEmpty {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    // Paper 48N: the ⋯ circle on the card, 44.
                    ThorbisMenu(items: items, accessibilityLabel: "Customer actions") { PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card) }
                }
            }
        }
        .thorbisDestination(item: $openPart) { part in
            hubPage(part).thorbisDestination(item: $openedJob) { JobDetailView(jobId: $0.id).tabletReadable() }
                .thorbisDestination(item: $openedRoute) { PaperRouteView(route: $0).tabletReadable() }
        }
        .thorbisDestination(isPresented: $showArchive) {
            ArchiveCustomerView(customerID: customer.id, customerName: record?.name ?? customer.name) { saved in
                record = saved
                _ = await store.refresh(api)
            }
        }
        .onChange(of: openPart) { before, part in
            tab = part?.tab ?? "Overview"
            // Back from Equipment: the row's count and names follow what was added or removed.
            if before == .equipment && part == nil {
                Task { equipment = try? await api.customerEquipment(customer.id) }
            }
        }
        .deviceHandoffs($handoff)
        .task { await load() }
        .task { await loadSmsConsent() }
        .task { await loadJobEmails() }
        .task(id: customer.id) { pricing = try? await api.memberPricing(customer.id) }
        .task(id: customer.id) { equipment = try? await api.customerEquipment(customer.id) }
        // The hub's Texts and calls and Notes rows: this sign-in's call log and on-phone books.
        .task(id: session.generation) {
            comms.messagingOn = InboxMessaging.on(session)
            comms.bind(actorID: session.user?.id, organizationID: session.activeOrganization?.id)
            phoneNotes.bind(organizationID: session.activeOrganization?.id)
            if callsAvailable { await comms.refresh(api: api) }
        }
        .task { await loadActivity(reset: true) }
        .task(id: recordsScope) {
            if recordsPublishedScope != recordsScope {
                records = nil
                recordsPublishedScope = nil
                recordsError = nil
            }
            if moneyRecordsPublishedScope != recordsScope {
                moneyRecords = nil
                moneyRecordsPublishedScope = nil
                moneyRecordsError = nil
            }
            await loadSelectedRecords()
        }
        .onAppear {
            customerWindowAnchor.visible = true
            RecentItems.shared.record(.customer, id: customer.id, title: customer.name, subtitle: "Customer")
            #if DEBUG
            // Once: coming back from the pushed page must not push it again.
            if PaperPreview.enabled && !previewOpened {
                previewOpened = true
                if PaperPreview.screen == "customer-jobs" { openPart = .jobs }
                // The compiled photos and files live on the Media segment.
                if PaperPreview.screen == "customer-records" { openPart = .media }
                if PaperPreview.screen == "customer-money" { openPart = .money }
                if PaperPreview.screen == "customer-media" { openPart = .media }
                if PaperPreview.screen == "customer-membership" { openPart = .membership }
                if PaperPreview.screen == "customer-activity" { openPart = .activity }
                if PaperPreview.screen == "customer-details" { openPart = .details }
                if PaperPreview.opensSheet("customer-archive") { showArchive = true }
                if PaperPreview.opensSheet("customer-edit") { showEditCustomer = true }
            }
            #endif
        }
        .onDisappear { customerWindowAnchor.visible = false }
        .onChange(of: tab, initial: true) { _, selectedTab in
            if selectedTab != "Overview" { Task { await loadSelectedRecords() } }
            if selectedTab == "Jobs" { Task { await loadJobRecords() } }
        }
        .refreshable {
            await SavedCopies.$liveOnly.withValue(true) {
                await load()
                await loadActivity(reset: true)
                await loadSelectedRecords()
                if tab == "Jobs" { await loadJobRecords() }
            }
        }
        // New job and the location sheets present from whichever screen is showing: here, or the
        // pushed hub page (`hubPresentations`), never both.
        .sheet(isPresented: openPart == nil ? $showNewJob : Binding<Bool>.constant(false)) { SheetSurface { NewJobSheet(preselected: customer) } }
        .sheet(isPresented: $showEditCustomer, onDismiss: {
            // Paper 48C's "Archive customer" closes the sheet first, then 48B is pushed.
            if archiveAfterEdit {
                archiveAfterEdit = false
                showArchive = true
            }
        }) {
            EditCustomerSheet(customerID: customer.id, onSaved: { _ in Task { await load() } },
                              onArchive: { archiveAfterEdit = true })
        }
        .sheet(item: $contactSheet, onDismiss: { Task { await load() } }) { item in SheetSurface {
            CustomerContactSheet(customerID: customer.id, contact: item.contact) { contact in
                contactState.save(contact)
                contactMutationError = nil
                error = nil
            }
        } }
        .sheet(item: openPart == nil ? $locationSheet : Binding<CustomerLocationSheet?>.constant(nil)) { item in SheetSurface {
            ServiceLocationSheet(customerID: customer.id, location: item.location) { saved in
                locationState.save(saved)
                locationError = nil
            }
        } }
        .thorbisConfirm(item: openPart == nil ? $locationToRemove : Binding<ServiceLocationRecord?>.constant(nil),
                        title: { _ in "Remove service location?" },
                        message: { _ in "This removes the location from \(record?.name ?? customer.name)." },
                        actions: { location in
            [ThorbisConfirmAction("Remove", role: .destructive) {
                Task { await removeLocation(location) }
            }]
        })
        .thorbisConfirm(item: $contactToRemove,
                        title: { _ in "Remove customer contact?" },
                        message: { contact in "This removes \(contact.name) from \(record?.name ?? customer.name)." },
                        actions: { contact in
            [ThorbisConfirmAction("Remove", role: .destructive) {
                Task { await removeContact(contact) }
            }]
        })
    }

    /// Paper 48A "Contact preferences": how this customer may be reached about their jobs, each
    /// on its own 56pt row. Phone calls have no preference on the server, so that row is not drawn.
    @ViewBuilder private var contactPreferences: some View {
        if record != nil, smsConsentLoaded || jobEmails != nil {
            PaperSection("Contact preferences") {
                VStack(alignment: .leading, spacing: 0) {
                    if smsConsentLoaded {
                        smsConsentRow.frame(minHeight: 56).padding(.horizontal, PaperCardMetrics.inset)
                    }
                    if smsConsentLoaded && jobEmails != nil { WellDivider() }
                    if jobEmails != nil {
                        jobEmailsRow.frame(minHeight: 56).padding(.horizontal, PaperCardMetrics.inset)
                    }
                }
            }
        }
    }

    /// Paper 48A "Record": Archive customer as a row at the foot of the page. It opens Archive
    /// customer (48B), the same page Customer actions opens.
    @ViewBuilder private var recordSection: some View {
        if canArchive, record != nil, !isArchived {
            PaperSection("Record") {
                Button { showArchive = true } label: {
                    HStack(spacing: 12) {
                        Text("Archive customer").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PaperChevron()
                    }
                    .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 9)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier("customer-record-archive")
                // Paper 48A: the archived list, one row down.
                WellDivider(leading: 16)
                Button { showRecentlyArchived = true } label: {
                    HStack(spacing: 12) {
                        Text("Recently archived customers").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PaperChevron()
                    }
                    .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 9)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier("customer-record-archived-list")
            }
        }
    }

    /// Paper 48N "Everything for Danielle": one card of rows, each opening its own page.
    private var hub: some View {
        let rows = hubRows
        return PaperSection("Everything for \(hubName)") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { WellDivider(leading: 16) }
                    hubRow(row.part, subtitle: row.subtitle)
                }
            }
        }
    }

    /// The hub's rows, each with what the app already knows about it; a row with nothing to say
    /// yet shows its title alone.
    private var hubRows: [CustomerHubRow] {
        // Paper 48N's order: Jobs, Texts and calls, Property, Equipment, Membership, Money, Notes.
        var rows = [CustomerHubRow(part: .jobs, subtitle: jobsSummary)]
        if session.user?.id != nil && session.activeOrganization?.id != nil {
            rows.append(CustomerHubRow(part: .comms, subtitle: commsSummary))
        }
        rows += [CustomerHubRow(part: .property, subtitle: propertySummary),
                 CustomerHubRow(part: .equipment, subtitle: equipmentSummary),
                 CustomerHubRow(part: .membership, subtitle: membershipSummary),
                 CustomerHubRow(part: .money, subtitle: "Estimates and invoices")]
        if phoneNotes.isOpen { rows.append(CustomerHubRow(part: .notes, subtitle: notesSummary)) }
        return rows
    }

    /// "Missed call · 9:39 AM" or the newest draft's words: the latest thing between this phone and
    /// the customer. Nothing to say until the call log has answered.
    private var commsSummary: String? {
        let entries = commsEntries
        if let line = CustomerComms.summary(entries) { return line }
        if callsAvailable && !comms.loaded && !comms.denied { return nil }
        return "No texts or calls yet"
    }

    /// "Prefers texts · dog in back yard": the newest notes kept on this phone, else a place's note
    /// from the server.
    private var notesSummary: String? {
        _ = phoneNotes.revision
        if let line = CustomerNoteRules.summary(phoneNotes.notes(for: customer.id)) { return line }
        let place = locations.compactMap { $0.notes?.split(whereSeparator: \.isNewline).first.map { String($0) } }
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return place ?? "No notes yet"
    }

    /// The first name for a person ("Everything for Danielle"); a business keeps its whole name.
    private var hubName: String {
        let name = record?.name ?? customer.name
        guard record?.accountType != "commercial", let first = name.split(separator: " ").first else { return name }
        return String(first)
    }

    private func hubTitle(_ part: CustomerHubPart) -> String {
        if part == .property && locations.count > 1 { return "Properties · \(locations.count)" }
        if part == .equipment, let count = equipment?.count, count > 0 { return "Equipment · \(count)" }
        return part.title
    }

    /// "Trane XR14 condenser · Rheem water heater": the first two things on file.
    private var equipmentSummary: String? {
        guard let equipment else { return nil }
        guard !equipment.isEmpty else { return "No equipment yet" }
        return equipment.prefix(2).map(\.name).joined(separator: " · ")
    }

    /// "AC not cooling · Today 4:00 p.m. · 6 past".
    private var jobsSummary: String? {
        guard session.can("job.view", feature: "jobs") else { return nil }
        guard !jobs.isEmpty else { return "No jobs yet" }
        var parts: [String] = []
        if let open = JobFiltering.customerJobSummary(jobs, customerID: customer.id)?.job {
            parts.append(open.title)
            if let date = JobFiltering.date(open.scheduledFor) { parts.append(date.visitLabel()) }
        }
        let past = jobs.filter { ["completed", "canceled"].contains($0.status) }.count
        if past > 0 { parts.append("\(past) past") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "412 Birchwood Ln · gate 4482#": the first service place's street and its gate.
    private var propertySummary: String? {
        guard let place = locations.first(where: { $0.kind == "service" }) ?? locations.first else { return nil }
        let street = NextStopPlace(jobID: "", organizationID: "", customerID: "", address: place.address).firstLine ?? place.address
        let gate = place.gateCode.flatMap { $0.isEmpty ? nil : "gate \($0)" }
        return [street, gate].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Comfort Club · 15% off", "Member", or "Not a member", once the server has said.
    private var membershipSummary: String? {
        guard let pricing else { return nil }
        guard pricing.isMember else { return "Not a member" }
        let discount = pricing.discountPercent > 0 ? "\(pricing.discountPercent)% off" : nil
        return [pricing.membership?.name ?? "Member", discount].compactMap { $0 }.joined(separator: " · ")
    }

    /// A hub row: 16 Medium title over a 14 muted line, a quiet chevron trailing, 60 tall.
    private func hubRow(_ part: CustomerHubPart, subtitle: String?) -> some View {
        let title = hubTitle(part)
        return Button { openPart = part } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PaperRowChevron()
            }
            .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(title)
        .accessibilityValue(subtitle ?? "")
        .accessibilityIdentifier("customer-hub-\(part.rawValue)")
    }

    /// A hub row's page, pushed. Jobs, Billing, Media and Activity are Paper 48D–48G's tabbed page:
    /// the number and since line, the name, the five segments ("Overview" goes back to the hub),
    /// then the segment's body. Every other page keeps its title over its sections.
    @ViewBuilder private func hubPage(_ part: CustomerHubPart) -> some View {
        ScrollView {
            if part.isTabbed {
                VStack(alignment: .leading, spacing: 0) {
                    OfflineBanner().padding(.horizontal, -PaperCardMetrics.margin)
                    CustomerTabsHeader(eyebrow: tabEyebrow, name: record?.name ?? customer.name,
                                       tabs: ["Overview", "Jobs", "Billing", "Media", "Activity"],
                                       selection: tab == "Overview" ? part.tab : tab) { chosen in
                        if chosen == "Overview" { openPart = nil } else { tab = chosen }
                    }
                    switch tab == "Overview" ? part.tab : tab {
                    case "Billing": billingTab
                    case "Media": recordsParts([.photos, .documents], media: true).padding(.top, 14)
                    case "Activity": activitySection.padding(.top, 14)
                    default:
                        if session.can("job.view", feature: "jobs") { jobsSection }
                        else { unavailable("Jobs", "You don’t have access to jobs in this workspace.").padding(.top, 22) }
                    }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 34)
            } else if part == .membership {
                VStack(alignment: .leading, spacing: 0) {
                    OfflineBanner().padding(.horizontal, -PaperCardMetrics.margin)
                    MembershipPlanBody(customerID: customer.id, customerName: record?.name ?? customer.name,
                                       plan: $plan, reload: planReload)
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 24)
            } else {
            VStack(alignment: .leading, spacing: 20) {
                OfflineBanner().padding(.horizontal, -PaperCardMetrics.margin)
                PaperPageTitle(title: hubTitle(part), subtitle: record?.name ?? customer.name, columnInset: PaperCardMetrics.margin)
                switch part {
                case .jobs, .money, .activity, .media:
                    EmptyView()
                case .property:
                    locationsSection
                case .equipment:
                    CustomerEquipmentSection(customerID: customer.id, locations: locations.filter { $0.kind == "service" })
                case .membership:
                    EmptyView()
                case .comms:
                    CustomerCommsSection(customerID: customer.id, customerName: record?.name ?? customer.name,
                                         numbers: customerNumbers, emails: customerEmails,
                                         dialable: primaryPhone.map { $0.filter { $0.isNumber || $0 == "+" } }.flatMap { $0.count >= 7 ? $0 : nil },
                                         callsAvailable: callsAvailable, model: comms)
                case .details:
                    if record == nil && error == nil {
                        PaperSection("Details") { SkeletonRows(count: 3, leading: false, inset: PaperCardMetrics.inset) }
                    } else {
                        details
                        contactPreferences
                    }
                    contactsSection.id("customer-contacts")
                    recordSection
                case .notes:
                    CustomerNotesSection(customerID: customer.id, customerName: record?.name ?? customer.name,
                                         locations: locations, model: phoneNotes)
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 24)
            }
        }
        .foregroundStyle(Theme.foreground).background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            // Paper 48D: the ⋯ circle stays on the tabbed page; New job moved into it from the
            // bar the Jobs page used to pin.
            if part == .membership, let plan, canEdit {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    ThorbisMenu(items: planMenuItems(plan), accessibilityLabel: "Plan actions") { PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card) }
                }
            }
            if part.isTabbed {
                let items = customerMenuItems(onPage: true)
                if !items.isEmpty {
                    ThorbisToolbarItem(placement: .topBarTrailing) {
                        ThorbisMenu(items: items, accessibilityLabel: "Customer actions") { PaperCircleLabel(symbol: "ellipsis", size: 44, fill: Theme.card) }
                    }
                }
            }
        }
        // Paper 85: "Book covered visit" is the plan page's commit, with the plan's menu beside it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if part == .membership, let plan, session.can("job.create", feature: "jobs"), !typeSize.isAccessibilitySize {
                PaperActionBar(title: "Book covered visit", symbol: "calendar", identifier: "membership-book-visit") { showNewJob = true } secondary: {
                    if canEdit {
                        ThorbisMenu(items: planMenuItems(plan), accessibilityLabel: "More plan actions", arrowEdge: .bottom) {
                            PaperCircleLabel(symbol: "ellipsis", size: 50, fill: Theme.card)
                        }
                    }
                }
            }
        }
        .thorbisDestination(isPresented: $showRecentlyArchived) { RecentlyArchivedCustomersPage() }
        #if DEBUG
        // `--paper-preview-sheet membership-cancel`: opens Cancel membership (85B) for a capture.
        .onChange(of: plan?.id) { _, _ in
            if PaperPreview.enabled, PaperPreview.opensSheet("membership-cancel"), cancellingPlan == nil, let plan { cancellingPlan = plan }
        }
        #endif
        .thorbisDestination(item: $cancellingPlan) { membership in
            CancelMembershipView(customerID: customer.id, membership: membership,
                                 customerName: record?.name ?? customer.name,
                                 onCancelled: { planReload += 1 })
        }
        .refreshable {
            await SavedCopies.$liveOnly.withValue(true) {
                await load()
                if part == .membership { planReload += 1 }
                if part.isTabbed {
                    await loadSelectedRecords()
                    if tab == "Activity" { await loadActivity(reset: true) }
                }
                if part.isTabbed && tab == "Jobs" { await loadJobRecords() }
                if part == .comms && callsAvailable { await comms.refresh(api: api) }
            }
        }
        // The pushed page presents its own New job and location sheets; the covered customer
        // screen stands down while a page is open.
        .sheet(isPresented: $showNewJob) { SheetSurface { NewJobSheet(preselected: customer) } }
        .sheet(item: $locationSheet) { item in SheetSurface {
            ServiceLocationSheet(customerID: customer.id, location: item.location) { saved in
                locationState.save(saved)
                locationError = nil
            }
        } }
        .thorbisConfirm(item: $locationToRemove,
                        title: { _ in "Remove service location?" },
                        message: { _ in "This removes the location from \(record?.name ?? customer.name)." },
                        actions: { location in
            [ThorbisConfirmAction("Remove", role: .destructive) {
                Task { await removeLocation(location) }
            }]
        })
    }

    /// Paper 48N: New job (the page's one brand commit) beside 50pt Call and Text circles. Email and
    /// Directions live in Customer actions. At accessibility sizes the circles drop under New job.
    @ViewBuilder private var actionRow: some View {
        let dialable = primaryPhone.map { $0.filter { $0.isNumber || $0 == "+" } }.flatMap { $0.count >= 7 ? $0 : nil }
        let canCreate = session.can("job.create", feature: "jobs")
        if canCreate || dialable != nil {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            layout {
                if canCreate {
                    Button { showNewJob = true } label: { Text("New job").inkCommit() }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("customer-new-job-action")
                }
                if let dialable, let call = URL(string: "tel:\(dialable)"), let text = URL(string: "sms:\(dialable)") {
                    HStack(spacing: 8) {
                        reachCircle("phone", label: "Call") { openURL(call) }
                        reachCircle("message", label: "Text") { inboxText(text, name: customer.name, openURL: openURL) }
                    }
                }
            }
        }
    }

    /// A 50pt card circle beside New job.
    private func reachCircle(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PaperIcon(symbol == "phone" ? .handset : .bubble, size: 18)
                .frame(width: 50, height: 50)
                .background(Theme.card, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }

    /// Paper 48N: the name at 34 Bold, then one muted line: phone · customer since 2022
    /// ("Archived" leads when it is).
    private var customerIdentity: some View {
        let name = record?.name ?? customer.name
        return PaperPageTitle(title: name, subtitle: identityLine, columnInset: PaperCardMetrics.margin)
    }

    /// Paper 48D: "CUS-0412 · Customer since Mar 2022" over the name on the tabbed page.
    private var tabEyebrow: String? {
        var parts = ["CUS-\(customer.id.suffix(4).uppercased())"]
        if isArchived { parts.append("Archived") }
        if let date = JobFiltering.date(record?.createdAt ?? customer.createdAt) {
            parts.append("Customer since \(date.formatted(.dateTime.month(.abbreviated).year()))")
        }
        return parts.joined(separator: " · ")
    }

    private var identityLine: String? {
        var parts: [String] = []
        if isArchived { parts.append("Archived") }
        if let phone = primaryPhone, !phone.isEmpty { parts.append(phone) }
        if let date = JobFiltering.date(record?.createdAt ?? customer.createdAt) {
            parts.append("customer since \(date.formatted(.dateTime.year()))")
        }
        guard let first = parts.first else { return nil }
        parts[0] = first.prefix(1).uppercased() + first.dropFirst()
        return parts.joined(separator: " · ")
    }

    /// Always open, on one panel: address first, then phone and email, then the rest (F18).
    /// Whether Details has a line to show, now that the text and email choices sit under
    /// Contact preferences: an empty card is never drawn.
    private func hasDetailLines(_ record: CustomerRecord) -> Bool {
        if record.accountType != nil || record.industry != nil || record.preferredContact != nil || record.billingTerms != nil { return true }
        if let address = record.address, !address.isEmpty, !CustomerFacts.address(address, isIn: locations.map(\.address)) { return true }
        if let phone = record.phone, !phone.isEmpty, !CustomerFacts.phone(phone, isIn: contacts.compactMap(\.phone)) { return true }
        if let email = record.email, !email.isEmpty, !CustomerFacts.email(email, isIn: contacts.compactMap(\.email)) { return true }
        return false
    }

    @ViewBuilder private var details: some View {
        if let record, hasDetailLines(record) {
            PaperSection("Details") {
                VStack(alignment: .leading, spacing: 0) {
                    // Every fact once: the address shows here only when no location carries it,
                    // the phone and email only when no contact does.
                    if let type = record.accountType { detailLine("Type") { Text(type.statusLabel) } }
                    if let address = record.address, !address.isEmpty, !CustomerFacts.address(address, isIn: locations.map(\.address)) {
                        detailLine("Address") { AddressLink(address: address) }
                    }
                    if let phone = record.phone, !phone.isEmpty, !CustomerFacts.phone(phone, isIn: contacts.compactMap(\.phone)) {
                        detailLine("Phone") { ContactActions(phone: phone, email: nil) }
                    }
                    if let email = record.email, !email.isEmpty, !CustomerFacts.email(email, isIn: contacts.compactMap(\.email)) {
                        detailLine("Email") { ContactActions(phone: nil, email: email, emailContext: "customer:\(customer.id)") }
                    }
                    if let industry = record.industry { detailLine("Industry") { Text(industry) } }
                    if let preferred = record.preferredContact { detailLine("Contact preference") { Text(preferred.statusLabel) } }
                    if let terms = record.billingTerms { detailLine("Billing terms") { Text(terms) } }
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
            VStack(alignment: .leading, spacing: 0) {
                PaperSection(title: summary.openCount > 1 ? "Open jobs" : "Open job", count: summary.openCount > 1 ? summary.openCount : nil) {
                    NavigationLink(value: job) {
                        // The jobs row grammar: the street, the problem, when and who; the status word trails.
                        JobRoomRow(job: job, street: street(for: job.locationId),
                                   when: JobFiltering.date(job.scheduledFor).map { $0.visitLabel() } ?? "No time yet",
                                   who: tech(job.assignedToUserId), late: late, titleLines: 2, inset: PaperCardMetrics.inset)
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityIdentifier("customer-next-visit")
                } accessory: {
                    if summary.openCount > 1 && !typeSize.isAccessibilitySize { seeAllJobs.padding(.vertical, -9) }
                }
                if summary.openCount > 1 && typeSize.isAccessibilitySize { seeAllJobs }
            }
        }
    }

    private var seeAllJobs: some View {
        // The section label's own ink and size; 44 to tap.
        Button { openPart = .jobs } label: {
            Text("See all jobs").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("customer-see-all-jobs")
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

    /// Email and Directions (Paper 48N keeps only Call and Text on the page), Save to Contacts,
    /// Customer view and the record changes.
    private var customerMenuItems: [ThorbisMenuItem] { customerMenuItems(onPage: false) }

    /// Paper 85 / 85B: the plan's menu. Cancel membership opens its own page.
    private func planMenuItems(_ plan: MembershipRecord) -> [ThorbisMenuItem] {
        var items: [ThorbisMenuItem] = []
        if typeSize.isAccessibilitySize, session.can("job.create", feature: "jobs") {
            items.append(ThorbisMenuItem("Book covered visit", icon: "calendar") { showNewJob = true })
        }
        items.append(ThorbisMenuItem("Cancel membership", icon: "xmark.circle", role: .destructive) { cancellingPlan = plan })
        return items
    }

    /// `onPage`: the tabbed page's menu. New job leads it; the timeline is a segment there, and the
    /// rows that open another page or a sheet of the hub's stay on the hub.
    private func customerMenuItems(onPage: Bool) -> [ThorbisMenuItem] {
        var items: [ThorbisMenuItem] = []
        if onPage, session.can("job.create", feature: "jobs") {
            items.append(ThorbisMenuItem("New job", icon: "plus") { showNewJob = true })
        }
        if let mail = MailDraft(recipient: primaryEmail) {
            items.append(ThorbisMenuItem("Email", icon: "envelope") { inboxEmail(mail, context: "customer:\(customer.id)") })
        }
        if let directionsURL {
            items.append(ThorbisMenuItem("Directions", icon: "arrow.triangle.turn.up.right.diamond") { openURL(directionsURL) })
        }
        if let record {
            items.append(ThorbisMenuItem("Save to Contacts", icon: "person.crop.circle.badge.plus") {
                handoff = .contact(ContactCardDraft.make(customer: record))
            })
        }
        // What Paper 48N's page no longer carries under the hub: the people and details, the timeline.
        items.append(ThorbisMenuItem("Contacts and details", icon: "person.2") { openPart = .details })
        if !onPage { items.append(ThorbisMenuItem("Activity", icon: "clock") { openPart = .activity }) }
        if let record, record.id == customer.id, let scope = ScopedRecordFavorites.currentScope(session: session, api: api),
           scope.organizationID.caseInsensitiveCompare(record.organizationId) == .orderedSame {
            let starred = favorites.isBound(to: scope) && favorites.entries.contains { $0.kind == .customer && $0.id == record.id.lowercased() }
            items.append(ThorbisMenuItem(starred ? "Remove from favorites" : "Add to favorites", icon: starred ? "star.slash" : "star") {
                favorites.bind(scope)
                favorites.toggle(.customer, id: record.id)
            })
        }
        if canEdit && !onPage {
            // Paper 48C: edit the customer's details in one sheet.
            items.append(ThorbisMenuItem("Edit customer", icon: "pencil") { showEditCustomer = true })
            // Customer view: hands the phone to the customer to check and fix their details.
            items.append(ThorbisMenuItem("Customer view", icon: "person.crop.rectangle",
                                         subtitle: "Hand the phone over to check their details") { presentCustomerDetails() })
            items.append(ThorbisMenuItem("Add contact", icon: "person.badge.plus", isDisabled: !contactsLoaded) { contactSheet = .add })
            items.append(ThorbisMenuItem("Add location", icon: "mappin.and.ellipse") { locationSheet = .add })
        }
        // Paper 48B / 48H: archive the customer, or bring an archived one back.
        if canArchive, record != nil, !onPage {
            if isArchived {
                items.append(ThorbisMenuItem("Restore customer", icon: "arrow.uturn.backward", isDisabled: restoring) {
                    Task { await restoreCustomer() }
                })
            } else {
                items.append(ThorbisMenuItem("Archive customer", icon: "archivebox", role: .destructive) { showArchive = true })
            }
        }
        return items
    }

    private func restoreCustomer() async {
        guard !restoring else { return }
        restoring = true
        defer { restoring = false }
        do {
            record = try await api.restoreCustomer(customer.id)
            error = nil
            _ = await store.refresh(api)
        } catch is CancellationError {
        } catch {
            self.error = error.isConnectivityFailure ? "Restoring needs a connection. Try again when you have signal."
                                                     : error.plainMessage(subject: "this customer")
        }
    }

    private func presentCustomerDetails() {
        guard canEdit, let record, record.id == customer.id,
              record.organizationId == session.activeOrganization?.id,
              let authority = CustomerHandoffExitAuthority.capture(api: api, session: session),
              let source = customerWindowAnchor.window, customerWindowAnchor.isAttached(to: source),
              let lease = customerView.claimLegacy() else {
            error = "Customer details aren't ready. Refresh and try again."
            return
        }
        let content = AnyView(CustomerSelfEditView(customerID: customer.id, currentAuthority: {
            legacyHandoff.active?.lease === lease && legacyHandoff.active?.isCurrent(api: api, session: session) == true &&
            session.can("customer.edit", feature: "core_crm")
        }, onFinished: { legacyHandoff.authenticatedExit(for: lease) })
            .environmentObject(api).environmentObject(session))
        guard let handoff = LegacyCustomerHandoff(lease: lease, content: content, api: api, session: session,
            capability: "customer.edit", feature: "core_crm", sourceAttached: { customerWindowAnchor.isAttached(to: source) },
            onDismiss: { _ in
                guard let exitRevision = customerView.idleRevision else { return }
                Task {
                    let current: @MainActor () -> Bool = { customerView.isIdleRevision(exitRevision) && customerWindowAnchor.isAttached(to: source) && authority.isCurrent(api: api, session: session) }
                    guard current() else { return }
                    await load(currentAuthority: current)
                    guard current() else { return }
                    await loadSmsConsent(currentAuthority: current)
                }
            }), legacyHandoff.present(handoff, sourceWindow: source, api: api, session: session) else {
            lease.release(); error = "Customer view is unavailable. Please try again."; return
        }
    }

    private func contactMenuItems(_ contact: CustomerContactRecord) -> [ThorbisMenuItem] {
        var items: [ThorbisMenuItem] = []
        if let phone = contactDialable(contact) {
            if let call = URL(string: "tel:\(phone)") { items.append(ThorbisMenuItem("Call", icon: "phone") { openURL(call) }) }
            if let text = URL(string: "sms:\(phone)") { items.append(ThorbisMenuItem("Text", icon: "message") { inboxText(text, name: contact.name, openURL: openURL) }) }
        }
        if let mail = MailDraft(recipient: contact.email) {
            items.append(ThorbisMenuItem("Email", icon: "envelope") { inboxEmail(mail, context: "customer:\(customer.id):contact:\(contact.id)") })
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

    private func contactDialable(_ contact: CustomerContactRecord) -> String? {
        guard let phone = contact.phone.map({ $0.filter { $0.isNumber || $0 == "+" } }), phone.count >= 7 else { return nil }
        return phone
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
        // Paper 48A: a switch like Emails. Flipping it asks first (the confirm below), because it
        // records what the customer said; the day it was recorded is read out with the switch.
        return Toggle(isOn: Binding(get: { smsConsent?.decision == "grant" }, set: { next in smsConsentChoice = next })) {
            // The recorded answer and its day stay visible: an off switch alone cannot tell
            // "asked to stop" from "never asked".
            VStack(alignment: .leading, spacing: 2) {
                Text("Texts").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                Text(smsConsentLabel).font(Theme.font(13)).foregroundStyle(Theme.subtleForeground)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Job texts")
        }
        .tint(Theme.brand)
        .disabled(!canEdit || session.isOffline)
        .accessibilityValue(smsConsentLabel)
        .accessibilityHint("Record what the customer said about job texts")
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

    /// Job emails: booking, schedule and cancel emails to this customer. Texts and calls are separate.
    private var jobEmailsRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(get: { jobEmails ?? true }, set: { next in Task { await saveJobEmails(next) } })) {
                Text("Emails").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .accessibilityLabel("Job emails")
            }
            .tint(Theme.brand)
            .disabled(!canEdit || jobEmailsSaving || session.isOffline)
            .accessibilityHint("Booking, schedule and cancel emails to this customer")
            if let jobEmailsError {
                Text(jobEmailsError).font(Theme.font(12)).foregroundStyle(Theme.destructive)
            }
        }
        .font(Theme.font(15))
        .frame(minHeight: 44)
    }

    private func loadJobEmails() async {
        guard session.can("customer.view", feature: "core_crm") else { return }
        // An older server or no access: leave the row out rather than show a guess.
        jobEmails = try? await api.customerJobEmailsEnabled(customer.id)
    }

    private func saveJobEmails(_ enabled: Bool) async {
        let previous = jobEmails
        jobEmails = enabled
        jobEmailsSaving = true
        defer { jobEmailsSaving = false }
        do {
            _ = try await api.setNoticePreference(NoticePreference(subjectKind: "customer", subjectKey: customer.id,
                                                                   channel: "email", enabled: enabled))
            jobEmailsError = nil
        } catch is CancellationError {
            jobEmails = previous
        } catch {
            jobEmails = previous
            jobEmailsError = error.isConnectivityFailure ? "Needs a connection" : "Couldn\u{2019}t save. Pull to refresh and try again."
        }
    }

    private var smsConsentLabel: String {
        guard let smsConsent else { return "Not asked" }
        let date = JobFiltering.date(smsConsent.recordedAt).map { " · " + $0.formatted(.dateTime.month(.abbreviated).day()) } ?? ""
        return (smsConsent.decision == "grant" ? "Allowed" : "Stopped") + date
    }

    private func loadSmsConsent(currentAuthority: @escaping @MainActor () -> Bool = { true }) async {
        guard currentAuthority(), session.can("customer.view", feature: "core_crm") else { return }
        do {
            let loaded = try await api.customerSmsConsent(customer.id)
            guard currentAuthority() else { return }
            smsConsent = loaded
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

    /// Contacts show the person first, with direct phone actions and the complete actions menu.
    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaperSection(title: "Contacts", count: contacts.isEmpty ? nil : contacts.count) {
                if contacts.isEmpty {
                    emptyText("No contacts").padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(contacts.enumerated()), id: \.element.id) { index, contact in
                            if index > 0 { WellDivider(leading: typeSize.isAccessibilitySize ? PaperCardMetrics.inset : PaperCardMetrics.inset + 28 + 12) }
                            contactRow(contact)
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

    private func contactRow(_ contact: CustomerContactRecord) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 4))
        return layout {
            HStack(alignment: .top, spacing: 10) {
                InitialsAvatar(name: contact.name, size: 32).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(contact.name).font(Theme.font(16, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    let subtitle = [contact.role, contact.primary ? "Primary" : nil, contact.phone ?? contact.email]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                    if !subtitle.isEmpty {
                        Text(subtitle).font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                if let phone = contactDialable(contact), let call = URL(string: "tel:\(phone)"), let text = URL(string: "sms:\(phone)") {
                    PaperCircleButton(symbol: "phone", label: "Call \(contact.name)", size: 32) { openURL(call) }
                    PaperCircleButton(symbol: "message", label: "Text \(contact.name)", size: 32) { inboxText(text, name: contact.name, openURL: openURL) }
                }
                ThorbisMenu(items: contactMenuItems(contact), accessibilityLabel: "Contact actions for \(contact.name)") {
                    Image(systemName: "ellipsis").foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
            }
            .disabled(isMutatingContact)
        }
        .padding(.leading, PaperCardMetrics.inset).padding(.trailing, 4)
        .padding(.vertical, 8)
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
                            if index > 0 { WellDivider(leading: typeSize.isAccessibilitySize ? PaperCardMetrics.inset : PaperCardMetrics.inset + 26 + 12) }
                            HStack(alignment: .top, spacing: 12) {
                                // At accessibility sizes the mark gives its width back to the words.
                                if !typeSize.isAccessibilitySize {
                                    PlaceMark(symbol: location.kind == "billing" ? "building.2" : "house",
                                              tint: location.kind == "billing" ? Theme.markTeal : Theme.markAccent)
                                        .padding(.top, 2)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    let headingLayout = typeSize.isAccessibilitySize
                                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
                                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                                    headingLayout {
                                        Text(location.label).font(Theme.font(16, weight: .medium))
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        StatusWord(text: location.kind.statusLabel).fixedSize()
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
    /// Paper 48D's Jobs segment: each open job on its own card under the day it is booked for, then
    /// "Past jobs · 6" with the lifetime figure over one card of rows (the job, its number and day,
    /// what it was invoiced).
    private var jobsSection: some View {
        let ordered = CustomerJobOrder.sorted(jobs)
        let open = ordered.filter { !["completed", "canceled"].contains($0.status) }
        let past = ordered.filter { ["completed", "canceled"].contains($0.status) }
        // Keep history approachable and avoid constructing every old row at once.
        let shownPast = Array(past.prefix(visiblePastCount))
        let recordsByID = CustomerJobHistory.firstByID(jobRecords, id: \.id)
        // A job can be listed twice (paged reads overlap); uniqueKeysWithValues would crash on that.
        let figures = Dictionary(past.compactMap { job in jobInvoiced(job.id).map { (job.id, $0) } }, uniquingKeysWith: { first, _ in first })
        let lifetime = figures.values.reduce(0, +)
        var days: [String] = []
        for job in open where !days.contains(openDay(job)) { days.append(openDay(job)) }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(days, id: \.self) { day in
                CustomerTabLabel(title: day)
                VStack(spacing: 8) {
                    ForEach(open.filter { openDay($0) == day }) { job in
                        CustomerOpenJobCard(job: job, line: openLine(job), invoiceLine: openInvoiceLine(job.id)) { openedJob = job }
                    }
                }
            }
            if !past.isEmpty {
                CustomerTabLabel(title: "Past jobs · \(past.count)") {
                    if lifetime > 0 {
                        Text("\(summaryMoney(lifetime, currency: "USD")) lifetime").font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                }
                CustomerRowsCard {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(shownPast.enumerated()), id: \.element.id) { index, job in
                            if index > 0 { WellDivider(leading: 16) }
                            Button { openedJob = job } label: {
                                CustomerFigureRow(title: job.title,
                                                  line: [job.shortRef, pastDay(job, record: recordsByID[job.id]), job.status == "canceled" ? "Canceled" : nil]
                                                    .compactMap { $0 }.joined(separator: " · "),
                                                  figure: figures[job.id].map { summaryMoney($0, currency: "USD") })
                            }
                            .buttonStyle(RowPressStyle())
                            .accessibilityHint("Opens the job")
                        }
                    }
                }
                if past.count > shownPast.count {
                    // One quiet button brings the rest of the history; the rows are lazy.
                    let remaining = past.count - shownPast.count
                    Button { withMotion { visiblePastCount = past.count } } label: {
                        Text("Show \(remaining) older job\(remaining == 1 ? "" : "s")")
                            .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .padding(.top, 4)
                }
            }
            if jobs.isEmpty {
                // New job sits on the customer's page and in Customer actions.
                ListRoomEmpty(glyph: .jobs, title: "No jobs yet",
                              message: session.can("job.create", feature: "jobs") ? "Create a job with New job." : nil)
                    .padding(.horizontal, -Theme.gutter).padding(.top, 22)
            }
        }
    }

    /// The label an open job's card sits under: "Today", "Tomorrow", "Upcoming", or "Not scheduled".
    private func openDay(_ job: Job) -> String {
        guard let date = JobFiltering.date(job.scheduledFor) else { return "Not scheduled" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date < .now ? "Earlier" : "Upcoming"
    }

    /// "JOB-2214 · 10:30 AM · Ramon M.": the number, when, and who.
    private func openLine(_ job: Job) -> String {
        var parts = [job.shortRef]
        if let date = JobFiltering.date(job.scheduledFor) {
            parts.append(Calendar.current.isDateInToday(date) || Calendar.current.isDateInTomorrow(date) ? date.tradeTime : date.visitLabel())
        }
        if let tech = tech(job.assignedToUserId) { parts.append(tech) }
        return parts.joined(separator: " · ")
    }

    /// "INV-2209 · $340 due": the job's unpaid invoice, once the records have loaded.
    private func openInvoiceLine(_ jobID: String) -> String? {
        guard let invoices = visibleRecords?.invoices.first(where: { $0.jobID == jobID })?.items else { return nil }
        for invoice in invoices where ["issued", "sent", "open", "overdue"].contains(invoice.status) {
            if let due = CustomerDocumentAmounts(lines: invoice.lines, currency: invoice.currency, amountPaid: invoice.amountPaid)?.due, due > 0 {
                return "INV-\(invoice.id.suffix(4).uppercased()) · \(summaryMoney(due, currency: invoice.currency)) due"
            }
        }
        return nil
    }

    /// What a past job was invoiced, in cents: its issued and paid invoices in dollars. Nil until
    /// the records load, or when the job has none.
    private func jobInvoiced(_ jobID: String) -> Int? {
        guard let invoices = visibleRecords?.invoices.first(where: { $0.jobID == jobID })?.items else { return nil }
        let totals = invoices.filter { !["draft", "void", "voided"].contains($0.status) && $0.currency == "USD" }
            .compactMap { CustomerDocumentAmounts(lines: $0.lines, currency: $0.currency, amountPaid: $0.amountPaid)?.total }
        return totals.isEmpty ? nil : totals.reduce(0, +)
    }

    /// A past job's day with its year (Paper 48D "Mar 12, 2026").
    private func pastDay(_ job: Job, record: JobRecord?) -> String? {
        JobFiltering.date(record?.completedAt ?? record?.canceledAt ?? job.scheduledFor ?? job.updatedAt).map(CustomerTabDates.full)
    }

    /// Paper 48E's Billing segment: the balance and Collect, the invoices, the estimates (which
    /// have no other home on the customer), and how the customer pays.
    @ViewBuilder private var billingTab: some View {
        let scope = recordsScope
        let visible = scope != nil && moneyRecordsPublishedScope == scope ? moneyRecords : nil
        let visibleError = scope != nil && moneyRecordsRequestedScope == scope ? moneyRecordsError : nil
        VStack(alignment: .leading, spacing: 0) {
            if scope == nil {
                emptyText("You don’t have access to this customer’s records.").padding(.top, 20)
            } else {
                if let visibleError {
                    ErrorBanner(message: visible == nil ? "Records did not load. \(visibleError)" : visibleError) { await loadMoneyRecords() }
                        .accessibilityIdentifier("customer-records-retry").padding(.top, 20)
                }
                if let visible {
                    billingBody(visible)
                } else if visibleError == nil {
                    CustomerRowsCard { SkeletonRows(count: 3, leading: false, inset: PaperCardMetrics.inset) }.padding(.top, 20)
                }
            }
        }
    }

    @ViewBuilder private func billingBody(_ compiled: CustomerJobCompilation) -> some View {
        let invoices = billingInvoices(compiled)
        let open = invoices.filter { $0.isOpen && ($0.due ?? 0) > 0 && $0.currency == "USD" }
        let balance = open.reduce(0) { $0 + ($1.due ?? 0) }
        let estimates = compiled.estimates.flatMap(\.items) + compiled.estimatesOffJob
        if compiled.invoicesAccessible {
            CustomerBalanceCard(balance: money(balance, currency: "USD"),
                                line: open.isEmpty ? "Nothing owed" : open.count == 1 ? open[0].heading : "\(open.count) unpaid invoices",
                                collectTitle: open.last.map { _ in "Collect \(summaryMoney(open.count == 1 ? balance : (open.last?.due ?? 0), currency: "USD"))" }) {
                // The oldest unpaid invoice: payment is taken on the invoice itself.
                if let first = open.last { openedRoute = .invoice(first.id) }
            }
            .padding(.top, 20)
            CustomerTabLabel(title: "Invoices and payments") {
                if invoices.count > 5 {
                    Button { withMotion { showsAllInvoices.toggle() } } label: {
                        Text(showsAllInvoices ? "Show fewer" : "See all").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.brandText)
                            .padding(.vertical, 13).contentShape(Rectangle()).padding(.vertical, -13)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            if invoices.isEmpty {
                Text("No invoices yet").font(Theme.font(15)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            } else {
                CustomerRowsCard {
                    ForEach(Array((showsAllInvoices ? invoices : Array(invoices.prefix(5))).enumerated()), id: \.element.id) { index, invoice in
                        if index > 0 { WellDivider(leading: 16) }
                        Button { openedRoute = .invoice(invoice.id) } label: {
                            CustomerFigureRow(title: invoice.heading, line: invoice.line(),
                                              lineColor: invoice.isOpen ? Theme.warning : Theme.muted,
                                              figure: invoice.isVoid ? nil : invoice.total.map { summaryMoney($0, currency: invoice.currency) },
                                              figureColor: invoice.status == "paid" ? Theme.success : Theme.foreground,
                                              figureWeight: invoice.isOpen ? .semibold : .medium)
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityHint("Opens the invoice")
                        .accessibilityIdentifier("customer-invoice-\(invoice.id)")
                    }
                }
            }
        } else {
            Label("Invoices are unavailable with your current access.", systemImage: "lock")
                .font(Theme.font(15)).foregroundStyle(Theme.muted).padding(.top, 20)
                .accessibilityIdentifier("customer-invoices-unavailable")
        }
        if compiled.estimatesAccessible, !estimates.isEmpty {
            CustomerTabLabel(title: "Estimates")
            CustomerRowsCard {
                ForEach(Array(estimates.enumerated()), id: \.element.id) { index, estimate in
                    let row = CustomerMoneyRow.estimate(estimate)
                    if index > 0 { WellDivider(leading: 16) }
                    Button { openedRoute = row.route } label: {
                        CustomerFigureRow(title: "\(row.reference) · \(row.title)",
                                          line: [estimate.status.statusLabel, row.meta].compactMap { $0 }.joined(separator: " · "),
                                          figure: row.amount.map { _ in "" }.flatMap { _ in
                                              CustomerDocumentAmounts(lines: estimate.lines, currency: "USD").map { summaryMoney($0.total, currency: "USD") }
                                          })
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityHint("Opens the estimate")
                    .accessibilityIdentifier("customer-estimate-\(estimate.id)")
                }
            }
        }
        if let pricing, pricing.isMember {
            // Paper 48E "How she pays": the app keeps no card on file and no autopay, so the
            // membership is the one row, and it opens the Membership page.
            CustomerTabLabel(title: "How \(hubName) pays")
            CustomerRowsCard {
                Button { openPart = .membership } label: {
                    HStack(spacing: 12) {
                        PaperIcon(.shield, size: 20, color: Theme.muted).frame(width: 40, height: 28)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(pricing.membership?.name ?? "Member").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                            if let line = membershipLine(pricing) {
                                Text(line).font(Theme.font(14)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        PaperRowChevron()
                    }
                    .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityHint("Opens the membership")
            }
        }
    }

    /// "15% off · renews Aug 1".
    private func membershipLine(_ pricing: MemberPricing) -> String? {
        var parts: [String] = []
        if pricing.discountPercent > 0 { parts.append("\(pricing.discountPercent)% off") }
        if let renews = JobFiltering.date(pricing.membership?.renewsOn) ?? pricing.membership?.renewsOn.flatMap({ try? Date($0, strategy: .iso8601.year().month().day()) }) {
            parts.append("\(parts.isEmpty ? "Renews" : "renews") \(CustomerTabDates.short(renews))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The customer's invoices, newest first, each with the job it bills.
    private func billingInvoices(_ compiled: CustomerJobCompilation) -> [CustomerBillingInvoice] {
        func make(_ invoice: InvoiceRecord, title: String?) -> CustomerBillingInvoice {
            let amounts = CustomerDocumentAmounts(lines: invoice.lines, currency: invoice.currency, amountPaid: invoice.amountPaid)
            return CustomerBillingInvoice(id: invoice.id, reference: "INV-\(invoice.id.suffix(4).uppercased())", title: title,
                                          status: invoice.status, total: amounts?.total, due: amounts?.due, paid: invoice.amountPaid, currency: invoice.currency,
                                          issuedAt: JobFiltering.date(invoice.issuedAt ?? invoice.createdAt), paidAt: JobFiltering.date(invoice.paidAt))
        }
        let all = compiled.invoices.flatMap { group in group.items.map { make($0, title: group.title) } }
            + compiled.invoicesOffJob.map { make($0, title: nil) }
        return all.sorted { ($0.issuedAt ?? .distantPast) > ($1.issuedAt ?? .distantPast) }
    }

    /// Paper 48F's Media segment: the compiled photos and documents, grouped by job.
    private func recordsParts(_ parts: Set<CustomerRecordsPart>, media: Bool = false) -> some View {
        let scope = recordsScope
        let visible = visibleRecords
        let visibleError = scope != nil && recordsRequestedScope == scope ? recordsError : nil
        let days = Dictionary(jobs.compactMap { job in
            JobFiltering.date(job.scheduledFor ?? job.updatedAt).map { (job.id, Calendar.current.isDateInToday($0) ? "today" : CustomerTabDates.full($0)) }
        }, uniquingKeysWith: { first, _ in first })
        return VStack(alignment: .leading, spacing: 10) {
            if scope == nil {
                emptyText("You don’t have access to this customer’s records.")
            } else {
                if let visibleError {
                    ErrorBanner(message: visible == nil ? "Records did not load. \(visibleError)" : visibleError) { await loadRecords() }
                        .accessibilityIdentifier("customer-records-retry")
                }
                if visible == nil && visibleError == nil {
                    SkeletonRows(count: 3, inset: 0)
                } else if let visible {
                    CustomerRecordsView(compilation: visible, customerID: customer.id, retryMedia: { await loadRecords() },
                                        parts: parts, mediaTab: media, jobDays: days)
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

    private func loadSelectedRecords() async {
        switch tab {
        case "Billing": await loadMoneyRecords()
        case "Jobs", "Media": await loadRecords()
        default: break
        }
    }

    private func loadMoneyRecords() async {
        guard let scope = recordsScope else { return }
        guard !moneyRecordsLoading || moneyRecordsRequestedScope != scope else { return }
        moneyRecordsLoadGeneration += 1
        let request = moneyRecordsLoadGeneration
        moneyRecordsLoading = true
        moneyRecordsRequestedScope = scope
        moneyRecordsError = nil
        defer { if moneyRecordsLoadGeneration == request { moneyRecordsLoading = false } }
        do {
            let recordsSession = session
            let compiled = try await CustomerJobCompilationLoader.load(customerID: scope.customerID,
                organizationID: scope.organizationID, api: api, access: scope.access, moneyOnly: true,
                isCurrent: { scope.isCurrent(session: recordsSession) })
            guard !Task.isCancelled, moneyRecordsLoadGeneration == request, scope.isCurrent(session: session) else { return }
            moneyRecords = compiled
            moneyRecordsPublishedScope = scope
            moneyRecordsError = nil
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, moneyRecordsLoadGeneration == request, scope.isCurrent(session: session) else { return }
            moneyRecordsError = error.localizedDescription
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
            let recordsSession = session
            let compiled = try await CustomerJobCompilationLoader.load(customerID: scope.customerID,
                organizationID: scope.organizationID, api: api, access: scope.access,
                isCurrent: { scope.isCurrent(session: recordsSession) })
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
                // Paper 48G: the label, the chips, then a timeline on the canvas (no card): a month
                // label over rows of a 32pt mark on a rail, what happened and when.
                VStack(alignment: .leading, spacing: 0) {
                    if activityLoading && activity.isEmpty {
                        PaperCard { SkeletonRows(count: 3, leading: false, inset: PaperCardMetrics.inset) }
                    } else if activity.isEmpty && customerCalls.isEmpty {
                        PaperCard {
                            emptyText(activityError == nil ? "Nothing yet" : "Not loaded")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 6)
                        }
                    } else {
                        activityChips
                        activityTimeline
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

    /// Paper 48G's chips. Calls shows when this role reads the call log; Texts has no chip because
    /// nothing is sent or received through Thorbis yet.
    private var activityFilters: [String] {
        callsAvailable ? ["All", "Calls", "Visits", "Payments"] : ["All", "Visits", "Payments"]
    }

    private func activityMatches(_ event: CustomerHistoryEntry) -> Bool {
        if activityFilter == "Calls" { return false }
        if activityFilter == "Visits" { return event.kind == "job" }
        if activityFilter == "Payments" { return event.kind == "payment" || event.kind == "invoice" }
        return true
    }

    /// Paper 48G's chips: 36 tall pills (a 44pt target), the chosen one in the ink.
    private var activityChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(activityFilters, id: \.self) { name in
                    activityChip(name)
                }
            }
        }
    }

    private func activityChip(_ name: String) -> some View {
        let selected = activityFilter == name
        return Button { activityFilter = name } label: {
            PaperChoiceChipLabel(title: name, isOn: selected)
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("customer-activity-filter-\(name.lowercased())")
    }

    /// The loaded history under the chosen chip, newest first, in "Today" and month groups.
    private var activityGroups: [CustomerActivityGroup] {
        var groups: [CustomerActivityGroup] = []
        for item in activityItems {
            let title = activityGroupTitle(item.at)
            if let last = groups.last, last.title == title {
                groups[groups.count - 1].events.append(item)
            } else {
                groups.append(CustomerActivityGroup(id: groups.count, title: title, events: [item]))
            }
        }
        return groups
    }

    /// The server's history under the chosen chip, with this customer's calls from the call log
    /// set among it by time (Paper 48G "Call from Danielle"). While older history is still to load,
    /// calls older than the oldest loaded event wait with it, so the order stays true.
    private var activityItems: [CustomerActivityItem] {
        let events = activity.filter(activityMatches).map(CustomerActivityItem.event)
        guard activityFilter == "All" || activityFilter == "Calls" else { return events }
        var calls = customerCalls
        if activityFilter == "All", activityCursor != nil,
           let oldest = activity.compactMap({ JobFiltering.date($0.occurredAt) }).min() {
            calls = calls.filter { ($0.startedDate ?? .distantPast) >= oldest }
        }
        var pending = calls.map(CustomerActivityItem.call)[...]
        if activityFilter == "Calls" || pending.isEmpty || events.isEmpty { return events + Array(pending) }
        var merged: [CustomerActivityItem] = []
        for event in events {
            if let date = JobFiltering.date(event.at) {
                while let call = pending.first, (JobFiltering.date(call.at) ?? .distantPast) > date {
                    merged.append(call)
                    pending = pending.dropFirst()
                }
            }
            merged.append(event)
        }
        return merged + Array(pending)
    }

    @ViewBuilder private var activityTimeline: some View {
        let groups = activityGroups
        if groups.isEmpty {
            Text("No \(activityFilter.lowercased()) in the activity loaded so far.")
                .font(Theme.font(14)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4).padding(.top, 12)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups) { group in
                    PaperSectionLabel(title: group.title)
                        .padding(.top, 14)
                    ForEach(Array(group.events.enumerated()), id: \.element.id) { index, item in
                        switch item {
                        case .event(let event): activityRow(event, last: index == group.events.count - 1)
                        case .call(let call): activityCallRow(call, last: index == group.events.count - 1)
                        }
                    }
                }
            }
        }
    }

    private func activityRow(_ event: CustomerHistoryEntry, last: Bool) -> some View {
        let mark = activityMark(event.kind)
        return ActivityLink(destination: ActivityDestinationMapping.customerHistory(event, customerID: customer.id),
                            showsChevron: false) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: mark.symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(mark.ink)
                    .frame(width: 32, height: 32)
                    .background(mark.fill, in: Circle())
                    .accessibilityHidden(true)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(event.summary).font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(activityTime(event.occurredAt)).font(Theme.font(13)).monospacedDigit()
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 6)
            }
            .padding(.bottom, last ? 8 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The rail: a 2pt line from under the mark to the next row's mark.
            .background(alignment: .topLeading) {
                if !last {
                    Rectangle().fill(Theme.hairline).frame(width: 2)
                        .padding(.leading, 15).padding(.top, 32)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A call from the business's call log on the timeline: what happened and how long, when, and
    /// what was said. It opens Texts and calls.
    private func activityCallRow(_ call: BookingCallRecord, last: Bool) -> some View {
        let missed = call.kind == .missed || call.kind == .dropped
        let title = [call.kind.heading, call.length.map { BookingCallRecord.clock($0) }].compactMap { $0 }.joined(separator: " · ")
        let said = call.summary?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Button { openPart = .comms } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "phone").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(missed ? Theme.destructive : Theme.brandText)
                    .frame(width: 32, height: 32)
                    .background(missed ? Theme.destructiveSurface : Theme.brandSurface, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title).font(Theme.font(15, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.foreground)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(activityTime(call.startedAt)).font(Theme.font(13)).monospacedDigit()
                            .foregroundStyle(Theme.muted)
                    }
                    if !said.isEmpty {
                        Text(said).font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.leading)
                            .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 6)
            }
            .padding(.bottom, last ? 8 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topLeading) {
                if !last {
                    Rectangle().fill(Theme.hairline).frame(width: 2)
                        .padding(.leading, 15).padding(.top, 32)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens texts and calls")
    }

    private func activityMark(_ kind: String) -> CustomerActivityMark {
        switch kind {
        case "payment": return CustomerActivityMark(symbol: "dollarsign", ink: Theme.success, fill: Theme.successSurface)
        case "job": return CustomerActivityMark(symbol: "box.truck", ink: Theme.warning, fill: Theme.warningSurface)
        case "contact": return CustomerActivityMark(symbol: "person", ink: Theme.brandText, fill: Theme.brandSurface)
        case "location": return CustomerActivityMark(symbol: "mappin.and.ellipse", ink: Theme.brandText, fill: Theme.brandSurface)
        case "estimate": return CustomerActivityMark(symbol: "doc.text", ink: Theme.foreground, fill: Theme.fill)
        case "invoice": return CustomerActivityMark(symbol: "doc.plaintext", ink: Theme.foreground, fill: Theme.fill)
        default: return CustomerActivityMark(symbol: "clock", ink: Theme.foreground, fill: Theme.fill)
        }
    }

    /// "Today", "March", or "March 2025" outside this year.
    private func activityGroupTitle(_ raw: String) -> String {
        guard let date = JobFiltering.date(raw) else { return "Earlier" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.wide))
        }
        return date.formatted(.dateTime.month(.wide).year())
    }

    /// The row's trailing time: the clock today, else "Mar 12" (with the year outside this one).
    private func activityTime(_ raw: String) -> String {
        guard let date = JobFiltering.date(raw) else { return "" }
        if Calendar.current.isDateInToday(date) { return date.tradeTime }
        if Calendar.current.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
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
    /// A site hazard (dogs on site): a word with its warning mark, then what to know. No coloured
    /// surface or rail; the mark and the word carry it (design.thorbis.com: words first, colour second).
    private func hazardRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.warning)
                .accessibilityHidden(true)
            (Text(title).font(Theme.font(14, weight: .medium)).foregroundColor(Theme.foreground)
             + Text("  \(value)").font(Theme.font(14)).foregroundColor(Theme.subtle))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning, \(title): \(value)")
    }

    private func emptyText(_ text: String) -> some View { PaperInlineEmpty(text).padding(.vertical, 6) }
    private func unavailable(_ title: String, _ message: String) -> some View { VStack(alignment: .leading, spacing: 6) { sectionTitle(title); emptyText(message) } }
    private func load(currentAuthority: @escaping @MainActor () -> Bool = { true }) async {
        guard currentAuthority() else { return }
        loadGeneration += 1
        let requestGeneration = loadGeneration
        let locationRequestGeneration = locationState.beginLoad()
        let contactRequestGeneration = contactState.beginLoading()
        do {
            let loadedRecord = try await api.fieldCustomer(customer.id)
            guard currentAuthority(), loadGeneration == requestGeneration else { return }
            record = loadedRecord
            let loadedContacts = try await api.fieldContacts(customer.id)
            guard currentAuthority(), loadGeneration == requestGeneration else { return }
            contactState.receive(loadedContacts, generation: contactRequestGeneration)
            let loadedLocations = try await api.fieldLocations(customer.id)
            guard currentAuthority(), loadGeneration == requestGeneration else { return }
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
    @Environment(\.openURL) private var openURL
    @Environment(\.inboxEmail) private var inboxEmail
    let value: String
    let isPhone: Bool
    let emailContext: String
    var size: CGFloat = 30
    private var url: URL? {
        let address = isPhone ? value.filter { $0.isNumber || $0 == "+" } : value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard !address.isEmpty else { return nil }
        return URL(string: (isPhone ? "tel:" : "mailto:") + address)
    }
    var body: some View {
        if let url {
            Button {
                if isPhone { openURL(url) } else { inboxEmail(url, context: emailContext) }
            } label: {
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
/// One "Today" or month group of the customer's timeline (Paper 48G).
private struct CustomerActivityGroup: Identifiable {
    let id: Int
    let title: String
    var events: [CustomerActivityItem]
}

/// A timeline row: something from the customer's history, or a call from the call log.
private enum CustomerActivityItem: Identifiable {
    case event(CustomerHistoryEntry)
    case call(BookingCallRecord)

    var id: String {
        switch self {
        case .event(let event): "event-\(event.id)"
        case .call(let call): "call-\(call.id)"
        }
    }

    var at: String {
        switch self {
        case .event(let event): event.occurredAt
        case .call(let call): call.startedAt
        }
    }
}

/// A timeline row's 32pt mark: its symbol, ink and surface.
private struct CustomerActivityMark {
    let symbol: String
    let ink: Color
    let fill: Color
}

@MainActor private enum ActivityStamp {
    static let abbreviated: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

/// Paper 48A's "Recently archived customers" row: the archived list (48H), read the way the
/// Customers list reads it.
private struct RecentlyArchivedCustomersPage: View {
    @EnvironmentObject private var api: APIClient
    @State private var records: [CustomerRecord] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        Group {
            if loaded {
                ArchivedCustomersView(customers: records) { _ in await load() }
            } else if let error {
                ScrollView { ErrorBanner(message: error, outer: PaperCardMetrics.margin).padding(.top, 12) }
                    .background(Theme.canvas)
            } else {
                ScrollView { SkeletonRows(count: 4, leading: false, inset: PaperCardMetrics.inset).paperCardMargin().padding(.top, 12) }
                    .background(Theme.canvas)
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            records = try await api.fieldCustomers(includeArchived: true)
            loaded = true
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
