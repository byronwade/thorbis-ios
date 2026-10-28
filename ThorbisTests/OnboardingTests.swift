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

    func testReviewLinkTypesLikeAWebAddress() {
        XCTAssertEqual(CompanyFact.label("review_link", fallback: "Review link"), "Review link")
        XCTAssertEqual(CompanyFact.keyboard("review_link"), .URL)
        XCTAssertEqual(CompanyFact.content("review_link"), .URL)
        XCTAssertFalse(CompanyFact.multiline("review_link"))
    }
}
