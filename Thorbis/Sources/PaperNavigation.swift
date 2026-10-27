import SwiftUI

struct RootView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @State private var tab: TabletSection = .more
    @State private var primaryTab: PrimaryTab = .initial
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
    #endif

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if geometry.size.width >= 1000 { sidebar }
                navigation(wide: geometry.size.width >= 1000)
            }.background(Theme.background)
        }
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
        .onAppear {
            if session.can("job.view", feature: "jobs") { path = NavigationPath(); tab = .schedule }
            else if session.can("customer.view", feature: "core_crm") { path = NavigationPath(); tab = .customers }
        }
    }

    private func phoneNavigation() -> some View {
        TabView(selection: $primaryTab) {
            Tab(PrimaryTab.schedule.title, systemImage: PrimaryTab.schedule.symbol, value: PrimaryTab.schedule) {
                NavigationStack(path: $schedulePath) { gated(.schedule) { ScheduleView() }.paperDestinations() }
            }
            Tab(PrimaryTab.jobs.title, systemImage: PrimaryTab.jobs.symbol, value: PrimaryTab.jobs) {
                NavigationStack(path: $jobsPath) { gated(.jobs) { JobsView() }.paperDestinations() }
            }
            Tab(PrimaryTab.customers.title, systemImage: PrimaryTab.customers.symbol, value: PrimaryTab.customers) {
                NavigationStack(path: $customersPath) { gated(.customers) { CustomersView() }.paperDestinations() }
            }
            Tab(PrimaryTab.more.title, systemImage: PrimaryTab.more.symbol, value: PrimaryTab.more) {
                NavigationStack(path: $morePath) { MoreView().paperDestinations() }
            }
            Tab(value: PrimaryTab.search, role: .search) {
                PaperGlobalSearch(embedded: true)
            }
        }
        .environment(\.paperShowMenu, { Task { @MainActor in primaryTab = .more } })
        .background(Theme.background)
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
        .sheet(isPresented: $previewNewEstimate) {
            NewEstimateView(customerID: PaperPreview.customerID, jobID: PaperPreview.jobID, title: "AC not cooling")
        }
        #endif
        .task {
            await store.refresh(api)
            #if DEBUG
            guard PaperPreview.enabled else { return }
            if PaperPreview.screen == "new-estimate" { previewNewEstimate = true; return }
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
            case "revenue": primaryTab = .more; morePath.append(PaperRoute.revenue)
            case "job", "job-invoice", "job-estimates", "job-activity", "job-media", "job-closeout":
                if let job = store.jobs.first(where: { $0.id == PaperPreview.jobID }) {
                    primaryTab = .jobs
                    jobsPath.append(job)
                    if PaperPreview.screen == "job-closeout" { jobsPath.append(PaperRoute.closeout(jobID: job.id)) }
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
}

private struct PaperDestinations: ViewModifier {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Job.self) { JobDetailView(jobId: $0.id) }
            .navigationDestination(for: Customer.self) { CustomerDetailView(customer: $0) }
            .navigationDestination(for: PaperRoute.self) { route in
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
                case .local(let section):
                    if let actor = session.user?.id, let org = session.activeOrganization?.id {
                        LocalWorkspaceView(section: section, actorID: actor, organizationID: org)
                    }
                }
            }
    }
}

extension View {
    func paperDestinations() -> some View { modifier(PaperDestinations()) }
}

/// Paper 76: one field, results grouped by record type.
struct PaperGlobalSearch: View {
    var embedded = false
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var jobs: [Job] { trimmed.isEmpty ? [] : JobFiltering.jobs(store.jobs, assignedTo: nil, search: trimmed) }
    private var customers: [Customer] { trimmed.isEmpty ? [] : store.customers.filter { $0.archived != true && $0.name.localizedCaseInsensitiveContains(trimmed) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if trimmed.isEmpty {
                        PaperEmptyState(symbol: "magnifyingglass", title: "Search your workspace",
                                        message: "Find jobs by title or job number, and customers by name.")
                    } else {
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
                        if jobs.isEmpty && customers.isEmpty { ContentUnavailableView.search(text: trimmed) }
                    }
                }
                .padding(.horizontal, Theme.gutter)
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
}
