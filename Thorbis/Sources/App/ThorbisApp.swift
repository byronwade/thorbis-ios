import SwiftUI
import ThorbisCore

@main
struct ThorbisApp: App {
    @State private var model = AppModel()
    @AppStorage("thorbis.appearance") private var appearance: Appearance = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.canvas)
            case .signedOut:
                SignInView()
            case let .choosingOrganization(organizations):
                OrganizationPickerView(organizations: organizations)
            case .signedIn:
                MainTabView()
            }
        }
        .task { await model.bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from the van: refresh what may have changed while away.
            if phase == .active, model.phase == .signedIn, let last = model.lastRefreshed, Date().timeIntervalSince(last) > 120 {
                Task { await model.refreshAll() }
            }
        }
    }
}

/// Durable records are navigable destinations, never sheet-only dead ends (HIG-006).
enum Route: Hashable {
    case job(String)
    case customer(String)
    case estimate(String)
    case invoice(String)
    case inbox
    case settings
}

extension View {
    func thorbisDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case let .job(id): JobDetailView(jobId: id)
            case let .customer(id): CustomerDetailView(customerId: id)
            case let .estimate(id): EstimateDetailView(estimateId: id)
            case let .invoice(id): InvoiceDetailView(invoiceId: id)
            case .inbox: InboxView()
            case .settings: SettingsView()
            }
        }
    }
}

enum AppTab: String, Hashable {
    case today, jobs, customers, money, search
}

/// Stable top-level destinations, not actions (HIG-005). On iPad the same tabs
/// adapt to a sidebar (HIG-016). An iPhone tab bar shows five items before it
/// folds the rest into More, so the inbox lives in every root screen's toolbar.
struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("thorbis.tab") private var tab: AppTab = .today

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                NavigationStack { TodayView().thorbisDestinations() }
            }
            Tab("Jobs", systemImage: "wrench.and.screwdriver", value: AppTab.jobs) {
                NavigationStack { JobsView().thorbisDestinations() }
            }
            Tab("Customers", systemImage: "person.2", value: AppTab.customers) {
                NavigationStack { CustomersView().thorbisDestinations() }
            }
            Tab("Money", systemImage: "doc.text", value: AppTab.money) {
                NavigationStack { MoneyView().thorbisDestinations() }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack { SearchView().thorbisDestinations() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

/// The inbox and account buttons every root screen carries; both are
/// destinations pushed on the current tab, not tabs of their own.
struct AccountToolbarItem: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink(value: Route.inbox) {
                Image(systemName: model.unreadNotices > 0 ? "tray.full" : "tray")
                    .overlay(alignment: .topTrailing) {
                        if model.unreadNotices > 0 {
                            Circle().fill(Theme.accent).frame(width: 8, height: 8).offset(x: 3, y: -3)
                        }
                    }
                    .frame(minWidth: Theme.minimumHit, minHeight: Theme.minimumHit)
            }
            .accessibilityLabel(model.unreadNotices > 0 ? "Inbox, \(model.unreadNotices) unread" : "Inbox")
            .accessibilityIdentifier("inbox")
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink(value: Route.settings) {
                Image(systemName: "person.crop.circle")
                    .frame(minWidth: Theme.minimumHit, minHeight: Theme.minimumHit)
            }
            .accessibilityLabel("Account and settings")
            .accessibilityIdentifier("settings")
        }
    }
}
