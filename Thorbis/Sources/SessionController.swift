import Foundation

struct SessionUser: Codable, Identifiable, Equatable {
    let id: String
    let name: String?
    let email: String?
}

struct SessionOrganization: Codable, Identifiable, Equatable {
    let id: String
    let name: String
}

struct FeatureDecision: Codable, Equatable {
    let enabled: Bool
    let released: Bool
    let entitled: Bool
    let stage: String?
    let reason: String?
}

private struct SessionPayload: Decodable {
    struct Session: Decodable {
        let userId: String?
        let activeOrganizationId: String?
        let expiresAt: String
    }
    let user: SessionUser
    let session: Session
}

private struct CatalogPayload: Decodable {
    struct Authority: Decodable {
        let actorId: String
        let organizationId: String
        let policyVersion: Int
        let generation: String
        let authorityExpiresAt: String?
    }
    let authority: Authority
    let authorityExpiresAt: String?
    let capabilities: [String]
    let resources: [APIClient.EmptyResponse]
    let views: [APIClient.EmptyResponse]
}

private struct FeaturesPayload: Decodable {
    let organizationId: String
    let evaluatedAt: String
    let features: [String: FeatureDecision]
}

/// What a revalidation compares. When any part (or the API origin) differs from what the session
/// holds, `authorityRevision` changes before the new authority is published, retiring work captured
/// under the old one, and reads the server refused under the old authority are asked again
/// (`APIClient.forgetRefusedReads`). An identical answer changes neither; only
/// `verificationRevision` ticks.
struct SessionAuthority: Equatable {
    let capabilities: Set<String>
    let features: [String: FeatureDecision]
    let policyVersion: Int?
    let generation: String?
}

private struct SessionValidationError: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

/// Owns the authenticated actor and one active workspace. Every transition retires its
/// old generation before network work, so late responses cannot republish old authority.
@MainActor
final class SessionController: ObservableObject {
    private static let explicitSignOutKey = "thorbis.session.explicitlySignedOut"
    enum Phase: Equatable {
        case restoring
        case signedOut
        case choosingWorkspace
        case noWorkspace
        case ready
        case failed
    }

    @Published private(set) var phase: Phase = .restoring
    @Published private(set) var user: SessionUser?
    @Published private(set) var organizations: [SessionOrganization] = []
    @Published private(set) var activeOrganization: SessionOrganization?
    @Published private(set) var capabilities: Set<String> = []
    @Published private(set) var features: [String: FeatureDecision] = [:]
    @Published private(set) var error: String?
    /// The server could not be reached at the last check; cached authority and data are in use.
    @Published private(set) var isOffline = false
    /// Policy version of the verified authority; offline command envelopes carry it.
    private(set) var policyVersion: Int?
    private(set) var authorityGeneration: String?
    private var authorityOrigin: String?

    var priceBookAuthority: PriceBookAuthority? {
        guard can("pricebook.view", feature: "price_book"), let actor = user?.id,
              let policyVersion, policyVersion > 0, let authorityGeneration, !authorityGeneration.isEmpty,
              let authorityOrigin, authorityOrigin == api.normalizedOrigin else { return nil }
        return PriceBookAuthority(actorID: actor, policyVersion: policyVersion,
                                  generation: authorityGeneration, revision: authorityRevision)
    }

    /// Changes before new authority is published: on sign-in, restore, a workspace switch and offline
    /// adoption, and when a revalidation finds different capabilities, features, policy version,
    /// authority generation or API origin (even at the same policy version). An identical revalidation
    /// keeps it, so open work survives a foreground or reconnect check. Work captured under it must
    /// stop or reauthorize when it changes. Visible per-job records (media, files) key on
    /// `recheckRevision`; reloads that should follow every answered check use `verificationRevision`.
    @Published private(set) var authorityRevision = UUID() {
        didSet {
            recheckRevision = UUID()
            ScopedRecordFavorites.shared.retireSession(generation: generation, authority: oldValue)
        }
    }
    /// Changes with `authorityRevision` and, before new authority is published, on every revalidation
    /// the server answers, even an identical one. Which jobs a person is assigned to is not part of the
    /// compared authority, so surfaces that show per-job records the server authorizes one by one
    /// (visible media and files, a customer's record lists) key on this to re-check access on every
    /// foreground and reconnect, as they always have.
    @Published private(set) var recheckRevision = UUID()
    /// Ticks after every check the server answered: each successful `revalidate()` (scene active,
    /// reconnect, offline backoff, saved-copy fallback) and each authority load. It means only "the
    /// server confirmed this session again", never "access changed". Reload data on it (`.task(id:)`,
    /// freshness windows); never capture it to guard or retire in-flight work: that is `authorityRevision`.
    @Published private(set) var verificationRevision = UUID()
    private(set) var generation = UUID() {
        didSet { ScopedRecordFavorites.shared.retireSession(generation: oldValue, authority: authorityRevision) }
    }
    var onInvalidate: (() -> Void)?
    /// Called after verified policy publication when job access has been revoked.
    var onJobAuthorityRevoked: (() -> Void)?
    /// Non-nil only after actor and workspace authority are verified. A nil pair
    /// retires session-owned drafts; ordinary foreground revalidation does not.
    var onVerifiedIdentity: ((_ actorID: String?, _ organizationID: String?) -> Void)?
    /// Explicit sign-out only: device copies of work (cache, unsent changes) are deleted.
    var onSignedOut: (() -> Void)?
    /// Awaited before sign-out or a workspace switch, while the session still authorizes requests.
    var onWillUnbindDevice: (() async -> Void)?

    /// Whether the workspace has a feature on, independent of a capability.
    func isFeatureOn(_ feature: String) -> Bool {
        guard let decision = features[feature] else { return false }
        return decision.enabled && decision.released && decision.entitled
    }

    private let api: APIClient
    private let defaults: UserDefaults
    private var sessionDeadline: Date?
    private var authorityDeadline: Date?
    private var expiryTask: Task<Void, Never>?
    /// True while sign-out runs, so the waiting screen says "Signing out" instead of "Opening".
    @Published private(set) var signingOut = false
    private var revalidation: UUID?
    private let snapshots: SessionSnapshotStoring

    init(api: APIClient, defaults: UserDefaults = .standard, snapshots: SessionSnapshotStoring? = nil) {
        self.api = api
        self.defaults = defaults
        self.snapshots = snapshots ?? (defaults == .standard ? KeychainSessionSnapshotStore.shared : MemorySessionSnapshotStore())
        api.onUnauthorized = { [weak self] in self?.invalidateUnauthorizedSession() }
    }

    func can(_ capability: String, feature: String? = nil) -> Bool {
        guard phase == .ready,
              let sessionDeadline, Date() < sessionDeadline,
              authorityDeadline.map({ Date() < $0 }) ?? true,
              capabilities.contains(capability)
        else { return false }
        guard let feature else { return true }
        guard let decision = features[feature] else { return false }
        return decision.enabled && decision.released && decision.entitled
    }

    func can(capability: String, feature: String? = nil) -> Bool {
        can(capability, feature: feature)
    }

    /// Paper 65B: after the server saved a new name, show it everywhere without a full restore.
    func applySavedName(_ name: String) {
        guard let current = user else { return }
        user = SessionUser(id: current.id, name: name, email: current.email)
    }

    func restore() async {
        guard !signingOut else { return }
        let requestGeneration = invalidate(next: .restoring)
        if defaults.bool(forKey: Self.explicitSignOutKey) {
            api.clearSessionCookies()
            phase = .signedOut
            onVerifiedIdentity?(nil, nil)
            return
        }
        await loadSession(generation: requestGeneration)
    }

    /// Foreground and reconnect check. Keeps the session, the loaded work and the
    /// user's place in the app; only a changed identity, a signed-out or expired
    /// session, or a 401 falls back to a full restore. No signal keeps the session.
    func revalidate() async {
        guard !signingOut else { return }
        guard phase == .ready, let currentUser = user, let currentOrganization = activeOrganization else {
            if phase == .failed || phase == .restoring { await restore() }
            return
        }
        let token = UUID()
        revalidation = token
        let sessionGeneration = generation
        do {
            let payload: SessionPayload? = try await api.send("GET", "/api/auth/get-session", authed: false)
            guard revalidation == token, generation == sessionGeneration, phase == .ready else { return }
            guard let payload, payload.user.id == currentUser.id,
                  payload.session.activeOrganizationId == currentOrganization.id,
                  let sessionExpiry = Self.date(payload.session.expiresAt), Date() < sessionExpiry
            else { await restore(); return }
            let catalog: CatalogPayload = try await api.send("GET", "/v1/query/catalog", authed: false)
            guard revalidation == token, generation == sessionGeneration, phase == .ready else { return }
            let binding = catalog.authority
            guard binding.actorId == currentUser.id, binding.organizationId == currentOrganization.id,
                  binding.policyVersion > 0, !binding.generation.isEmpty
            else { await restore(); return }
            var authorityExpiry: Date?
            if let raw = catalog.authorityExpiresAt ?? binding.authorityExpiresAt {
                guard let parsed = Self.date(raw), Date() < parsed else { await restore(); return }
                authorityExpiry = parsed
            }
            let exposure: FeaturesPayload = try await api.send("GET", "/v1/features", authed: false)
            guard revalidation == token, generation == sessionGeneration, phase == .ready else { return }
            guard exposure.organizationId == currentOrganization.id else { await restore(); return }
            let held = SessionAuthority(capabilities: capabilities, features: features,
                                        policyVersion: policyVersion, generation: authorityGeneration)
            let fresh = SessionAuthority(capabilities: Set(catalog.capabilities), features: exposure.features,
                                         policyVersion: binding.policyVersion, generation: binding.generation)
            // An identical answer keeps the revision, so a foreground or reconnect check leaves open
            // work (a customer's approval, an open document, a held create) as it was.
            if held != fresh || authorityOrigin != api.normalizedOrigin {
                api.forgetRefusedReads()
                // Changed before the new authority is published, so work captured under the old one retires.
                authorityRevision = UUID()
            } else {
                // Per-job records (media, a customer's lists) are re-checked on every answered check.
                recheckRevision = UUID()
            }
            capabilities = Set(catalog.capabilities)
            features = exposure.features
            sessionDeadline = sessionExpiry
            authorityDeadline = authorityExpiry
            policyVersion = binding.policyVersion
            authorityGeneration = binding.generation
            authorityOrigin = api.normalizedOrigin
            if !can("job.view", feature: "jobs") { onJobAuthorityRevoked?() }
            isOffline = false
            expiryTask?.cancel()
            scheduleExpiry(generation: sessionGeneration, deadline: min(sessionExpiry, authorityExpiry ?? sessionExpiry))
            saveSnapshot()
            // Last, so a subscriber sees the whole verified state it announces.
            verificationRevision = UUID()
        } catch is CancellationError {
        } catch {
            guard revalidation == token, generation == sessionGeneration, phase == .ready else { return }
            // Unreachable or failing server: keep working on the verified session until its own deadlines.
            if error.isTransientServerFailure { isOffline = true } else { await restore() }
        }
    }

    private func saveSnapshot() {
        guard phase == .ready, let user, let activeOrganization, let sessionDeadline, let policyVersion else { return }
        snapshots.save(SessionSnapshot(user: user, organization: activeOrganization, organizations: organizations,
                                       capabilities: capabilities.sorted(), features: features, policyVersion: policyVersion,
                                       sessionDeadline: sessionDeadline, authorityDeadline: authorityDeadline,
                                       authorityGeneration: authorityGeneration, authorityOrigin: authorityOrigin))
    }

    /// Cold launch with no signal: adopt the last verified authority if it has not expired.
    private func adoptSnapshot(generation requestGeneration: UUID) -> Bool {
        guard generation == requestGeneration, let snapshot = snapshots.load(),
              Date() < snapshot.sessionDeadline, snapshot.authorityDeadline.map({ Date() < $0 }) ?? true
        else { return false }
        authorityRevision = UUID()
        user = snapshot.user
        organizations = snapshot.organizations
        activeOrganization = snapshot.organization
        capabilities = Set(snapshot.capabilities)
        features = snapshot.features
        sessionDeadline = snapshot.sessionDeadline
        authorityDeadline = snapshot.authorityDeadline
        policyVersion = snapshot.policyVersion
        authorityGeneration = snapshot.authorityOrigin == api.normalizedOrigin ? snapshot.authorityGeneration : nil
        authorityOrigin = authorityGeneration == nil ? nil : snapshot.authorityOrigin
        api.auth = .session
        api.displayName = snapshot.user.name ?? snapshot.user.email ?? ""
        error = nil
        isOffline = true
        phase = .ready
        if !can("job.view", feature: "jobs") { onJobAuthorityRevoked?() }
        onVerifiedIdentity?(snapshot.user.id, snapshot.organization.id)
        scheduleExpiry(generation: requestGeneration,
                       deadline: min(snapshot.sessionDeadline, snapshot.authorityDeadline ?? snapshot.sessionDeadline))
        return true
    }

    func signIn(email: String, password: String) async {
        guard !signingOut else { return }
        let requestGeneration = invalidate(next: .signedOut)
        defaults.set(true, forKey: Self.explicitSignOutKey)
        api.clearSessionCookies()
        do {
            struct Credentials: Encodable { let email: String; let password: String }
            let _: APIClient.EmptyResponse = try await api.send(
                "POST", "/api/auth/sign-in/email",
                body: Credentials(email: email, password: password), authed: false
            )
            guard generation == requestGeneration else { return }
            await loadSession(generation: requestGeneration)
            guard generation == requestGeneration else { return }
            if phase == .ready || phase == .choosingWorkspace || phase == .noWorkspace {
                defaults.set(false, forKey: Self.explicitSignOutKey)
            }
        } catch {
            fail(error, generation: requestGeneration)
        }
    }

    /// Owner registration (Better Auth `POST /api/auth/sign-up/email`). A new account has no
    /// workspace yet, so this lands on `.noWorkspace`, where the owner names their company.
    func signUp(name: String, email: String, password: String) async {
        guard !signingOut else { return }
        let requestGeneration = invalidate(next: .signedOut)
        defaults.set(true, forKey: Self.explicitSignOutKey)
        api.clearSessionCookies()
        do {
            struct Registration: Encodable { let name: String; let email: String; let password: String }
            let _: APIClient.EmptyResponse = try await api.send(
                "POST", "/api/auth/sign-up/email",
                body: Registration(name: name, email: email, password: password), authed: false
            )
            guard generation == requestGeneration else { return }
            await loadSession(generation: requestGeneration)
            guard generation == requestGeneration else { return }
            if phase == .ready || phase == .choosingWorkspace || phase == .noWorkspace {
                defaults.set(false, forKey: Self.explicitSignOutKey)
            }
        } catch {
            fail(error, generation: requestGeneration)
        }
    }

    /// Set when this phone just created a company, so the owner is walked through setup once.
    @Published var startBusinessSetup = false

    /// Creates a company the signed-in account owns (Better Auth `POST /api/auth/organization/create`,
    /// which makes the creator its owner), then opens it like any other workspace.
    /// Throws so the form can keep what was typed and say why.
    func createCompany(name: String) async throws {
        guard !signingOut, user != nil else { throw Problem(title: nil, status: nil, detail: "Sign in again to create a company.") }
        struct NewCompany: Encodable { let name: String; let slug: String }
        let created: SessionOrganization = try await api.send(
            "POST", "/api/auth/organization/create",
            body: NewCompany(name: name, slug: CompanySlug.make(from: name)), authed: false
        )
        guard !created.id.isEmpty else { throw Problem(title: nil, status: nil, detail: "The company was not created. Try again.") }
        if !organizations.contains(where: { $0.id == created.id }) { organizations.append(created) }
        startBusinessSetup = true
        await selectOrganization(id: created.id)
    }

    func selectOrganization(id: String) async {
        guard !signingOut else { return }
        guard organizations.contains(where: { $0.id == id }), user != nil else {
            error = "That workspace is unavailable."
            return
        }
        let knownOrganizations = organizations
        // Notifications for the old workspace stop before the switch.
        await onWillUnbindDevice?()
        snapshots.clear()
        // The widgets drop the old workspace's jobs before the new one writes its own.
        TodaySnapshot.clear()
        let requestGeneration = invalidate(next: .restoring)
        do {
            struct Selection: Encodable { let organizationId: String }
            let _: APIClient.EmptyResponse = try await api.send(
                "POST", "/api/auth/organization/set-active",
                body: Selection(organizationId: id), authed: false
            )
            guard generation == requestGeneration else { return }
            await loadSession(generation: requestGeneration, expectedOrganization: id,
                              knownOrganizations: knownOrganizations)
        } catch {
            fail(error, generation: requestGeneration)
        }
    }

    func signOut() async {
        guard !signingOut else { return }
        signingOut = true
        defer { signingOut = false }
        await onWillUnbindDevice?()
        defaults.set(true, forKey: Self.explicitSignOutKey)
        snapshots.clear()
        PriceBookCatalog.shared.clear()
        onSignedOut?()
        onVerifiedIdentity?(nil, nil)
        let requestGeneration = invalidate(next: .restoring)
        do {
            let _: APIClient.EmptyResponse = try await api.send(
                "POST", "/api/auth/sign-out", body: [String: String](), authed: false
            )
        } catch {
            // Local access stays revoked even if the server is unavailable.
        }
        guard generation == requestGeneration else { return }
        api.clearSessionCookies()
        phase = .signedOut
    }

    private func invalidateUnauthorizedSession() {
        guard !signingOut, phase == .ready else { return }
        defaults.set(true, forKey: Self.explicitSignOutKey)
        snapshots.clear()
        invalidate(next: .failed)
        api.clearSessionCookies()
        // The Home and Lock Screen widgets stop showing customers once the session is gone.
        TodaySnapshot.clear()
        error = "Your session expired. Sign in again."
    }

    @discardableResult
    private func invalidate(next: Phase) -> UUID {
        authorityRevision = UUID()
        generation = UUID()
        revalidation = nil
        isOffline = false
        policyVersion = nil
        authorityGeneration = nil
        authorityOrigin = nil
        api.invalidateRequests()
        expiryTask?.cancel()
        expiryTask = nil
        sessionDeadline = nil
        authorityDeadline = nil
        capabilities = []
        features = [:]
        activeOrganization = nil
        organizations = []
        user = nil
        error = nil
        api.auth = .none
        api.displayName = ""
        phase = next
        onInvalidate?()
        if next == .signedOut || next == .failed { onVerifiedIdentity?(nil, nil) }
        return generation
    }

    private func loadSession(generation requestGeneration: UUID,
                             expectedOrganization: String? = nil,
                             knownOrganizations: [SessionOrganization]? = nil) async {
        do {
            let payload: SessionPayload? = try await api.send(
                "GET", "/api/auth/get-session", authed: false
            )
            guard generation == requestGeneration else { return }
            guard let payload else {
                // The server says this session is gone: the offline copy must not reopen it.
                snapshots.clear()
                phase = .signedOut
                onVerifiedIdentity?(nil, nil)
                return
            }
            guard !payload.user.id.isEmpty,
                  payload.session.userId.map({ $0 == payload.user.id }) ?? true,
                  let sessionExpiry = Self.date(payload.session.expiresAt)
            else { throw SessionValidationError(reason: "Invalid session identity.") }
            guard Date() < sessionExpiry else {
                snapshots.clear()
                phase = .signedOut
                onVerifiedIdentity?(nil, nil)
                return
            }
            let memberships: [SessionOrganization]
            if let knownOrganizations {
                memberships = knownOrganizations
            } else {
                do {
                    memberships = try await api.send("GET", "/api/auth/organization/list", authed: false)
                } catch {
                    // The server has just said whose session this is and which company it has open.
                    // When that is not the offline copy's account and company, and the list cannot be
                    // read to show the person still belongs there, the copy is forgotten. Otherwise
                    // `fail` below, or the next launch without signal, would reopen a company the
                    // person was removed from (removal nulls the active company).
                    if generation == requestGeneration, let held = snapshots.load(),
                       held.user.id != payload.user.id || held.organization.id != payload.session.activeOrganizationId {
                        snapshots.clear()
                    }
                    throw error
                }
                guard generation == requestGeneration else { return }
            }
            guard Set(memberships.map(\.id)).count == memberships.count,
                  memberships.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty })
            else { throw SessionValidationError(reason: "Invalid workspace list.") }
            // A removed member's sessions come back with no active company (the server nulls it), so
            // the offline copy is forgotten here, before the no-workspace and picker paths, whenever
            // it names another account or a company this account no longer belongs to. Otherwise a
            // later launch without signal would reopen the company the person was removed from.
            if let held = snapshots.load(),
               held.user.id != payload.user.id || !memberships.contains(where: { $0.id == held.organization.id }) {
                snapshots.clear()
            }
            user = payload.user
            organizations = memberships
            sessionDeadline = sessionExpiry
            if memberships.isEmpty {
                phase = .noWorkspace
                onVerifiedIdentity?(nil, nil)
                return
            }
            if let expectedOrganization, payload.session.activeOrganizationId != expectedOrganization {
                throw SessionValidationError(reason: "Workspace activation was not confirmed.")
            }
            guard let activeId = payload.session.activeOrganizationId else {
                if memberships.count == 1 {
                    await activateOnlyOrganization(memberships[0].id, generation: requestGeneration,
                                                   memberships: memberships)
                } else {
                    phase = .choosingWorkspace
                    onVerifiedIdentity?(nil, nil)
                }
                return
            }
            guard let active = memberships.first(where: { $0.id == activeId }) else {
                throw SessionValidationError(reason: "Active workspace is not a membership.")
            }
            await loadAuthority(for: payload.user, organization: active,
                                sessionExpiry: sessionExpiry, generation: requestGeneration)
        } catch {
            fail(error, generation: requestGeneration)
        }
    }

    private func activateOnlyOrganization(_ id: String, generation requestGeneration: UUID,
                                          memberships: [SessionOrganization]) async {
        do {
            struct Selection: Encodable { let organizationId: String }
            let _: APIClient.EmptyResponse = try await api.send(
                "POST", "/api/auth/organization/set-active",
                body: Selection(organizationId: id), authed: false
            )
            guard generation == requestGeneration else { return }
            await loadSession(generation: requestGeneration, expectedOrganization: id,
                              knownOrganizations: memberships)
        } catch {
            fail(error, generation: requestGeneration)
        }
    }

    private func loadAuthority(for actor: SessionUser, organization: SessionOrganization,
                               sessionExpiry: Date, generation requestGeneration: UUID) async {
        do {
            let catalog: CatalogPayload = try await api.send("GET", "/v1/query/catalog", authed: false)
            guard generation == requestGeneration else { return }
            let binding = catalog.authority
            guard binding.actorId == actor.id, binding.organizationId == organization.id,
                  binding.policyVersion > 0, !binding.generation.isEmpty,
                  Set(catalog.capabilities).count == catalog.capabilities.count,
                  catalog.capabilities.allSatisfy({ !$0.isEmpty })
            else { throw SessionValidationError(reason: "Workspace authority could not be verified.") }
            let authorityExpiry: Date?
            if let raw = catalog.authorityExpiresAt ?? binding.authorityExpiresAt {
                guard let parsed = Self.date(raw), Date() < parsed else {
                    throw SessionValidationError(reason: "Workspace authority has expired.")
                }
                authorityExpiry = parsed
            } else {
                authorityExpiry = nil
            }
            let exposure: FeaturesPayload = try await api.send("GET", "/v1/features", authed: false)
            guard generation == requestGeneration else { return }
            guard exposure.organizationId == organization.id,
                  Self.date(exposure.evaluatedAt) != nil
            else { throw SessionValidationError(reason: "Workspace features could not be verified.") }
            self.authorityRevision = UUID()
            self.user = actor
            self.activeOrganization = organization
            self.capabilities = Set(catalog.capabilities)
            self.features = exposure.features
            self.sessionDeadline = sessionExpiry
            self.authorityDeadline = authorityExpiry
            self.api.auth = .session
            self.api.displayName = actor.name ?? actor.email ?? ""
            self.policyVersion = binding.policyVersion
            self.authorityGeneration = binding.generation
            self.authorityOrigin = api.normalizedOrigin
            self.error = nil
            self.phase = .ready
            if !can("job.view", feature: "jobs") { onJobAuthorityRevoked?() }
            saveSnapshot()
            onVerifiedIdentity?(actor.id, organization.id)
            scheduleExpiry(generation: requestGeneration,
                           deadline: min(sessionExpiry, authorityExpiry ?? sessionExpiry))
            verificationRevision = UUID()
        } catch {
            fail(error, generation: requestGeneration)
        }
    }

    private func scheduleExpiry(generation requestGeneration: UUID, deadline: Date) {
        // Capped at a year so a far-future expiry from the server can't overflow the conversion.
        let nanoseconds = UInt64(min(max(0, deadline.timeIntervalSinceNow), 31_536_000) * 1_000_000_000)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self, self.generation == requestGeneration else { return }
            self.invalidate(next: .failed)
            self.error = "Session or workspace authority expired. Sign in again."
        }
    }

    private func fail(_ failure: Error, generation requestGeneration: UUID) {
        guard generation == requestGeneration else { return }
        if failure.isTransientServerFailure, !defaults.bool(forKey: Self.explicitSignOutKey),
           adoptSnapshot(generation: requestGeneration) { return }
        let description = failure.plainMessage()
        // Only an answer that proves the session or membership is gone forgets the offline copy.
        // A captive portal or a CDN page must not end a technician's offline access.
        if failure is SessionValidationError || (failure as? Problem)?.status == 401 { snapshots.clear() }
        invalidate(next: .failed)
        error = description
    }

    #if DEBUG
    /// Screenshot fixtures only (PaperPreview states screens): show a signed-out, expired or
    /// waiting screen without a server. Not reachable outside `--paper-preview`.
    func previewForce(_ next: Phase, error message: String? = nil, signingOut out: Bool = false) {
        guard PaperPreview.enabled else { return }
        // The picker keeps the account and its companies; every other state starts clean.
        if next == .choosingWorkspace { phase = next } else if next != .ready { invalidate(next: next) }
        error = message
        signingOut = out
    }
    #endif

    private static func date(_ value: String) -> Date? { JobFiltering.date(value) }
}
