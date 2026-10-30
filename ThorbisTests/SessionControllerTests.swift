import XCTest
import Combine
@testable import Thorbis

@MainActor
final class SessionControllerTests: XCTestCase {
    private let actor = "019f0000-0000-7000-8000-000000000011"
    private let first = "019f0000-0000-7000-8000-000000000001"
    private let second = "019f0000-0000-7000-8000-000000000002"

    private var activeSession: String {
        #"{"user":{"id":"019f0000-0000-7000-8000-000000000011","name":"Fixture technician","email":"fixture@example.invalid","emailVerified":true},"session":{"id":"fixture-session","userId":"019f0000-0000-7000-8000-000000000011","activeOrganizationId":"019f0000-0000-7000-8000-000000000001","expiresAt":"2099-10-27T12:00:00.000Z"}}"#
    }

    private var inactiveSession: String {
        activeSession.replacingOccurrences(of: #""activeOrganizationId":"019f0000-0000-7000-8000-000000000001""#, with: #""activeOrganizationId":null"#)
    }

    private var oneOrganization: String {
        #"[{"id":"019f0000-0000-7000-8000-000000000001","name":"Fixture workspace"}]"#
    }

    private var catalog: String {
        #"{"authority":{"actorId":"019f0000-0000-7000-8000-000000000011","organizationId":"019f0000-0000-7000-8000-000000000001","policyVersion":1,"generation":"fixture-generation"},"capabilities":["job.view","customer.view"],"resources":[],"views":[]}"#
    }

    private var features: String {
        #"{"organizationId":"019f0000-0000-7000-8000-000000000001","evaluatedAt":"2026-10-26T12:00:00.000Z","features":{"jobs":{"enabled":true,"released":true,"entitled":true,"stage":"general"},"price_book":{"enabled":false,"released":false,"entitled":true,"stage":"internal","reason":"not_released"}}}"#
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "thorbis.session.tests.\(UUID().uuidString)")!
    }

    private func controller(_ replies: [URLProtocolFixture.Reply]) -> (SessionController, APIClient) {
        let api = APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")
        return (SessionController(api: api, defaults: isolatedDefaults()), api)
    }

    func testActivityRetirementNotifiedOnRevalidationRevocation() async {
        let revoked = catalog.replacingOccurrences(of: #"["job.view","customer.view"]"#, with: #"["customer.view"]"#)
        let (session, _) = controller([
            .init(200, activeSession), .init(200, oneOrganization), .init(200, catalog), .init(200, features),
            .init(200, activeSession), .init(200, revoked), .init(200, features),
            .init(200, activeSession), .init(200, catalog), .init(200, features)
        ])
        await session.restore()
        var retirementCount = 0
        session.onJobAuthorityRevoked = { retirementCount += 1 }
        await session.revalidate()
        XCTAssertEqual(retirementCount, 1)
        await session.revalidate()
        XCTAssertEqual(retirementCount, 1, "Regrant must not retire newly authorized activity")
    }

    func testMediaAuthorityRevisionChangesBeforeSameVersionRevokeAndRegrant() async {
        let revoked = catalog.replacingOccurrences(of: #"["job.view","customer.view"]"#, with: #"["customer.view"]"#)
        let (session, _) = controller([
            .init(200, activeSession), .init(200, oneOrganization), .init(200, catalog), .init(200, features),
            .init(200, activeSession), .init(200, revoked), .init(200, features),
            .init(200, activeSession), .init(200, catalog), .init(200, features)
        ])
        await session.restore()
        let generation = session.generation
        let initialRevision = session.authorityRevision
        var revokeRevision: UUID?
        var grantRevision: UUID?
        let subscription = session.$capabilities.dropFirst().sink { capabilities in
            if capabilities.contains("job.view") { grantRevision = session.authorityRevision }
            else { revokeRevision = session.authorityRevision }
        }
        await session.revalidate()
        XCTAssertFalse(session.can("job.view", feature: "jobs"))
        XCTAssertNotNil(revokeRevision)
        XCTAssertNotEqual(revokeRevision, initialRevision, "The media revision must change before revocation is published")
        let afterRevoke = session.authorityRevision
        await session.revalidate()
        XCTAssertTrue(session.can("job.view", feature: "jobs"))
        XCTAssertEqual(session.generation, generation)
        XCTAssertNotNil(grantRevision)
        XCTAssertNotEqual(grantRevision, afterRevoke, "Regrant must force a fresh media authorization")
        withExtendedLifetime(subscription) {}
    }

    func testCustomerLocationsNeverReuseAuthorityAfterRevocationAndRegrant() async {
        let enabled = features.replacingOccurrences(of: "\"jobs\":", with: "\"core_crm\":{\"enabled\":true,\"released\":true,\"entitled\":true,\"stage\":\"general\"},\"jobs\":")
        let revoked = catalog.replacingOccurrences(of: #"["job.view","customer.view"]"#, with: #"["job.view"]"#)
        let (session, api) = controller([
            .init(200, activeSession), .init(200, oneOrganization), .init(200, catalog), .init(200, enabled),
            .init(200, activeSession), .init(200, revoked), .init(200, enabled),
            .init(200, activeSession), .init(200, catalog), .init(200, enabled)
        ])
        await session.restore()
        let original = CustomerLocationScope.capture(session: session, api: api, customerID: first)!
        let location = ServiceLocationRecord(id: "location", organizationId: first, customerId: first,
            label: "Private address", kind: "service", address: "123 Main", notes: nil, coordinates: nil,
            gateCode: nil, alarmCode: nil, dogOnSite: nil, parking: nil, createdAt: "2026", updatedAt: "2026")
        var locations = CustomerScopedLocations()
        let firstRequest = locations.begin(scope: original)
        XCTAssertTrue(locations.receive([location], scope: original, request: firstRequest, current: original))
        XCTAssertEqual(locations.visible(in: original), [location])
        let delayed = locations.begin(scope: original)
        await session.revalidate()
        XCTAssertTrue(locations.visible(in: CustomerLocationScope.capture(session: session, api: api, customerID: first)).isEmpty)
        await session.revalidate()
        let regranted = CustomerLocationScope.capture(session: session, api: api, customerID: first)!
        XCTAssertNotEqual(original, regranted)
        XCTAssertTrue(locations.visible(in: regranted).isEmpty, "Old rows must not be reauthorized")
        locations.save(location, scope: original, current: regranted)
        XCTAssertTrue(locations.visible(in: regranted).isEmpty, "An old edit must not publish after regrant")
        XCTAssertFalse(locations.receive([location], scope: original, request: delayed, current: regranted))
        let fresh = locations.begin(scope: regranted)
        XCTAssertTrue(locations.receive([location], scope: regranted, request: fresh, current: regranted))
        XCTAssertEqual(locations.visible(in: regranted), [location])
        locations.remove(id: location.id, scope: original, current: regranted)
        XCTAssertEqual(locations.visible(in: regranted), [location], "An old removal must not mutate the new view")
        api.invalidateRequests()
        let invalidated = CustomerLocationScope.capture(session: session, api: api, customerID: first)
        XCTAssertTrue(locations.visible(in: invalidated).isEmpty)
    }

    func testCustomerRecordsScopeRejectsStaleCompletionAfterSameVersionRevokeAndRegrant() async {
        let enabledFeatures = features.replacingOccurrences(of: "\"jobs\":", with: "\"core_crm\":{\"enabled\":true,\"released\":true,\"entitled\":true,\"stage\":\"general\"},\"jobs\":")
        let revoked = catalog.replacingOccurrences(of: #"["job.view","customer.view"]"#, with: #"["job.view"]"#)
        let (session, _) = controller([
            .init(200, activeSession), .init(200, oneOrganization), .init(200, catalog), .init(200, enabledFeatures),
            .init(200, activeSession), .init(200, revoked), .init(200, enabledFeatures),
            .init(200, activeSession), .init(200, catalog), .init(200, enabledFeatures)
        ])
        await session.restore()
        let oldScope = CustomerRecordsScope.capture(session: session, customerID: first)
        XCTAssertNotNil(oldScope)
        let (completion, continuation) = AsyncStream<Void>.makeStream()
        var stalePublished = false
        let oldRequest = Task { @MainActor in
            for await _ in completion {
                if oldScope!.isCurrent(session: session) { stalePublished = true }
                break
            }
        }
        await session.revalidate()
        XCTAssertNil(CustomerRecordsScope.capture(session: session, customerID: first))
        await session.revalidate()
        let newScope = CustomerRecordsScope.capture(session: session, customerID: first)
        XCTAssertNotNil(newScope)
        XCTAssertNotEqual(oldScope, newScope, "A completion captured before revocation cannot publish after regrant")
        XCTAssertFalse(oldScope!.isCurrent(session: session), "An old in-flight request must fail the same guard used by the view")
        XCTAssertTrue(newScope!.isCurrent(session: session))
        XCTAssertEqual(oldScope?.generation, newScope?.generation)
        XCTAssertEqual(oldScope?.policyVersion, newScope?.policyVersion)
        continuation.yield(())
        continuation.finish()
        await oldRequest.value
        XCTAssertFalse(stalePublished, "A request that completes after regrant must not publish its old data")
    }

    func testRestoreNullSessionLeavesNoAuthority() async {
        let (session, api) = controller([.init(200, "null")])

        await session.restore()

        XCTAssertEqual(session.phase, .signedOut)
        XCTAssertNil(session.user)
        XCTAssertFalse(session.can("job.view"))
        XCTAssertEqual(api.auth, .none)
        XCTAssertEqual(URLProtocolFixture.recorded.map { $0.url?.path }, ["/api/auth/get-session"])
    }

    func testRestoreExpiredSessionDoesNotListMemberships() async {
        let expired = activeSession.replacingOccurrences(of: "2099-10-27", with: "2000-10-27")
        let (session, _) = controller([.init(200, expired)])

        await session.restore()

        XCTAssertEqual(session.phase, .signedOut)
        XCTAssertFalse(session.can("job.view"))
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
    }

    func testRestoreActiveMembershipPublishesBoundAuthorityAndFeatures() async {
        let (session, api) = controller([.init(200, activeSession), .init(200, oneOrganization), .init(200, catalog), .init(200, features)])

        await session.restore()

        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.user?.id, actor)
        XCTAssertEqual(session.activeOrganization?.id, first)
        XCTAssertTrue(session.can("job.view"))
        XCTAssertTrue(session.can("job.view", feature: "jobs"))
        XCTAssertFalse(session.can("job.view", feature: "price_book"))
        XCTAssertFalse(session.can("unknown.action"))
        XCTAssertFalse(session.can("job.view", feature: "missing"))
        XCTAssertEqual(api.auth, .session)
        XCTAssertEqual(URLProtocolFixture.recorded.map { $0.url?.path }, [
            "/api/auth/get-session", "/api/auth/organization/list", "/v1/query/catalog", "/v1/features"
        ])
    }

    func testSameIdentityForegroundRestorePreservesSessionDraftButSignOutClearsIt() async throws {
        let (session, _) = controller([
            .init(200, activeSession), .init(200, oneOrganization), .init(200, catalog), .init(200, features),
            .init(200, activeSession), .init(200, oneOrganization), .init(200, catalog), .init(200, features),
            .init(200, "{}")
        ])
        let inbox = InboxLocalDrafts()
        session.onVerifiedIdentity = { actorID, organizationID in
            if let actorID, let organizationID { inbox.bind(actorID: actorID, organizationID: organizationID) }
            else { inbox.clear() }
        }

        await session.restore()
        try inbox.save(channel: .email, recipient: "person@example.com", subject: "Visit", body: "Hello", mode: .draft)
        await session.restore()
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(inbox.messages.count, 1)

        await session.signOut()
        XCTAssertEqual(session.phase, .signedOut)
        XCTAssertTrue(inbox.messages.isEmpty)
    }

    func testMultipleMembershipsRequireExplicitSelection() async {
        let organizations = #"[{"id":"019f0000-0000-7000-8000-000000000001","name":"First"},{"id":"019f0000-0000-7000-8000-000000000002","name":"Second"}]"#
        let (session, _) = controller([.init(200, inactiveSession), .init(200, organizations)])

        await session.restore()

        XCTAssertEqual(session.phase, .choosingWorkspace)
        XCTAssertEqual(session.organizations.map(\.id), [first, second])
        XCTAssertFalse(session.can("job.view"))
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
    }

    func testNoMembershipsLeavesNeutralWorkspaceState() async {
        let (session, api) = controller([.init(200, inactiveSession), .init(200, "[]")])

        await session.restore()

        XCTAssertEqual(session.phase, .noWorkspace)
        XCTAssertEqual(session.user?.id, actor)
        XCTAssertNil(session.activeOrganization)
        XCTAssertFalse(session.can("job.view"))
        XCTAssertEqual(api.auth, .none)
    }

    func testSignInHydratesBeforePublishingWorkspace() async {
        let (session, _) = controller([
            .init(200, #"{"token":"fixture-ignored"}"#), .init(200, activeSession),
            .init(200, oneOrganization), .init(200, catalog), .init(200, features)
        ])

        await session.signIn(email: "fixture@example.invalid", password: "test-password")

        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(URLProtocolFixture.recorded.map { $0.url?.path }, [
            "/api/auth/sign-in/email", "/api/auth/get-session", "/api/auth/organization/list",
            "/v1/query/catalog", "/v1/features"
        ])
        let body = try? XCTUnwrap(URLProtocolFixture.recorded[0].body)
        let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
        XCTAssertEqual(json?["email"], "fixture@example.invalid")
        XCTAssertEqual(json?["password"], "test-password")
    }

    func testSignInFailureNeverPublishesIdentity() async {
        let (session, api) = controller([.init(401, #"{"code":"INVALID_EMAIL_OR_PASSWORD","message":"Invalid credentials"}"#)])

        await session.signIn(email: "fixture@example.invalid", password: "bad-password")

        XCTAssertEqual(session.phase, .failed)
        XCTAssertNil(session.user)
        XCTAssertFalse(session.can("job.view"))
        XCTAssertEqual(api.auth, .none)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
    }

    func testSignInKeepsLoginPhaseWhileRequestIsPending() async throws {
        let gate = URLProtocolFixture.Gate()
        let (session, _) = controller([.init(401, "{}", gate: gate)])
        let signIn = Task { await session.signIn(email: "fixture@example.invalid", password: "test-password") }
        for _ in 0..<100 where URLProtocolFixture.recorded.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(session.phase, .signedOut)
        gate.release()
        await signIn.value
    }

    func testNewSignInDoesNotReusePreviousOriginCookie() async throws {
        let gate = URLProtocolFixture.Gate()
        let transport = URLProtocolFixture.session([.init(401, "{}", gate: gate)])
        let storage = try XCTUnwrap(transport.configuration.httpCookieStorage)
        let previous = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "app.thorbis.com", .path: "/", .name: "thorbis.session", .value: "previous-account"
        ]))
        storage.setCookie(previous)
        defer { storage.deleteCookie(previous) }
        let api = APIClient(session: transport, baseURL: "https://app.thorbis.com")
        let session = SessionController(api: api, defaults: isolatedDefaults())

        let signIn = Task { await session.signIn(email: "new@example.invalid", password: "invalid") }
        for _ in 0..<100 where URLProtocolFixture.recorded.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(URLProtocolFixture.recorded.first?.url?.path, "/api/auth/sign-in/email")
        XCTAssertNil(URLProtocolFixture.recorded.first?.header("cookie"))
        XCTAssertFalse(storage.cookies?.contains(where: { $0.name == "thorbis.session" }) ?? false)
        gate.release()
        await signIn.value
    }

    func testOneMembershipIsActivatedBeforeAuthorityLoads() async {
        let (session, _) = controller([
            .init(200, inactiveSession), .init(200, oneOrganization), .init(200, "{}"),
            .init(200, activeSession), .init(200, catalog), .init(200, features)
        ])

        await session.restore()

        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(URLProtocolFixture.recorded.map { $0.url?.path }, [
            "/api/auth/get-session", "/api/auth/organization/list", "/api/auth/organization/set-active",
            "/api/auth/get-session", "/v1/query/catalog", "/v1/features"
        ])
        let body = try? XCTUnwrap(URLProtocolFixture.recorded[2].body)
        let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
        XCTAssertEqual(json?["organizationId"], first)
    }

    func testWorkspaceSelectionRevalidatesSessionAndPublishesOnlySelectedAuthority() async {
        let memberships = #"[{"id":"019f0000-0000-7000-8000-000000000001","name":"First"},{"id":"019f0000-0000-7000-8000-000000000002","name":"Second"}]"#
        let selectedSession = activeSession.replacingOccurrences(of: first, with: second)
        let selectedCatalog = catalog.replacingOccurrences(of: first, with: second)
        let selectedFeatures = features.replacingOccurrences(of: first, with: second)
        let (session, _) = controller([
            .init(200, inactiveSession), .init(200, memberships), .init(200, "{}"),
            .init(200, selectedSession), .init(200, selectedCatalog), .init(200, selectedFeatures)
        ])
        await session.restore()

        await session.selectOrganization(id: second)

        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.activeOrganization?.id, second)
        XCTAssertTrue(session.can("job.view", feature: "jobs"))
        XCTAssertEqual(URLProtocolFixture.recorded.map { $0.url?.path }, [
            "/api/auth/get-session", "/api/auth/organization/list", "/api/auth/organization/set-active",
            "/api/auth/get-session", "/v1/query/catalog", "/v1/features"
        ])
    }

    func testInvalidCatalogFailsClosed() async {
        let wrongActor = catalog.replacingOccurrences(of: actor, with: "other-actor")
        let (session, api) = controller([.init(200, activeSession), .init(200, oneOrganization), .init(200, wrongActor)])

        await session.restore()

        XCTAssertEqual(session.phase, .failed)
        XCTAssertFalse(session.can("job.view"))
        XCTAssertTrue(session.capabilities.isEmpty)
        XCTAssertEqual(api.auth, .none)
    }

    func testFailedFeatureLookupDoesNotGrantCapabilities() async {
        let (session, _) = controller([.init(200, activeSession), .init(200, oneOrganization), .init(200, catalog), .init(503, "{}")])

        await session.restore()

        XCTAssertEqual(session.phase, .failed)
        XCTAssertFalse(session.can("job.view"))
    }

    func testSignOutRevokesServerSessionAndClearsLocalAuthorityEvenOnFailure() async {
        let (session, api) = controller([
            .init(200, activeSession), .init(200, oneOrganization), .init(200, catalog), .init(200, features),
            .init(503, "{}")
        ])
        var invalidations = 0
        session.onInvalidate = { invalidations += 1 }
        await session.restore()
        let before = invalidations

        await session.signOut()

        XCTAssertEqual(session.phase, .signedOut)
        XCTAssertNil(session.user)
        XCTAssertTrue(session.capabilities.isEmpty)
        XCTAssertFalse(session.can("job.view"))
        XCTAssertEqual(api.auth, .none)
        XCTAssertEqual(invalidations, before + 1)
        XCTAssertEqual(URLProtocolFixture.recorded.last?.url?.path, "/api/auth/sign-out")
        XCTAssertEqual(URLProtocolFixture.recorded.last?.method, "POST")
    }

    func testLateRestoreResponseCannotRepublishAfterSignOut() async throws {
        let gate = URLProtocolFixture.Gate()
        let (session, api) = controller([.init(200, activeSession, gate: gate), .init(200, "{}")])
        let restore = Task { await session.restore() }
        for _ in 0..<100 where URLProtocolFixture.recorded.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(URLProtocolFixture.recorded.first?.url?.path, "/api/auth/get-session")

        await session.signOut()
        gate.release()
        await restore.value

        XCTAssertEqual(session.phase, .signedOut)
        XCTAssertNil(session.user)
        XCTAssertTrue(session.capabilities.isEmpty)
        XCTAssertEqual(api.auth, .none)
        XCTAssertEqual(URLProtocolFixture.recorded.map { $0.url?.path }, [
            "/api/auth/get-session", "/api/auth/sign-out"
        ])
    }

    func testFailedRemoteSignOutRemovesOnlySessionOriginCookie() async throws {
        let transport = URLProtocolFixture.session([
            .init(200, activeSession), .init(200, oneOrganization), .init(200, catalog),
            .init(200, features), .init(503, "{}")
        ])
        let storage = try XCTUnwrap(transport.configuration.httpCookieStorage)
        let current = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "app.thorbis.com", .path: "/", .name: "thorbis.session", .value: "old"
        ]))
        let unrelated = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "other.example", .path: "/", .name: "other.session", .value: "keep"
        ]))
        storage.setCookie(current)
        storage.setCookie(unrelated)
        defer { storage.deleteCookie(current); storage.deleteCookie(unrelated) }
        let api = APIClient(session: transport, baseURL: "https://app.thorbis.com")
        let session = SessionController(api: api, defaults: isolatedDefaults())
        await session.restore()

        await session.signOut()

        XCTAssertEqual(session.phase, .signedOut)
        XCTAssertFalse(storage.cookies?.contains(where: { $0.name == "thorbis.session" }) ?? false)
        XCTAssertTrue(storage.cookies?.contains(where: { $0.name == "other.session" }) ?? false)
    }

    func testExplicitSignOutPreventsLaterRestoreOfLateCookie() async {
        let defaults = isolatedDefaults()
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, activeSession), .init(200, oneOrganization), .init(200, catalog),
            .init(200, features), .init(200, "{}")
        ]), baseURL: "https://app.thorbis.com")
        let session = SessionController(api: api, defaults: defaults)
        await session.restore()
        await session.signOut()

        let laterAPI = APIClient(session: URLProtocolFixture.session([.init(200, activeSession)]),
                                 baseURL: "https://app.thorbis.com")
        let laterSession = SessionController(api: laterAPI, defaults: defaults)
        await laterSession.restore()

        XCTAssertEqual(laterSession.phase, .signedOut)
        XCTAssertNil(laterSession.user)
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
    }

    func testSuccessfulFreshSignInUnlocksFutureRestore() async {
        let defaults = isolatedDefaults()
        let prior = SessionController(api: APIClient(session: URLProtocolFixture.session([.init(200, "{}")]),
                                                     baseURL: "https://app.thorbis.com"), defaults: defaults)
        await prior.signOut()
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, "{}"), .init(200, activeSession), .init(200, oneOrganization),
            .init(200, catalog), .init(200, features)
        ]), baseURL: "https://app.thorbis.com")
        let session = SessionController(api: api, defaults: defaults)

        await session.signIn(email: "fixture@example.invalid", password: "new-password")

        XCTAssertEqual(session.phase, .ready)
        let future = SessionController(api: APIClient(session: URLProtocolFixture.session([.init(200, "null")]),
                                                     baseURL: "https://app.thorbis.com"), defaults: defaults)
        await future.restore()
        XCTAssertEqual(URLProtocolFixture.recorded.first?.url?.path, "/api/auth/get-session")
    }

    func testSignOutBlocksFreshSignInUntilServerReplyThenAllowsIt() async throws {
        let gate = URLProtocolFixture.Gate()
        let (session, _) = controller([
            .init(200, activeSession), .init(200, oneOrganization), .init(200, catalog),
            .init(200, features), .init(200, "{}", gate: gate),
            .init(200, "{}"), .init(200, activeSession), .init(200, oneOrganization),
            .init(200, catalog), .init(200, features)
        ])
        await session.restore()
        let signOut = Task { await session.signOut() }
        for _ in 0..<100 where URLProtocolFixture.recorded.count < 5 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(session.phase, .restoring)
        XCTAssertFalse(session.can("job.view"))

        await session.signIn(email: "fixture@example.invalid", password: "new-password")
        await session.restore()
        await session.selectOrganization(id: first)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 5)
        XCTAssertNil(session.error)
        gate.release()
        await signOut.value
        XCTAssertEqual(session.phase, .signedOut)

        await session.signIn(email: "fixture@example.invalid", password: "new-password")
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(URLProtocolFixture.recorded[5].url?.path, "/api/auth/sign-in/email")
    }

    func testAuthenticatedDetail401InvalidatesSessionAndStoreBeforeThrowing() async {
        let (session, api) = controller([
            .init(200, activeSession), .init(200, oneOrganization), .init(200, catalog),
            .init(200, features), .init(401, #"{"title":"Unauthorized","status":401}"#)
        ])
        var invalidations = 0
        session.onInvalidate = { invalidations += 1 }
        await session.restore()
        let before = invalidations

        do {
            _ = try await api.job("00000000-0000-4000-8000-000000000001")
            XCTFail("Expected unauthorized detail")
        } catch let problem as Problem {
            XCTAssertEqual(problem.status, 401)
            XCTAssertEqual(session.phase, .failed)
            XCTAssertEqual(api.auth, .none)
            XCTAssertTrue(session.capabilities.isEmpty)
            XCTAssertEqual(invalidations, before + 1)
        } catch { XCTFail("Unexpected error: \(error)") }
    }
}
