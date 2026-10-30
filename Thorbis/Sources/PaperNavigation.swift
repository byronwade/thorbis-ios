import SwiftUI

extension AppBottomBar.Sync {
    static func savedWork(_ snapshot: SavedWorkSnapshot?) -> Self? {
        guard let snapshot, snapshot.hasPendingWork else { return nil }
        if snapshot.hasListingWarning { return .needsChecking }
        if snapshot.attentionCount > 0 { return .needsReview(snapshot.attentionCount) }
        if snapshot.isSending { return .syncing(snapshot.totalCount) }
        return .waiting(snapshot.totalCount)
    }
}

struct RootView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @EnvironmentObject private var pendingMedia: PendingMediaStore
    @State private var tab: TabletSection = .more
    @EnvironmentObject private var layout: MenuLayout
    @EnvironmentObject private var whatsNew: WhatsNew
    /// The selected phone tab: a MenuItem id, "more" or "search".
    @State private var selectedTab = PrimaryTab.initial.rawValue
    /// Paths for tabs an owner added (Inbox, Estimates, ...), keyed by MenuItem id.
    @State private var customPaths: [String: NavigationPath] = [:]
    /// The pop-up menu over the bottom bar.
    @State private var menuOpen = false
    /// The last place opened from the menu that is not pinned; the bar's switcher slot shows it.
    @State private var lastPlace: MenuItem?
    /// iPhone search: the bar turns into a field and results rise in a drawer above it.
    @State private var barSearching = false
    @State private var barQuery = ""
    @State private var newCustomer = false
    @State private var newEstimate = false
    /// The bar's create menu, and the choice that runs once it has closed.
    @State private var createMenuOpen = false
    @State private var pendingCreate: (() -> Void)?
    @State private var reviewScope: SavedWorkScope?
    @ObservedObject private var recents = RecentItems.shared
    /// The phone's width, which sizes the pop-up menu against the bar.
    @State private var phoneWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSettings = false
    @State private var path = NavigationPath()
    @State private var schedulePath = NavigationPath()
    @State private var jobsPath = NavigationPath()
    @State private var customersPath = NavigationPath()
    @State private var morePath = NavigationPath()
    @State private var search = false
    /// Words a Siri or Shortcuts search asked for, typed into the iPad search sheet.
    @State private var searchSeed = ""
    @State private var settings = false
    @State private var workspace = false
    @State private var createJob = false
    #if DEBUG
    @State private var previewInvoiceEditor = false
    @State private var previewInvoiceDetail = false
    @State private var previewEstimateRevision = false
    @State private var previewNewEstimate = false
    @State private var previewNewCustomer = false
    @State private var previewSignature = false
    #endif

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if geometry.size.width >= 1000 { sidebar }
                navigation(wide: geometry.size.width >= 1000)
            }.background(Theme.background)
        }
        // The Home Screen widget reads today's jobs from the shared container.
        .onChange(of: store.jobs, initial: true) { writeTodaySnapshot() }
        .onChange(of: store.customers) { writeTodaySnapshot() }
        // The owner's company-wide tabs and More menu, when one has been saved.
        .task(id: session.activeOrganization?.id) {
            guard session.activeOrganization != nil else { return }
            #if DEBUG
            if PaperPreview.enabled { return }
            #endif
            await layout.refreshCompanyLayout(api: api)
        }
        // With no company or saved phone layout, the bar starts from the person's role.
        .onChange(of: session.capabilities, initial: true) { applyRoleDefaults() }
        // MA-19: once after an update, risen over the home screen rather than during launch.
        .task {
            #if DEBUG
            if PaperPreview.enabled, PaperPreview.screen != "whats-new" { return }
            #endif
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            // A link, notification or Live Activity opened the app for a reason, before or during
            // the pause; the notes wait for the next launch.
            if store.openedForRecord { whatsNew.skipThisLaunch = true }
            whatsNew.presentIfNeeded()
        }
        .sheet(item: $whatsNew.showing, onDismiss: { whatsNew.dismissed() }) { content in
            WhatsNewSheet(content: content) { whatsNew.dismissed() }
        }
    }

    private func applyRoleDefaults() {
        #if DEBUG
        // Screenshots and UI tests keep the standard bar.
        if PaperPreview.enabled { return }
        #endif
        guard session.phase == .ready else { return }
        layout.applyRoleDefaults(WorkRole(session), permitted: { $0.permitted(session) })
    }

    private func writeTodaySnapshot() {
        guard !store.jobs.isEmpty, session.can("job.view", feature: "jobs") else { return }
        let items = store.jobs.map {
            TodaySnapshot.Item(id: $0.id, at: JobFiltering.date($0.scheduledFor), title: $0.title,
                               customer: store.customerName($0.customerId), status: $0.status)
        }
        TodaySnapshot.save(TodaySnapshot(items: items, writtenAt: Date()))
    }

    @ViewBuilder private func navigation(wide: Bool) -> some View {
        if wide { tabletNavigation() } else { phoneNavigation() }
    }

    private func tabletNavigation() -> some View {
        NavigationStack(path: $path) {
            Group {
                switch tab {
                case .schedule:
                    PaperTabletSchedule()
                case .jobs: JobsView()
                case .customers: CustomersView()
                case .more: MoreView()
                case .place(let item): if let route = item.route { PaperRouteView(route: route) }
                case .local(let section): PaperRouteView(route: .local(section))
                }
            }
            .environment(\.paperShowMenu, { Task { @MainActor in settings = true } })
            .background(Theme.background)
            .paperDestinations()
        }
        .sheet(isPresented: $search, onDismiss: { searchSeed = "" }) { PaperGlobalSearch(initialQuery: searchSeed) }
        // The same one Settings as the phone.
        .sheet(isPresented: $settings) { SettingsView() }
        .sheet(isPresented: $workspace) { WorkspaceSelectionView() }
        .sheet(isPresented: $createJob) { NewJobSheet() }
        #if DEBUG
        .sheet(isPresented: $previewInvoiceEditor) {
            NavigationStack {
                InvoiceLineEditorView(invoice: PaperPreview.invoice) { _ in }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $previewInvoiceDetail) {
            NavigationStack {
                InvoiceDetailView(id: PaperPreview.invoiceDetailPreviewID).paperDestinations()
            }
        }
        .sheet(isPresented: $previewEstimateRevision) {
            EstimateRevisionEditorView(estimate: PaperPreview.screen == "estimate-draft" ? PaperPreview.draftEstimate : PaperPreview.estimate) { _ in }
                .environmentObject(api)
                .environmentObject(session)
                .environmentObject(store)
        }
        #endif
        .task {
            await store.refresh(api)
            #if DEBUG
            if PaperPreview.enabled {
                if PaperPreview.screen == "invoice-editor" {
                    previewInvoiceEditor = true
                    return
                }
                if PaperPreview.screen == "invoice-detail" || PaperPreview.screen == "invoice-payment" || PaperPreview.isPaymentRefundPreview {
                    previewInvoiceDetail = true
                    return
                }
                if PaperPreview.screen == "estimate-revision" || PaperPreview.screen == "estimate-draft" {
                    previewEstimateRevision = true
                    return
                }
                switch PaperPreview.screen {
                case "jobs": tab = .jobs
                case "my-day": tab = .schedule
                case "customers": tab = .customers
                case "menu", "more": settings = true
                case "job", "job-invoice": if let job = store.jobs.first(where: { $0.id == PaperPreview.jobID }) { path.append(job) }
                case "customer", "customer-activity", "customer-records": if let customer = store.customers.first(where: { $0.id == PaperPreview.customerID }) { path.append(customer) }
                default: break
                }
            }
            #endif
        }
        .onChange(of: store.requestedJobID, initial: true) { openRequestedJob(phone: false) }
        .onChange(of: store.jobs) { openRequestedJob(phone: false) }
        .onChange(of: store.requestedSchedule) { path = NavigationPath(); tab = .schedule }
        .onChange(of: store.requestedRecord, initial: true) { openRequestedRecord(phone: false) }
        .onChange(of: store.requestedSearch, initial: true) { openRequestedSearch(phone: false) }
        .onAppear {
            if session.can("job.view", feature: "jobs") { path = NavigationPath(); tab = .schedule }
            else if session.can("customer.view", feature: "core_crm") { path = NavigationPath(); tab = .customers }
        }
    }

    /// Linear-style phone navigation: no side menu and no system tab bar. A floating bar holds the
    /// pinned places and a switcher slot; the switcher opens a menu of every place, with the business
    /// switcher on top. The bar shows on a place's first screen and steps aside for pushed screens.
    @ViewBuilder private func phoneNavigation() -> some View {
        #if DEBUG
        if PaperPreview.enabled, PaperPreview.screen == "ipad-sidebar" {
            // Screenshot-only: this phone is narrower than the 1000pt sidebar breakpoint.
            // The column is the same 244pt sidebar the regular-width layout uses.
            sidebar
                .frame(maxHeight: .infinity, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface.ignoresSafeArea())
                .task { await store.refresh(api) }
        } else {
            phoneShell()
        }
        #else
        phoneShell()
        #endif
    }

    private func phoneShell() -> some View {
        GeometryReader { geometry in
            phonePlaces()
                .accessibilityHidden(menuOpen || barSearching)
                .overlay {
                    if barSearching {
                        // Frost the screen behind so only the drawer and field read; a tap closes search.
                        Rectangle().fill(.ultraThinMaterial)
                            .overlay(Theme.background.opacity(0.55))
                            .ignoresSafeArea()
                            .onTapGesture { closeBarSearch() }
                            .accessibilityHidden(true)
                            .transition(.opacity)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // Pulled down into the home indicator's margin, like Linear, so it sits low and small.
                    if atTabRoot || menuOpen || barSearching {
                        VStack(spacing: 10) {
                            if barSearching {
                                searchDrawer(height: max(geometry.size.height - 92, 240))
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            } else if let job = currentJob, !menuOpen {
                                CurrentJobChip(job: job, customer: store.customerName(job.customerId)) {
                                    store.requestedJobID = job.id
                                }
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            bottomBar
                        }
                        .padding(.bottom, AppBottomBar.bottomGap)
                        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: currentJob?.id)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: barSync)
                    }
                }
                // The bar measures from the screen's edge, not the home indicator, so screens get an
                // inset exactly as tall as the bar and nothing hides behind it.
                .ignoresSafeArea(.container, edges: .bottom)
                .overlay {
                    if menuOpen {
                        // A light veil; a tap anywhere outside the menu closes it.
                        Color.black.opacity(0.08)
                            .ignoresSafeArea()
                            .onTapGesture { closeMenu() }
                            .accessibilityHidden(true)
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if menuOpen {
                        appMenu
                            // As wide as the bar's capsule, so it reads as the capsule opening up.
                            .frame(maxHeight: geometry.size.height - 24, alignment: .bottom)
                            .padding(.leading, 16)
                            .padding(.bottom, barDrop(geometry))
                            .transition(reduceMotion
                                ? .opacity
                                : .scale(scale: 0.6, anchor: .bottomLeading).combined(with: .opacity))
                    }
                }
                // Rotation or a new window size closes the menu instead of leaving it misplaced.
                .onChange(of: geometry.size.width, initial: true) { phoneWidth = geometry.size.width }
                .onChange(of: geometry.size.width) { if menuOpen { closeMenu() } }
        }
        .sheet(isPresented: $createMenuOpen, onDismiss: {
            let run = pendingCreate
            pendingCreate = nil
            run?()
        }) { createMenu }
    }

    /// Recent records and results in a card that rises from the bar. Drag its handle down to close.
    private func searchDrawer(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(Theme.border).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity, minHeight: 22)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 8).onEnded { if $0.translation.height > 60 { closeBarSearch() } })
                .accessibilityHidden(true)
            PaperGlobalSearch(externalQuery: $barQuery, openResult: openSearchResult)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bar-search-results")
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .modifier(FloatingSurface(shape: RoundedRectangle(cornerRadius: 28, style: .continuous)))
        .padding(.horizontal, 12)
    }

    private var searchAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.86)
    }

    private func openBarSearch() {
        closeMenu()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(searchAnimation) { barSearching = true }
    }

    private func closeBarSearch() {
        withAnimation(searchAnimation) {
            barSearching = false
            barQuery = ""
        }
    }

    /// A picked result closes search and opens on the place showing, so Back returns there.
    private func openSearchResult(_ destination: SearchDestination) {
        closeBarSearch()
        switch destination {
        case .job(let job): pushOnCurrent(job)
        case .customer(let customer): pushOnCurrent(customer)
        case .route(let route): pushOnCurrent(route)
        }
    }

    private func pushOnCurrent<V: Hashable>(_ value: V) {
        switch selectedTab {
        case PrimaryTab.schedule.rawValue: schedulePath.append(value)
        case PrimaryTab.jobs.rawValue: jobsPath.append(value)
        case PrimaryTab.customers.rawValue: customersPath.append(value)
        case PrimaryTab.more.rawValue: morePath.append(value)
        default: customPaths[selectedTab, default: NavigationPath()].append(value)
        }
    }

    /// The places bar pins: the layout's tabs this role can open.
    private var pinnedPlaces: [MenuItem] { layout.visibleTabs(session) }

    private var menuPlaces: [MenuItem] {
        AppMenuContent.places(tabs: pinnedPlaces, hidden: layout.hidden, order: layout.menuOrder,
                              permitted: { $0.permitted(session) })
    }

    private var localSections: [LocalWorkspaceSection] {
        guard session.user?.id != nil, session.activeOrganization?.id != nil else { return [] }
        return LocalWorkspaceSection.allCases.filter { session.can($0.requiredCapability, feature: $0.requiredFeature) }
    }

    /// The job this person is on now. Schedule already leads with it, so the chip stays off there.
    private var currentJob: Job? {
        guard selectedTab != MenuItem.schedule.rawValue, session.can("job.view", feature: "jobs") else { return nil }
        let me = session.user?.id
        return PaperWorkGroups.inProgress(store.jobs).first { $0.assignedToUserId == nil || $0.assignedToUserId == me }
    }

    private var savedWorkScope: SavedWorkScope? {
        .capture(session: session, api: api, media: pendingMedia, outbox: outbox)
    }

    private var savedWorkSnapshot: SavedWorkSnapshot? {
        guard let scope = savedWorkScope else { return nil }
        return .make(scope: scope, entries: outbox.entries, media: pendingMedia.items,
                     mediaErrors: pendingMedia.errors, unverifiedMediaIDs: pendingMedia.unverifiedIDs,
                     uploadingMediaID: pendingMedia.uploadingID, commandsSyncing: outbox.syncing,
                     jobs: store.jobs, listingWarning: pendingMedia.storageWarning)
    }

    private var barSync: AppBottomBar.Sync? { .savedWork(savedWorkSnapshot) }

    /// Long-press Search: the last records opened here, and the outbox when it holds anything.
    private var searchActions: [[AppBottomBar.QuickAction]] {
        let recent = recents.items.prefix(4).map { item in
            AppBottomBar.QuickAction(title: item.title, symbol: item.kind == .job ? "briefcase" : "person") { openRecent(item) }
        }
        var sync: [AppBottomBar.QuickAction] = []
        if let snapshot = savedWorkSnapshot, snapshot.hasPendingWork {
            sync.append(.init(title: "Review saved work", symbol: snapshot.attentionCount > 0 || snapshot.hasListingWarning
                              ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath") {
                reviewScope = savedWorkScope
            })
        }
        return [Array(recent), sync].filter { !$0.isEmpty }
    }

    /// What this person may start from the bar, in a fixed order so + means the same on every screen.
    private var createChoices: [AppBottomBar.QuickAction] {
        var create: [AppBottomBar.QuickAction] = []
        if session.can("job.create", feature: "jobs") {
            create.append(.init(title: "New job", symbol: "briefcase") { createJob = true })
        }
        if session.can("estimate.create", feature: "estimates") {
            create.append(.init(title: "New estimate", symbol: "doc.text") { newEstimate = true })
        }
        if session.can("customer.create", feature: "core_crm") {
            create.append(.init(title: "New customer", symbol: "person.badge.plus") { newCustomer = true })
        }
        return create
    }

    /// The bar's +: a small create menu. With one choice it starts that directly; with none it hides.
    private var barCreate: (label: String, run: () -> Void)? {
        let choices = createChoices
        if choices.count == 1, let only = choices.first { return (only.title, { closeMenu(); only.run() }) }
        guard !choices.isEmpty else { return nil }
        return ("Create", { closeMenu(); createMenuOpen = true })
    }

    /// Long-press +: the same creates, straight from the press (a shortcut, never the only way).
    private var newActions: [[AppBottomBar.QuickAction]] {
        let choices = createChoices
        return choices.count > 1 ? [choices] : []
    }

    /// The create menu's card. The picked sheet opens once this one has closed; presenting both in
    /// one pass would drop the second.
    private var createMenu: some View {
        ThorbisMenuCard(items: createChoices.map { choice in
            ThorbisMenuItem(choice.title, icon: choice.symbol, action: choice.run)
        }, title: "Create") { item in
            pendingCreate = item.action
            createMenuOpen = false
        }
    }

    private func openRecent(_ item: RecentItems.Item) {
        switch item.kind {
        case .job: store.requestedJobID = item.id
        case .customer: store.requestedRecord = .customer(item.id)
        }
    }

    /// Negative bottom padding that lowers the bar from the safe area to `AppBottomBar.bottomGap` off the
    /// screen edge. Phones without a home indicator keep the gap above the edge.
    private func barDrop(_ geometry: GeometryProxy) -> CGFloat {
        AppBottomBar.bottomGap - geometry.safeAreaInsets.bottom
    }

    private var bottomBar: some View {
        AppBottomBar(
            pinned: pinnedPlaces,
            switcher: AppMenuContent.switcher(current: MenuItem(rawValue: selectedTab), last: lastPlace, pinned: pinnedPlaces),
            current: selectedTab,
            menuOpen: menuOpen,
            select: { open($0) },
            openMenu: { setMenu(open: true) },
            search: { openBarSearch() },
            create: barCreate,
            sync: barSync,
            searchActions: searchActions,
            newActions: newActions,
            searchActive: barSearching,
            searchQuery: $barQuery,
            closeSearch: { closeBarSearch() }
        )
    }

    private var appMenu: some View {
        AppMenu(
            width: phoneWidth,
            circles: barCreate == nil ? 1 : 2,
            places: menuPlaces,
            local: localSections,
            current: selectedTab,
            open: { item in closeMenu(); open(item) },
            openLocal: { section in
                closeMenu()
                primaryTab = .more
                morePath = NavigationPath()
                morePath.append(PaperRoute.local(section))
            },
            manageBusinesses: { closeMenu(); workspace = true },
            settings: { closeMenu(); showSettings = true },
            close: closeMenu
        )
    }

    private func setMenu(open: Bool) {
        guard open != menuOpen else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.86)) {
            menuOpen = open
        }
    }

    private func closeMenu() { setMenu(open: false) }

    /// Only the selected place is mounted. Each place's stack lives in RootView state, so its
    /// pushed screens survive a switch. Hidden-but-mounted places leaked into VoiceOver: a
    /// NavigationStack's UIKit tree ignores SwiftUI's accessibilityHidden.
    private func placeStack() -> some View {
        place(selectedTab).id(selectedTab)
        // Kept off phonePlaces' long modifier chain, which is at the type checker's limit.
        .onChange(of: store.requestedSearch, initial: true) { openRequestedSearch(phone: true) }
    }

    /// The selected place, with the sheets and request handlers every place shares.
    private func phonePlaces() -> some View {
        placeStack()
        // The bottom bar is the way around; screens drop their top-left menu button.
        .environment(\.paperShowMenu, { Task { @MainActor in setMenu(open: true) } })
        .environment(\.paperMenuButton, false)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $search) { PaperGlobalSearch() }
        .sheet(isPresented: $newCustomer) { NewCustomerSheet() }
        .sheet(isPresented: $newEstimate) { NewEstimateView() }
        .sheet(item: $reviewScope) { SavedWorkReviewView(scope: $0) }
        .onChange(of: reviewScope?.isCurrent(session: session, api: api, media: pendingMedia, outbox: outbox) ?? true) { _, valid in
            if !valid { reviewScope = nil }
        }
        .background(Theme.background)
        .onChange(of: store.requestedJobID, initial: true) { openRequestedJob(phone: true) }
        .onChange(of: store.jobs) { openRequestedJob(phone: true) }
        .onChange(of: store.requestedSchedule) { schedulePath = NavigationPath(); primaryTab = .schedule }
        .onChange(of: store.requestedRecord, initial: true) { openRequestedRecord(phone: true) }
        .sheet(isPresented: $workspace) { WorkspaceSelectionView() }
        .sheet(isPresented: $createJob) { NewJobSheet() }
        #if DEBUG
        .sheet(isPresented: $previewInvoiceEditor) {
            NavigationStack { InvoiceLineEditorView(invoice: PaperPreview.invoice) { _ in } }
                .presentationDetents([.large])
        }
        .sheet(isPresented: $previewInvoiceDetail) {
            NavigationStack { InvoiceDetailView(id: PaperPreview.invoiceDetailPreviewID).paperDestinations() }
        }
        .sheet(isPresented: $previewEstimateRevision) {
            EstimateRevisionEditorView(estimate: PaperPreview.screen == "estimate-draft" ? PaperPreview.draftEstimate : PaperPreview.estimate) { _ in }
                .environmentObject(api).environmentObject(session).environmentObject(store)
        }
        .sheet(isPresented: $previewNewCustomer) { NewCustomerSheet() }
        .sheet(isPresented: $previewSignature) {
            SignatureCaptureSheet(title: "Approve $970.00", summary: "By signing, Danielle Marlowe approves \"AC repair and compressor replacement\" as shown.",
                                  jobID: PaperPreview.jobID, suggestedName: "Danielle Marlowe") { _ in nil }
        }
        .sheet(isPresented: $previewNewEstimate) {
            NewEstimateView(customerID: PaperPreview.customerID, jobID: PaperPreview.jobID, title: "AC not cooling")
        }
        #endif
        .task {
            await store.refresh(api)
            #if DEBUG
            guard PaperPreview.enabled else { return }
            if PaperPreview.screen == "new-estimate" { previewNewEstimate = true; return }
            if PaperPreview.screen == "offline" || PaperPreview.screen == "offline-job" {
                PaperPreviewProtocol.simulateNoSignal = true
                await session.revalidate()
                outbox.enqueue(.progress(.init(jobId: PaperPreview.jobID, to: "en_route", etaMinutes: 15)), policyVersion: session.policyVersion ?? 1)
                outbox.enqueue(.note(.init(jobId: PaperPreview.jobID, body: "Gate code 4417 — dog in the back yard.")), policyVersion: session.policyVersion ?? 1)
                if PaperPreview.screen == "offline-job", let job = store.jobs.first(where: { $0.id == PaperPreview.jobID }) {
                    primaryTab = .jobs
                    jobsPath.append(job)
                }
                return
            }
            if PaperPreview.screen == "invoice-editor" { previewInvoiceEditor = true; return }
            if PaperPreview.screen == "invoice-detail" || PaperPreview.screen == "invoice-payment" || PaperPreview.isPaymentRefundPreview { previewInvoiceDetail = true; return }
            if PaperPreview.screen == "estimate-revision" || PaperPreview.screen == "estimate-draft" { previewEstimateRevision = true; return }
            switch PaperPreview.screen {
            case "jobs": primaryTab = .jobs
            case "my-day", "schedule": primaryTab = .schedule
            case "customers": primaryTab = .customers
            case "menu", "more": primaryTab = .more
            case "search", "search-typed":
                RecentItems.shared.bind(actorID: session.user?.id ?? "preview", organizationID: session.activeOrganization?.id ?? "preview")
                RecentItems.shared.clear()
                RecentItems.shared.record(.customer, id: PaperPreview.customerID, title: "Danielle Marlowe", subtitle: "Customer")
                RecentItems.shared.record(.job, id: PaperPreview.jobID, title: "AC not cooling", subtitle: "JOB-2214 · Danielle Marlowe")
                if PaperPreview.screen == "search-typed" { barQuery = "AC" }
                barSearching = true
            case "inbox":
                primaryTab = .more
                morePath.append(PaperRoute.inbox)
            case "estimates": primaryTab = .more; morePath.append(PaperRoute.estimates)
            case "invoices": primaryTab = .more; morePath.append(PaperRoute.invoices)
            case "price-book": primaryTab = .more; morePath.append(PaperRoute.priceBook)
            case "team": primaryTab = .more; morePath.append(PaperRoute.team)
            case "customize-menu": primaryTab = .more; morePath.append(PaperRoute.customizeMenu)
            case "signature": previewSignature = true
            case "new-job": createJob = true
            case "create-menu": primaryTab = .jobs; createMenuOpen = true
            case "schedule-unscheduled": primaryTab = .schedule
            case "settings": showSettings = true
            case "app-menu", "app-menu-edit", "side-menu", "side-menu-search": menuOpen = true
            case "bar-live", "bar-syncing":
                // A tech mid-job on Jobs, with two changes saved on the phone.
                RecentItems.shared.bind(actorID: session.user?.id ?? "preview", organizationID: session.activeOrganization?.id ?? "preview")
                RecentItems.shared.clear()
                RecentItems.shared.record(.customer, id: "preview-customer-2", title: "Riverstone HVAC", subtitle: "Customer")
                RecentItems.shared.record(.job, id: PaperPreview.jobID, title: "AC not cooling", subtitle: "JOB-2214")
                if PaperPreview.screen == "bar-live" { PaperPreviewProtocol.simulateNoSignal = true; await session.revalidate() }
                outbox.enqueue(.note(.init(jobId: PaperPreview.jobID, body: "Gate code 4417.")), policyVersion: session.policyVersion ?? 1)
                outbox.enqueue(.note(.init(jobId: PaperPreview.jobID, body: "Replaced the capacitor.")), policyVersion: session.policyVersion ?? 1)
                primaryTab = .jobs
            case "attention": primaryTab = .more; morePath.append(PaperRoute.attention)
            case "estimate-detail", "estimate-draft-detail": primaryTab = .more; morePath.append(PaperRoute.estimate(PaperPreview.estimate.id))
            case "reports": primaryTab = .more; morePath.append(PaperRoute.reports)
            case "billing": primaryTab = .more; morePath.append(PaperRoute.billing)
            case "notices": primaryTab = .more; morePath.append(PaperRoute.notices)
            case "payments": primaryTab = .more; morePath.append(PaperRoute.payments)
            case "billing-detail":
                primaryTab = .more
                morePath.append(PaperRoute.billing)
                morePath.append(PaperRoute.billingSchedule("00000000-0000-4000-8000-000000009501"))
            case "new-customer": primaryTab = .customers; previewNewCustomer = true
            case "revenue": primaryTab = .more; morePath.append(PaperRoute.revenue)
            case "job", "job-invoice", "job-estimates", "job-activity", "job-media", "job-closeout", "job-invoice-empty", "job-assign", "job-followups",
                 "customer-view", "customer-view-estimates", "customer-view-invoice", "customer-view-details":
                if let job = store.jobs.first(where: { $0.id == PaperPreview.jobID }) {
                    primaryTab = .jobs
                    jobsPath.append(job)
                    if PaperPreview.screen == "job-closeout" { jobsPath.append(PaperRoute.closeout(jobID: job.id)) }
                    if PaperPreview.screen == "job-assign" { jobsPath.append(PaperRoute.assign(jobID: job.id)) }
                    if PaperPreview.screen == "job-followups" { jobsPath.append(PaperRoute.followUps(jobID: job.id)) }
                }
            case "customer", "customer-activity", "customer-records":
                if let customer = store.customers.first(where: { $0.id == PaperPreview.customerID }) {
                    primaryTab = .customers
                    customersPath.append(customer)
                }
            default: break
            }
            #endif
        }
    }

    private var primaryAccess: PrimaryTabAccess {
        PrimaryTabAccess(
            canViewJobs: session.can("job.view", feature: "jobs"),
            canViewCustomers: session.can("customer.view", feature: "core_crm")
        )
    }

    /// Tabs stay stable for every role; a tab the role cannot use says so (HIG-005).
    private var atTabRoot: Bool {
        switch selectedTab {
        case PrimaryTab.schedule.rawValue: schedulePath.isEmpty
        case PrimaryTab.jobs.rawValue: jobsPath.isEmpty
        case PrimaryTab.customers.rawValue: customersPath.isEmpty
        case PrimaryTab.more.rawValue: morePath.isEmpty
        case PrimaryTab.search.rawValue: false
        default: customPaths[selectedTab]?.isEmpty ?? true
        }
    }

    /// Every place is its own root; one that is not pinned takes the bar's switcher slot.
    private func open(_ item: MenuItem) {
        if !pinnedPlaces.contains(item) { lastPlace = item }
        selectedTab = item.rawValue
    }

    /// Proxy so tab switches can still be written as `primaryTab = .jobs`.
    private var primaryTab: PrimaryTab {
        get { PrimaryTab(rawValue: selectedTab) ?? .more }
        nonmutating set { selectedTab = newValue.rawValue }
    }

    @ViewBuilder private func place(_ id: String) -> some View {
        if let item = MenuItem(rawValue: id) {
            tabRoot(item)
        } else {
            NavigationStack(path: $morePath) { MoreView().paperDestinations() }
        }
    }

    @ViewBuilder private func tabRoot(_ item: MenuItem) -> some View {
        switch item {
        case .schedule: NavigationStack(path: $schedulePath) { gated(.schedule) { ScheduleView() }.paperDestinations() }
        case .jobs: NavigationStack(path: $jobsPath) { gated(.jobs) { JobsView() }.paperDestinations() }
        case .customers: NavigationStack(path: $customersPath) { gated(.customers) { CustomersView() }.paperDestinations() }
        default:
            NavigationStack(path: Binding(get: { customPaths[item.rawValue] ?? NavigationPath() },
                                          set: { customPaths[item.rawValue] = $0 })) {
                if let route = item.route { PaperRouteView(route: route).paperDestinations() }
            }
        }
    }

    /// Opens the job a Live Activity tap asked for, once the job list has it.
    private func openRequestedJob(phone: Bool) {
        guard let id = store.requestedJobID, session.can("job.view", feature: "jobs"),
              let job = id == JobActivityLink.nextJob ? PaperWorkGroups.next(store.jobs) : store.jobs.first(where: { $0.id == id })
        else { return }
        store.requestedJobID = nil
        if phone {
            let tabs = layout.visibleTabs(session)
            if tabs.contains(.schedule) {
                primaryTab = .schedule
                schedulePath = NavigationPath()
                schedulePath.append(job)
            } else if tabs.contains(.jobs) {
                primaryTab = .jobs
                jobsPath = NavigationPath()
                jobsPath.append(job)
            } else {
                primaryTab = .more
                morePath = NavigationPath()
                morePath.append(job)
            }
        } else {
            tab = .schedule
            path = NavigationPath()
            path.append(job)
        }
    }

    /// Opens search with the words a Siri or Shortcuts search asked for.
    private func openRequestedSearch(phone: Bool) {
        guard let query = store.requestedSearch else { return }
        store.requestedSearch = nil
        if phone {
            barQuery = query
            if !barSearching { openBarSearch() }
        } else {
            searchSeed = query
            search = true
        }
    }

    /// Opens the customer, estimate or invoice a link or notification asked for (RecordLink).
    private func openRequestedRecord(phone: Bool) {
        guard let record = store.requestedRecord else { return }
        store.requestedRecord = nil
        let access = record.access
        guard session.can(access.capability, feature: access.feature) else { return }
        var target = NavigationPath()
        switch record {
        case .customer(let id):
            target.append(store.customers.first { $0.id == id } ?? Customer(id: id, name: "Customer", archived: nil, createdAt: nil))
        case .estimate(let id): target.append(PaperRoute.estimate(id))
        case .invoice(let id): target.append(PaperRoute.invoice(id))
        }
        if phone {
            if case .customer = record, layout.visibleTabs(session).contains(.customers) {
                primaryTab = .customers
                customersPath = target
            } else {
                primaryTab = .more
                morePath = target
            }
        } else {
            if case .customer = record { tab = .customers } else { tab = .schedule }
            path = target
        }
    }

    @ViewBuilder private func gated<Content: View>(_ destination: PrimaryTab, @ViewBuilder content: () -> Content) -> some View {
        if primaryAccess.canOpen(destination) {
            content()
        } else {
            VStack(spacing: 0) {
                PaperHeader(title: destination.title, subtitle: "Access unavailable")
                PaperEmptyState(symbol: destination.symbol, title: "\(destination.title) unavailable",
                                message: primaryAccess.unavailableMessage(for: destination))
                Spacer()
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// The same places as the phone menu, in the person's Customize menu order, grouped like More.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { workspace = true } label: {
                HStack(spacing: 9) {
                    Image("ThorbisMark").resizable().scaledToFit().padding(4)
                        .frame(width: 24, height: 24).background(Theme.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Theme.border))
                        .accessibilityHidden(true)
                    Text(session.activeOrganization?.name ?? "Workspace").font(Theme.font(15, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 12))
                }.padding(.horizontal, 8).frame(minHeight: 44)
            }.padding(.bottom, 10)
            SidebarSearchButton { search = true }.padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(MenuItem.Group.allCases, id: \.self) { group in
                        let items = menuPlaces.filter { $0.group == group }
                        let local = group == .phone ? localSections : []
                        if !items.isEmpty || !local.isEmpty {
                            if group != .work {
                                Text(group.rawValue).font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
                                    .padding(.horizontal, 8).padding(.top, 14).padding(.bottom, 4)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            ForEach(items) { item in
                                sidebarRow(item.title, icon: item.symbol, target: tabletSection(item), count: sidebarCount(item))
                            }
                            ForEach(local, id: \.self) { section in
                                sidebarRow(section.title, icon: section.moreSymbol, target: .local(section))
                            }
                        }
                    }
                    menuRow("Settings", icon: "gearshape") { settings = true }.padding(.top, 14)
                }
            }
            .scrollIndicators(.hidden)
            SidebarAccountButton(name: session.user?.name ?? "") { settings = true }
                .padding(.top, 12)
        }.padding(.vertical, 14).padding(.horizontal, 10).frame(width: 244)
            .foregroundStyle(Theme.foreground).buttonStyle(.plain)
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
    }

    private func tabletSection(_ item: MenuItem) -> TabletSection {
        switch item {
        case .schedule: .schedule
        case .jobs: .jobs
        case .customers: .customers
        default: .place(item)
        }
    }

    private func sidebarCount(_ item: MenuItem) -> Int? {
        switch item {
        case .schedule: JobFiltering.schedule(store.jobs, range: .today).count
        case .jobs: store.jobs.count
        default: nil
        }
    }

    private func sidebarRow(_ title: String, icon: String, target: TabletSection, count: Int? = nil) -> some View {
        Button { path = NavigationPath(); tab = target } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 17)).frame(width: 18).foregroundStyle(Theme.muted)
                Text(title).font(Theme.font(15, weight: tab == target ? .medium : .regular))
                Spacer()
                if let count { Text("\(count)").font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.muted) }
            }.padding(.horizontal, 8).frame(minHeight: 44).background(tab == target ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }.accessibilityAddTraits(tab == target ? .isSelected : [])
    }

    private func menuRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 17)).frame(width: 18).foregroundStyle(Theme.muted)
                Text(title).font(Theme.font(15))
                Spacer(minLength: 0)
            }.padding(.horizontal, 8).frame(minHeight: 44).contentShape(Rectangle())
        }
    }
}

/// Secondary destinations pushed onto the current tab's stack.
enum PaperRoute: Hashable {
    case inbox, estimates, invoices, priceBook, revenue, drafts
    case local(LocalWorkspaceSection)
    case closeout(jobID: String)
    case team
    case reports
    case assign(jobID: String)
    case billing
    case billingSchedule(String)
    case notices
    case estimate(String)
    case invoice(String)
    case followUps(jobID: String)
    case customizeMenu
    case whatsNew
    case attention
    case payments
    case businessSetup
    case companyDetails
    case job(String)
    case media(jobID: String, assetID: String)
    case note(jobID: String, noteID: String)
    case contact(customerID: String, contactID: String)
    case location(customerID: String, locationID: String)
}

private struct PaperDestinations: ViewModifier {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController

    func body(content: Content) -> some View {
        content
            .thorbisDestination(for: Job.self) { JobDetailView(jobId: $0.id) }
            .thorbisDestination(for: Customer.self) { CustomerDetailView(customer: $0) }
            .thorbisDestination(for: PaperRoute.self) { PaperRouteView(route: $0) }
    }
}

/// The screen for a route, used both as a pushed destination and as a custom tab's root.
struct PaperRouteView: View {
    let route: PaperRoute
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController

    var body: some View {
        switch route {
        case .inbox:
            WorkspaceNoticesView(api: api, available: session.can("job.view", feature: "job_booking_notices")).id(session.generation)
        case .estimates: EstimatesView()
        case .invoices: InvoicesView()
        case .priceBook:
            WorkspacePriceBookView(api: api, canList: true, canViewDetail: session.can("organization.settings.edit", feature: "price_book")).id(session.generation)
        // Money and Reports are one place: Revenue first, then the reports.
        case .revenue: ReportsView(includesRevenue: true).id(session.generation)
        case .drafts:
            if let actor = session.user?.id, let org = session.activeOrganization?.id {
                InboxLocalDraftView(actorID: actor, organizationID: org)
            }
        case .closeout(let jobID): JobCloseoutView(jobID: jobID)
        case .team: TeamView()
        case .reports: ReportsView(includesRevenue: MenuItem.money.permitted(session), initialTab: "Operations")
        case .assign(let jobID): JobAssignmentView(jobID: jobID)
        case .billing: BillingSchedulesView()
        case .billingSchedule(let id): BillingScheduleDetailView(scheduleID: id)
        case .notices: NoticeSettingsView()
        case .estimate(let id): EstimateDetailView(id: id)
        case .invoice(let id): InvoiceDetailView(id: id)
        case .followUps(let jobID): JobFollowUpsView(jobID: jobID)
        case .customizeMenu: CustomizeMenuView()
        case .whatsNew: WhatsNewHistoryView()
        case .attention: NeedsAttentionView()
        case .payments: PaymentsSetupView()
        case .businessSetup: BusinessSetupView()
        case .companyDetails: CompanyDetailsView()
        case .job(let id): JobDetailView(jobId: id)
        case .media(let jobID, let assetID): JobMediaDetailView(jobID: jobID, assetID: assetID)
        case .note(let jobID, let noteID): JobNoteDetailView(jobID: jobID, noteID: noteID)
        case .contact(let customerID, let contactID): CustomerContactDetailView(customerID: customerID, contactID: contactID)
        case .location(let customerID, let locationID): ServiceLocationDetailView(customerID: customerID, locationID: locationID)
        case .local(let section):
            if let actor = session.user?.id, let org = session.activeOrganization?.id {
                LocalWorkspaceView(section: section, actorID: actor, organizationID: org)
            }
        }
    }
}

extension View {
    func paperDestinations() -> some View { modifier(PaperDestinations()) }
}

/// One result from the server's Search Gateway (`GET /v1/search`, packages/query SearchResult).
struct ServerSearchResult: Decodable, Identifiable, Hashable {
    let sourceId: String
    let resultType: String
    let entityId: String
    let title: String
    let subtitle: String?
    let status: String?
    var id: String { "\(sourceId):\(entityId)" }
}

struct ServerSearchPage: Decodable {
    let items: [ServerSearchResult]
    let nextCursor: String?
    let completeness: String?
}

extension APIClient {
    /// The Search Gateway pages with `nextCursor`. Keep asking until it stops, and refuse a blank or repeated cursor.
    func search(_ query: String, limit: Int = 25) async throws -> ServerSearchPage {
        let generation = requestGeneration
        var items: [ServerSearchResult] = []
        var cursor: String?
        var seen = Set<String>()
        var completeness: String?
        let queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(limit))]
        repeat {
            try Task.checkCancellation()
            guard generation == requestGeneration else { throw CancellationError() }
            let page: ServerSearchPage = try await send("GET", "/v1/search", queryItems: queryItems, cursor: cursor)
            items.append(contentsOf: page.items)
            completeness = page.completeness
            cursor = page.nextCursor
            if let cursor, cursor.isEmpty || !seen.insert(cursor).inserted {
                throw Problem(title: "Pagination cursor loop", status: nil, detail: "Repeated or empty cursor")
            }
        } while cursor != nil
        return ServerSearchPage(items: items, nextCursor: nil, completeness: completeness)
    }
}

/// Where a search result leads, for callers that push it themselves.
enum SearchDestination {
    case job(Job)
    case customer(Customer)
    case route(PaperRoute)
}

/// Paper 76: one field, results grouped by record type. The server's Search Gateway
/// searches the whole company; with no signal the phone's saved jobs and customers answer.
struct PaperGlobalSearch: View {
    var embedded = false
    /// Set by the iPhone's bottom search: its field owns the text, and a picked result is handed
    /// back to push on the current place instead of inside this view.
    var externalQuery: Binding<String>? = nil
    var openResult: ((SearchDestination) -> Void)? = nil
    /// Words to start with, from a Siri or Shortcuts search.
    var initialQuery = ""
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var server: [ServerSearchResult] = []
    @State private var serverQuery = ""
    @State private var serverFailed = false
    @State private var searching = false
    /// The sheet opens typing-ready: the field takes focus and the keyboard is up on arrival.
    @FocusState private var fieldFocused: Bool
    @ObservedObject private var recents = RecentItems.shared
    @State private var path = NavigationPath()
    /// Recent items that still resolve to a record this person can open.
    private enum RecentTarget { case job(Job), customer(Customer) }
    private var recentlyOpened: [(RecentItems.Item, RecentTarget)] {
        recents.items.prefix(5).compactMap { item in
            switch item.kind {
            case .job:
                guard session.can("job.view", feature: "jobs"), let job = store.jobs.first(where: { $0.id == item.id }) else { return nil }
                return (item, .job(job))
            case .customer:
                guard session.can("customer.view", feature: "core_crm"),
                      let customer = store.customers.first(where: { $0.id == item.id }) else { return nil }
                return (item, .customer(customer))
            }
        }
    }
    private var trimmed: String { (externalQuery?.wrappedValue ?? query).trimmingCharacters(in: .whitespacesAndNewlines) }
    private var useServer: Bool { !serverFailed && !session.isOffline && serverQuery == trimmed && !trimmed.isEmpty }
    private var jobs: [Job] { trimmed.isEmpty ? [] : JobFiltering.jobs(store.jobs, assignedTo: nil, search: trimmed) }
    private var customers: [Customer] { trimmed.isEmpty ? [] : store.customers.filter { $0.archived != true && $0.name.localizedCaseInsensitiveContains(trimmed) } }
    private var serverGroups: [(String, [ServerSearchResult])] {
        let order = ["job", "customer", "estimate", "invoice"]
        let grouped = Dictionary(grouping: server, by: \.resultType)
        return grouped.keys.sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }.map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        if openResult != nil {
            results
                .foregroundStyle(Theme.foreground)
                .scrollDismissesKeyboard(.interactively)
        } else {
            NavigationStack(path: $path) {
                results
                    .foregroundStyle(Theme.foreground)
                    .background(Theme.background)
                    .navigationTitle("Search")
                    .navigationBarTitleDisplayMode(.large)
                    .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Jobs, customers, invoices")
                    .searchFocused($fieldFocused)
                    .task {
                        if query.isEmpty, !initialQuery.isEmpty { query = initialQuery }
                        if !embedded { fieldFocused = true }
                    }
                    .toolbar {
                        if !embedded {
                            ThorbisToolbarItem(placement: .confirmationAction, prominent: true) { Button("Done") { dismiss() } }
                        }
                    }
                    .paperDestinations()
            }
        }
    }

    private func go(_ destination: SearchDestination) {
        if let openResult { return openResult(destination) }
        switch destination {
        case .job(let job): path.append(job)
        case .customer(let customer): path.append(customer)
        case .route(let route): path.append(route)
        }
    }

    private func searchLink<L: View>(_ job: Job, @ViewBuilder label: () -> L) -> some View {
        Button(action: { go(.job(job)) }, label: label)
    }
    private func searchLink<L: View>(_ customer: Customer, @ViewBuilder label: () -> L) -> some View {
        Button(action: { go(.customer(customer)) }, label: label)
    }
    private func searchLink<L: View>(_ route: PaperRoute, @ViewBuilder label: () -> L) -> some View {
        Button(action: { go(.route(route)) }, label: label)
    }

    private var results: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if trimmed.isEmpty {
                        // Before anything is typed, show what people most often come back to.
                        let canViewJobs = session.can("job.view", feature: "jobs")
                        let recent = (canViewJobs ? store.jobs : []).filter { !["completed", "canceled"].contains($0.status) }
                            .sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }.prefix(6)
                        // What this person opened last comes first, like Mail and Maps search.
                        let opened = recentlyOpened
                        if !opened.isEmpty {
                            PaperGroupHeader(title: "Recently opened").padding(.top, 8)
                            ForEach(opened, id: \.0) { item, destination in
                                Button {
                                    switch destination {
                                    case .job(let job): go(.job(job))
                                    case .customer(let customer): go(.customer(customer))
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: item.kind == .job ? "briefcase" : "person")
                                            .font(.system(size: 15)).foregroundStyle(Theme.muted).frame(width: 26)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title).font(Theme.font(15, weight: .medium)).lineLimit(1)
                                            Text(item.subtitle).font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(1)
                                        }
                                        Spacer(minLength: 8)
                                    }
                                    .frame(minHeight: 52).contentShape(Rectangle())
                                }
                                .buttonStyle(RowPressStyle())
                            }
                        }
                        if recent.isEmpty && opened.isEmpty {
                            PaperEmptyState(symbol: "magnifyingglass", title: "Search your workspace",
                                            message: "Jobs, customers, estimates and invoices across the company.")
                        } else if !recent.isEmpty {
                            PaperGroupHeader(title: "Open jobs").padding(.top, opened.isEmpty ? 8 : 16)
                            ForEach(Array(recent)) { job in
                                searchLink(job) {
                                    HStack(spacing: 12) {
                                        StatusRing(status: job.status).accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(job.title).font(Theme.font(15, weight: .medium)).lineLimit(1)
                                            Text("\(job.shortRef) · \(store.customerName(job.customerId)) · \(job.status.statusLabel)")
                                                .font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(1)
                                        }
                                        Spacer(minLength: 8)
                                    }
                                    .frame(minHeight: 52).contentShape(Rectangle())
                                }
                                .buttonStyle(RowPressStyle())
                            }
                        }
                    } else if useServer {
                        ForEach(serverGroups, id: \.0) { type, results in
                            PaperGroupHeader(title: label(type), count: results.count).padding(.top, 8)
                            ForEach(results) { result in serverRow(result) }
                        }
                        if server.isEmpty && !searching { PaperEmptyState.search(trimmed) }
                        if searching { SkeletonRows(count: 2, inset: 0).padding(.top, 8) }
                    } else {
                        if session.isOffline || serverFailed {
                            Label(session.isOffline ? "Offline · searching what's saved on this phone" : "Company search is unavailable · showing what's on this phone",
                                  systemImage: "iphone")
                                .font(Theme.font(12)).foregroundStyle(Theme.muted).padding(.top, 8)
                        }
                        if session.can("job.view", feature: "jobs"), !jobs.isEmpty {
                            PaperGroupHeader(title: "Jobs", count: jobs.count).padding(.top, 8)
                            ForEach(jobs) { job in
                                searchLink(job) {
                                    HStack(spacing: 10) {
                                        StatusRing(status: job.status)
                                        Text(job.shortRef).font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.muted)
                                            .frame(width: 66, alignment: .leading)
                                        Text(job.title).font(Theme.font(15, weight: .medium)).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }.frame(minHeight: 46).contentShape(Rectangle())
                                }.buttonStyle(RowPressStyle())
                            }
                        }
                        if session.can("customer.view", feature: "core_crm"), !customers.isEmpty {
                            PaperGroupHeader(title: "Customers", count: customers.count).padding(.top, 16)
                            ForEach(customers) { customer in
                                searchLink(customer) {
                                    HStack(spacing: 12) {
                                        Avatar(name: customer.name, size: 26)
                                        Text(customer.name).font(Theme.font(15, weight: .medium))
                                        Spacer(minLength: 0)
                                    }.frame(minHeight: 46).contentShape(Rectangle())
                                }.buttonStyle(RowPressStyle())
                            }
                        }
                        if searching { SkeletonRows(count: 3, inset: 0).padding(.top, 8) }
                        else if jobs.isEmpty && customers.isEmpty { PaperEmptyState.search(trimmed) }
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            .task(id: trimmed) {
                guard !trimmed.isEmpty, !session.isOffline else { return }
                // Wait for a pause in typing before asking the server.
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                searching = true
                defer { searching = false }
                do {
                    let page = try await api.search(trimmed)
                    guard !Task.isCancelled else { return }
                    server = page.items
                    serverQuery = trimmed
                    serverFailed = false
                } catch is CancellationError {
                } catch {
                    guard !Task.isCancelled else { return }
                    serverFailed = true
                }
            }
    }

    private func label(_ type: String) -> String {
        switch type {
        case "job": "Jobs"
        case "customer": "Customers"
        case "estimate": "Estimates"
        case "invoice": "Invoices"
        case "billing_schedule": "Billing schedules"
        case "payment": "Payments"
        case "location": "Locations"
        default: type.statusLabel
        }
    }

    @ViewBuilder private func serverRow(_ result: ServerSearchResult) -> some View {
        let row = HStack(spacing: 12) {
            Image(systemName: icon(result.resultType)).font(.system(size: 15)).foregroundStyle(Theme.muted).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title).font(Theme.font(15, weight: .medium)).lineLimit(1)
                if let subtitle = result.subtitle { Text(subtitle).font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if let status = result.status { Text(status.statusLabel).font(Theme.font(12)).foregroundStyle(Theme.muted) }
        }
        .frame(minHeight: 50).contentShape(Rectangle())
        switch result.resultType {
        case "job":
            NavigationLink(value: store.jobs.first { $0.id == result.entityId }
                           ?? Job(id: result.entityId, customerId: nil, title: result.title, status: result.status ?? "scheduled",
                                  createdAt: nil, updatedAt: nil, allowedTransitions: nil)) { row }.buttonStyle(RowPressStyle())
        case "customer":
            NavigationLink(value: store.customers.first { $0.id == result.entityId }
                           ?? Customer(id: result.entityId, name: result.title, archived: nil, createdAt: nil)) { row }.buttonStyle(RowPressStyle())
        case "estimate":
            NavigationLink(value: PaperRoute.estimate(result.entityId)) { row }.buttonStyle(RowPressStyle())
        case "invoice":
            NavigationLink(value: PaperRoute.invoice(result.entityId)) { row }.buttonStyle(RowPressStyle())
        case "billing_schedule":
            NavigationLink(value: PaperRoute.billingSchedule(result.entityId)) { row }.buttonStyle(RowPressStyle())
        default:
            row.opacity(0.6)
        }
    }

    private func icon(_ type: String) -> String {
        switch type {
        case "job": "briefcase"
        case "customer": "person"
        case "estimate": "doc.text"
        case "invoice": "doc.plaintext"
        default: "circle"
        }
    }
}
