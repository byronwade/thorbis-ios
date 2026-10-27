import SwiftUI

struct RootView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @State private var tab: Tab = .more
    @State private var path = NavigationPath()
    @State private var menu = false
    @State private var search = false
    @State private var settings = false
    @State private var workspace = false
    @State private var createJob = false
    @State private var priceBook = false
    @State private var drafts = false

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if geometry.size.width >= 1000 { sidebar }
                navigation(wide: geometry.size.width >= 1000)
            }.background(Theme.background)
        }
    }

    private func navigation(wide: Bool) -> some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                Group {
                    switch tab {
                    case .schedule:
                        if wide { PaperTabletSchedule() } else { ScheduleView() }
                    case .jobs: JobsView()
                    case .customers: CustomersView()
                    case .more: MoreView()
                    }
                }
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: wide ? 0 : 70) }
                .environment(\.paperShowMenu, { Task { @MainActor in menu = true } })
                if !wide { dock.padding(.bottom, 4) }
                if menu { menuOverlay }
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
        .task {
            await store.refresh(api)
            #if DEBUG
            if PaperPreview.enabled {
                switch PaperPreview.screen {
                case "jobs": tab = .jobs
                case "customers": tab = .customers
                case "menu": menu = true
                case "job": if let job = store.jobs.first(where: { $0.id == PaperPreview.jobID }) { path.append(job) }
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { workspace = true } label: {
                HStack(spacing: 9) {
                    Text(String((session.activeOrganization?.name ?? "W").prefix(1)))
                        .font(Theme.font(12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 24, height: 24).background(Theme.brand, in: RoundedRectangle(cornerRadius: 7))
                    Text(session.activeOrganization?.name ?? "Workspace").font(Theme.font(14, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 10))
                }.padding(.horizontal, 8).frame(minHeight: 44)
            }.padding(.bottom, 10)
            Button { search = true } label: {
                HStack(spacing: 8) { Image(systemName: "magnifyingglass"); Text("Search"); Spacer() }
                    .font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.horizontal, 10)
                    .frame(height: 34).background(Theme.fill, in: RoundedRectangle(cornerRadius: 9))
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
                }.padding(.horizontal, 8).frame(minHeight: 40)
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
            }.padding(.horizontal, 8).frame(minHeight: 38).background(tab == target ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: 9))
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
                    Image(systemName: "ellipsis").frame(width: 48, height: 38)
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
                .frame(width: 48, height: 38).background(tab == target ? Theme.fill : .clear, in: Capsule())
        }.accessibilityLabel(title).accessibilityAddTraits(tab == target ? .isSelected : [])
    }

    private var menuOverlay: some View {
        ZStack(alignment: .bottomLeading) {
            Color(hex: 0x111110).opacity(0.16).ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture { menu = false }.accessibilityLabel("Close navigation")
            VStack {
                HStack(spacing: 8) {
                    Button { menu = false; workspace = true } label: {
                        HStack(spacing: 6) {
                            Text(String((session.activeOrganization?.name ?? "W").prefix(1))).font(Theme.font(11, weight: .bold))
                                .frame(width: 20, height: 20).background(Theme.fill, in: RoundedRectangle(cornerRadius: 6))
                            Text(session.activeOrganization?.name ?? "Workspace").font(Theme.font(14, weight: .semibold)).lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 10))
                        }.padding(.horizontal, 12).frame(height: 40).background(Theme.card, in: Capsule())
                    }
                    Spacer(minLength: 0)
                    if session.can("job.create", feature: "jobs") {
                        Button { menu = false; createJob = true } label: { Image(systemName: "square.and.pencil").frame(width: 40, height: 40).background(Theme.card, in: Circle()) }.accessibilityLabel("New job")
                    }
                    Button { menu = false; settings = true } label: { Image(systemName: "gearshape").frame(width: 40, height: 40).background(Theme.card, in: Circle()) }.accessibilityLabel("Settings")
                }.padding(.horizontal, 14).padding(.top, 4)
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(spacing: 2) {
                        if session.can("job.view", feature: "jobs") {
                            menuRow("Schedule", icon: "calendar", selected: tab == .schedule) { path = NavigationPath(); tab = .schedule }
                            menuRow("Jobs", icon: "briefcase", selected: tab == .jobs) { path = NavigationPath(); tab = .jobs }
                        }
                        if session.can("customer.view", feature: "core_crm") { menuRow("Customers", icon: "person.2", selected: tab == .customers) { path = NavigationPath(); tab = .customers } }
                        menuRow("Message drafts", icon: "bubble.left") { drafts = true }
                        if session.can("pricebook.view", feature: "price_book") { menuRow("Price book", icon: "book.closed") { priceBook = true } }
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
            }.padding(.horizontal, 10).frame(minHeight: 42).background(selected ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: 12))
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
                    }.font(Theme.font(15)).padding(.horizontal, 12).frame(height: 40)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.brand))
                    Button("Cancel") { dismiss() }.font(Theme.font(15, weight: .medium))
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
