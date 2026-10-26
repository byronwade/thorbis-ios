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
            case .settings: SettingsView()
            }
        }
    }
}

enum AppTab: String, Hashable {
    case today, jobs, customers, money, inbox, search
}

/// Stable top-level destinations, not actions (HIG-005). On iPad the same tabs
/// adapt to a sidebar (HIG-016).
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
            Tab("Inbox", systemImage: "tray", value: AppTab.inbox) {
                NavigationStack { InboxView().thorbisDestinations() }
            }
            .badge(model.unreadNotices)
            Tab(value: AppTab.search, role: .search) {
                NavigationStack { SearchView().thorbisDestinations() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

/// The account button every root screen carries; settings is a destination, not a tab.
struct AccountToolbarItem: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
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
