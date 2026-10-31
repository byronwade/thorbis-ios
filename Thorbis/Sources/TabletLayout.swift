import SwiftUI

// MARK: - Split selection

/// Set by the iPad's split columns. When present, list rows select into the detail column
/// beside them instead of pushing; on iPhone it is nil and rows push as before.
struct PaperSplitSelection {
    var selectedID: String?
    var select: (_ id: String, _ value: AnyHashable) -> Void
}

extension EnvironmentValues {
    @Entry var paperSplit: PaperSplitSelection? = nil
    /// The iPad detail column's readable width. Nil on iPhone, where screens fill the width.
    @Entry var paperReadableWidth: CGFloat? = nil
}

/// The selection fill for a chosen row: the one blue, inset inside the row's sheet.
private struct SplitSelectedFill: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        content.background {
            if selected { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.brandSurface).padding(3) }
        }
    }
}

/// A list row that pushes `value` on iPhone and selects it into the detail column on iPad.
struct PaperSplitLink<Value: Hashable, Label: View>: View {
    let id: String
    let value: Value
    @ViewBuilder var label: () -> Label
    @Environment(\.paperSplit) private var split

    var body: some View {
        if let split {
            let selected = split.selectedID == id
            Button { split.select(id, AnyHashable(value)) } label: {
                label().modifier(SplitSelectedFill(selected: selected))
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            NavigationLink(value: value) { label() }
        }
    }
}

/// The same for rows that push a destination view on iPhone (estimates, invoices).
struct PaperSplitDestinationLink<Destination: View, Label: View>: View {
    let id: String
    let value: AnyHashable
    @ViewBuilder var destination: () -> Destination
    @ViewBuilder var label: () -> Label
    @Environment(\.paperSplit) private var split

    var body: some View {
        if let split {
            let selected = split.selectedID == id
            Button { split.select(id, value) } label: {
                label().modifier(SplitSelectedFill(selected: selected))
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            NavigationLink { destination() } label: { label() }
        }
    }
}

/// Caps a screen at the iPad's readable width, centred on the cream ground. No-op on iPhone.
struct TabletReadable: ViewModifier {
    @Environment(\.paperReadableWidth) private var width

    func body(content: Content) -> some View {
        if let width {
            content
                .frame(maxWidth: width)
                .frame(maxWidth: .infinity)
                .background(Theme.canvas)
        } else {
            content
        }
    }
}

extension View {
    func tabletReadable() -> some View { modifier(TabletReadable()) }
}

extension TabletSection {
    /// Places with a list column beside their detail.
    var isSplit: Bool {
        switch self {
        case .schedule, .jobs, .customers, .place(.estimates), .place(.invoices): true
        default: false
        }
    }
}

/// What the person picked in a split's list: the id keys the detail, the value builds it.
struct TabletPick: Equatable {
    let id: String
    let value: AnyHashable
}

// MARK: - Tablet root

/// The iPad layout at regular width: a sidebar of places, a list column and a detail column.
/// Each column has its own navigation bar. Only the detail column has a NavigationStack with a
/// path; the list column's stack never pushes (rows select), so stacks are siblings, never nested.
struct TabletRoot: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var layout: MenuLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tab: TabletSection = .schedule
    @State private var path = NavigationPath()
    @State private var picks: [TabletSection: TabletPick] = [:]
    @State private var scheduleRange = "Today"
    @State private var scheduleSelection: String?
    @StateObject private var addresses = JobAddressBook()
    /// Landscape: the person folded the sidebar away. Portrait: the sidebar is drawn over the columns.
    @State private var sidebarFolded = false
    @State private var sidebarOpen = false

    @State private var search = false
    @State private var searchSeed = ""
    /// What a search action starts once the search sheet has closed (a sheet can't open over one leaving).
    @State private var afterSearch: (() -> Void)?
    @State private var settings = false
    @State private var workspace = false
    @State private var createJob = false
    @State private var newEstimate = false
    @State private var newCustomer = false
    @State private var createMenuOpen = false
    @State private var pendingCreate: (() -> Void)?

    static let sidebarWidth: CGFloat = 280
    static let readableWidth: CGFloat = 720
    /// From here the sidebar sits beside the columns (iPad landscape); narrower, it slides over them.
    static let inlineSidebarWidth: CGFloat = 1100

    var body: some View {
        GeometryReader { geometry in
            let inline = geometry.size.width >= Self.inlineSidebarWidth && !sidebarFolded
            HStack(spacing: 0) {
                if inline {
                    sidebar(fold: { withAnimation(motion) { sidebarFolded = true } })
                    columnRule
                }
                VStack(spacing: 0) {
                    if !inline { topBar(wide: geometry.size.width >= Self.inlineSidebarWidth) }
                    columns(width: geometry.size.width - (inline ? Self.sidebarWidth + 1 : 0))
                }
            }
            .overlay(alignment: .leading) {
                if !inline && sidebarOpen {
                    ZStack(alignment: .leading) {
                        Color.black.opacity(0.22).ignoresSafeArea()
                            .onTapGesture { withAnimation(motion) { sidebarOpen = false } }
                            .accessibilityLabel("Close sidebar")
                            .accessibilityAddTraits(.isButton)
                        sidebar(fold: { withAnimation(motion) { sidebarOpen = false } })
                            .background(Theme.canvas)
                            .shadow(color: .black.opacity(0.18), radius: 24, x: 4)
                            .transition(.move(edge: .leading))
                    }
                    .transition(.opacity)
                }
            }
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        // iPad: the sidebar holds Create and Settings, so no header menu circle or floating + pill.
        .environment(\.paperMenuButton, false)
        .environment(\.paperShowMenu, { Task { @MainActor in settings = true } })
        .background { keyboardShortcuts }
        .sheet(isPresented: $search, onDismiss: {
            searchSeed = ""
            let run = afterSearch
            afterSearch = nil
            run?()
        }) { SheetSurface { PaperGlobalSearch(initialQuery: searchSeed, actions: searchActions) } }
        .sheet(isPresented: $settings) { SheetSurface { SettingsView() } }
        .sheet(isPresented: $workspace) { SheetSurface { WorkspaceSelectionView() } }
        .sheet(isPresented: $createJob) { SheetSurface { NewJobSheet() } }
        .sheet(isPresented: $newEstimate) { SheetSurface { NewEstimateView() } }
        .sheet(isPresented: $newCustomer) { SheetSurface { NewCustomerSheet() } }
        .sheet(isPresented: $createMenuOpen, onDismiss: {
            let run = pendingCreate
            pendingCreate = nil
            run?()
        }) { SheetSurface {
            ThorbisMenuCard(items: createChoices, title: "Create") { item in
                pendingCreate = item.action
                createMenuOpen = false
            }
        } }
        .onChange(of: scheduleSelection) { path = NavigationPath() }
        .onChange(of: scheduleRange) { path = NavigationPath() }
        .onChange(of: store.requestedJobID, initial: true) { openRequestedJob() }
        .onChange(of: store.jobs) { openRequestedJob() }
        .onChange(of: store.requestedSchedule) { show(.schedule); scheduleRange = "Today" }
        .onChange(of: store.requestedRecord, initial: true) { openRequestedRecord() }
        .onChange(of: store.requestedSearch, initial: true) {
            guard let query = store.requestedSearch else { return }
            store.requestedSearch = nil
            searchSeed = query
            search = true
        }
        .task(id: "addr|\(store.jobs.map { "\($0.id):\($0.locationId ?? "")" }.joined(separator: ","))|\(session.generation)") {
            guard session.can("customer.view", feature: "core_crm") else { return }
            await addresses.load(Array(store.jobs.prefix(60)), api: api, organizationID: session.activeOrganization?.id,
                                 identity: "\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)")
        }
        .onAppear {
            if session.can("job.view", feature: "jobs") { tab = .schedule }
            else if session.can("customer.view", feature: "core_crm") { tab = .customers }
            else if let first = menuPlaces.first { tab = section(for: first) }
        }
        .task {
            await store.refresh(api)
            #if DEBUG
            if PaperPreview.enabled { applyPreview() }
            #endif
        }
    }

    private var motion: Animation { reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.88) }

    private var columnRule: some View { Rectangle().fill(Theme.border).frame(width: 1).ignoresSafeArea() }

    // MARK: Columns

    @ViewBuilder private func columns(width: CGFloat) -> some View {
        if tab.isSplit && !(tab == .schedule && scheduleRange == "Week") {
            let listWidth: CGFloat = width >= 1000 ? 380 : 340
            HStack(spacing: 0) {
                NavigationStack {
                    listColumn
                        .environment(\.paperSplit, PaperSplitSelection(selectedID: picks[tab]?.id) { id, value in
                            picks[tab] = TabletPick(id: id, value: value)
                            path = NavigationPath()
                        })
                }
                .id(tab)
                .frame(width: listWidth)
                columnRule
                detailStack
            }
        } else {
            detailStack
        }
    }

    @ViewBuilder private var listColumn: some View {
        switch tab {
        case .schedule:
            PaperTabletSchedule(range: $scheduleRange, selectedID: $scheduleSelection, addresses: addresses,
                                newJob: canCreateJob ? { createJob = true } : nil)
        case .jobs: JobsView()
        case .customers: CustomersView()
        case .place(let item): if let route = item.route { PaperRouteView(route: route) }
        default: EmptyView()
        }
    }

    private var detailStack: some View {
        NavigationStack(path: $path) {
            detailRoot
                .background(Theme.canvas)
                .paperDestinations()
        }
        .environment(\.paperReadableWidth, Self.readableWidth)
    }

    @ViewBuilder private var detailRoot: some View {
        switch tab {
        case .schedule:
            switch scheduleRange {
            case "Map":
                ScrollView {
                    ScheduleMapView(jobs: PaperTabletSchedule.todayJobs(store.jobs, canView: session.can("job.view", feature: "jobs"))
                        .filter { $0.status != "canceled" }, selection: $scheduleSelection)
                        .padding(.top, 16)
                }
                .toolbar(.hidden, for: .navigationBar)
            case "Week":
                TabletWeekBoard(range: $scheduleRange, addresses: addresses) { path.append($0) }
                    .toolbar(.hidden, for: .navigationBar)
            default:
                if let id = scheduleSelection {
                    jobDetail(id)
                } else if store.loading && store.jobs.isEmpty {
                    SkeletonRows(count: 8, leading: false).frame(maxHeight: .infinity, alignment: .top)
                } else {
                    placeholder("calendar", "Pick a job", "Choose a job on the left to see its details, notes and invoice here.")
                }
            }
        case .jobs:
            if let pick = picks[.jobs] { jobDetail(pick.id) }
            else { placeholder("briefcase", "Pick a job", "Choose a job on the left to open it here.") }
        case .customers:
            if let pick = picks[.customers], let customer = pick.value.base as? Customer {
                CustomerDetailView(customer: customer).id(pick.id).tabletReadable()
            } else {
                placeholder("person.2", "Pick a customer", "Choose a customer on the left to see their jobs, places and money.")
            }
        case .place(.estimates):
            if let pick = picks[tab] { EstimateDetailView(id: pick.id).id(pick.id).tabletReadable() }
            else { placeholder("doc.text", "Pick an estimate", "Choose an estimate on the left to read and send it here.") }
        case .place(.invoices):
            if let pick = picks[tab] { InvoiceDetailView(id: pick.id).id(pick.id).tabletReadable() }
            else { placeholder("doc.plaintext", "Pick an invoice", "Choose an invoice on the left to see what's owed and collect payment.") }
        case .place(let item):
            if let route = item.route { PaperRouteView(route: route).tabletReadable() }
        case .local(let section):
            PaperRouteView(route: .local(section)).tabletReadable()
        case .more:
            MoreView().tabletReadable()
        }
    }

    /// The phone's job screen, keyed so a store refresh never rebuilds it (the wrong-invoice fix).
    @ViewBuilder private func jobDetail(_ id: String) -> some View {
        let identity = store.jobs.first { $0.id == id }.map(PaperTabletSchedule.detailIdentity) ?? id
        JobDetailView(jobId: id, showsBack: false)
            .id(identity)
            .tabletReadable()
    }

    private func placeholder(_ symbol: String, _ title: String, _ message: String) -> some View {
        VStack {
            Spacer(minLength: 0)
            PaperEmptyState(symbol: symbol, title: title, message: message)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Top bar (sidebar hidden)

    /// Portrait or a folded sidebar: the same Search and Create, beside a button that brings the
    /// sidebar back. It sits above the columns, never over their rows.
    private func topBar(wide: Bool) -> some View {
        HStack(spacing: 10) {
            PaperCircleButton(symbol: "sidebar.left", label: "Show sidebar", fill: Theme.card, bordered: true) {
                withAnimation(motion) { if wide { sidebarFolded = false } else { sidebarOpen = true } }
            }
            Text(title(of: tab)).font(Theme.font(16, weight: .medium)).lineLimit(1)
            Spacer(minLength: 12)
            TabletSearchField(compact: true) { search = true }.frame(maxWidth: 300)
            if !createChoices.isEmpty { createButton }
        }
        .padding(.horizontal, 12).frame(height: 56)
        .background(Theme.canvas)
    }

    private var createButton: some View {
        Button { createMenuOpen = true } label: {
            PaperCircleLabel(symbol: "plus", size: 40, fill: Theme.card, bordered: true)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Create")
        .accessibilityHint("New job, estimate or customer")
    }

    // MARK: Sidebar

    private func sidebar(fold: @escaping () -> Void) -> some View {
        TabletSidebar(
            places: menuPlaces,
            local: localSections,
            current: tab,
            section: section(for:),
            count: sidebarCount,
            currentJob: currentJob,
            currentJobTitle: currentJob.map { addresses.street($0) ?? $0.title },
            currentJobCustomer: currentJob.map { store.customerName($0.customerId) },
            canCreate: !createChoices.isEmpty,
            select: { target in
                withAnimation(motion) { sidebarOpen = false }
                show(target)
            },
            openJob: { job in
                withAnimation(motion) { sidebarOpen = false }
                store.requestedJobID = job.id
            },
            search: { search = true },
            create: { createMenuOpen = true },
            workspace: { workspace = true },
            settings: { settings = true },
            fold: fold
        )
        .frame(width: Self.sidebarWidth)
    }

    private func show(_ target: TabletSection) {
        path = NavigationPath()
        tab = target
    }

    private var menuPlaces: [MenuItem] {
        AppMenuContent.places(tabs: layout.visibleTabs(session), hidden: layout.hidden, order: layout.menuOrder,
                              permitted: { $0.permitted(session) })
    }

    private var localSections: [LocalWorkspaceSection] {
        guard session.user?.id != nil, session.activeOrganization?.id != nil else { return [] }
        return LocalWorkspaceSection.allCases.filter { session.can($0.requiredCapability, feature: $0.requiredFeature) }
    }

    private func section(for item: MenuItem) -> TabletSection {
        switch item {
        case .schedule: .schedule
        case .jobs: .jobs
        case .customers: .customers
        default: .place(item)
        }
    }

    private func title(of section: TabletSection) -> String {
        switch section {
        case .schedule: "Schedule"
        case .jobs: "Jobs"
        case .customers: "Customers"
        case .more: "More"
        case .place(let item): item.title
        case .local(let local): local.title
        }
    }

    private func sidebarCount(_ item: MenuItem) -> Int? {
        switch item {
        case .schedule: JobFiltering.schedule(store.jobs, range: .today).count
        case .jobs: store.jobs.count
        default: nil
        }
    }

    /// The job this person is on now, pinned at the foot of the sidebar on every place.
    private var currentJob: Job? {
        guard session.can("job.view", feature: "jobs") else { return nil }
        let me = session.user?.id
        return PaperWorkGroups.inProgress(store.jobs).first { $0.assignedToUserId == nil || $0.assignedToUserId == me }
    }

    private var canCreateJob: Bool { session.can("job.create", feature: "jobs") }

    /// The same creates as the phone's +, in the same order.
    private var createChoices: [ThorbisMenuItem] {
        var items: [ThorbisMenuItem] = []
        if canCreateJob { items.append(ThorbisMenuItem("New job", icon: "briefcase", subtitle: "⌘N") { createJob = true }) }
        if session.can("estimate.create", feature: "estimates") {
            items.append(ThorbisMenuItem("New estimate", icon: "doc.text") { newEstimate = true })
        }
        if session.can("customer.create", feature: "core_crm") {
            items.append(ThorbisMenuItem("New customer", icon: "person.badge.plus") { newCustomer = true })
        }
        return items
    }

    /// What typing in search can start: the same creates, Settings and places as the sidebar.
    private var searchActions: [SearchAction] {
        let later: (@escaping () -> Void) -> () -> Void = { run in { afterSearch = run; search = false } }
        let creates = createChoices.map { item in (item.title, item.icon ?? "plus", later(item.action)) }
        return SearchAction.standard(creates: creates, settings: later { settings = true }, places: menuPlaces,
                                     openPlace: { place in afterSearch = nil; search = false; show(section(for: place)) })
    }

    // MARK: Keyboard

    /// Always mounted, so the shortcuts work whether the sidebar is shown, folded or closed.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("Search") { search = true }.keyboardShortcut("f", modifiers: .command)
            Button("Search everything") { search = true }.keyboardShortcut("k", modifiers: .command)
            if canCreateJob { Button("New job") { createJob = true }.keyboardShortcut("n", modifiers: .command) }
            if !createChoices.isEmpty { Button("Create") { createMenuOpen = true }.keyboardShortcut("n", modifiers: [.command, .shift]) }
            Button("Toggle sidebar") { withAnimation(motion) { sidebarFolded.toggle(); sidebarOpen.toggle() } }
                .keyboardShortcut("s", modifiers: [.command, .control])
            ForEach(Array(menuPlaces.prefix(9).enumerated()), id: \.element) { index, item in
                Button(item.title) { show(section(for: item)) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Deep links

    /// A link, notification or Live Activity asked for a job: select it where it is listed.
    private func openRequestedJob() {
        guard let id = store.requestedJobID, session.can("job.view", feature: "jobs"),
              let job = id == JobActivityLink.nextJob ? PaperWorkGroups.next(store.jobs) : store.jobs.first(where: { $0.id == id })
        else { return }
        store.requestedJobID = nil
        if JobFiltering.schedule(store.jobs, range: .today).contains(where: { $0.id == job.id }) {
            show(.schedule)
            scheduleRange = "Today"
            scheduleSelection = job.id
        } else {
            show(.jobs)
            picks[.jobs] = TabletPick(id: job.id, value: job)
        }
    }

    /// Opens the customer, estimate or invoice a link or notification asked for (RecordLink).
    private func openRequestedRecord() {
        guard let record = store.requestedRecord else { return }
        store.requestedRecord = nil
        let access = record.access
        guard session.can(access.capability, feature: access.feature) else { return }
        switch record {
        case .customer(let id):
            let customer = store.customers.first { $0.id == id } ?? Customer(id: id, name: "Customer", archived: nil, createdAt: nil)
            show(.customers)
            picks[.customers] = TabletPick(id: id, value: customer)
        case .estimate(let id):
            show(.place(.estimates))
            picks[.place(.estimates)] = TabletPick(id: id, value: PaperRoute.estimate(id))
        case .invoice(let id):
            show(.place(.invoices))
            picks[.place(.invoices)] = TabletPick(id: id, value: PaperRoute.invoice(id))
        }
    }

    #if DEBUG
    /// Screenshot-only: the same preview screen names as the phone, laid out for iPad.
    private func applyPreview() {
        let job = store.jobs.first { $0.id == PaperPreview.jobID }
        let customer = store.customers.first { $0.id == PaperPreview.customerID }
        switch PaperPreview.screen {
        case "schedule", "my-day": show(.schedule)
        case "schedule-week": show(.schedule); scheduleRange = "Week"
        case "schedule-map": show(.schedule); scheduleRange = "Map"
        case "jobs", "jobs-filters":
            show(.jobs)
            if let job { picks[.jobs] = TabletPick(id: job.id, value: job) }
        case "customers", "customer", "customer-activity", "customer-records", "customer-jobs", "customer-money":
            show(.customers)
            if let customer { picks[.customers] = TabletPick(id: customer.id, value: customer) }
        case "estimates", "estimate-detail":
            show(.place(.estimates))
            picks[.place(.estimates)] = TabletPick(id: PaperPreview.estimate.id, value: PaperRoute.estimate(PaperPreview.estimate.id))
        case "invoices":
            show(.place(.invoices))
            picks[.place(.invoices)] = TabletPick(id: PaperPreview.invoiceDetailPreviewID, value: PaperRoute.invoice(PaperPreview.invoiceDetailPreviewID))
        case "job", "job-invoice", "job-estimates", "job-activity", "job-notes", "job-media", "job-onsite", "job-history":
            if let job { store.requestedJobID = job.id }
        case "ipad-sidebar": sidebarOpen = true; sidebarFolded = true
        case "inbox": show(.place(.inbox))
        case "attention": show(.place(.attention))
        case "reports": show(.place(.reports))
        case "revenue": show(.place(.money))
        case "settings", "menu", "more": settings = true
        case "new-job": createJob = true
        case "create-menu": createMenuOpen = true
        case "search", "search-typed": search = true
        default: break
        }
    }
    #endif
}

// MARK: - Sidebar

/// The iPad sidebar: business switcher, Search and Create, the places from the phone menu
/// (same order and grouping), Settings, then the job you're on and your account at the foot.
struct TabletSidebar: View {
    @EnvironmentObject private var session: SessionController
    let places: [MenuItem]
    let local: [LocalWorkspaceSection]
    let current: TabletSection
    let section: (MenuItem) -> TabletSection
    let count: (MenuItem) -> Int?
    let currentJob: Job?
    let currentJobTitle: String?
    let currentJobCustomer: String?
    let canCreate: Bool
    let select: (TabletSection) -> Void
    let openJob: (Job) -> Void
    let search: () -> Void
    let create: () -> Void
    let workspace: () -> Void
    let settings: () -> Void
    var fold: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                businessSwitcher
                if let fold {
                    PaperCircleButton(symbol: "sidebar.left", label: "Hide sidebar", action: fold)
                }
            }
            .padding(.bottom, 10)
            HStack(spacing: 8) {
                TabletSearchField(compact: false, action: search)
                if canCreate {
                    Button(action: create) {
                        PaperCircleLabel(symbol: "plus", size: 44, fill: Theme.card, bordered: true)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Create")
                    .accessibilityHint("New job, estimate or customer")
                }
            }
            .padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(MenuItem.Group.allCases, id: \.self) { group in
                        let items = places.filter { $0.group == group }
                        let locals = group == .phone ? local : []
                        if !items.isEmpty || !locals.isEmpty {
                            if group != .work {
                                Text(group == .phone ? "On this iPad" : group.rawValue)
                                    .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                                    .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 4)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            ForEach(items) { item in
                                row(item.title, icon: item.symbol, target: section(item), count: count(item))
                            }
                            ForEach(locals, id: \.self) { section in
                                row(section.title, icon: section.moreSymbol, target: .local(section))
                            }
                        }
                    }
                    Button(action: settings) {
                        rowLabel("Settings", icon: "gearshape", selected: false, count: nil)
                    }
                    .buttonStyle(RowPressStyle())
                    .padding(.top, 14)
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            if let currentJob { currentJobCard(currentJob) }
            SidebarAccountButton(name: session.user?.name ?? "", action: settings)
                .padding(.top, 8)
        }
        .padding(.vertical, 12).padding(.horizontal, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
    }

    private var businessSwitcher: some View {
        Button(action: workspace) {
            HStack(spacing: 10) {
                Image("ThorbisMark").resizable().scaledToFit().padding(5)
                    .frame(width: 30, height: 30)
                    .panelBackground(cornerRadius: 8)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border))
                    .accessibilityHidden(true)
                Text(session.activeOrganization?.name ?? "Workspace")
                    .font(Theme.font(16, weight: .medium)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel("Business, \(session.activeOrganization?.name ?? "Workspace")")
        .accessibilityHint("Switch or manage businesses")
    }

    private func row(_ title: String, icon: String, target: TabletSection, count: Int? = nil) -> some View {
        let selected = current == target
        return Button { select(target) } label: {
            rowLabel(title, icon: icon, selected: selected, count: count)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Selected place: the segmented control's white pill on the cream ground.
    private func rowLabel(_ title: String, icon: String, selected: Bool, count: Int?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).frame(width: 22)
                .foregroundStyle(selected ? Theme.foreground : Theme.muted)
            Text(title).font(Theme.font(15, weight: selected ? .medium : .regular)).lineLimit(1)
            Spacer(minLength: 0)
            if let count, count > 0 {
                Text("\(count)").font(Theme.font(13, weight: .medium)).monospacedDigit().foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 10).frame(minHeight: 44)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(Theme.selectedSegment)
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.border.opacity(0.6)))
            }
        }
        .contentShape(Rectangle())
    }

    /// The job you're on, always one tap away — in the sidebar's foot, never floating over rows.
    private func currentJobCard(_ job: Job) -> some View {
        Button { openJob(job) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(StatusWord.jobTint(job.status) ?? Theme.muted).frame(width: 7, height: 7)
                    Text("On now · \(job.status.statusLabel)").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                }
                Text(currentJobTitle ?? job.title).font(Theme.font(15, weight: .medium)).lineLimit(2)
                if let currentJobCustomer {
                    Text(currentJobCustomer).font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .panelBackground(cornerRadius: Theme.cardRadius)
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.border.opacity(0.6)))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Current job, \(currentJobTitle ?? job.title), \(job.status.statusLabel)")
        .accessibilityHint("Opens the job")
    }
}

/// The ⌘F search field: a rimmed row that opens search everywhere.
struct TabletSearchField: View {
    var compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text("Search").lineLimit(1)
                Spacer(minLength: 0)
                Text("⌘F").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted.opacity(0.8))
                    .accessibilityHidden(true)
            }
            .font(Theme.font(15))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: compact ? 40 : 44)
            .panelBackground(cornerRadius: Theme.controlRadius)
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.border))
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Search")
        .accessibilityHint("Jobs, customers, invoices. Command F")
    }
}

// MARK: - Week board

/// Schedule → Week on iPad: one column per day of this week, each a sheet of that day's jobs in
/// time order. Today's header is ink. A job opens full width in the detail column.
struct TabletWeekBoard: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @Binding var range: String
    @ObservedObject var addresses: JobAddressBook
    let open: (Job) -> Void

    private var days: [Date] {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
    }

    private var jobs: [Job] {
        guard session.can("job.view", feature: "jobs") else { return [] }
        return JobFiltering.schedule(store.jobs, range: .week)
    }

    private var subtitle: String {
        guard let first = days.first, let last = days.last else { return "" }
        let span = "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
        return "\(span) · \(jobs.count) \(jobs.count == 1 ? "job" : "jobs") this week"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Schedule").font(Theme.font(30, weight: .medium)).tracking(-0.6)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle).font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 12).padding(.bottom, 12)
            PaperTabs(options: PaperTabletSchedule.ranges, selection: $range)
                .frame(maxWidth: 420, alignment: .leading)
                .padding(.bottom, 8)
            GeometryReader { geometry in
                let spacing: CGFloat = 10
                let fit = (geometry.size.width - Theme.gutter * 2 - spacing * 6) / 7
                let column = max(fit, 132)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(days, id: \.self) { day in
                            dayColumn(day).frame(width: column)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
                .scrollIndicators(column > fit ? .visible : .hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .refreshable { await store.refresh(api) }
    }

    private func dayColumn(_ day: Date) -> some View {
        let calendar = Calendar.current
        let today = calendar.isDateInToday(day)
        let members = jobs.filter { JobFiltering.date($0.scheduledFor).map { calendar.isDate($0, inSameDayAs: day) } ?? false }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(Theme.font(13, weight: .medium)).foregroundStyle(today ? Theme.foreground : Theme.muted)
                Text(day.formatted(.dateTime.day()))
                    .font(Theme.font(15, weight: .medium)).monospacedDigit()
                    .foregroundStyle(today ? Theme.onInk : Theme.foreground)
                    .frame(minWidth: 28, minHeight: 28)
                    .background { if today { Circle().fill(Theme.ink) } }
                Spacer(minLength: 0)
                if !members.isEmpty {
                    Text("\(members.count)").font(Theme.font(13, weight: .medium)).monospacedDigit().foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(spacing: 0) {
                    if members.isEmpty {
                        Text("Nothing booked").font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .padding(.horizontal, 12)
                    }
                    ForEach(members) { job in card(job) }
                }
                .padding(4)
                .panelBackground(cornerRadius: Theme.cardRadius)
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.border.opacity(0.6)))
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func card(_ job: Job) -> some View {
        let street = addresses.street(job)
        let customer = store.customerName(job.customerId)
        let time = JobFiltering.date(job.scheduledFor)?.tradeTime ?? "No time"
        return Button { open(job) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(time).font(Theme.font(13, weight: .medium)).monospacedDigit().foregroundStyle(Theme.muted)
                Text(street ?? job.title).font(Theme.font(15, weight: .medium)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(street != nil ? job.title : customer).font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(2)
                StatusWord(jobStatus: job.status).padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .jobContextMenu(job, customer: customer)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(time), \(street ?? job.title), \(customer), \(job.status.statusLabel)")
    }
}
