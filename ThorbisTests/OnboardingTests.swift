import XCTest
@testable import Thorbis

@MainActor
final class OnboardingTests: XCTestCase {
    private let actor = "019f0000-0000-7000-8000-000000000011"
    private let company = "019f0000-0000-7000-8000-000000000001"

    private var newAccountSession: String {
        #"{"user":{"id":"019f0000-0000-7000-8000-000000000011","name":"Dana Owner","email":"dana@example.invalid","emailVerified":false},"session":{"id":"fixture-session","userId":"019f0000-0000-7000-8000-000000000011","activeOrganizationId":null,"expiresAt":"2099-10-27T12:00:00.000Z"}}"#
    }

    private var activeSession: String {
        newAccountSession.replacingOccurrences(of: #""activeOrganizationId":null"#,
                                               with: #""activeOrganizationId":"019f0000-0000-7000-8000-000000000001""#)
    }

    private var catalog: String {
        #"{"authority":{"actorId":"019f0000-0000-7000-8000-000000000011","organizationId":"019f0000-0000-7000-8000-000000000001","policyVersion":1,"generation":"fixture-generation"},"capabilities":["organization.settings.edit","organization.members.manage"],"resources":[],"views":[]}"#
    }

    private var features: String {
        #"{"organizationId":"019f0000-0000-7000-8000-000000000001","evaluatedAt":"2026-10-28T12:00:00.000Z","features":{"jobs":{"enabled":true,"released":true,"entitled":true}}}"#
    }

    private func controller(_ replies: [URLProtocolFixture.Reply]) -> SessionController {
        let api = APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")
        return SessionController(api: api, defaults: UserDefaults(suiteName: "thorbis.onboarding.tests.\(UUID().uuidString)")!)
    }

    private func json(_ index: Int) -> [String: Any]? {
        guard let body = URLProtocolFixture.recorded[index].body else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    func testSignUpLandsOnCreateCompany() async {
        let session = controller([
            .init(200, #"{"token":"t","user":{"id":"019f0000-0000-7000-8000-000000000011","name":"Dana Owner","email":"dana@example.invalid"}}"#),
            .init(200, newAccountSession),
            .init(200, "[]"),
        ])

        await session.signUp(name: "Dana Owner", email: "dana@example.invalid", password: "correct-horse")

        XCTAssertEqual(session.phase, .noWorkspace)
        XCTAssertEqual(session.user?.name, "Dana Owner")
        XCTAssertEqual(URLProtocolFixture.recorded.map { $0.url?.path }, [
            "/api/auth/sign-up/email", "/api/auth/get-session", "/api/auth/organization/list",
        ])
        XCTAssertEqual(json(0)?["email"] as? String, "dana@example.invalid")
        XCTAssertEqual(json(0)?["name"] as? String, "Dana Owner")
    }

    func testTakenEmailStaysSignedOutWithTheServersReason() async {
        let session = controller([
            .init(422, #"{"code":"USER_ALREADY_EXISTS","message":"User already exists. Use another email."}"#),
        ])

        await session.signUp(name: "Dana", email: "dana@example.invalid", password: "correct-horse")

        XCTAssertEqual(session.phase, .failed)
        XCTAssertEqual(SignUpView.message(for: session.error),
                       "That email already has an account. Log in instead, or reset the password.")
    }

    func testCreateCompanyOpensItAndAsksForSetup() async throws {
        let session = controller([
            .init(200, #"{"token":"t","user":{"id":"019f0000-0000-7000-8000-000000000011","name":"Dana Owner","email":"dana@example.invalid"}}"#),
            .init(200, newAccountSession),
            .init(200, "[]"),
            .init(200, #"{"id":"019f0000-0000-7000-8000-000000000001","name":"Wade Plumbing","slug":"wade-plumbing-abc123","members":[]}"#),
            .init(200, "{}"),
            .init(200, activeSession),
            .init(200, catalog),
            .init(200, features),
        ])
        await session.signUp(name: "Dana Owner", email: "dana@example.invalid", password: "correct-horse")
        XCTAssertEqual(session.phase, .noWorkspace)

        try await session.createCompany(name: "Wade Plumbing")

        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.activeOrganization?.id, company)
        XCTAssertTrue(session.startBusinessSetup)
        XCTAssertTrue(session.can("organization.settings.edit"))
        let paths = URLProtocolFixture.recorded.map { $0.url?.path ?? "" }
        XCTAssertEqual(Array(paths.suffix(5)), [
            "/api/auth/organization/create", "/api/auth/organization/set-active",
            "/api/auth/get-session", "/v1/query/catalog", "/v1/features",
        ])
        let create = try XCTUnwrap(json(paths.count - 5))
        XCTAssertEqual(create["name"] as? String, "Wade Plumbing")
        XCTAssertTrue((create["slug"] as? String)?.hasPrefix("wade-plumbing-") == true)
    }

    func testSlugIsURLSafeAndNeverEmpty() {
        XCTAssertEqual(CompanySlug.make(from: "Wade’s Plumbing & Heating", suffix: "x1"), "wade-s-plumbing-heating-x1")
        XCTAssertEqual(CompanySlug.make(from: "Café Électrique", suffix: "x1"), "cafe-electrique-x1")
        XCTAssertEqual(CompanySlug.make(from: "!!!", suffix: "x1"), "company-x1")
        XCTAssertLessThanOrEqual(CompanySlug.make(from: String(repeating: "a", count: 90), suffix: "x1").count, 43)
        XCTAssertEqual(CompanySlug.randomSuffix().count, 6)
    }

    func testProfileDecodesTheServerShape() throws {
        let body = #"{"organizationId":"019f0000-0000-7000-8000-000000000001","facts":[{"factKey":"legal_name","label":"Legal business name","tier":1,"value":"Wade Plumbing LLC","source":"user_confirmed","confirmedAt":"2026-10-28T12:00:00.000Z","version":1}],"catalog":[{"factKey":"legal_name","label":"Legal business name","tier":1,"required":true,"confirmed":true},{"factKey":"primary_phone","label":"Primary phone","tier":1,"required":true,"confirmed":false},{"factKey":"entity_type","label":"Entity type","tier":2,"required":false,"confirmed":false}],"coreReady":false,"missingCore":["primary_phone"]}"#
        let profile = try JSONDecoder().decode(OrganizationProfile.self, from: Data(body.utf8))
        XCTAssertEqual(profile.value("legal_name"), "Wade Plumbing LLC")
        XCTAssertNil(profile.value("primary_phone"))
        XCTAssertEqual(profile.catalog.map(CompanyFact.group), [0, 0, 2])
        XCTAssertEqual(CompanyFact.label("primary_phone", fallback: "Primary phone"), "Business phone")
        XCTAssertEqual(CompanyFeaturesView.label("job_sms_notices"), "Job SMS notices")
    }
}

@MainActor
final class BusinessSetupRecoveryTests: XCTestCase {
    func testOfflineChecksAreUnknownAndOnlyPermittedChecksRun() async throws {
        let gate = URLProtocolFixture.Gate()
        let authorityGate = URLProtocolFixture.Gate()
        let replies: [URLProtocolFixture.Reply] = [
            .init(200, #"{"token":"t","user":{"id":"019f0000-0000-7000-8000-000000000011","name":"Dana","email":"dana@example.invalid"}}"#),
            .init(200, #"{"user":{"id":"019f0000-0000-7000-8000-000000000011","name":"Dana","email":"dana@example.invalid","emailVerified":false},"session":{"id":"s","userId":"019f0000-0000-7000-8000-000000000011","activeOrganizationId":null,"expiresAt":"2099-10-27T12:00:00.000Z"}}"#),
            .init(200, "[]"),
            .init(200, #"{"id":"019f0000-0000-7000-8000-000000000001","name":"Wade Plumbing","slug":"wade","members":[]}"#),
            .init(200, "{}"),
            .init(200, #"{"user":{"id":"019f0000-0000-7000-8000-000000000011","name":"Dana","email":"dana@example.invalid","emailVerified":false},"session":{"id":"s","userId":"019f0000-0000-7000-8000-000000000011","activeOrganizationId":"019f0000-0000-7000-8000-000000000001","expiresAt":"2099-10-27T12:00:00.000Z"}}"#),
            .init(200, #"{"authority":{"actorId":"019f0000-0000-7000-8000-000000000011","organizationId":"019f0000-0000-7000-8000-000000000001","policyVersion":1,"generation":"fixture"},"capabilities":["organization.settings.edit","organization.members.manage"],"resources":[],"views":[]}"#),
            .init(200, #"{"organizationId":"019f0000-0000-7000-8000-000000000001","evaluatedAt":"2026-10-28T12:00:00.000Z","features":{"jobs":{"enabled":true,"released":true,"entitled":true}}}"#),
            URLProtocolFixture.offline, URLProtocolFixture.offline, URLProtocolFixture.offline, URLProtocolFixture.offline,
            .init(200, #"{"organizationId":"019f0000-0000-7000-8000-000000000001","facts":[],"catalog":[],"coreReady":true,"missingCore":[]}"#),
            URLProtocolFixture.offline, .init(200, #"{"items":[],"nextCursor":null}"#), URLProtocolFixture.offline,
            .init(200, #"{"organizationId":"019f0000-0000-7000-8000-000000000001","facts":[],"catalog":[],"coreReady":true,"missingCore":[]}"#),
            .init(200, #"{"state":"action_required","chargesReady":false,"payoutsReady":false,"actionRequired":true,"requirements":{"eventuallyDueCount":1,"currentlyDueCount":2,"pastDueCount":0}}"#),
            .init(200, #"{"items":[],"nextCursor":null}"#), .init(200, #"{"items":[],"nextCursor":null}"#),
            .init(200, #"{"organizationId":"019f0000-0000-7000-8000-000000000099","facts":[],"catalog":[],"coreReady":true,"missingCore":[]}"#),
            .init(200, #"{"state":"action_required","chargesReady":false,"payoutsReady":false,"actionRequired":true,"requirements":{"eventuallyDueCount":1,"currentlyDueCount":2,"pastDueCount":0}}"#),
            .init(200, #"{"items":[],"nextCursor":null}"#), .init(200, #"{"items":[],"nextCursor":null}"#),
            .init(200, #"{"organizationId":"019f0000-0000-7000-8000-000000000001","facts":[],"catalog":[],"coreReady":true,"missingCore":[]}"#, gate: authorityGate),
            .init(200, #"{"user":{"id":"019f0000-0000-7000-8000-000000000011","name":"Dana","email":"dana@example.invalid","emailVerified":false},"session":{"id":"s","userId":"019f0000-0000-7000-8000-000000000011","activeOrganizationId":"019f0000-0000-7000-8000-000000000001","expiresAt":"2099-10-27T12:00:00.000Z"}}"#),
            .init(200, #"{"authority":{"actorId":"019f0000-0000-7000-8000-000000000011","organizationId":"019f0000-0000-7000-8000-000000000001","policyVersion":2,"generation":"revoked"},"capabilities":[],"resources":[],"views":[]}"#),
            .init(200, #"{"organizationId":"019f0000-0000-7000-8000-000000000001","evaluatedAt":"2026-10-28T12:00:00.000Z","features":{}}"#),
            .init(200, #"{"user":{"id":"019f0000-0000-7000-8000-000000000011","name":"Dana","email":"dana@example.invalid","emailVerified":false},"session":{"id":"s","userId":"019f0000-0000-7000-8000-000000000011","activeOrganizationId":"019f0000-0000-7000-8000-000000000001","expiresAt":"2099-10-27T12:00:00.000Z"}}"#),
            .init(200, #"{"authority":{"actorId":"019f0000-0000-7000-8000-000000000011","organizationId":"019f0000-0000-7000-8000-000000000001","policyVersion":3,"generation":"restored"},"capabilities":["organization.settings.edit","organization.members.manage"],"resources":[],"views":[]}"#),
            .init(200, #"{"organizationId":"019f0000-0000-7000-8000-000000000001","evaluatedAt":"2026-10-28T12:00:00.000Z","features":{}}"#),
            .init(200, #"{"organizationId":"019f0000-0000-7000-8000-000000000001","facts":[],"catalog":[],"coreReady":true,"missingCore":[]}"#, gate: gate),
        ]
        let api = APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")
        let session = SessionController(api: api, defaults: UserDefaults(suiteName: "thorbis.setup.\(UUID().uuidString)")!)
        await session.signUp(name: "Dana", email: "dana@example.invalid", password: "correct-horse")
        try await session.createCompany(name: "Wade Plumbing")
        let model = BusinessSetupModel()
        await model.refresh(api: api, session: session)
        XCTAssertEqual(Set(model.steps(session)), Set([.details, .payments, .team]))
        XCTAssertEqual(model.done, [])
        XCTAssertEqual(model.unavailable, Set([.details, .payments, .team]), "Offline status checks must remain unknown")
        await model.refresh(api: api, session: session)
        XCTAssertEqual(model.done, [.details])
        XCTAssertEqual(model.unavailable, [.payments, .team], "A single failed team source cannot prove incomplete")
        await model.refresh(api: api, session: session)
        XCTAssertEqual(model.done, [.details])
        XCTAssertEqual(model.unavailable, [], "A successful retry resolves unknown statuses")
        XCTAssertFalse(URLProtocolFixture.recorded.contains { $0.url?.path == "/v1/query" })
        let setupPaths = Set(["/v1/organization/profile", "/v1/organization/merchant-readiness", "/v1/organization/invitations", "/v1/organization/role-members"])
        XCTAssertTrue(URLProtocolFixture.recorded.filter { setupPaths.contains($0.url?.path ?? "") }.allSatisfy { $0.header("Cache-Control") == "no-cache" })
        await model.refresh(api: api, session: session)
        XCTAssertFalse(model.done.contains(.details), "A different organization's profile cannot complete this setup")
        XCTAssertEqual(model.unavailable, [.details])
        let beforeAuthority = URLProtocolFixture.recorded.count
        let stale = Task { await model.refresh(api: api, session: session) }
        for _ in 0..<100 where URLProtocolFixture.recorded.count == beforeAuthority {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(URLProtocolFixture.recorded.count, beforeAuthority + 1)
        let revision = session.authorityRevision
        await session.revalidate()
        XCTAssertFalse(session.can("organization.settings.edit"))
        await session.revalidate()
        XCTAssertTrue(session.can("organization.settings.edit"))
        XCTAssertNotEqual(session.authorityRevision, revision)
        authorityGate.release()
        await stale.value
        XCTAssertFalse(model.isCurrent(api: api, session: session))
        XCTAssertEqual(URLProtocolFixture.recorded.count, beforeAuthority + 7, "Old authority must not continue the refresh")
        let count = URLProtocolFixture.recorded.count
        let refresh = Task { await model.refresh(api: api, session: session) }
        for _ in 0..<100 where URLProtocolFixture.recorded.count == count {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(URLProtocolFixture.recorded.count, count + 1)
        api.baseURL = "https://other.example.invalid"
        gate.release()
        await refresh.value
        XCTAssertFalse(model.isCurrent(api: api, session: session))
        XCTAssertFalse(model.loaded)
        XCTAssertEqual(URLProtocolFixture.recorded.count, count + 1, "A stale refresh must not start later checks")
    }
}

@MainActor
final class SetupPaginationTests: XCTestCase {
    func testIncompletePaginationCannotProveTeamAbsent() async {
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, #"{"items":[],"nextCursor":"repeat"}"#),
            .init(200, #"{"items":[],"nextCursor":"repeat"}"#),
            .init(200, #"{"items":[],"nextCursor":"repeat"}"#),
            .init(200, #"{"items":[],"nextCursor":"repeat"}"#),
        ]), baseURL: "https://app.thorbis.com")
        do { _ = try await api.pendingInvitations(requireComplete: true); XCTFail("A repeated cursor is incomplete") } catch { }
        do { _ = try await api.roleMembers(requireComplete: true); XCTFail("A repeated cursor is incomplete") } catch { }
    }

    func testExpiredInvitationsAndDuplicateMembersDoNotProveCompletion() async throws {
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, #"{"items":[{"id":"i1","email":"a@example.invalid","role":"technician","status":"expired","createdAt":"2026-10-30","expiresAt":"2026-10-30"},{"id":"i2","email":"b@example.invalid","role":"technician","status":"canceled","createdAt":"2026-10-30","expiresAt":"2026-10-30"}],"nextCursor":"more"}"#),
            .init(200, #"{"items":[],"nextCursor":null}"#),
            .init(200, #"{"items":[{"member":{"memberId":"m1","userId":"u1","displayName":"Dana","email":"d@example.invalid","isLegalOwner":true,"legalMembershipRoles":[]},"authority":{"kind":"legacy_fallback","currentAssignmentVersion":0,"reason":"never_assigned","roles":[]}}],"nextCursor":"more"}"#),
            .init(200, #"{"items":[{"member":{"memberId":"m1","userId":"u1","displayName":"Dana","email":"d@example.invalid","isLegalOwner":true,"legalMembershipRoles":[]},"authority":{"kind":"legacy_fallback","currentAssignmentVersion":0,"reason":"never_assigned","roles":[]}}],"nextCursor":null}"#),
        ]), baseURL: "https://app.thorbis.com")
        let invitations = try await api.pendingInvitations(requireComplete: true)
        let members = try await api.roleMembers(requireComplete: true)
        XCTAssertTrue(invitations.isEmpty)
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 4)
    }

    func testPositiveEvidenceDoesNotNeedRemainingPages() async throws {
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, #"{"items":[{"id":"i1","email":"tech@example.invalid","role":"technician","status":"pending","createdAt":"2026-10-30","expiresAt":"2026-11-30"}],"nextCursor":"more"}"#),
            .init(200, #"{"items":[{"member":{"memberId":"m1","userId":"u1","displayName":"Dana","email":"d@example.invalid","isLegalOwner":true,"legalMembershipRoles":[]},"authority":{"kind":"legacy_fallback","currentAssignmentVersion":0,"reason":"never_assigned","roles":[]}},{"member":{"memberId":"m2","userId":"u2","displayName":"Alex","email":"a@example.invalid","isLegalOwner":false,"legalMembershipRoles":[]},"authority":{"kind":"legacy_fallback","currentAssignmentVersion":0,"reason":"never_assigned","roles":[]}}],"nextCursor":"more"}"#),
        ]), baseURL: "https://app.thorbis.com")
        let invitations = try await api.pendingInvitations(requireComplete: true)
        let members = try await api.roleMembers(requireComplete: true)
        XCTAssertEqual(invitations.count, 1)
        XCTAssertEqual(members.count, 2)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
    }
}
