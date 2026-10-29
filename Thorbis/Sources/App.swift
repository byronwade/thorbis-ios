import SwiftUI

@main
struct ThorbisApp: App {
    @UIApplicationDelegateAdaptor(ThorbisAppDelegate.self) private var appDelegate
    @AppStorage("thorbis.appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var api: APIClient
    @StateObject private var store: Store
    @StateObject private var session: SessionController
    @StateObject private var inboxBoard: InboxLocalDrafts
    @StateObject private var connectivity = ConnectivityMonitor()
    @StateObject private var pendingMedia: PendingMediaStore
    @StateObject private var outbox: FieldOutbox
    @StateObject private var menuLayout = MenuLayout()
    @StateObject private var whatsNew: WhatsNew
    @State private var publicEstimateToken: String?
    @StateObject private var estimateHandoff = JobEstimateHandoffPresenter()

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
        let outbox = PaperPreview.enabled ? PaperPreview.outbox() : FieldOutbox()
        #else
        let outbox = FieldOutbox()
        #endif
        #if DEBUG
        let pendingMedia = PaperPreview.enabled ? PaperPreview.mediaStore() : PendingMediaStore.shared
        #else
        let pendingMedia = PendingMediaStore.shared
        #endif
        let store = Store { [weak session] api in
            guard let session else { throw CancellationError() }
            return try await Store.fetchAuthorized(api: api, session: session)
        }
        session.onInvalidate = { [weak store, weak pendingMedia] in
            store?.invalidate()
            pendingMedia?.bind(nil)
            JobLiveActivity.retire()
        }
        session.onJobAuthorityRevoked = { JobLiveActivity.retire() }
        session.onSignedOut = { [weak store, weak outbox, weak pendingMedia] in
            store?.cache.clearAll()
            outbox?.clearAll()
            pendingMedia?.clearAll()
            JobDetailCache.clearAll()
            TodaySnapshot.clear()
            JobInvoiceMemory.clear()
            Task { @MainActor in RecentItems.shared.clear() }
        }
        session.onVerifiedIdentity = { [weak inboxBoard, weak store, weak outbox, weak pendingMedia, weak api] actorID, organizationID in
            if let actorID, let organizationID {
                inboxBoard?.bind(actorID: actorID, organizationID: organizationID)
            } else {
                inboxBoard?.clear()
            }
            store?.bindCache(actorID: actorID, organizationID: organizationID)
            PushNotifications.shared.identityChanged(signedIn: actorID != nil && organizationID != nil)
            outbox?.bind(actorID: actorID, organizationID: organizationID)
            if let actorID, let organizationID, let origin = api?.normalizedOrigin {
                pendingMedia?.bind(PendingMediaScope(actorID: actorID, organizationID: organizationID, origin: origin))
            } else { pendingMedia?.bind(nil) }
            Task { @MainActor in RecentItems.shared.bind(actorID: actorID, organizationID: organizationID) }
        }
        PushNotifications.shared.start(api: api, store: store)
        session.onWillUnbindDevice = { await PushNotifications.shared.unbind() }
        store.onUnauthorized = { [weak session] in Task { await session?.restore() } }
        PaperChrome.configureNavigationBar()
        #if DEBUG
        _whatsNew = StateObject(wrappedValue: PaperPreview.enabled ? WhatsNew(defaults: PaperPreview.defaults()) : WhatsNew())
        #else
        _whatsNew = StateObject(wrappedValue: WhatsNew())
        #endif
        _api = StateObject(wrappedValue: api)
        _store = StateObject(wrappedValue: store)
        _session = StateObject(wrappedValue: session)
        _inboxBoard = StateObject(wrappedValue: inboxBoard)
        _outbox = StateObject(wrappedValue: outbox)
        _pendingMedia = StateObject(wrappedValue: pendingMedia)
        #if DEBUG
        _publicEstimateToken = State(initialValue: PaperPreview.enabled && PaperPreview.screen == "public-estimate" ? "preview-estimate" : nil)
        #else
        _publicEstimateToken = State(initialValue: nil)
        #endif
    }

    @ViewBuilder private var appContent: some View {
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
                    .onAppear { whatsNew.signedInThisLaunch = true }
            case .choosingWorkspace, .noWorkspace:
                WorkspaceSelectionView()
            case .ready:
                RootView().id(session.generation).businessSetupPrompt()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
            Group {
                #if DEBUG
                if PaperPreview.enabled, PaperPreview.screen.hasPrefix("present-") {
                    CustomerPresentationPreview(screen: PaperPreview.screen)
                } else if PaperPreview.enabled, let screen = PaperPreview.onboardingScreen {
                    OnboardingPreview(screen: screen)
                } else {
                    appContent
                }
                #else
                appContent
                #endif
            }
            }
            .fullScreenCover(isPresented: Binding(get: { estimateHandoff.active != nil }, set: { _ in })) {
                if let model = estimateHandoff.active {
                    JobEstimateProtectedOwner(model: model, presenter: estimateHandoff)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .environmentObject(estimateHandoff)
            .environmentObject(api)
            .environmentObject(store)
            .environmentObject(session)
            .environmentObject(inboxBoard)
            .environmentObject(connectivity)
            .environmentObject(outbox)
            .environmentObject(pendingMedia)
            .environmentObject(menuLayout)
            .environmentObject(whatsNew)
            .font(Theme.font(15))
            .foregroundStyle(Theme.foreground)
            .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
            .tint(Theme.brandText)
            #if DEBUG
            .safeAreaInset(edge: .top, spacing: 0) {
                if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-review-failure") {
                    PaperPreview.reviewConnectionControl
                }
            }
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
                whatsNew.skipThisLaunch = true
                if let token = PublicEstimateActionLink.token(from: url) {
                    publicEstimateToken = token
                } else if let jobID = JobActivityLink.jobID(from: url) {
                    store.requestedJobID = jobID
                } else if let record = RecordLink(url: url) {
                    store.requestedRecord = record
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
        await pendingMedia.drain(api: api, canUpload: { session.can("job.edit", feature: "jobs") })
        await store.refresh(api)
    }
}

struct WorkspaceSelectionView: View {
    @EnvironmentObject var session: SessionController
    var body: some View {
        // A new owner names their company here; see Onboarding.swift.
        WorkspaceGateView()
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var jobs: [Job] = []
    /// A job a Live Activity or link asked to open; RootView pushes it and clears this.
    @Published var requestedJobID: String? {
        didSet { if requestedJobID != nil { openedForRecord = true } }
    }
    /// Latched when a link, notification or Live Activity asked for a record this launch, since
    /// RootView clears the request as soon as it opens it. What's new waits for the next launch.
    var openedForRecord = false
    /// Bumped by the "Show my schedule" shortcut; RootView switches to Schedule.
    @Published var requestedSchedule = 0
    /// A customer, estimate or invoice a link asked to open; RootView pushes it and clears this.
    @Published var requestedRecord: RecordLink? {
        didSet { if requestedRecord != nil { openedForRecord = true } }
    }
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
        var customers = session.can("customer.view", feature: "core_crm") ? try await api.customers() : []
        guard session.generation == identity, session.phase == .ready else { throw CancellationError() }
        // Technicians get an empty customer list by design and read each customer through their
        // assigned job, so fill in the names their jobs need one by one.
        if session.can("customer.view", feature: "core_crm") {
            let known = Set(customers.map(\.id))
            let missing = Array(Set(jobs.compactMap(\.customerId)).subtracting(known)).sorted().prefix(40)
            for id in missing {
                guard let record = try? await api.fieldCustomer(id) else { continue }
                customers.append(Customer(id: record.id, name: record.name, archived: nil, createdAt: nil))
            }
            guard session.generation == identity, session.phase == .ready else { throw CancellationError() }
        }
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

/// MA-15: errors name the exit. The words stay body colour, only the mark is tinted, and
/// when the screen can try again it offers one "Try again".
struct ErrorBanner: View {
    let message: String
    var retry: (() async -> Void)? = nil
    @State private var retrying = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                .accessibilityHidden(true)
            Text(message).foregroundStyle(Theme.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button {
                    Task { retrying = true; await retry(); retrying = false }
                } label: {
                    Text("Try again").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 12).frame(minHeight: 32)
                        .background(Theme.card, in: Capsule()).overlay(Capsule().stroke(Theme.border))
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(retrying)
            }
        }
        .font(Theme.font(13))
        .padding(.horizontal, 12).padding(.vertical, retry == nil ? 12 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .padding(.horizontal, Theme.gutter).padding(.top, 8)
        .accessibilityElement(children: .contain)
    }
}
