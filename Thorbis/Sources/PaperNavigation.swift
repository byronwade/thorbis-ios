import SwiftUI

struct RootView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @State private var tab: TabletSection = .more
    @EnvironmentObject private var layout: MenuLayout
    @EnvironmentObject private var whatsNew: WhatsNew
    /// The selected phone tab: a MenuItem id, "more" or "search".
    @State private var selectedTab = PrimaryTab.initial.rawValue
    /// Paths for tabs an owner added (Inbox, Estimates, ...), keyed by MenuItem id.
    @State private var customPaths: [String: NavigationPath] = [:]
    @State private var drawerOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Live finger travel while dragging the menu open or closed.
    @State private var drawerDrag: CGFloat = 0
    @State private var showSettings = false
    @State private var path = NavigationPath()
    @State private var typedTabletPath: [PaperTypedJobsRoute] = []
    @StateObject private var typedTabletOwner = PaperTypedJobsOwner()
    @State private var schedulePath = NavigationPath()
    @State private var typedSchedulePath: [PaperTypedJobsRoute] = []
    @StateObject private var typedScheduleOwner = PaperTypedJobsOwner()
    @State private var jobsPath = NavigationPath()
    @State private var typedJobsPath: [PaperTypedJobsRoute] = []
    @StateObject private var typedJobsOwner = PaperTypedJobsOwner()
    @State private var customersPath = NavigationPath()
    @State private var morePath = NavigationPath()
    @State private var search = false
    @State private var settings = false
    @State private var workspace = false
    @State private var createJob = false
    @State private var priceBook = false
    @State private var drafts = false
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
        Group {
            if typedJobsExperiment {
                NavigationStack(path: Binding(get: { typedTabletPath }, set: { next in
                    let old = typedTabletPath
                    typedTabletPath = next
                    typedTabletOwner.changed(from: old, to: next)
                })) {
                    tabletRootContent
                        .environment(\.paperTypedJobsOwner, typedTabletOwner)
                        .navigationDestination(for: PaperTypedJobsRoute.self) { route in
                            PaperTypedDestination(route: route).environment(\.paperTypedJobsOwner, typedTabletOwner)
                        }
                }
            } else {
                NavigationStack(path: $path) { tabletRootContent.paperDestinations() }
            }
        }
        .sheet(isPresented: $search) { PaperGlobalSearch() }
        .sheet(isPresented: $settings) { NavigationStack { MoreView().paperDestinations().safeAreaInset(edge: .top) { HStack { Spacer(); Button("Done") { settings = false }.font(Theme.font(15, weight: .medium)).frame(minWidth: 44, minHeight: 44) }.padding(.horizontal, Theme.gutter) } } }
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
                case "job", "job-invoice": if let job = store.jobs.first(where: { $0.id == PaperPreview.jobID }) { pushTabletJob(job) }
                case "customer", "customer-activity", "customer-records": if let customer = store.customers.first(where: { $0.id == PaperPreview.customerID }) { pushTabletCustomer(customer) }
                default: break
                }
            }
            #endif
        }
        .onChange(of: store.requestedJobID, initial: true) { openRequestedJob(phone: false) }
        .onChange(of: store.jobs) { openRequestedJob(phone: false) }
        .onChange(of: store.requestedSchedule) { resetTabletPath(); tab = .schedule }
        .onChange(of: store.requestedRecord, initial: true) { openRequestedRecord(phone: false) }
        .onAppear {
            if session.can("job.view", feature: "jobs") { resetTabletPath(); tab = .schedule }
            else if session.can("customer.view", feature: "core_crm") { resetTabletPath(); tab = .customers }
        }
    }

    private var tabletRootContent: some View {
            Group {
                switch tab {
                case .schedule:
                    PaperTabletSchedule()
                case .jobs: JobsView()
                case .customers: CustomersView()
                case .more: MoreView()
                }
            }
            .environment(\.paperShowMenu, { Task { @MainActor in settings = true } })
            .background(Theme.background)
            .navigationDestination(isPresented: $priceBook) {
                WorkspacePriceBookView(api: api, canList: true, canViewDetail: session.can("organization.settings.edit", feature: "price_book")).id(session.generation)
            }
            .navigationDestination(isPresented: $drafts) {
                if let actor = session.user?.id, let org = session.activeOrganization?.id {
                    InboxLocalDraftView(actorID: actor, organizationID: org)
                }
            }
    }

    /// ChatGPT-style push (design.thorbis.com MA-03, MA-04): the menu sits underneath and the whole
    /// app slides right as one card that follows the finger both ways. The menu eases in from 30% of
    /// its width (parallax), the card dims to 40% and rounds to 24 with progress, and release settles
    /// on a critically damped spring from the finger's projected end. Transform and opacity only, so
    /// nothing re-lays out mid-gesture. With Reduce Motion nothing slides: the menu fades in over the app.
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
            phoneDrawer()
        }
        #else
        phoneDrawer()
        #endif
    }

    private func phoneDrawer() -> some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width * 0.82, 330)
            let base: CGFloat = drawerOpen ? width : 0
            let offset = min(max(base + drawerDrag, 0), width)
            let progress = width > 0 ? offset / width : 0
            ZStack(alignment: .leading) {
                SideMenu(open: { item in closeDrawer(); open(item) },
                         openRecent: { item in closeDrawer(); openRecent(item) },
                         search: { closeDrawer(); selectedTab = PrimaryTab.search.rawValue },
                         newJob: { closeDrawer(); createJob = true },
                         settings: { closeDrawer(); showSettings = true },
                         close: closeDrawer,
                         current: selectedTab,
                         switchWorkspace: session.organizations.count > 1 ? { closeDrawer(); workspace = true } : nil)
                    .frame(width: width)
                    .offset(x: reduceMotion ? 0 : -width * 0.3 * (1 - progress))
                    .opacity(reduceMotion ? progress : (progress > 0 ? 1 : 0))
                    .zIndex(reduceMotion ? 2 : 0)
                    .allowsHitTesting(drawerOpen)
                    .accessibilityHidden(!drawerOpen)
                phoneTabs()
                    .clipShape(RoundedRectangle(cornerRadius: reduceMotion ? 0 : 24 * progress, style: .continuous))
                    // D-017: a rounded figure on canvas gets a real rim that follows its radius.
                    .overlay {
                        RoundedRectangle(cornerRadius: reduceMotion ? 0 : 24 * progress, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                            .opacity(reduceMotion ? 0 : progress)
                            .allowsHitTesting(false)
                    }
                    // MA-04: while the menu is open the app is inert for VoiceOver too.
                    .accessibilityHidden(drawerOpen)
                    .overlay {
                        // D-021: a dim mix over the card; tap or drag it to close. It is the one
                        // element VoiceOver finds over the app while the menu is open.
                        Color.black.opacity(0.4 * progress)
                            .clipShape(RoundedRectangle(cornerRadius: reduceMotion ? 0 : 24 * progress, style: .continuous))
                            .contentShape(Rectangle())
                            .onTapGesture { closeDrawer() }
                            .allowsHitTesting(drawerOpen)
                            .accessibilityElement()
                            .accessibilityLabel("Close menu")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { closeDrawer() }
                            .accessibilityHidden(!drawerOpen)
                    }
                    .offset(x: reduceMotion ? 0 : offset)
                    .simultaneousGesture(drawerOpen ? closeDrag(width: width) : nil)
                    .overlay(alignment: .leading) {
                        // Swipe in from the left edge at a tab's first screen; elsewhere the
                        // system back swipe keeps that edge.
                        if !drawerOpen && atTabRoot {
                            Color.clear.frame(width: 24).contentShape(Rectangle())
                                .gesture(openDrag(width: width))
                                .accessibilityHidden(true)
                        }
                    }
                    .zIndex(1)
                    // Always full-bleed, so the card's corners meet the screen's and opening the
                    // menu never changes the layout under the finger.
                    .ignoresSafeArea(.container)
            }
            .background(Theme.surface.ignoresSafeArea())
            // Rotation or a new window size closes the menu instead of leaving it half-open.
            .onChange(of: geometry.size.width) { if drawerOpen { closeDrawer() } }
        }
    }

    private func openDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { drawerDrag = max(0, $0.translation.width) }
            .onEnded { value in
                let open = value.translation.width > width * 0.35 || value.predictedEndTranslation.width > width * 0.6
                settleDrawer(open: open)
            }
    }

    private func closeDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { drawerDrag = min(0, $0.translation.width) }
            .onEnded { value in
                let close = -value.translation.width > width * 0.3 || -value.predictedEndTranslation.width > width * 0.5
                settleDrawer(open: !close)
            }
    }

    private func settleDrawer(open: Bool) {
        if open != drawerOpen { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        // MA-03: critically damped (no bounce) at 0.3 s; Reduce Motion fades in 150 ms.
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 1)) {
            drawerOpen = open
            drawerDrag = 0
        }
    }

    private func phoneTabs() -> some View {
        TabView(selection: $selectedTab) {
            ForEach(layout.visibleTabs(session)) { item in
                Tab(item.tabTitle, systemImage: item.symbol, value: item.rawValue) { tabRoot(item) }
            }
            Tab(PrimaryTab.more.title, systemImage: PrimaryTab.more.symbol, value: PrimaryTab.more.rawValue) {
                NavigationStack(path: $morePath) { MoreView().paperDestinations() }
            }
            Tab(value: PrimaryTab.search.rawValue, role: .search) {
                PaperGlobalSearch(embedded: true)
            }
        }
        // The menu button and the avatar open the side menu.
        .environment(\.paperShowMenu, { Task { @MainActor in settleDrawer(open: true) } })
        .sheet(isPresented: $showSettings) { SettingsView() }
        .background(Theme.background)
        .onChange(of: store.requestedJobID, initial: true) { openRequestedJob(phone: true) }
        .onChange(of: store.jobs) { openRequestedJob(phone: true) }
        .onChange(of: store.requestedSchedule) { resetSchedulePath(); primaryTab = .schedule }
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
            if ProcessInfo.processInfo.arguments.contains("--typed-route-test-schedule-deep-link") {
                store.requestedJobID = PaperPreview.jobID
                return
            }
            if PaperPreview.screen == "new-estimate" { previewNewEstimate = true; return }
            if PaperPreview.screen == "offline" || PaperPreview.screen == "offline-job" {
                PaperPreviewProtocol.simulateNoSignal = true
                await session.revalidate()
                outbox.enqueue(.progress(.init(jobId: PaperPreview.jobID, to: "en_route", etaMinutes: 15)), policyVersion: session.policyVersion ?? 1)
                outbox.enqueue(.note(.init(jobId: PaperPreview.jobID, body: "Gate code 4417 — dog in the back yard.")), policyVersion: session.policyVersion ?? 1)
                if PaperPreview.screen == "offline-job", let job = store.jobs.first(where: { $0.id == PaperPreview.jobID }) {
                    primaryTab = .jobs
                    pushJobsJob(job)
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
            case "search": primaryTab = .search
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
            case "settings": showSettings = true
            case "side-menu", "side-menu-search":
                RecentItems.shared.bind(actorID: session.user?.id ?? "preview", organizationID: session.activeOrganization?.id ?? "preview")
                RecentItems.shared.clear()
                RecentItems.shared.record(.customer, id: "preview-customer-2", title: "Riverstone HVAC", subtitle: "Customer")
                RecentItems.shared.record(.job, id: "preview-job-3", title: "No heat upstairs", subtitle: "JOB-2208")
                RecentItems.shared.record(.job, id: "preview-job-2", title: "Water heater leak", subtitle: "JOB-2211")
                RecentItems.shared.record(.customer, id: PaperPreview.customerID, title: "Danielle Marlowe", subtitle: "Customer")
                RecentItems.shared.record(.job, id: PaperPreview.jobID, title: "AC not cooling", subtitle: "JOB-2214 · Danielle Marlowe")
                drawerOpen = true
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
            case "job", "job-invoice", "job-estimates", "job-activity", "job-media", "job-closeout", "job-invoice-empty", "job-assign", "job-followups":
                if let job = store.jobs.first(where: { $0.id == PaperPreview.jobID }) {
                    primaryTab = .jobs
                    pushJobsJob(job)
                    if PaperPreview.screen == "job-closeout" { pushJobsPaper(.closeout(jobID: job.id)) }
                    if PaperPreview.screen == "job-assign" { pushJobsPaper(.assign(jobID: job.id)) }
                    if PaperPreview.screen == "job-followups" { pushJobsPaper(.followUps(jobID: job.id)) }
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
        case PrimaryTab.schedule.rawValue: typedJobsExperiment ? typedSchedulePath.isEmpty : schedulePath.isEmpty
        case PrimaryTab.jobs.rawValue: typedJobsExperiment ? typedJobsPath.isEmpty : jobsPath.isEmpty
        case PrimaryTab.customers.rawValue: customersPath.isEmpty
        case PrimaryTab.more.rawValue: morePath.isEmpty
        case PrimaryTab.search.rawValue: false
        default: customPaths[selectedTab]?.isEmpty ?? true
        }
    }

    private func closeDrawer() { settleDrawer(open: false) }

    /// A tab if it is one; otherwise More with that place pushed.
    private func open(_ item: MenuItem) {
        if layout.visibleTabs(session).contains(item) {
            selectedTab = item.rawValue
        } else if let route = item.route {
            primaryTab = .more
            morePath = NavigationPath()
            morePath.append(route)
        }
    }

    private func openRecent(_ item: RecentItems.Item) {
        switch item.kind {
        case .job:
            guard session.can("job.view", feature: "jobs") else { return }
            if store.jobs.contains(where: { $0.id == item.id }) {
                store.requestedJobID = item.id
                return
            }
            // A job opened from company search may not be in the loaded list yet; open it by ID.
            let tabs = layout.visibleTabs(session)
            if tabs.contains(.schedule) {
                primaryTab = .schedule
                resetSchedulePath()
                pushSchedulePaper(.job(item.id))
            } else if tabs.contains(.jobs) {
                primaryTab = .jobs
                resetJobsPath()
                pushJobsPaper(.job(item.id))
            } else {
                primaryTab = .more
                morePath = NavigationPath()
                morePath.append(PaperRoute.job(item.id))
            }
        case .customer:
            guard session.can("customer.view", feature: "core_crm") else { return }
            // The list cache leaves out archived customers, so fall back to the saved entry and let
            // the detail screen load the rest.
            let customer = store.customers.first(where: { $0.id == item.id })
                ?? Customer(id: item.id, name: item.title, archived: nil, createdAt: nil)
            if layout.visibleTabs(session).contains(.customers) {
                primaryTab = .customers
                customersPath = NavigationPath()
                customersPath.append(customer)
            } else {
                primaryTab = .more
                morePath = NavigationPath()
                morePath.append(customer)
            }
        }
    }

    /// Proxy so tab switches can still be written as `primaryTab = .jobs`.
    private var primaryTab: PrimaryTab {
        get { PrimaryTab(rawValue: selectedTab) ?? .more }
        nonmutating set { selectedTab = newValue.rawValue }
    }

    @ViewBuilder private func tabRoot(_ item: MenuItem) -> some View {
        switch item {
        case .schedule:
            if typedJobsExperiment {
                NavigationStack(path: Binding(get: { typedSchedulePath }, set: { next in
                    let old = typedSchedulePath
                    typedSchedulePath = next
                    typedScheduleOwner.changed(from: old, to: next)
                })) {
                    gated(.schedule) { ScheduleView() }
                        .environment(\.paperTypedJobsOwner, typedScheduleOwner)
                        .navigationDestination(for: PaperTypedJobsRoute.self) { route in
                            PaperTypedDestination(route: route).environment(\.paperTypedJobsOwner, typedScheduleOwner)
                        }
                }
            } else {
                NavigationStack(path: $schedulePath) { gated(.schedule) { ScheduleView() }.paperDestinations() }
            }
        case .jobs:
            if typedJobsExperiment {
                NavigationStack(path: Binding(get: { typedJobsPath }, set: { next in
                    let old = typedJobsPath
                    typedJobsPath = next
                    typedJobsOwner.changed(from: old, to: next)
                })) {
                    gated(.jobs) { JobsView() }
                        .environment(\.paperTypedJobsOwner, typedJobsOwner)
                        .navigationDestination(for: PaperTypedJobsRoute.self) { route in
                            PaperTypedDestination(route: route).environment(\.paperTypedJobsOwner, typedJobsOwner)
                        }
                }
            } else {
                NavigationStack(path: $jobsPath) { gated(.jobs) { JobsView() }.paperDestinations() }
            }
        case .customers: NavigationStack(path: $customersPath) { gated(.customers) { CustomersView() }.paperDestinations() }
        default:
            NavigationStack(path: Binding(get: { customPaths[item.rawValue] ?? NavigationPath() },
                                          set: { customPaths[item.rawValue] = $0 })) {
                if let route = item.route { PaperRouteView(route: route).paperDestinations() }
            }
        }
    }

    private func resetTabletPath() {
        if typedJobsExperiment { typedTabletOwner.discardPendingPop(); typedTabletPath = [] } else { path = NavigationPath() }
    }

    private func pushTabletJob(_ job: Job) {
        if typedJobsExperiment { typedTabletOwner.discardPendingPop(); typedTabletPath.append(.job(job)) } else { path.append(job) }
    }

    private func pushTabletCustomer(_ customer: Customer) {
        if typedJobsExperiment { typedTabletOwner.discardPendingPop(); typedTabletPath.append(.customer(customer)) } else { path.append(customer) }
    }

    private func resetSchedulePath() {
        if typedJobsExperiment { typedScheduleOwner.discardPendingPop(); typedSchedulePath = [] } else { schedulePath = NavigationPath() }
    }

    private func pushScheduleJob(_ job: Job) {
        if typedJobsExperiment { typedScheduleOwner.discardPendingPop(); typedSchedulePath.append(.job(job)) } else { schedulePath.append(job) }
    }

    private func pushSchedulePaper(_ route: PaperRoute) {
        if typedJobsExperiment { typedScheduleOwner.discardPendingPop(); typedSchedulePath.append(.paper(route)) } else { schedulePath.append(route) }
    }

    private func resetJobsPath() {
        if typedJobsExperiment { typedJobsOwner.discardPendingPop(); typedJobsPath = [] } else { jobsPath = NavigationPath() }
    }

    private func pushJobsJob(_ job: Job) {
        if typedJobsExperiment { typedJobsOwner.discardPendingPop(); typedJobsPath.append(.job(job)) } else { jobsPath.append(job) }
    }

    private func pushJobsPaper(_ route: PaperRoute) {
        if typedJobsExperiment { typedJobsOwner.discardPendingPop(); typedJobsPath.append(.paper(route)) } else { jobsPath.append(route) }
    }

    private var typedJobsExperiment: Bool { PaperTypedRouteExperiment.enabled }

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
                resetSchedulePath()
                pushScheduleJob(job)
            } else if tabs.contains(.jobs) {
                primaryTab = .jobs
                resetJobsPath()
                pushJobsJob(job)
            } else {
                primaryTab = .more
                morePath = NavigationPath()
                morePath.append(job)
            }
        } else {
            tab = .schedule
            resetTabletPath()
            pushTabletJob(job)
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
            if typedJobsExperiment {
                resetTabletPath()
                switch record {
                case .customer(let id): pushTabletCustomer(store.customers.first { $0.id == id } ?? Customer(id: id, name: "Customer", archived: nil, createdAt: nil))
                case .estimate(let id): typedTabletPath.append(.paper(.estimate(id)))
                case .invoice(let id): typedTabletPath.append(.paper(.invoice(id)))
                }
            } else { path = target }
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
            if session.can("job.view", feature: "jobs") {
                sidebarRow("Schedule", icon: "calendar", target: .schedule, count: JobFiltering.schedule(store.jobs, range: .today).count)
                sidebarRow("Jobs", icon: "briefcase", target: .jobs, count: store.jobs.count)
            }
            if session.can("customer.view", feature: "core_crm") { sidebarRow("Customers", icon: "person.2", target: .customers) }
            menuRow("Message drafts", icon: "bubble.left") { drafts = true }
            if session.can("pricebook.view", feature: "price_book") { menuRow("Price book", icon: "book.closed") { priceBook = true } }
            menuRow("Workspace tools", icon: "slider.horizontal.3") { settings = true }
            Spacer()
            SidebarAccountButton(name: session.user?.name ?? "") { settings = true }
                .padding(.top, 12)
        }.padding(.vertical, 14).padding(.horizontal, 10).frame(width: 244)
            .foregroundStyle(Theme.foreground).buttonStyle(.plain)
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
    }

    private func sidebarRow(_ title: String, icon: String, target: TabletSection, count: Int? = nil) -> some View {
        Button { resetTabletPath(); tab = target } label: {
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
            .navigationDestination(for: Job.self) { JobDetailView(jobId: $0.id) }
            .navigationDestination(for: Customer.self) { CustomerDetailView(customer: $0) }
            .navigationDestination(for: PaperRoute.self) { PaperRouteView(route: $0) }
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
        case .revenue: WorkspaceRevenueView(api: api, available: true).id(session.generation)
        case .drafts:
            if let actor = session.user?.id, let org = session.activeOrganization?.id {
                InboxLocalDraftView(actorID: actor, organizationID: org)
            }
        case .closeout(let jobID): JobCloseoutView(jobID: jobID)
        case .team: TeamView()
        case .reports: ReportsView()
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

/// Paper 76: one field, results grouped by record type. The server's Search Gateway
/// searches the whole company; with no signal the phone's saved jobs and customers answer.
struct PaperGlobalSearch: View {
    var embedded = false
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var server: [ServerSearchResult] = []
    @State private var serverQuery = ""
    @State private var serverFailed = false
    @State private var searching = false
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
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var useServer: Bool { !serverFailed && !session.isOffline && serverQuery == trimmed && !trimmed.isEmpty }
    private var jobs: [Job] { trimmed.isEmpty ? [] : JobFiltering.jobs(store.jobs, assignedTo: nil, search: trimmed) }
    private var customers: [Customer] { trimmed.isEmpty ? [] : store.customers.filter { $0.archived != true && $0.name.localizedCaseInsensitiveContains(trimmed) } }
    private var serverGroups: [(String, [ServerSearchResult])] {
        let order = ["job", "customer", "estimate", "invoice"]
        let grouped = Dictionary(grouping: server, by: \.resultType)
        return grouped.keys.sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }.map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack(path: $path) {
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
                                    case .job(let job): path.append(job)
                                    case .customer(let customer): path.append(customer)
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
                                PaperCompatibleLink(value: job) {
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
                                PaperCompatibleLink(value: job) {
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
                                PaperCompatibleLink(value: customer) {
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
            .foregroundStyle(Theme.foreground)
            .background(Theme.background)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Jobs, customers, invoices")
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .paperDestinations()
        }
        .environment(\.paperTypedJobsOwner, nil)
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
            PaperCompatibleLink(value: store.jobs.first { $0.id == result.entityId }
                           ?? Job(id: result.entityId, customerId: nil, title: result.title, status: result.status ?? "scheduled",
                                  createdAt: nil, updatedAt: nil, allowedTransitions: nil)) { row }.buttonStyle(RowPressStyle())
        case "customer":
            PaperCompatibleLink(value: store.customers.first { $0.id == result.entityId }
                           ?? Customer(id: result.entityId, name: result.title, archived: nil, createdAt: nil)) { row }.buttonStyle(RowPressStyle())
        case "estimate":
            PaperCompatibleLink(value: PaperRoute.estimate(result.entityId)) { row }.buttonStyle(RowPressStyle())
        case "invoice":
            PaperCompatibleLink(value: PaperRoute.invoice(result.entityId)) { row }.buttonStyle(RowPressStyle())
        case "billing_schedule":
            PaperCompatibleLink(value: PaperRoute.billingSchedule(result.entityId)) { row }.buttonStyle(RowPressStyle())
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
