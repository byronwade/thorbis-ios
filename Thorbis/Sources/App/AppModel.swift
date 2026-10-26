import Foundation
import Observation
import ThorbisCore

/// Where the app is in its session lifecycle.
enum Phase: Equatable {
    case launching
    case signedOut
    case choosingOrganization([Organization])
    case signedIn
}

/// One shared, observable cache of the workspace for the signed-in person.
/// The server stays the authority: every mutation goes through `ThorbisAPI`
/// and the cache is replaced with what the server returns, never guessed.
@MainActor
@Observable
final class AppModel {
    private(set) var phase: Phase = .launching
    private(set) var environment: APIEnvironment
    private(set) var account: Account?
    private(set) var organization: Organization?

    private(set) var jobs: [Job] = []
    private(set) var customers: [Customer] = []
    private(set) var estimates: [Estimate] = []
    private(set) var invoices: [Invoice] = []
    private(set) var notices: [StaffNotice] = []
    private(set) var assignees: [Assignee] = []

    private(set) var isRefreshing = false
    private(set) var refreshError: String?
    private(set) var noticesError: String?
    private(set) var lastRefreshed: Date?

    let isFixture: Bool
    @ObservationIgnored private(set) var api: ThorbisAPI
    @ObservationIgnored private let keychain = KeychainStore()
    @ObservationIgnored private let defaults: UserDefaults

    /// Bumped whenever the workspace changes, so a refresh started for the
    /// previous workspace or session can't write its results into this one.
    @ObservationIgnored private var generation = 0
    /// Set when the app opened offline with a saved session and still needs
    /// to confirm the session and load who is signed in.
    @ObservationIgnored private var needsIdentity = false
    /// Records saved (e.g. after a job action) while a refresh is in flight; the
    /// refresh's older snapshot must not overwrite them.
    @ObservationIgnored private var storedDuringRefresh: Set<String> = []

    private static let environmentKey = "thorbis.environment"

    init(defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        #if DEBUG
        let fixture = arguments.contains("--ui-fixture") || arguments.contains("--preview")
        #else
        let fixture = false
        #endif
        isFixture = fixture
        if arguments.contains("--reset") {
            defaults.removeObject(forKey: Self.environmentKey)
            KeychainStore().clearAll()
        }

        let saved = defaults.data(forKey: Self.environmentKey).flatMap { try? JSONDecoder().decode(APIEnvironment.self, from: $0) }
        let environment = saved ?? .production
        self.environment = environment
        let keychain = KeychainStore()
        #if DEBUG
        if fixture {
            api = ThorbisAPI(environment: environment, transport: FixtureTransport())
            return
        }
        #endif
        api = ThorbisAPI(
            environment: environment,
            credentials: keychain.load(for: environment),
            onCredentialsChange: { credentials in keychain.save(credentials, for: environment) }
        )
    }

    // MARK: Session

    func bootstrap() async {
        #if DEBUG
        if isFixture {
            _ = try? await api.signIn(email: "mike@example.com", password: "fixture")
        }
        #endif
        guard await api.credentials.isSignedIn else {
            phase = .signedOut
            return
        }
        await resumeSession()
    }

    func signIn(email: String, password: String) async throws {
        let session = try await api.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        try await finishSignIn(session)
    }

    func useDevIdentity() async throws {
        try await api.useDevIdentity()
        await enterDevWorkspace()
    }

    func chooseOrganization(_ organization: Organization) async throws {
        try await api.setActiveOrganization(organization.id)
        self.organization = organization
        clearWorkspace()
        phase = .signedIn
        await loadAccount()
        await refreshAll()
    }

    func switchOrganization() async {
        do {
            let organizations = try await api.organizations()
            phase = .choosingOrganization(organizations)
        } catch {
            handle(error)
        }
    }

    func signOut() async {
        await api.signOut()
        clearWorkspace()
        account = nil
        organization = nil
        phase = .signedOut
    }

    func setEnvironment(_ environment: APIEnvironment) async {
        guard environment != self.environment else { return }
        await api.signOut()
        self.environment = environment
        defaults.set(try? JSONEncoder().encode(environment), forKey: Self.environmentKey)
        let keychain = keychain
        api = ThorbisAPI(
            environment: environment,
            credentials: keychain.load(for: environment),
            onCredentialsChange: { credentials in keychain.save(credentials, for: environment) }
        )
        clearWorkspace()
        phase = .signedOut
    }

    private func resumeSession() async {
        if case .devHeaders = await api.credentials {
            await enterDevWorkspace()
            return
        }
        do {
            let session = try await api.session()
            try await finishSignIn(session)
        } catch APIError.unauthenticated {
            phase = .signedOut
        } catch {
            // Offline at launch with a saved session: open the app and let lists show the problem.
            // The next refresh retries the session before anything is shown as "mine".
            needsIdentity = true
            phase = .signedIn
            refreshError = message(for: error)
        }
    }

    /// The local API's dev headers act as a fixed user; use that id so "Mine" matches assignments.
    private func enterDevWorkspace() async {
        let user = (try? await api.me()) ?? Account(id: ThorbisAPI.devUserId, name: "Local dev", email: nil)
        account = user
        organization = Organization(id: ThorbisAPI.devOrganizationId, name: "Local workspace")
        phase = .signedIn
        await refreshAll()
    }

    private func finishSignIn(_ session: AuthSession) async throws {
        // The session already names the user; /v1/me only adds detail, so "Mine" never
        // depends on that second request succeeding.
        if account?.id != session.user.id {
            account = Account(id: session.user.id, name: session.user.name, email: session.user.email)
        }
        if let activeOrganizationId = session.session.activeOrganizationId {
            // The name is cosmetic here; the session already has its workspace.
            let organizations = (try? await api.organizations()) ?? []
            organization = organizations.first { $0.id == activeOrganizationId } ?? Organization(id: activeOrganizationId, name: "Workspace")
        } else {
            // Without a workspace the list decides what happens next, so a failure must surface.
            let organizations = try await api.organizations()
            if organizations.count == 1, let only = organizations.first {
                try await api.setActiveOrganization(only.id)
                organization = only
            } else {
                phase = .choosingOrganization(organizations)
                return
            }
        }
        phase = .signedIn
        await loadAccount()
        await refreshAll()
    }

    private func loadAccount() async {
        if let account = try? await api.me() { self.account = account }
    }

    private func clearWorkspace() {
        generation += 1
        needsIdentity = false
        jobs = []; customers = []; estimates = []; invoices = []; notices = []; assignees = []
        refreshError = nil; noticesError = nil; lastRefreshed = nil
        isRefreshing = false
    }

    /// Finishes an offline launch once the server is reachable again. Returns
    /// true when the caller should still load lists (the server is still unreachable).
    private func restoreIdentity() async -> Bool {
        do {
            let session = try await api.session()
            needsIdentity = false
            try await finishSignIn(session)
            return false // finishSignIn ran its own refresh, or is asking for a workspace
        } catch {
            handle(error)
            return phase == .signedIn
        }
    }

    // MARK: Loading

    func refreshAll() async {
        guard phase == .signedIn, !isRefreshing else { return }
        if needsIdentity {
            let loadHere = await restoreIdentity()
            guard loadHere, phase == .signedIn, !isRefreshing else { return }
        }
        let started = generation
        isRefreshing = true
        storedDuringRefresh = []
        defer {
            if started == generation {
                isRefreshing = false
                storedDuringRefresh = []
            }
        }
        let api = api
        async let jobs = Self.attempt { try await api.jobs() }
        async let customers = Self.attempt { try await api.customers() }
        async let estimates = Self.attempt { try await api.estimates() }
        async let invoices = Self.attempt { try await api.invoices() }
        async let notices = Self.attempt { try await api.staffNotices() }
        async let assignees = Self.attempt { try await api.assignees() }
        let results = await (jobs, customers, estimates, invoices, notices, assignees)
        // The workspace changed while this was loading; these records belong to the old one.
        guard started == generation else { return }

        var failures: [Error] = []
        func take<T>(_ result: Result<T, Error>, _ assign: (T) -> Void) {
            switch result {
            case let .success(value): assign(value)
            case let .failure(error): failures.append(error)
            }
        }
        take(results.0) { self.jobs = merge($0, keeping: self.jobs, kind: "job") }
        take(results.1) { self.customers = merge($0, keeping: self.customers, kind: "customer") }
        // Money and inbox may be outside a role's grants; a refusal there must not hide jobs.
        take(results.2) { self.estimates = merge($0, keeping: self.estimates, kind: "estimate") }
        take(results.3) { self.invoices = merge($0, keeping: self.invoices, kind: "invoice") }
        switch results.4 {
        case let .success(value): self.notices = value; noticesError = nil
        case let .failure(error): if !Self.isPermission(error) { noticesError = message(for: error) }
        }
        if case let .success(value) = results.5 { self.assignees = value }
        if let first = failures.first(where: { !Self.isPermission($0) }) {
            handle(first)
        } else {
            refreshError = nil
            lastRefreshed = Date()
        }
    }

    func refreshNotices() async {
        let started = generation
        do {
            let value = try await api.staffNotices()
            guard started == generation else { return }
            notices = value
            noticesError = nil
        } catch {
            guard started == generation else { return }
            noticesError = message(for: error)
        }
    }

    /// Runs a request whose result will land in this workspace's cache. If the
    /// workspace changes while it is in flight, the result is dropped (it belongs
    /// to the previous workspace) and the caller sees a cancellation. A failure is
    /// dropped the same way, so an old session's 401 can't sign out the new one.
    func send<T: Sendable>(_ request: @MainActor (ThorbisAPI) async throws -> T) async throws -> T {
        let started = generation
        let result: T
        do {
            result = try await request(api)
        } catch {
            guard started == generation else { throw CancellationError() }
            throw error
        }
        guard started == generation else { throw CancellationError() }
        return result
    }

    /// Applies a refresh snapshot, keeping any record saved after the refresh began.
    private func merge<T: Identifiable>(_ fresh: [T], keeping current: [T], kind: String) -> [T] where T.ID == String {
        let touched = current.filter { storedDuringRefresh.contains("\(kind):\($0.id)") }
        guard !touched.isEmpty else { return fresh }
        let newer = Dictionary(touched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let freshIds = Set(fresh.map(\.id))
        return touched.filter { !freshIds.contains($0.id) } + fresh.map { newer[$0.id] ?? $0 }
    }

    private func noteStored(_ kind: String, _ id: String) {
        if isRefreshing { storedDuringRefresh.insert("\(kind):\(id)") }
    }

    nonisolated static func attempt<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async -> Result<T, Error> {
        do { return .success(try await body()) } catch { return .failure(error) }
    }

    private static func isPermission(_ error: Error) -> Bool {
        if case let APIError.problem(status, _) = error { return status == 403 }
        return false
    }

    // MARK: Cache

    var unreadNotices: Int { notices.filter { !$0.read }.count }
    var userId: String? { account?.id }

    func customer(_ id: String?) -> Customer? { customers.first { $0.id == id } }
    func customerName(_ id: String?) -> String { customer(id)?.name ?? "Customer" }
    func assigneeName(_ id: String?) -> String? {
        guard let id else { return nil }
        if id == account?.id { return "You" }
        return assignees.first { $0.userId == id }?.displayName
    }

    func cached(job id: String) -> Job? { jobs.first { $0.id == id } }

    func store(_ job: Job) {
        noteStored("job", job.id)
        if let index = jobs.firstIndex(where: { $0.id == job.id }) { jobs[index] = job } else { jobs.insert(job, at: 0) }
    }

    func store(_ customer: Customer) {
        noteStored("customer", customer.id)
        if let index = customers.firstIndex(where: { $0.id == customer.id }) { customers[index] = customer } else { customers.append(customer) }
    }

    func store(_ estimate: Estimate) {
        noteStored("estimate", estimate.id)
        if let index = estimates.firstIndex(where: { $0.id == estimate.id }) { estimates[index] = estimate } else { estimates.insert(estimate, at: 0) }
    }

    func store(_ invoice: Invoice) {
        noteStored("invoice", invoice.id)
        if let index = invoices.firstIndex(where: { $0.id == invoice.id }) { invoices[index] = invoice } else { invoices.insert(invoice, at: 0) }
    }

    func markNoticesRead() async {
        do {
            let fresh = try await send { api in
                try await api.markNoticesRead()
                return try await api.staffNotices()
            }
            notices = fresh
            noticesError = nil
        } catch is CancellationError {
        } catch { handle(error) }
    }

    // MARK: Errors

    /// Central error routing: an ended session returns to sign-in; anything else is shown in place.
    func handle(_ error: Error) {
        switch error as? APIError {
        case .unauthenticated?:
            clearWorkspace()
            phase = .signedOut
        case .noActiveOrganization?:
            Task { await switchOrganization() }
        default:
            refreshError = error.localizedDescription
        }
    }

    /// What to show for a failed request, or nil when there is nothing to show:
    /// a cancelled request, or one that belonged to a workspace the user has left.
    func message(for error: Error) -> String? {
        if error is CancellationError { return nil }
        if case APIError.unauthenticated = error { handle(error) }
        return error.localizedDescription
    }
}
