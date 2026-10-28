import SwiftUI

struct RootView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @State private var tab: TabletSection = .more
    @EnvironmentObject private var layout: MenuLayout
    /// The selected phone tab: a MenuItem id, "more" or "search".
    @State private var selectedTab = PrimaryTab.initial.rawValue
    /// Paths for tabs an owner added (Inbox, Estimates, ...), keyed by MenuItem id.
    @State private var customPaths: [String: NavigationPath] = [:]
    @State private var path = NavigationPath()
    @State private var schedulePath = NavigationPath()
    @State private var jobsPath = NavigationPath()
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
                }
            }
            .environment(\.paperShowMenu, { Task { @MainActor in settings = true } })
            .background(Theme.background)
            .paperDestinations()
            .navigationDestination(isPresented: $priceBook) {
                WorkspacePriceBookView(api: api, canList: true, canViewDetail: session.can("organization.settings.edit", feature: "price_book")).id(session.generation)
            }
            .navigationDestination(isPresented: $drafts) {
                if let actor = session.user?.id, let org = session.activeOrganization?.id {
                    InboxLocalDraftView(actorID: actor, organizationID: org)
                }
            }
        }
        .sheet(isPresented: $search) { PaperGlobalSearch() }
        .sheet(isPresented: $settings) { NavigationStack { MoreView().paperDestinations().safeAreaInset(edge: .top) { HStack { Spacer(); Button("Done") { settings = false }.font(Theme.font(15, weight: .semibold)).frame(minWidth: 44, minHeight: 44) }.padding(.horizontal, Theme.gutter) } } }
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
                InvoiceDetailView(id: PaperPreview.invoiceDetailPreviewID)
            }
        }
        .sheet(isPresented: $previewEstimateRevision) {
            EstimateRevisionEditorView(estimate: PaperPreview.estimate) { _ in }
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
                if PaperPreview.screen == "estimate-revision" {
                    previewEstimateRevision = true
                    return
                }
                switch PaperPreview.screen {
                case "jobs": tab = .jobs
                case "my-day": tab = .schedule
                case "customers": tab = .customers
                case "menu", "more": settings = true
                case "job", "job-invoice": if let job = store.jobs.first(where: { $0.id == PaperPreview.jobID }) { path.append(job) }
                case "customer": if let customer = store.customers.first(where: { $0.id == PaperPreview.customerID }) { path.append(customer) }
                default: break
                }
            }
            #endif
        }
        .onChange(of: store.requestedJobID, initial: true) { openRequestedJob(phone: false) }
        .onChange(of: store.jobs) { openRequestedJob(phone: false) }
        .onChange(of: store.requestedSchedule) { path = NavigationPath(); tab = .schedule }
        .onAppear {
            if session.can("job.view", feature: "jobs") { path = NavigationPath(); tab = .schedule }
            else if session.can("customer.view", feature: "core_crm") { path = NavigationPath(); tab = .customers }
        }
    }

    private func phoneNavigation() -> some View {
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
        .environment(\.paperShowMenu, { Task { @MainActor in primaryTab = .more } })
        .background(Theme.background)
        .onChange(of: store.requestedJobID, initial: true) { openRequestedJob(phone: true) }
        .onChange(of: store.jobs) { openRequestedJob(phone: true) }
        .onChange(of: store.requestedSchedule) { schedulePath = NavigationPath(); primaryTab = .schedule }
        .sheet(isPresented: $workspace) { WorkspaceSelectionView() }
        .sheet(isPresented: $createJob) { NewJobSheet() }
        #if DEBUG
        .sheet(isPresented: $previewInvoiceEditor) {
            NavigationStack { InvoiceLineEditorView(invoice: PaperPreview.invoice) { _ in } }
                .presentationDetents([.large])
        }
        .sheet(isPresented: $previewInvoiceDetail) { NavigationStack { InvoiceDetailView(id: PaperPreview.invoiceDetailPreviewID) } }
        .sheet(isPresented: $previewEstimateRevision) {
            EstimateRevisionEditorView(estimate: PaperPreview.estimate) { _ in }
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
            if PaperPreview.screen == "estimate-revision" { previewEstimateRevision = true; return }
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
            case "attention": primaryTab = .more; morePath.append(PaperRoute.attention)
            case "estimate-detail": primaryTab = .more; morePath.append(PaperRoute.estimate(PaperPreview.estimate.id))
            case "reports": primaryTab = .more; morePath.append(PaperRoute.reports)
            case "billing": primaryTab = .more; morePath.append(PaperRoute.billing)
            case "notices": primaryTab = .more; morePath.append(PaperRoute.notices)
            case "billing-detail":
                primaryTab = .more
                morePath.append(PaperRoute.billing)
                morePath.append(PaperRoute.billingSchedule("00000000-0000-4000-8000-000000009501"))
            case "new-customer": primaryTab = .customers; previewNewCustomer = true
            case "revenue": primaryTab = .more; morePath.append(PaperRoute.revenue)
            case "job", "job-invoice", "job-estimates", "job-activity", "job-media", "job-closeout", "job-invoice-empty", "job-assign", "job-followups":
                if let job = store.jobs.first(where: { $0.id == PaperPreview.jobID }) {
                    primaryTab = .jobs
                    jobsPath.append(job)
                    if PaperPreview.screen == "job-closeout" { jobsPath.append(PaperRoute.closeout(jobID: job.id)) }
                    if PaperPreview.screen == "job-assign" { jobsPath.append(PaperRoute.assign(jobID: job.id)) }
                    if PaperPreview.screen == "job-followups" { jobsPath.append(PaperRoute.followUps(jobID: job.id)) }
                }
            case "customer":
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
    /// Proxy so tab switches can still be written as `primaryTab = .jobs`.
    private var primaryTab: PrimaryTab {
        get { PrimaryTab(rawValue: selectedTab) ?? .more }
        nonmutating set { selectedTab = newValue.rawValue }
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
                        .frame(width: 24, height: 24).background(Theme.card, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.border))
                        .accessibilityHidden(true)
                    Text(session.activeOrganization?.name ?? "Workspace").font(Theme.font(14, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 10))
                }.padding(.horizontal, 8).frame(minHeight: 44)
            }.padding(.bottom, 10)
            Button { search = true } label: {
                HStack(spacing: 8) { Image(systemName: "magnifyingglass"); Text("Search"); Spacer() }
                    .font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.horizontal, 10)
                    .frame(minHeight: 44).background(Theme.fill, in: RoundedRectangle(cornerRadius: 9))
            }.padding(.bottom, 12)
            if session.can("job.view", feature: "jobs") {
                sidebarRow("Schedule", icon: "calendar", target: .schedule, count: JobFiltering.schedule(store.jobs, range: .today).count)
                sidebarRow("Jobs", icon: "briefcase", target: .jobs, count: store.jobs.count)
            }
            if session.can("customer.view", feature: "core_crm") { sidebarRow("Customers", icon: "person.2", target: .customers) }
            menuRow("Message drafts", icon: "bubble.left") { drafts = true }
            if session.can("pricebook.view", feature: "price_book") { menuRow("Price book", icon: "book.closed") { priceBook = true } }
            menuRow("Workspace tools", icon: "slider.horizontal.3") { settings = true }
            Spacer()
            Button { settings = true } label: {
                HStack(spacing: 9) {
                    Avatar(name: session.user?.name ?? "", size: 26)
                    Text(session.user?.name ?? "Account").font(Theme.font(14)).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "gearshape").font(.system(size: 15)).foregroundStyle(Theme.muted)
                }.padding(.horizontal, 8).frame(minHeight: 44)
            }
        }.padding(.vertical, 14).padding(.horizontal, 10).frame(width: 244)
            .foregroundStyle(Theme.foreground).buttonStyle(.plain)
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
    }

    private func sidebarRow(_ title: String, icon: String, target: TabletSection, count: Int? = nil) -> some View {
        Button { path = NavigationPath(); tab = target } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 17)).frame(width: 18).foregroundStyle(Theme.muted)
                Text(title).font(Theme.font(14, weight: tab == target ? .medium : .regular))
                Spacer()
                if let count { Text("\(count)").font(Theme.monoFont(11, weight: .medium)).foregroundStyle(Theme.muted) }
            }.padding(.horizontal, 8).frame(minHeight: 44).background(tab == target ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.accessibilityAddTraits(tab == target ? .isSelected : [])
    }

    private func menuRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 17)).frame(width: 18).foregroundStyle(Theme.muted)
                Text(title).font(Theme.font(14))
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
    case attention
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
        case .attention: NeedsAttentionView()
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
    func search(_ query: String, limit: Int = 25) async throws -> ServerSearchPage {
        try await send("GET", "/v1/search", queryItems: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(limit))])
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
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if trimmed.isEmpty {
                        PaperEmptyState(symbol: "magnifyingglass", title: "Search your workspace",
                                        message: "Jobs, customers, estimates and invoices across the company.")
                    } else if useServer {
                        ForEach(serverGroups, id: \.0) { type, results in
                            PaperGroupHeader(title: label(type), count: results.count).padding(.top, 8)
                            ForEach(results) { result in serverRow(result) }
                        }
                        if server.isEmpty && !searching { ContentUnavailableView.search(text: trimmed) }
                    } else {
                        if session.isOffline || serverFailed {
                            Label(session.isOffline ? "Offline · searching what's saved on this phone" : "Company search is unavailable · showing what's on this phone",
                                  systemImage: "iphone")
                                .font(Theme.font(12)).foregroundStyle(Theme.muted).padding(.top, 8)
                        }
                        if session.can("job.view", feature: "jobs"), !jobs.isEmpty {
                            PaperGroupHeader(title: "Jobs", count: jobs.count).padding(.top, 8)
                            ForEach(jobs) { job in
                                NavigationLink(value: job) {
                                    HStack(spacing: 10) {
                                        StatusRing(status: job.status)
                                        Text(job.shortRef).font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.muted)
                                            .frame(width: 66, alignment: .leading)
                                        Text(job.title).font(Theme.font(15, weight: .medium)).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }.frame(minHeight: 46).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                        if session.can("customer.view", feature: "core_crm"), !customers.isEmpty {
                            PaperGroupHeader(title: "Customers", count: customers.count).padding(.top, 16)
                            ForEach(customers) { customer in
                                NavigationLink(value: customer) {
                                    HStack(spacing: 12) {
                                        Avatar(name: customer.name, size: 26)
                                        Text(customer.name).font(Theme.font(15, weight: .medium))
                                        Spacer(minLength: 0)
                                    }.frame(minHeight: 46).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                        if searching { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20) }
                        else if jobs.isEmpty && customers.isEmpty { ContentUnavailableView.search(text: trimmed) }
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
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Jobs and customers")
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .paperDestinations()
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
                                  createdAt: nil, updatedAt: nil, allowedTransitions: nil)) { row }.buttonStyle(.plain)
        case "customer":
            NavigationLink(value: store.customers.first { $0.id == result.entityId }
                           ?? Customer(id: result.entityId, name: result.title, archived: nil, createdAt: nil)) { row }.buttonStyle(.plain)
        case "estimate":
            NavigationLink(value: PaperRoute.estimate(result.entityId)) { row }.buttonStyle(.plain)
        case "invoice":
            NavigationLink(value: PaperRoute.invoice(result.entityId)) { row }.buttonStyle(.plain)
        case "billing_schedule":
            NavigationLink(value: PaperRoute.billingSchedule(result.entityId)) { row }.buttonStyle(.plain)
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
