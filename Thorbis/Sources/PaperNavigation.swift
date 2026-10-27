import SwiftUI

private enum PhoneSecondaryDestination: String, Identifiable {
    case schedule, customers, drafts, priceBook
    var id: String { rawValue }
}

struct RootView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @State private var tab: Tab = .more
    @State private var primaryTab: PrimaryTab = .initial
    @State private var path = NavigationPath()
    @State private var jobsPath = NavigationPath()
    @State private var arrivePath = NavigationPath()
    @State private var phoneDestination: PhoneSecondaryDestination?
    @State private var menu = false
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
            ZStack(alignment: .bottom) {
                Group {
                    switch tab {
                    case .schedule:
                        PaperTabletSchedule()
                    case .jobs: JobsView()
                    case .customers: CustomersView()
                    case .more: MoreView()
                    }
                }
                .environment(\.paperShowMenu, { Task { @MainActor in menu = true } })
                if menu { menuOverlay(wide: true) }
            }
            .background(Theme.background)
            .navigationDestination(for: Job.self) { JobDetailView(jobId: $0.id) }
            .navigationDestination(for: Customer.self) { CustomerDetailView(customer: $0) }
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
        .sheet(isPresented: $settings) { NavigationStack { MoreView().navigationDestination(for: Job.self) { JobDetailView(jobId: $0.id) }.navigationDestination(for: Customer.self) { CustomerDetailView(customer: $0) }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { settings = false } } } } }
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
                case "my-day": tab = .jobs
                case "customers": tab = .customers
                case "menu": menu = true
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
        ZStack {
            TabView(selection: $primaryTab) {
                NavigationStack(path: $jobsPath) {
                    gatedJobs(.jobs)
                        .navigationDestination(for: Job.self) { JobDetailView(jobId: $0.id) }
                        .navigationDestination(for: Customer.self) { CustomerDetailView(customer: $0) }
                }
                .tabItem { Label(PrimaryTab.jobs.title, systemImage: PrimaryTab.jobs.symbol) }
                .tag(PrimaryTab.jobs)

                NavigationStack(path: $arrivePath) {
                    gatedJobs(.arrive)
                        .navigationDestination(for: Job.self) { JobDetailView(jobId: $0.id) }
                        .navigationDestination(for: Customer.self) { CustomerDetailView(customer: $0) }
                }
                .tabItem { Label(PrimaryTab.arrive.title, systemImage: PrimaryTab.arrive.symbol) }
                .tag(PrimaryTab.arrive)

                NavigationStack {
                    WorkspaceNoticesView(api: api, available: primaryAccess.canOpen(.inbox))
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button { menu = true } label: { Image(systemName: "ellipsis") }
                                    .accessibilityLabel("More")
                            }
                        }
                }
                .tabItem { Label(PrimaryTab.inbox.title, systemImage: PrimaryTab.inbox.symbol) }
                .tag(PrimaryTab.inbox)
            }
            .environment(\.paperShowMenu, { Task { @MainActor in menu = true } })
            if menu { menuOverlay(wide: false) }
        }
        .background(Theme.background)
        .sheet(isPresented: $search) { PaperGlobalSearch() }
        .sheet(isPresented: $settings) {
            NavigationStack {
                MoreView()
                    .navigationDestination(for: Job.self) { JobDetailView(jobId: $0.id) }
                    .navigationDestination(for: Customer.self) { CustomerDetailView(customer: $0) }
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { settings = false } } }
            }
        }
        .sheet(isPresented: $workspace) { WorkspaceSelectionView() }
        .sheet(isPresented: $createJob) { NewJobSheet() }
        .sheet(item: $phoneDestination) { destination in
            NavigationStack {
                Group {
                    switch destination {
                    case .schedule: ScheduleView()
                    case .customers: CustomersView()
                    case .drafts:
                        if let actor = session.user?.id, let org = session.activeOrganization?.id {
                            InboxLocalDraftView(actorID: actor, organizationID: org)
                        }
                    case .priceBook:
                        WorkspacePriceBookView(api: api, canList: true, canViewDetail: session.can("organization.settings.edit", feature: "price_book")).id(session.generation)
                    }
                }
                .navigationDestination(for: Job.self) { JobDetailView(jobId: $0.id) }
                .navigationDestination(for: Customer.self) { CustomerDetailView(customer: $0) }
                .safeAreaInset(edge: .top) {
                    HStack {
                        Spacer()
                        Button("Done") { phoneDestination = nil }
                            .font(Theme.font(15, weight: .medium))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .padding(.horizontal, 16)
                    .background(Theme.background)
                }
            }
        }
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
        #endif
        .task {
            await store.refresh(api)
            #if DEBUG
            guard PaperPreview.enabled else { return }
            if PaperPreview.screen == "invoice-editor" { previewInvoiceEditor = true; return }
            if PaperPreview.screen == "invoice-detail" || PaperPreview.screen == "invoice-payment" || PaperPreview.isPaymentRefundPreview { previewInvoiceDetail = true; return }
            if PaperPreview.screen == "estimate-revision" { previewEstimateRevision = true; return }
            switch PaperPreview.screen {
            case "jobs": primaryTab = .jobs
            case "my-day": primaryTab = .arrive
            case "customers": phoneDestination = .customers
            case "menu": menu = true
            case "job", "job-invoice":
                if let job = store.jobs.first(where: { $0.id == PaperPreview.jobID }) {
                    primaryTab = .jobs
                    jobsPath.append(job)
                }
            case "customer": phoneDestination = .customers
            default: break
            }
            #endif
        }
    }

    private var primaryAccess: PrimaryTabAccess {
        PrimaryTabAccess(
            canViewJobs: session.can("job.view", feature: "jobs"),
            canViewStaffNotices: session.can("job.view", feature: "job_booking_notices")
        )
    }

    @ViewBuilder private func gatedJobs(_ mode: JobsViewMode) -> some View {
        let destination: PrimaryTab = mode == .arrive ? .arrive : .jobs
        if primaryAccess.canOpen(destination) {
            JobsView(mode: mode)
        } else {
            VStack(spacing: 0) {
                PaperHeader(title: destination.title, icon: destination.symbol, subtitle: "Access unavailable")
                ContentUnavailableView(
                    destination == .arrive ? "Arrive unavailable" : "Jobs unavailable",
                    systemImage: destination == .arrive ? "location.north.circle" : "briefcase",
                    description: Text(primaryAccess.unavailableMessage(for: destination))
                )
            }
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

    private func sidebarRow(_ title: String, icon: String, target: Tab, count: Int? = nil) -> some View {
        Button { path = NavigationPath(); tab = target } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 17)).frame(width: 18).foregroundStyle(Theme.muted)
                Text(title).font(Theme.font(14, weight: tab == target ? .medium : .regular))
                Spacer()
                if let count { Text("\(count)").font(Theme.monoFont(11, weight: .medium)).foregroundStyle(Theme.muted) }
            }.padding(.horizontal, 8).frame(minHeight: 44).background(tab == target ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.accessibilityAddTraits(tab == target ? .isSelected : [])
    }

    private var dock: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                if session.can("job.view", feature: "jobs") {
                    dockButton("Schedule", icon: "calendar", target: .schedule)
                    dockButton("Jobs", icon: "briefcase", target: .jobs)
                }
                if session.can("customer.view", feature: "core_crm") { dockButton("Customers", icon: "person.2", target: .customers) }
                Button { withAnimation(.easeInOut(duration: 0.18)) { menu = true } } label: {
                    Image(systemName: "ellipsis").frame(width: 48, height: 44)
                }.accessibilityLabel("More")
            }.padding(6).background(Theme.card, in: Capsule()).overlay(Capsule().stroke(Theme.border))
            Button { search = true } label: {
                Image(systemName: "magnifyingglass").frame(width: 50, height: 50)
                    .background(Theme.card, in: Circle()).overlay(Circle().stroke(Theme.border))
            }.accessibilityLabel("Search workspace")
        }.font(.system(size: 18)).foregroundStyle(Theme.muted).buttonStyle(.plain)
            .shadow(color: Color(hex: 0x1A1714).opacity(0.12), radius: 12, y: 8)
    }

    private func dockButton(_ title: String, icon: String, target: Tab) -> some View {
        Button { path = NavigationPath(); tab = target } label: {
            Image(systemName: icon).foregroundStyle(tab == target ? Theme.foreground : Theme.muted)
                .frame(width: 48, height: 44).background(tab == target ? Theme.fill : .clear, in: Capsule())
        }.accessibilityLabel(title).accessibilityAddTraits(tab == target ? .isSelected : [])
    }

    private func menuOverlay(wide: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color(hex: 0x111110).opacity(0.16).ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture { menu = false }.accessibilityLabel("Close navigation")
            VStack {
                HStack(spacing: 8) {
                    Button { menu = false; workspace = true } label: {
                        HStack(spacing: 6) {
                            Image("ThorbisMark").resizable().scaledToFit().padding(3)
                                .frame(width: 20, height: 20).background(Theme.card, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
                                .accessibilityHidden(true)
                            Text(session.activeOrganization?.name ?? "Workspace").font(Theme.font(14, weight: .semibold)).lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 10))
                        }.padding(.horizontal, 12).frame(minHeight: 44).background(Theme.card, in: Capsule())
                    }
                    Spacer(minLength: 0)
                    if session.can("job.create", feature: "jobs") {
                        Button { menu = false; createJob = true } label: { Image(systemName: "square.and.pencil").frame(width: 40, height: 40).background(Theme.card, in: Circle()).frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("New job")
                    }
                    Button { menu = false; settings = true } label: { Image(systemName: "gearshape").frame(width: 40, height: 40).background(Theme.card, in: Circle()).frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Settings")
                }.padding(.horizontal, 14).padding(.top, 4)
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(spacing: 2) {
                        if session.can("job.view", feature: "jobs") {
                            menuRow("Schedule", icon: "calendar", selected: wide && tab == .schedule) {
                                if wide { path = NavigationPath(); tab = .schedule }
                                else { phoneDestination = .schedule }
                            }
                            menuRow("Jobs", icon: "briefcase", selected: wide ? tab == .jobs : primaryTab == .jobs) {
                                if wide { path = NavigationPath(); tab = .jobs }
                                else { primaryTab = .jobs }
                            }
                            if !wide {
                                menuRow("Arrive", icon: "location.north.circle", selected: primaryTab == .arrive) { primaryTab = .arrive }
                            }
                        }
                        if session.can("customer.view", feature: "core_crm") {
                            menuRow("Customers", icon: "person.2", selected: wide && tab == .customers) {
                                if wide { path = NavigationPath(); tab = .customers }
                                else { phoneDestination = .customers }
                            }
                        }
                        if !wide && primaryAccess.canOpen(.inbox) {
                            menuRow("Inbox", icon: "tray", selected: primaryTab == .inbox) { primaryTab = .inbox }
                        }
                        menuRow("Message drafts", icon: "bubble.left") {
                            if wide { drafts = true } else { phoneDestination = .drafts }
                        }
                        if session.can("pricebook.view", feature: "price_book") {
                            menuRow("Price book", icon: "book.closed") {
                                if wide { priceBook = true } else { phoneDestination = .priceBook }
                            }
                        }
                        Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 10).padding(.vertical, 4)
                        menuRow("Workspace tools", icon: "slider.horizontal.3") { settings = true }
                    }.padding(6).frame(width: 250).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
                    Spacer(minLength: 10)
                    Button { menu = false; search = true } label: { Image(systemName: "magnifyingglass").frame(width: 50, height: 50).background(Theme.card, in: Circle()).overlay(Circle().stroke(Theme.border)) }.accessibilityLabel("Search workspace")
                }.padding(.horizontal, 14).padding(.bottom, 4)
            }
        }.buttonStyle(.plain).foregroundStyle(Theme.foreground)
    }

    private func menuRow(_ title: String, icon: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button { menu = false; action() } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 18)).frame(width: 18).foregroundStyle(Theme.muted)
                Text(title).font(Theme.font(15, weight: selected ? .medium : .regular))
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).frame(minHeight: 44).background(selected ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct PaperGlobalSearch: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var jobs: [Job] { JobFiltering.jobs(store.jobs, assignedTo: nil, search: query) }
    private var customers: [Customer] { store.customers.filter { $0.archived != true && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                        TextField("Search jobs and customers", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }.font(Theme.font(15)).padding(.horizontal, 12).frame(minHeight: 44)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.brand))
                    Button("Cancel") { dismiss() }.font(Theme.font(15, weight: .medium)).frame(minWidth: 44, minHeight: 44)
                }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 14)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if session.can("job.view", feature: "jobs") {
                            section("Jobs", count: jobs.count)
                            ForEach(jobs) { job in
                                NavigationLink(value: job) {
                                    HStack(spacing: 10) {
                                        Image(systemName: statusIcon(job.status).0).foregroundStyle(statusIcon(job.status).1).frame(width: 22)
                                        Text(job.shortRef).font(Theme.monoFont(12, weight: .medium)).foregroundStyle(Theme.muted).frame(width: 62)
                                        Text(job.title).font(Theme.font(15, weight: .medium)).lineLimit(2)
                                        Spacer(minLength: 0)
                                    }.frame(minHeight: 44).padding(.horizontal, 2).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                        if session.can("customer.view", feature: "core_crm") {
                            section("Customers", count: customers.count).padding(.top, 16)
                            ForEach(customers) { customer in
                                NavigationLink(value: customer) {
                                    HStack(spacing: 10) {
                                        Avatar(name: customer.name, size: 22)
                                        Text(customer.name).font(Theme.font(15, weight: .medium))
                                        Spacer(minLength: 0)
                                    }.frame(minHeight: 44).padding(.horizontal, 2).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                        if jobs.isEmpty && customers.isEmpty { ContentUnavailableView.search(text: query) }
                    }.padding(.horizontal, 20)
                }
            }.foregroundStyle(Theme.foreground).background(Theme.background).toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Job.self) { JobDetailView(jobId: $0.id) }
                .navigationDestination(for: Customer.self) { CustomerDetailView(customer: $0) }
        }
    }
    private func section(_ title: String, count: Int) -> some View {
        HStack { Text(title).font(Theme.font(13, weight: .medium)); Spacer(); Text("\(count)").font(Theme.monoFont(12)) }
            .foregroundStyle(Theme.muted).padding(.horizontal, 2).padding(.bottom, 4)
    }
}
