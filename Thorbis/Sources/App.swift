import SwiftUI

@main
struct ThorbisApp: App {
    @AppStorage("thorbis.appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var api: APIClient
    @StateObject private var store: Store
    @StateObject private var session: SessionController
    @StateObject private var inboxBoard: InboxLocalDrafts

    init() {
        #if DEBUG
        let api = PaperPreview.enabled ? PaperPreview.api() : APIClient()
        let session = SessionController(api: api, defaults: PaperPreview.enabled ? PaperPreview.defaults() : .standard)
        #else
        let api = APIClient()
        let session = SessionController(api: api)
        #endif
        let inboxBoard = InboxLocalDrafts()
        let store = Store { [weak session] api in
            guard let session else { throw CancellationError() }
            return try await Store.fetchAuthorized(api: api, session: session)
        }
        session.onInvalidate = { [weak store] in store?.invalidate() }
        session.onVerifiedIdentity = { [weak inboxBoard] actorID, organizationID in
            if let actorID, let organizationID {
                inboxBoard?.bind(actorID: actorID, organizationID: organizationID)
            } else {
                inboxBoard?.clear()
            }
        }
        store.onUnauthorized = { [weak session] in Task { await session?.restore() } }
        _api = StateObject(wrappedValue: api)
        _store = StateObject(wrappedValue: store)
        _session = StateObject(wrappedValue: session)
        _inboxBoard = StateObject(wrappedValue: inboxBoard)
    }

    var body: some Scene {
        WindowGroup {
            Group {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .environmentObject(api)
            .environmentObject(store)
            .environmentObject(session)
            .environmentObject(inboxBoard)
            .font(Theme.font(15))
            .foregroundStyle(Theme.foreground)
            .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
            .tint(Theme.brand)
            #if DEBUG
            .overlay(alignment: .bottom) { if PaperPreview.enabled { PaperPreview.banner.allowsHitTesting(false) } }
            #endif
            .task { await session.restore() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, session.phase == .ready else { return }
                Task { await session.restore() }
            }
        }
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
    @Published var customers: [Customer] = []
    @Published var error: String?
    @Published var loading = false

    private var generation = UUID()
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
    }

    func refresh(_ api: APIClient) async {
        let currentGeneration = generation
        let requestID = UUID()
        refreshID = requestID
        loading = true
        defer { if refreshID == requestID { loading = false } }
        do {
            let (newJobs, newCustomers) = try await fetch(api)
            guard generation == currentGeneration, refreshID == requestID else { return }
            jobs = newJobs
            customers = newCustomers
            error = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == currentGeneration, refreshID == requestID else { return }
            if let problem = error as? Problem, problem.status == 401 {
                invalidate()
                onUnauthorized?()
            } else {
                self.error = error.localizedDescription
            }
        }
    }

    func customerName(_ id: String?) -> String {
        customers.first { $0.id == id }?.name ?? "Customer"
    }
}

enum Tab: Hashable { case schedule, jobs, customers, more }

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
