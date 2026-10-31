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
    @EnvironmentObject private var layout: MenuLayout
    @EnvironmentObject private var whatsNew: WhatsNew
    /// The place showing on the phone: a MenuItem id, or "local-<section>" for a record kept on this phone.
    @State private var selectedTab = PrimaryTab.initial.rawValue
    /// Paths for every place other than Schedule, Jobs and Customers, keyed by place id.
    @State private var customPaths: [String: NavigationPath] = [:]
    /// Set once the launch place is settled, so a later capability refresh never moves the person.
    @State private var settledLaunchPlace = false
    /// The side drawer (2026-10-31, after the Claude and ChatGPT apps): open, and a drag in progress.
    @State private var drawerOpen = false
    @State private var drawerDrag: CGFloat = 0
    @AccessibilityFocusState private var drawerTitleFocus: Bool
    /// The drawer's Edit menu: the pinned places and their order.
    @State private var editingMenu = false
    /// Whether Inbox holds unread notices, as the server last said. Unknown shows no dot.
    @State private var inboxUnread = false
    /// The version of each recent job last seen in the drawer, so a change since then wears a dot.
    @State private var recentSeen: [String: String] = [:]
    /// iPhone search: a field floats low on the screen and results rise in a card above it.
    @State private var barSearching = false
    /// The floating search's field and results share this.
    @StateObject private var searchModel = SearchModel()
    @State private var newCustomer = false
    @State private var newEstimate = false
    /// The create menu, and the choice that runs once it has closed.
    @State private var createMenuOpen = false
    @State private var pendingCreate: (() -> Void)?
    @State private var reviewScope: SavedWorkScope?
    @ObservedObject private var recents = RecentItems.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showSettings = false
    @State private var schedulePath = NavigationPath()
    @State private var jobsPath = NavigationPath()
    @State private var customersPath = NavigationPath()
    @State private var search = false
    @State private var workspace = false
    @State private var createJob = false
    #if DEBUG
    @State private var previewInvoiceEditor = false
    @State private var previewInvoiceDetail = false
    @State private var previewEstimateRevision = false
    @State private var previewNewEstimate = false
    @State private var previewNewCustomer = false
    @State private var previewSignature = false
    /// Screenshot-only sheets for the redesigned forms (job-schedule, equipment-editor).
    @State private var previewFormSheet: String?
    #endif

    var body: some View {
        GeometryReader { geometry in
            navigation(wide: usesTabletLayout(width: geometry.size.width))
                .background(Theme.background)
        }
        #if DEBUG
        .modifier(PreviewLandscape())
        #endif
        // Widgets, the Control Center control and Spotlight read today's jobs from here.
        .modifier(GlanceSnapshotWriter())
        // The owner's company-wide pinned places and menu, when one has been saved.
        .task(id: session.activeOrganization?.id) {
            guard session.activeOrganization != nil else { return }
            await refreshInboxDot()
            #if DEBUG
            if PaperPreview.enabled { return }
            #endif
            await layout.refreshCompanyLayout(api: api)
        }
        // With no company or saved phone layout, the drawer's pinned places start from the person's role.
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
        // Screenshots and UI tests keep the standard layout (the owner Home screenshot sets its own).
        if PaperPreview.enabled { return }
        #endif
        guard session.phase == .ready else { return }
        layout.applyRoleDefaults(WorkRole(session), permitted: { $0.permitted(session) })
        openHomeAtLaunch()
    }

    /// Owners whose pinned places lead with Home open there; everyone else still opens on Today. Only
    /// at launch, only from the untouched first place, and never over a record a link asked for.
    private func openHomeAtLaunch() {
        guard !settledLaunchPlace else { return }
        settledLaunchPlace = true
        guard layout.visibleTabs(session).first == .home, selectedTab == PrimaryTab.initial.rawValue,
              schedulePath.isEmpty, !store.openedForRecord else { return }
        selectedTab = MenuItem.home.rawValue
    }

    /// iPad at regular width gets the sidebar and split columns; compact width (Slide Over, a
    /// narrow Split View) and every iPhone get the phone layout.
    @ViewBuilder private func navigation(wide: Bool) -> some View {
        if wide { TabletRoot() } else { phoneShell() }
    }

    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Regular width on an iPad, and room for a list beside a detail. Below that the phone layout.
    private func usesTabletLayout(width: CGFloat) -> Bool {
        #if DEBUG
        if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-compact") { return false }
        #endif
        return UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular && width >= 700
    }

    // MARK: - The drawer shell

    /// The phone's navigation: the drawer underneath, and the place showing as a card on top. Opening
    /// the drawer slides the card right, where it waits with rounded corners and a soft shadow; a tap
    /// or a drag on the card closes it. Reduce Motion keeps the card still and fades the drawer in.
    private func phoneShell() -> some View {
        GeometryReader { geometry in
            let width = DrawerMotion.width(screen: geometry.size.width, accessibilitySize: typeSize.isAccessibilitySize)
            let progress = DrawerMotion.progress(open: drawerOpen, drag: drawerDrag, width: width)
            let insets = geometry.safeAreaInsets
            ZStack(alignment: .leading) {
                if !reduceMotion, progress > 0 {
                    drawer(width: width, full: typeSize.isAccessibilitySize)
                        .frame(width: width)
                        .simultaneousGesture(closeDrag(width: width))
                }
                card(progress: progress, width: width, insets: insets)
                if reduceMotion, drawerOpen {
                    drawer(width: width, full: typeSize.isAccessibilitySize)
                        .frame(width: width)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Theme.card.ignoresSafeArea())
        }
        .sheet(isPresented: $createMenuOpen, onDismiss: {
            let run = pendingCreate
            pendingCreate = nil
            run?()
        }) { createMenu }
        .sheet(isPresented: $editingMenu) {
            AppMenuEditor { editingMenu = false }
                .padding(.top, 8)
                .presentationDetents([.large])
                .presentationBackground(Theme.background)
        }
    }

    private var drawerAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.36, dampingFraction: 0.86)
    }

    /// The place showing, as the drawer's card.
    private func card(progress: CGFloat, width: CGFloat, insets: EdgeInsets) -> some View {
        let shape = DrawerCardShape(radius: 44 * progress, top: insets.top, bottom: insets.bottom)
        return phonePlaces()
            .accessibilityHidden(barSearching || drawerOpen)
            .overlay { searchOverlay }
            .clipShape(shape)
            .background {
                shape.fill(Theme.background)
                    .shadow(color: .black.opacity(0.16 * progress), radius: 28, x: -6)
            }
            .overlay {
                // While open the card only closes the drawer: a tap, or a drag back to the left.
                if drawerOpen {
                    Color.black.opacity(reduceMotion ? 0.18 : 0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { closeDrawer() }
                        .gesture(closeDrag(width: width))
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .leading) {
                // A swipe from the left edge opens the drawer, on place roots only; pushed screens
                // keep the system back swipe.
                if atTabRoot, !drawerOpen, !barSearching {
                    Color.clear
                        .frame(width: 18)
                        .contentShape(Rectangle())
                        .gesture(openDrag(width: width))
                        .accessibilityHidden(true)
                }
            }
            .offset(x: reduceMotion ? 0 : width * progress)
    }

    private func drawer(width: CGFloat, full: Bool) -> some View {
        AppDrawer(
            title: session.activeOrganization?.name ?? "Thorbis",
            current: selectedTab,
            now: currentJob.map { ($0, store.customerName($0.customerId)) },
            savedWork: barSync,
            pinned: pinnedPlaces,
            places: otherPlaces,
            local: localSections,
            recents: drawerRecents,
            dots: placeDots,
            create: drawerCreate,
            settingsItems: settingsItems,
            showsClose: full,
            titleFocus: $drawerTitleFocus,
            search: { closeDrawer(thenRun: { openBarSearch() }) },
            close: { closeDrawer() },
            openPlace: { item in closeDrawer(thenRun: nil); open(item) },
            openLocal: { section in closeDrawer(thenRun: nil); openLocal(section) },
            openNow: { if let job = currentJob { closeDrawer(thenRun: nil); store.requestedJobID = job.id } },
            openSavedWork: { closeDrawer(thenRun: { reviewScope = savedWorkScope }) },
            openRecent: { item in
                markSeen(item)
                closeDrawer(thenRun: nil)
                openRecent(item)
            },
            editMenu: { closeDrawer(thenRun: { editingMenu = true }) }
        )
        // VoiceOver: the drawer is a modal group while open; the escape gesture closes it.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { closeDrawer() }
        .accessibilityIdentifier("drawer")
    }

    private func openDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard value.translation.width > 0 else { return }
                drawerDrag = min(width, value.translation.width)
            }
            .onEnded { value in
                let open = DrawerMotion.settlesOpen(wasOpen: false, translation: value.translation.width,
                                                    predicted: value.predictedEndTranslation.width, width: width)
                if open { openDrawer() } else { withAnimation(drawerAnimation) { drawerDrag = 0 } }
            }
    }

    private func closeDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .global)
            .onChanged { value in
                guard drawerOpen, abs(value.translation.width) > abs(value.translation.height) else { return }
                drawerDrag = max(-width, min(0, value.translation.width))
            }
            .onEnded { value in
                guard drawerOpen else { return }
                let open = DrawerMotion.settlesOpen(wasOpen: true, translation: drawerDrag,
                                                    predicted: drawerDrag == 0 ? 0 : value.predictedEndTranslation.width, width: width)
                if open { withAnimation(drawerAnimation) { drawerDrag = 0 } } else { closeDrawer() }
            }
    }

    private func openDrawer() {
        if barSearching { closeBarSearch() }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(drawerAnimation) {
            drawerOpen = true
            drawerDrag = 0
        }
        Task { await refreshInboxDot() }
        // VoiceOver lands on the drawer's title once it has slid in.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            drawerTitleFocus = true
        }
    }

    /// Closes the drawer, then runs `thenRun` (a sheet or search) once the card is back.
    private func closeDrawer(thenRun: (() -> Void)? = nil) {
        guard drawerOpen else { thenRun?(); return }
        markRecentsSeen()
        withAnimation(drawerAnimation) {
            drawerOpen = false
            drawerDrag = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(thenRun == nil ? 350 : 280))
            thenRun?()
            // VoiceOver returns to the place, whose first element is the menu circle.
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }

    /// The place root's menu circle: opens the drawer and wears its dot.
    private var drawerControl: PaperDrawerControl {
        PaperDrawerControl(open: { Task { @MainActor in openDrawer() } },
                           hasNews: !placeDots.isEmpty || drawerRecents.contains(where: \.changed) || (barSync?.needsPerson ?? false),
                           status: barSync?.words)
    }

    // MARK: - Drawer content

    /// The places the person pinned to the top of the drawer (the layout's tabs) this role can open.
    private var pinnedPlaces: [MenuItem] { layout.visibleTabs(session) }

    private var menuPlaces: [MenuItem] {
        AppMenuContent.places(tabs: pinnedPlaces, hidden: layout.hidden, order: layout.menuOrder,
                              permitted: { $0.permitted(session) })
    }

    /// Every other place, in the order the person set in Edit menu.
    private var otherPlaces: [MenuItem] {
        AppMenuContent.menu(tabs: pinnedPlaces, hidden: layout.hidden, order: layout.menuOrder,
                            permitted: { $0.permitted(session) })
    }

    /// Records kept only on this phone (Fleet, Equipment, Agreements, Team), as More listed them.
    private var localSections: [LocalWorkspaceSection] {
        guard session.user?.id != nil, session.activeOrganization?.id != nil else { return [] }
        return LocalWorkspaceSection.allCases.filter { session.can($0.requiredCapability, feature: $0.requiredFeature) }
    }

    /// Places that wear the drawer's dot: Inbox with unread notices, Needs attention with jobs that
    /// have no time (the part this phone already holds; unpaid and waiting documents need a read).
    private var placeDots: Set<MenuItem> {
        var dots: Set<MenuItem> = []
        if inboxUnread, MenuItem.inbox.permitted(session), !layout.hidden.contains(.inbox) { dots.insert(.inbox) }
        if MenuItem.attention.permitted(session), !layout.hidden.contains(.attention),
           !NeedsAttention.unscheduled(store.jobs).isEmpty { dots.insert(.attention) }
        return dots
    }

    /// The recently opened jobs and customers search shows, newest first.
    private var drawerRecents: [DrawerRecent] {
        recents.items.prefix(8).compactMap { item in
            switch item.kind {
            case .customer:
                guard session.can("customer.view", feature: "core_crm") else { return nil }
                return DrawerRecent(item: item)
            case .job:
                guard session.can("job.view", feature: "jobs") else { return nil }
                let job = store.jobs.first { $0.id == item.id }
                let waiting = outbox.entries.contains { $0.jobID == item.id }
                let changed = job.flatMap { job in recentSeen[item.id].map { $0 != (job.updatedAt ?? "") } } ?? false
                return DrawerRecent(item: item, status: job?.status, busy: job?.status == "in_progress" || waiting, changed: changed)
            }
        }
    }

    /// Records the version of each recent job as seen, so only later changes wear a dot.
    private func markRecentsSeen() {
        for item in recents.items where item.kind == .job {
            if let job = store.jobs.first(where: { $0.id == item.id }) { recentSeen[item.id] = job.updatedAt ?? "" }
        }
    }

    private func markSeen(_ item: RecentItems.Item) {
        guard item.kind == .job, let job = store.jobs.first(where: { $0.id == item.id }) else { return }
        recentSeen[item.id] = job.updatedAt ?? ""
    }

    /// Asks the server whether Inbox holds unread notices (one row is enough to know).
    private func refreshInboxDot() async {
        guard session.can("job.view", feature: "job_booking_notices") else { inboxUnread = false; return }
        if let page = try? await api.staffNotices(limit: 1) { inboxUnread = page.unreadState == .present }
    }

    /// The gear circle: every business (the current one checked), Add a business, Settings, Edit menu.
    private var settingsItems: [ThorbisMenuItem] {
        let businesses = session.organizations.map { organization in
            let current = organization.id == session.activeOrganization?.id
            return ThorbisMenuItem(organization.name, icon: "building.2", isSelected: current) {
                guard !current else { return }
                closeDrawer()
                Task { await session.selectOrganization(id: organization.id) }
            }
        }
        return businesses + [
            ThorbisMenuItem("Add a business", icon: "plus") { closeDrawer(thenRun: { workspace = true }) },
            ThorbisMenuItem("Settings", icon: "gearshape") { closeDrawer(thenRun: { showSettings = true }) },
            ThorbisMenuItem("Edit menu", icon: "slider.horizontal.3") { closeDrawer(thenRun: { editingMenu = true }) },
        ]
    }

    /// The drawer's ink capsule: New job when this person may book one (a long press lists the
    /// other creates); otherwise the create menu, or nothing.
    private var drawerCreate: PaperCreateAction? {
        let choices = createChoices
        guard !choices.isEmpty else { return nil }
        if let job = choices.first(where: { $0.title == "New job" }) {
            return PaperCreateAction(label: "New job", run: { closeDrawer(thenRun: job.run) }, choices: choices.map { choice in
                AppBottomBar.QuickAction(title: choice.title, symbol: choice.symbol) { closeDrawer(thenRun: choice.run) }
            })
        }
        if choices.count == 1, let only = choices.first {
            return PaperCreateAction(label: only.title, run: { closeDrawer(thenRun: only.run) }, choices: [])
        }
        return PaperCreateAction(label: "Create", run: { closeDrawer(thenRun: { createMenuOpen = true }) }, choices: [])
    }

    // MARK: - Search

    /// Frosts the place, raises the results card and floats the field low on the screen.
    @ViewBuilder private var searchOverlay: some View {
        if barSearching {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    Rectangle().fill(.ultraThinMaterial)
                        .overlay(Theme.background.opacity(0.55))
                        .ignoresSafeArea()
                        .onTapGesture { closeBarSearch() }
                        .accessibilityHidden(true)
                    VStack(spacing: 10) {
                        searchDrawer(height: max(geometry.size.height - 92, 240))
                        FloatingSearchBar(query: $searchModel.query, close: { closeBarSearch() }, submit: { searchModel.submit() })
                    }
                    .padding(.bottom, 8)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    /// Recent records and results in a card above the field. Drag its handle down to close.
    private func searchDrawer(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(Theme.border).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity, minHeight: 22)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 8).onEnded { if $0.translation.height > 60 { closeBarSearch() } })
                .accessibilityHidden(true)
            PaperGlobalSearch(model: searchModel, openResult: openSearchResult, focus: .of(place: selectedTab), actions: searchCommands)
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
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        searchModel.opened()
        withAnimation(searchAnimation) { barSearching = true }
    }

    private func closeBarSearch() {
        withAnimation(searchAnimation) {
            barSearching = false
            searchModel.query = ""
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
        default: customPaths[selectedTab, default: NavigationPath()].append(value)
        }
    }

    /// What typing in search can start: the creates, Settings, and every place this person can
    /// open, from the same lists the drawer uses. Each closes search first.
    private var searchCommands: [SearchAction] {
        SearchAction.standard(
            creates: createChoices.map { choice in (choice.title, choice.symbol, { closeBarSearch(); choice.run() }) },
            settings: { closeBarSearch(); showSettings = true },
            places: menuPlaces,
            openPlace: { place in closeBarSearch(); open(place) })
    }

    /// The job this person is on now: the drawer's Now row (the in-app twin of the Live Activity).
    private var currentJob: Job? {
        guard session.can("job.view", feature: "jobs") else { return nil }
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

    /// What this person may start from a header +, in a fixed order so + means the same on every screen.
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

    /// The header +: a small create menu. With one choice it starts that directly; with none it hides.
    /// A long press offers the same creates straight from the press.
    private var headerCreate: PaperCreateAction? {
        let choices = createChoices
        if choices.count == 1, let only = choices.first { return PaperCreateAction(label: only.title, run: only.run, choices: []) }
        guard !choices.isEmpty else { return nil }
        return PaperCreateAction(label: "Create", run: { createMenuOpen = true }, choices: choices)
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

    // MARK: - Places

    /// Only the selected place is mounted. Each place's stack lives in RootView state, so its
    /// pushed screens survive a switch. Hidden-but-mounted places leaked into VoiceOver: a
    /// NavigationStack's UIKit tree ignores SwiftUI's accessibilityHidden.
    private func placeStack() -> some View {
        place(selectedTab).id(selectedTab)
        // Kept off phonePlaces' long modifier chain, which is at the type checker's limit.
        .onChange(of: store.requestedSearch, initial: true) { openRequestedSearch(phone: true) }
        // The menu circle shows on a place's root only, never on a pushed screen.
        .environment(\.paperDrawer, atTabRoot && !barSearching ? drawerControl : nil)
        .onChange(of: recents.items) { _, items in
            // A record opened just now is seen as it is.
            if let first = items.first { markSeen(first) }
        }
    }

    /// The selected place, with the sheets and request handlers every place shares.
    private func phonePlaces() -> some View {
        placeStack()
        // The drawer is the way around. Anything that asked for "the menu" opens it; the floating
        // + pill stays off (paperMenuButton false), as New lives in the headers and the drawer.
        .environment(\.paperShowMenu, { Task { @MainActor in openDrawer() } })
        .environment(\.paperMenuButton, false)
        .environment(\.paperCreate, headerCreate)
        .environment(\.paperOpenPlace, { item in Task { @MainActor in open(item) } })
        .environment(\.paperManageBusinesses, { Task { @MainActor in workspace = true } })
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
        .onChange(of: store.requestedSchedule) {
            if drawerOpen { closeDrawer() }
            schedulePath = NavigationPath()
            primaryTab = .schedule
        }
        .onChange(of: store.requestedRecord, initial: true) { openRequestedRecord(phone: true) }
        .sheet(isPresented: $workspace) { WorkspaceSelectionView() }
        .sheet(isPresented: $createJob) { NewJobSheet() }
        #if DEBUG
        .modifier(PreviewSheets(invoiceEditor: $previewInvoiceEditor, invoiceDetail: $previewInvoiceDetail,
                                estimateRevision: $previewEstimateRevision, newCustomer: $previewNewCustomer,
                                formSheet: $previewFormSheet, signature: $previewSignature, newEstimate: $previewNewEstimate))
        #endif
        .task {
            await store.refresh(api)
            #if DEBUG
            await runPreview()
            #endif
        }
    }

    #if DEBUG
    /// Screenshot and UI-test setups (`--paper-preview --paper-preview-screen <name>`).
    private func runPreview() async {
        guard PaperPreview.enabled else { return }
        defer {
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-drawer-open") {
                seedPreviewRecents()
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    openDrawer()
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--perf-tab-cycle") {
            // Scripted place switching for the request-count measurement (PerfProbe).
            for tab in [PrimaryTab.customers, .schedule, .customers, .schedule, .customers] {
                try? await Task.sleep(for: .seconds(2))
                print("[perf] tab -> \(tab.rawValue)")
                primaryTab = tab
            }
            return
        }
        if PaperPreview.screen == "new-estimate" { previewNewEstimate = true; return }
        if PaperPreview.screen == "offline" || PaperPreview.screen.hasPrefix("offline-") {
            // The day was opened with signal: let today's read-ahead finish, then lose signal.
            await DayPrefetch.shared.waitUntilIdle()
            // Forget reads from moments ago, as if the tech walked into the basement later.
            api.invalidateRequests()
            PaperPreviewProtocol.simulateNoSignal = true
            await session.revalidate()
            outbox.enqueue(.progress(.init(jobId: PaperPreview.jobID, to: "en_route", etaMinutes: 15)), policyVersion: session.policyVersion ?? 1)
            outbox.enqueue(.note(.init(jobId: PaperPreview.jobID, body: "Gate code 4417 — dog in the back yard.")), policyVersion: session.policyVersion ?? 1)
            let job = store.jobs.first(where: { $0.id == PaperPreview.jobID })
            switch PaperPreview.screen {
            case "offline-job", "offline-job-money":
                if let job { primaryTab = .jobs; jobsPath.append(job) }
            case "offline-followups":
                outbox.enqueue(.followUp(.init(jobId: PaperPreview.jobID, kind: FieldFollowUpRequest.Kind.notifyOffice.rawValue,
                                               reason: "Compressor on order, customer away until Friday",
                                               nextAction: "Call the customer to book the fit")), policyVersion: session.policyVersion ?? 1)
                primaryTab = .jobs
                jobsPath.append(PaperRoute.followUps(jobID: PaperPreview.jobID))
            case "offline-estimate":
                previewPlace(.estimates, then: .estimate(PaperPreview.estimate.id))
            case "offline-invoice":
                previewPlace(.invoices, then: .invoice(PaperPreview.invoice.id))
            case "offline-customer":
                if let customer = store.customers.first(where: { $0.id == PaperPreview.customerID }) {
                    primaryTab = .customers
                    customersPath.append(customer)
                }
            case "offline-customers": primaryTab = .customers
            default: break
            }
            return
        }
        if ["invoice-editor", "invoice-editor-line"].contains(PaperPreview.screen) { previewInvoiceEditor = true; return }
        if PaperPreview.screen == "invoice-detail" || PaperPreview.screen == "invoice-payment" || PaperPreview.isPaymentRefundPreview { previewInvoiceDetail = true; return }
        if ["estimate-revision", "estimate-draft", "builder-options", "builder-picker", "builder-line"].contains(PaperPreview.screen) { previewEstimateRevision = true; return }
        switch PaperPreview.screen {
        case "jobs", "jobs-filters": primaryTab = .jobs
        case "my-day", "schedule": primaryTab = .schedule
        case "customers": primaryTab = .customers
        // More became the drawer: these open it over Today.
        case "menu", "more", "app-menu":
            seedPreviewRecents()
            try? await Task.sleep(for: .seconds(1))
            openDrawer()
        case "app-menu-edit": editingMenu = true
        case "search", "search-typed", "search-customers":
            // `search-customers` opens the same search over Customers, where customers lead.
            if PaperPreview.screen == "search-customers" { primaryTab = .customers }
            RecentItems.shared.bind(actorID: session.user?.id ?? "preview", organizationID: session.activeOrganization?.id ?? "preview")
            RecentItems.shared.clear()
            RecentItems.shared.record(.customer, id: PaperPreview.customerID, title: "Danielle Marlowe", subtitle: "Customer")
            RecentItems.shared.record(.job, id: PaperPreview.jobID, title: "AC not cooling", subtitle: "JOB-2214 · Danielle Marlowe")
            if PaperPreview.screen == "search-typed" { searchModel.query = "AC" }
            barSearching = true
        case "search-empty", "search-phone", "search-actions", "search-street", "search-offline":
            // Recent searches and records on the empty field; the typed screens show each kind of match.
            RecentItems.shared.bind(actorID: session.user?.id ?? "preview", organizationID: session.activeOrganization?.id ?? "preview")
            RecentItems.shared.clear()
            RecentItems.shared.record(.customer, id: PaperPreview.customerID, title: "Danielle Marlowe", subtitle: "Customer")
            RecentItems.shared.record(.job, id: PaperPreview.jobID, title: "AC not cooling", subtitle: "JOB-2214 · Danielle Marlowe")
            RecentItems.shared.recordSearch("water heater")
            RecentItems.shared.recordSearch("INV-2240")
            RecentItems.shared.recordSearch("Petrov")
            primaryTab = .jobs
            if PaperPreview.screen == "search-offline" {
                // Search once with signal so the lists are saved on the phone, then lose it.
                searchModel.opened()
                await searchModel.loadRecords(api: api, session: session, store: store)
                api.invalidateRequests()
                PaperPreviewProtocol.simulateNoSignal = true
                await session.revalidate()
            }
            searchModel.opened()
            barSearching = true
            switch PaperPreview.screen {
            case "search-phone": searchModel.query = "555-0413"
            case "search-actions": searchModel.query = "new"
            case "search-street": searchModel.query = "birch"
            case "search-offline": searchModel.query = "chen"
            default: break
            }
            if ProcessInfo.processInfo.arguments.contains("--paper-preview-search-submit") {
                // The same path as Return in the field: the top hit opens.
                try? await Task.sleep(for: .seconds(3))
                searchModel.submit()
            }
        case "inbox": previewPlace(.inbox)
        case "estimates": previewPlace(.estimates)
        case "invoices": previewPlace(.invoices)
        case "price-book": previewPlace(.priceBook)
        case "drafts": previewPlace(.drafts)
        case "local-fleet": openLocal(.fleet)
        case "local-equipment": openLocal(.equipment)
        case "local-agreements": openLocal(.agreements)
        case "team": previewPlace(.team)
        case "customize-menu": schedulePath.append(PaperRoute.customizeMenu)
        case "signature": previewSignature = true
        case "job-schedule", "equipment-editor", "equipment-sections": primaryTab = .jobs; previewFormSheet = PaperPreview.screen
        case "new-job", "book-job", "book-job-filled": createJob = true
        case "dispatch-board": primaryTab = .schedule
        case "create-menu": primaryTab = .jobs; createMenuOpen = true
        case "schedule-unscheduled": primaryTab = .schedule
        case "settings": showSettings = true
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
        case "attention": previewPlace(.attention)
        case "owner-home":
            layout.tabs = [.home, .schedule, .money, .customers]
            selectedTab = MenuItem.home.rawValue
        case "estimate-detail", "estimate-draft-detail": previewPlace(.estimates, then: .estimate(PaperPreview.estimate.id))
        case "reports": previewPlace(.reports)
        case "billing": previewPlace(.billing)
        case "notices": previewPlace(.notices)
        case "payments": schedulePath.append(PaperRoute.payments)
        case "billing-detail": previewPlace(.billing, then: .billingSchedule("00000000-0000-4000-8000-000000009501"))
        case "new-customer": primaryTab = .customers; previewNewCustomer = true
        case "revenue": previewPlace(.money)
        case "job", "job-invoice", "job-estimates", "job-activity", "job-notes", "job-media", "job-closeout", "job-invoice-empty", "job-assign", "job-followups",
             "job-history", "job-history-empty", "job-onsite",
             "customer-view", "customer-view-estimates", "customer-view-invoice", "customer-view-details":
            if let job = store.jobs.first(where: { $0.id == PaperPreview.jobID }) {
                primaryTab = .jobs
                jobsPath.append(job)
                if PaperPreview.screen == "job-closeout" { jobsPath.append(PaperRoute.closeout(jobID: job.id)) }
                if PaperPreview.screen == "job-assign" { jobsPath.append(PaperRoute.assign(jobID: job.id)) }
                if PaperPreview.screen == "job-followups" { jobsPath.append(PaperRoute.followUps(jobID: job.id)) }
            }
        case "customer", "customer-activity", "customer-records", "customer-jobs", "customer-money":
            if let customer = store.customers.first(where: { $0.id == PaperPreview.customerID }) {
                primaryTab = .customers
                customersPath.append(customer)
            }
        default: break
        }
    }

    /// Opens a place as its own root, with an optional screen pushed on it.
    private func previewPlace(_ item: MenuItem, then route: PaperRoute? = nil) {
        selectedTab = item.rawValue
        var path = NavigationPath()
        if let route { path.append(route) }
        customPaths[item.rawValue] = path
    }

    /// A few recent records so the drawer's Recents shows in screenshots.
    private func seedPreviewRecents() {
        RecentItems.shared.bind(actorID: session.user?.id ?? "preview", organizationID: session.activeOrganization?.id ?? "preview")
        guard RecentItems.shared.items.isEmpty else { return }
        RecentItems.shared.record(.customer, id: "preview-customer-2", title: "Riverstone HVAC", subtitle: "Customer")
        RecentItems.shared.record(.customer, id: PaperPreview.customerID, title: "Danielle Marlowe", subtitle: "Customer")
        if let other = store.jobs.first(where: { $0.id != PaperPreview.jobID }) {
            RecentItems.shared.record(.job, id: other.id, title: other.title, subtitle: other.shortRef)
        }
        RecentItems.shared.record(.job, id: PaperPreview.jobID, title: store.jobs.first { $0.id == PaperPreview.jobID }?.title ?? "AC not cooling",
                                  subtitle: "JOB-2214 · Danielle Marlowe")
    }
    #endif

    private var primaryAccess: PrimaryTabAccess {
        PrimaryTabAccess(
            canViewJobs: session.can("job.view", feature: "jobs"),
            canViewCustomers: session.can("customer.view", feature: "core_crm")
        )
    }

    /// Whether the place showing is on its first screen (where the menu circle and edge swipe live).
    private var atTabRoot: Bool {
        switch selectedTab {
        case PrimaryTab.schedule.rawValue: schedulePath.isEmpty
        case PrimaryTab.jobs.rawValue: jobsPath.isEmpty
        case PrimaryTab.customers.rawValue: customersPath.isEmpty
        default: customPaths[selectedTab]?.isEmpty ?? true
        }
    }

    /// Every place opens as its own root. Picking the place already showing returns to its root.
    private func open(_ item: MenuItem) {
        if selectedTab == item.rawValue { popToRoot(item.rawValue) }
        selectedTab = item.rawValue
    }

    private func openLocal(_ section: LocalWorkspaceSection) {
        let id = "local-\(section.rawValue)"
        if selectedTab == id { popToRoot(id) }
        selectedTab = id
    }

    private func popToRoot(_ id: String) {
        switch id {
        case PrimaryTab.schedule.rawValue: schedulePath = NavigationPath()
        case PrimaryTab.jobs.rawValue: jobsPath = NavigationPath()
        case PrimaryTab.customers.rawValue: customersPath = NavigationPath()
        default: customPaths[id] = NavigationPath()
        }
    }

    /// Proxy so place switches can still be written as `primaryTab = .jobs`.
    private var primaryTab: PrimaryTab {
        get { PrimaryTab(rawValue: selectedTab) ?? .schedule }
        nonmutating set { selectedTab = newValue.rawValue }
    }

    private func customPath(_ id: String) -> Binding<NavigationPath> {
        Binding(get: { customPaths[id] ?? NavigationPath() }, set: { customPaths[id] = $0 })
    }

    @ViewBuilder private func place(_ id: String) -> some View {
        if let item = MenuItem(rawValue: id) {
            tabRoot(item)
        } else if id.hasPrefix("local-"), let section = LocalWorkspaceSection(rawValue: String(id.dropFirst(6))) {
            NavigationStack(path: customPath(id)) {
                PaperRouteView(route: .local(section)).modifier(DrawerCircleInBar()).paperDestinations()
            }
        } else {
            tabRoot(.schedule)
        }
    }

    @ViewBuilder private func tabRoot(_ item: MenuItem) -> some View {
        switch item {
        case .schedule: NavigationStack(path: $schedulePath) { gated(.schedule) { ScheduleView() }.paperDestinations() }
        case .jobs: NavigationStack(path: $jobsPath) { gated(.jobs) { JobsView() }.paperDestinations() }
        case .customers: NavigationStack(path: $customersPath) { gated(.customers) { CustomersView() }.paperDestinations() }
        default:
            NavigationStack(path: customPath(item.rawValue)) {
                if let route = item.route {
                    // Places whose root shows a navigation bar carry the menu circle there, and
                    // their Paper header (Estimates, Invoices) then leaves it out.
                    PaperRouteView(route: route)
                        .modifier(DrawerCircleInBar(enabled: !item.drawerCircleInHeader))
                        .paperDestinations()
                }
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
            if drawerOpen { closeDrawer() }
            let tabs = layout.visibleTabs(session)
            if tabs.contains(.schedule) || !tabs.contains(.jobs) {
                primaryTab = .schedule
                schedulePath = NavigationPath()
                schedulePath.append(job)
            } else {
                primaryTab = .jobs
                jobsPath = NavigationPath()
                jobsPath.append(job)
            }
        }
    }

    /// Opens search with the words a Siri or Shortcuts search asked for.
    private func openRequestedSearch(phone: Bool) {
        guard let query = store.requestedSearch else { return }
        store.requestedSearch = nil
        if phone {
            if drawerOpen { closeDrawer() }
            if !barSearching { openBarSearch() }
            searchModel.query = query
        }
    }

    /// Opens the customer, estimate or invoice a link or notification asked for (RecordLink), on
    /// the place it belongs to when this person can open it, else on the place showing.
    private func openRequestedRecord(phone: Bool) {
        guard let record = store.requestedRecord else { return }
        store.requestedRecord = nil
        let access = record.access
        guard session.can(access.capability, feature: access.feature) else { return }
        var target = NavigationPath()
        let home: MenuItem
        switch record {
        case .customer(let id):
            target.append(store.customers.first { $0.id == id } ?? Customer(id: id, name: "Customer", archived: nil, createdAt: nil))
            home = .customers
        case .estimate(let id): target.append(PaperRoute.estimate(id)); home = .estimates
        case .invoice(let id): target.append(PaperRoute.invoice(id)); home = .invoices
        }
        guard phone else { return }
        if drawerOpen { closeDrawer() }
        if home == .customers, MenuItem.customers.permitted(session) {
            primaryTab = .customers
            customersPath = target
        } else if home.permitted(session) {
            selectedTab = home.rawValue
            customPaths[home.rawValue] = target
        } else {
            // No list of its own to sit on: it opens over the place showing, so Back returns there.
            switch selectedTab {
            case PrimaryTab.schedule.rawValue: schedulePath = target
            case PrimaryTab.jobs.rawValue: jobsPath = target
            case PrimaryTab.customers.rawValue: customersPath = target
            default: customPaths[selectedTab] = target
            }
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

}

/// The menu circle in the navigation bar, for place roots that show one (Inbox, Estimates, Reports,
/// Team, …). The screen inside then gets no drawer of its own, so a Paper header there draws no
/// second circle. Shows only while the shell offers the drawer, so pushed screens keep Back.
private struct DrawerCircleInBar: ViewModifier {
    var enabled = true
    @Environment(\.paperDrawer) private var drawer

    func body(content: Content) -> some View {
        if enabled, let drawer {
            content
                .environment(\.paperDrawer, nil)
                .toolbar {
                    ThorbisToolbarItem(placement: .topBarLeading) { DrawerMenuCircle(control: drawer) }
                }
        } else {
            content
        }
    }
}

#if DEBUG
/// Screenshot-only sheets, kept off the shell's long modifier chain.
private struct PreviewSheets: ViewModifier {
    @Binding var invoiceEditor: Bool
    @Binding var invoiceDetail: Bool
    @Binding var estimateRevision: Bool
    @Binding var newCustomer: Bool
    @Binding var formSheet: String?
    @Binding var signature: Bool
    @Binding var newEstimate: Bool
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $invoiceEditor) {
                NavigationStack { InvoiceLineEditorView(invoice: PaperPreview.invoice) { _ in } }
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $invoiceDetail) {
                NavigationStack { InvoiceDetailView(id: PaperPreview.invoiceDetailPreviewID).paperDestinations() }
            }
            .sheet(isPresented: $estimateRevision) {
                EstimateRevisionEditorView(estimate: PaperPreview.screen == "estimate-draft" ? PaperPreview.draftEstimate
                                           : PaperPreview.screen.hasPrefix("builder-") ? PaperPreview.optionsEstimate : PaperPreview.estimate) { _ in }
                    .environmentObject(api).environmentObject(session).environmentObject(store)
            }
            .sheet(isPresented: $newCustomer) { NewCustomerSheet() }
            .modifier(PreviewFormSheet(screen: $formSheet))
            .sheet(isPresented: $signature) {
                SignatureCaptureSheet(title: "Approve $970.00", summary: "By signing, Danielle Marlowe approves \"AC repair and compressor replacement\" as shown.",
                                      jobID: PaperPreview.jobID, suggestedName: "Danielle Marlowe") { _ in nil }
            }
            .sheet(isPresented: $newEstimate) {
                NewEstimateView(customerID: PaperPreview.customerID, jobID: PaperPreview.jobID, title: "AC not cooling")
            }
    }
}
#endif

/// Secondary destinations pushed onto the current place's stack.
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
    /// The owner's Home and the lists behind its figures.
    case home
    case homeList(HomeList)
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
            // tabletReadable: iPad's detail column caps pushed screens at a readable width.
            .thorbisDestination(for: Job.self) { JobDetailView(jobId: $0.id).tabletReadable() }
            .thorbisDestination(for: Customer.self) { CustomerDetailView(customer: $0).tabletReadable() }
            .thorbisDestination(for: PaperRoute.self) { PaperRouteView(route: $0).tabletReadable() }
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
        case .home: OwnerHomeView()
        case .homeList(let list): OwnerHomeListView(list: list)
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

#if DEBUG
/// Screenshot-only: presents a redesigned form sheet by preview screen name.
private struct PreviewFormSheet: ViewModifier {
    @Binding var screen: String?
    private var shown: Binding<Bool> { Binding(get: { screen != nil }, set: { if !$0 { screen = nil } }) }

    func body(content: Content) -> some View {
        content.sheet(isPresented: shown) {
            if screen == "job-schedule" {
                QuickScheduleSheet(jobID: PaperPreview.jobID)
            } else if screen == "equipment-sections" {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        CustomerMembershipSection(customerID: PaperPreview.customerID)
                        CustomerEquipmentSection(customerID: PaperPreview.customerID, locations: [])
                    }
                    .padding(.horizontal, PaperCardMetrics.margin).padding(.vertical, 24)
                }
                .background(Theme.background)
            } else {
                EquipmentEditor(customerID: PaperPreview.customerID, locations: [], existing: nil) {}
            }
        }
    }
}
#endif

#if DEBUG
/// Screenshot-only (`--paper-preview-landscape`): iPadOS's windowed mode refuses programmatic
/// rotation, so the app is laid out at the landscape size and turned a quarter. The capture is
/// turned back afterwards. Layout is real; safe areas are approximate.
private struct PreviewLandscape: ViewModifier {
    func body(content: Content) -> some View {
        if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-landscape") {
            GeometryReader { geometry in
                content
                    .frame(width: geometry.size.height, height: geometry.size.width)
                    .rotationEffect(.degrees(90))
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        } else {
            content
        }
    }
}
#endif
