import SwiftUI

@main
struct ThorbisApp: App {
    @StateObject private var api = APIClient()
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup {
            Group {
                if api.auth == .none { LoginView() } else { RootView() }
            }
            .environmentObject(api).environmentObject(store)
            .preferredColorScheme(.dark)
            .tint(Theme.brand)
        }
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var customers: [Customer] = []
    @Published var error: String?
    @Published var loading = false

    func refresh(_ api: APIClient) async {
        loading = true; defer { loading = false }
        do {
            async let j = api.jobs()
            async let c = api.customers()
            (jobs, customers) = try await (j, c)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func customerName(_ id: String?) -> String {
        customers.first { $0.id == id }?.name ?? "Customer"
    }
}

enum Tab: Hashable { case schedule, jobs, customers, more }

struct RootView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var store: Store
    @State private var tab: Tab = ProcessInfo.processInfo.environment["THORBIS_TAB"].flatMap { ["jobs": Tab.jobs, "customers": .customers, "more": .more][$0] } ?? .schedule

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                Group {
                    switch tab {
                    case .schedule: ScheduleView()
                    case .jobs: JobsView()
                    case .customers: CustomersView()
                    case .more: MoreView()
                    }
                }
                .background(Theme.background)
                .navigationDestination(for: Job.self) { JobDetailView(jobId: $0.id) }
                .navigationDestination(for: Customer.self) { CustomerDetailView(customer: $0) }
            }
            PillTabBar(tab: $tab)
        }
        .background(Theme.background.ignoresSafeArea())
        .task { await store.refresh(api) }
    }
}

struct PillTabBar: View {
    @Binding var tab: Tab
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                item(.schedule, "calendar")
                item(.jobs, "briefcase")
                item(.customers, "person.2")
                item(.more, "ellipsis")
            }
            .padding(5)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(Theme.border))
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.foreground)
                .frame(width: 46, height: 46)
                .background(Theme.surface, in: Circle()).overlay(Circle().stroke(Theme.border))
        }
        .padding(.bottom, 4)
    }
    func item(_ t: Tab, _ icon: String) -> some View {
        Button { tab = t } label: {
            Image(systemName: icon).font(.system(size: 14, weight: .medium))
                .foregroundStyle(tab == t ? Theme.foreground : Theme.muted)
                .frame(width: 40, height: 36)
                .background(tab == t ? Theme.accent : .clear, in: Capsule())
        }
    }
}

struct ScreenHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    @EnvironmentObject var api: APIClient
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(Theme.brand).font(.system(size: 16))
                Text(title).font(.system(size: 22, weight: .bold))
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                Spacer()
                Image(systemName: "magnifyingglass").font(.system(size: 13)).frame(width: 30, height: 30).background(Theme.fill, in: Circle())
                Text(initials(api.displayName)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.brand)
                    .frame(width: 30, height: 30).background(Theme.brandSurface, in: Circle())
            }
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }
}

struct SegmentTabs: View {
    let options: [String]
    @Binding var selected: String
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { o in
                Button { selected = o } label: {
                    Text(o).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected == o ? Theme.foreground : Theme.muted)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(selected == o ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.top, 8)
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.system(size: 13)).foregroundStyle(Theme.warning)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16).padding(.top, 8)
    }
}
