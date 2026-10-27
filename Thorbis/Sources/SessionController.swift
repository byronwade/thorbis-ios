import Foundation

struct SessionUser: Decodable, Identifiable, Equatable {
    let id: String
    let name: String?
    let email: String?
}

struct SessionOrganization: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
}

struct FeatureDecision: Decodable, Equatable {
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

    private(set) var generation = UUID()
    var onInvalidate: (() -> Void)?
    /// Non-nil only after actor and workspace authority are verified. A nil pair
    /// retires session-owned drafts; ordinary foreground revalidation does not.
    var onVerifiedIdentity: ((_ actorID: String?, _ organizationID: String?) -> Void)?

    private let api: APIClient
    private let defaults: UserDefaults
    private var sessionDeadline: Date?
    private var authorityDeadline: Date?
    private var expiryTask: Task<Void, Never>?
    private var signingOut = false

    init(api: APIClient, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
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

    func selectOrganization(id: String) async {
        guard !signingOut else { return }
        guard organizations.contains(where: { $0.id == id }), user != nil else {
            error = "That workspace is unavailable."
            return
        }
        let knownOrganizations = organizations
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
        defaults.set(true, forKey: Self.explicitSignOutKey)
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
        invalidate(next: .failed)
        api.clearSessionCookies()
        error = "Your session expired. Sign in again."
    }

    @discardableResult
    private func invalidate(next: Phase) -> UUID {
        generation = UUID()
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
                phase = .signedOut
                onVerifiedIdentity?(nil, nil)
                return
            }
            guard !payload.user.id.isEmpty,
                  payload.session.userId.map({ $0 == payload.user.id }) ?? true,
                  let sessionExpiry = Self.date(payload.session.expiresAt)
            else { throw SessionValidationError(reason: "Invalid session identity.") }
            guard Date() < sessionExpiry else {
                phase = .signedOut
                onVerifiedIdentity?(nil, nil)
                return
            }
            let memberships: [SessionOrganization]
            if let knownOrganizations {
                memberships = knownOrganizations
            } else {
                memberships = try await api.send("GET", "/api/auth/organization/list", authed: false)
                guard generation == requestGeneration else { return }
            }
            guard Set(memberships.map(\.id)).count == memberships.count,
                  memberships.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty })
            else { throw SessionValidationError(reason: "Invalid workspace list.") }
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
            self.user = actor
            self.activeOrganization = organization
            self.capabilities = Set(catalog.capabilities)
            self.features = exposure.features
            self.sessionDeadline = sessionExpiry
            self.authorityDeadline = authorityExpiry
            self.api.auth = .session
            self.api.displayName = actor.name ?? actor.email ?? ""
            self.error = nil
            self.phase = .ready
            onVerifiedIdentity?(actor.id, organization.id)
            scheduleExpiry(generation: requestGeneration,
                           deadline: min(sessionExpiry, authorityExpiry ?? sessionExpiry))
        } catch {
            fail(error, generation: requestGeneration)
        }
    }

    private func scheduleExpiry(generation requestGeneration: UUID, deadline: Date) {
        let nanoseconds = UInt64(max(0, deadline.timeIntervalSinceNow) * 1_000_000_000)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self, self.generation == requestGeneration else { return }
            self.invalidate(next: .failed)
            self.error = "Session or workspace authority expired. Sign in again."
        }
    }

    private func fail(_ failure: Error, generation requestGeneration: UUID) {
        guard generation == requestGeneration else { return }
        let description = failure.localizedDescription
        invalidate(next: .failed)
        error = description
    }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
