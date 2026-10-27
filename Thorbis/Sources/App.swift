import SwiftUI

@main
struct ThorbisApp: App {
    @AppStorage("thorbis.appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var api: APIClient
    @StateObject private var store: Store
    @StateObject private var session: SessionController
    @StateObject private var inboxBoard: InboxLocalDrafts
    @StateObject private var connectivity = ConnectivityMonitor()
    @StateObject private var outbox: FieldOutbox
    @State private var publicEstimateToken: String?

    init() {
        #if DEBUG
        let api = PaperPreview.enabled ? PaperPreview.api() : APIClient()
        let session = SessionController(api: api, defaults: PaperPreview.enabled ? PaperPreview.defaults() : .standard)
        #else
        let api = APIClient()
        let session = SessionController(api: api)
        #endif
        let inboxBoard = InboxLocalDrafts()
        #if DEBUG
        let outbox = PaperPreview.enabled ? FieldOutbox(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), defaults: PaperPreview.defaults()) : FieldOutbox()
        #else
        let outbox = FieldOutbox()
        #endif
        let store = Store { [weak session] api in
            guard let session else { throw CancellationError() }
            return try await Store.fetchAuthorized(api: api, session: session)
        }
        session.onInvalidate = { [weak store] in store?.invalidate() }
        session.onSignedOut = { [weak store, weak outbox] in
            store?.cache.clearAll()
            outbox?.clearAll()
            PendingPhotoStore.clearAll()
            JobDetailCache.clearAll()
            Task { await JobLiveActivity.endAll() }
        }
        session.onVerifiedIdentity = { [weak inboxBoard, weak store, weak outbox] actorID, organizationID in
            if let actorID, let organizationID {
                inboxBoard?.bind(actorID: actorID, organizationID: organizationID)
            } else {
                inboxBoard?.clear()
            }
            store?.bindCache(actorID: actorID, organizationID: organizationID)
            outbox?.bind(actorID: actorID, organizationID: organizationID)
        }
        store.onUnauthorized = { [weak session] in Task { await session?.restore() } }
        PaperChrome.configureNavigationBar()
        _api = StateObject(wrappedValue: api)
        _store = StateObject(wrappedValue: store)
        _session = StateObject(wrappedValue: session)
        _inboxBoard = StateObject(wrappedValue: inboxBoard)
        _outbox = StateObject(wrappedValue: outbox)
        #if DEBUG
        _publicEstimateToken = State(initialValue: PaperPreview.enabled && PaperPreview.screen == "public-estimate" ? "preview-estimate" : nil)
        #else
        _publicEstimateToken = State(initialValue: nil)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let publicEstimateToken {
                    PublicEstimateActionView(token: publicEstimateToken) {
                        self.publicEstimateToken = nil
                    }
                    .id(publicEstimateToken)
                } else {
                    switch session.phase {
                    case .restoring:
                        ProgressView("Opening your workspace…")
                    case .signedOut, .failed:
                        LoginView()
                    case .choosingWorkspace, .noWorkspace:
                        WorkspaceSelectionView()
                    case .ready:
                        RootView().id(session.generation)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .environmentObject(api)
            .environmentObject(store)
            .environmentObject(session)
            .environmentObject(inboxBoard)
            .environmentObject(connectivity)
            .environmentObject(outbox)
            .font(Theme.font(15))
            .foregroundStyle(Theme.foreground)
            .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
            .tint(Theme.brandText)
            #if DEBUG
            .overlay(alignment: .bottom) { if PaperPreview.enabled { PaperPreview.banner.allowsHitTesting(false) } }
            #endif
            .task {
                connectivity.onReconnect = { Task { await resync() } }
                store.onServerReached = {
                    // Any answer from the server (including pull to refresh) ends offline mode.
                    guard session.isOffline else { return }
                    Task { await resync() }
                }
                await session.restore()
            }
            .task(id: session.isOffline) {
                // While offline, keep checking with backoff in case no network event fires
                // (captive Wi-Fi, a server outage, a cellular hand-off).
                var delay: UInt64 = 15
                while session.isOffline, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                    guard !Task.isCancelled, session.isOffline else { return }
                    await resync()
                    delay = min(delay * 2, 120)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Re-check without tearing down the session, the loaded work or navigation.
                guard phase == .active, session.phase == .ready else { return }
                Task { await resync() }
            }
            .onOpenURL { url in
                if let token = PublicEstimateActionLink.token(from: url) {
                    publicEstimateToken = token
                } else if let jobID = JobActivityLink.jobID(from: url) {
                    store.requestedJobID = jobID
                } else if url.scheme == "thorbis", url.host() == "schedule" {
                    store.requestedSchedule += 1
                }
            }
        }
    }
}

extension ThorbisApp {
    @MainActor private func resync() async {
        await session.revalidate()
        guard session.phase == .ready, !session.isOffline else { return }
        if !outbox.pending.isEmpty {
            await outbox.drain(api: api, useCommandEndpoint: session.isFeatureOn("offline_sync"))
        }
        await PendingPhotoStore.uploadAll(api: api)
        await store.refresh(api)
    }
}

struct WorkspaceSelectionView: View {
    @EnvironmentObject var session: SessionController
    var body: some View {
        NavigationStack {
            List {
                if session.organizations.isEmpty {
                    ContentUnavailableView("No workspace yet", systemImage: "building.2", description: Text("Your account has no workspace membership. Ask your workspace administrator for an invitation."))
                } else {
                    ForEach(session.organizations) { organization in
                        Button(organization.name) { Task { await session.selectOrganization(id: organization.id) } }
                    }
                }
                Button("Sign out", role: .destructive) { Task { await session.signOut() } }
            }
            .navigationTitle("Choose workspace")
        }
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var jobs: [Job] = []
    /// A job a Live Activity or link asked to open; RootView pushes it and clears this.
    @Published var requestedJobID: String?
    /// Bumped by the "Show my schedule" shortcut; RootView switches to Schedule.
    @Published var requestedSchedule = 0
    @Published var customers: [Customer] = []
    @Published var error: String?
    @Published var loading = false
    /// When the shown jobs came from the on-device copy instead of the server.
    @Published private(set) var cachedAt: Date?
    /// Called after the server answered a refresh, proof that it is reachable again.
    var onServerReached: (() -> Void)?

    private var generation = UUID()
    private var cacheIdentity: (actorID: String, organizationID: String)?
    var cache = WorkspaceCache()
    private var refreshID = UUID()
    private let fetch: @MainActor (APIClient) async throws -> ([Job], [Customer])
    var onUnauthorized: (() -> Void)?

    init(fetch: @escaping @MainActor (APIClient) async throws -> ([Job], [Customer]) = { api in
        async let jobs = api.jobs()
        async let customers = api.customers()
        return try await (jobs, customers)
    }) {
        self.fetch = fetch
    }

    static func fetchAuthorized(api: APIClient, session: SessionController) async throws -> ([Job], [Customer]) {
        let identity = session.generation
        guard session.phase == .ready else { throw CancellationError() }
        let jobs = session.can("job.view", feature: "jobs") ? try await api.jobs() : []
        guard session.generation == identity, session.phase == .ready else { throw CancellationError() }
        let customers = session.can("customer.view", feature: "core_crm") ? try await api.customers() : []
        guard session.generation == identity, session.phase == .ready else { throw CancellationError() }
        return (jobs, customers)
    }

    func invalidate() {
        generation = UUID()
        refreshID = UUID()
        jobs = []
        customers = []
        error = nil
        loading = false
        cachedAt = nil
        cacheIdentity = nil
    }

    /// Binds the on-device copy to the verified actor and workspace and shows it until
    /// the server answers. A nil pair (sign-out) deletes every cached workspace.
    func bindCache(actorID: String?, organizationID: String?) {
        guard let actorID, let organizationID else {
            cacheIdentity = nil
            return
        }
        cacheIdentity = (actorID, organizationID)
        if jobs.isEmpty && customers.isEmpty, let cached = cache.load(actorID: actorID, organizationID: organizationID) {
            jobs = cached.jobs
            customers = cached.customers
            cachedAt = cached.savedAt
        }
    }

    @discardableResult
    func refresh(_ api: APIClient) async -> StoreRefreshResult {
        let currentGeneration = generation
        let requestID = UUID()
        refreshID = requestID
        loading = true
        defer { if refreshID == requestID { loading = false } }
        do {
            let (newJobs, newCustomers) = try await fetch(api)
            guard generation == currentGeneration, refreshID == requestID else { return .superseded }
            jobs = newJobs
            customers = newCustomers
            error = nil
            cachedAt = nil
            onServerReached?()
            if let identity = cacheIdentity {
                cache.save(.init(savedAt: Date(), jobs: newJobs, customers: newCustomers),
                           actorID: identity.actorID, organizationID: identity.organizationID)
            }
            return .applied
        } catch is CancellationError {
            return .superseded
        } catch {
            guard generation == currentGeneration, refreshID == requestID else { return .superseded }
            if let problem = error as? Problem, problem.status == 401 {
                invalidate()
                onUnauthorized?()
            } else if error.isConnectivityFailure, !jobs.isEmpty || !customers.isEmpty {
                // No signal: keep showing what is on the phone; the offline banner says so.
                self.error = nil
                return .failed
            } else {
                self.error = error.localizedDescription
                return .failed
            }
            return .superseded
        }
    }

    func customerName(_ id: String?) -> String {
        customers.first { $0.id == id }?.name ?? "Customer"
    }
}

enum StoreRefreshResult: Equatable {
    case applied
    case failed
    case superseded
}

/// iPad sidebar sections.
enum TabletSection: Hashable { case schedule, jobs, customers, more }

/// iPhone tab bar: Paper's technician dock as native destinations (HIG-005).
/// Search uses the system search tab role.
enum PrimaryTab: String, CaseIterable, Identifiable {
    case schedule, jobs, customers, more, search

    static let initial: PrimaryTab = .schedule

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .schedule: "calendar"
        case .jobs: "briefcase"
        case .customers: "person.2"
        case .more: "ellipsis"
        case .search: "magnifyingglass"
        }
    }
}

struct PrimaryTabAccess {
    let canViewJobs: Bool
    let canViewCustomers: Bool

    func canOpen(_ tab: PrimaryTab) -> Bool {
        switch tab {
        case .schedule, .jobs: canViewJobs
        case .customers: canViewCustomers
        case .more, .search: true
        }
    }

    func unavailableMessage(for tab: PrimaryTab) -> String {
        switch tab {
        case .schedule, .jobs: "Your role does not allow access to jobs."
        case .customers: "Your role does not allow access to customers."
        case .more, .search: ""
        }
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(Theme.font(13)).foregroundStyle(Theme.warning)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, Theme.gutter).padding(.top, 8)
    }
}
