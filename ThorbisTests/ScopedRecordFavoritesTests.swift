import XCTest
@testable import Thorbis

@MainActor
final class ScopedRecordFavoritesTests: XCTestCase {
    private let jobID = "00000000-0000-4000-8000-000000000101"
    private let organizationID = "00000000-0000-4000-8000-000000000002"
    private let actorID = "00000000-0000-4000-8000-000000000001"

    private func defaults() -> UserDefaults {
        let name = "favorites-tests-\(UUID())"
        let result = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return result
    }

    private func scope(_ api: APIClient, actor: String? = nil, organization: String? = nil) -> ScopedRecordFavorites.Scope {
        .init(actorID: actor ?? actorID, organizationID: organization ?? organizationID,
              origin: api.normalizedOrigin!, sessionGeneration: UUID(), authorityRevision: UUID(),
              apiGeneration: api.requestGeneration, savedCopyRevision: api.savedCopyScopeRevision)
    }

    private func job(_ id: String, organization: String? = nil, title: String = "Private job") -> String {
        "{\"id\":\"\(id)\",\"organizationId\":\"\(organization ?? organizationID)\",\"customerId\":\"00000000-0000-4000-8000-000000000003\",\"title\":\"\(title)\",\"status\":\"scheduled\",\"createdAt\":\"2026-10-01T12:00:00Z\",\"updatedAt\":\"2026-10-01T12:00:00Z\"}"
    }

    func testOnlyFreshVerifiedRecordsExposeTitlesAndStorageContainsIDsOnly() async {
        let saved = defaults()
        let api = APIClient(session: URLProtocolFixture.session([.init(200, job(jobID))]), baseURL: "https://app.thorbis.com")
        let model = ScopedRecordFavorites(defaults: saved)
        let context = scope(api)
        model.bind(context)
        XCTAssertTrue(model.toggle(.job, id: jobID))
        XCTAssertTrue(model.visible.isEmpty)
        await model.refresh(api: api, canOpen: { _ in true }, isCurrent: { true })
        XCTAssertEqual(model.visible.map(\.title), ["Private job"])
        XCTAssertFalse(String(data: saved.data(forKey: ScopedRecordFavorites.storageKey)!, encoding: .utf8)!.contains("Private job"))
        XCTAssertEqual(URLProtocolFixture.recorded.first?.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(URLProtocolFixture.recorded.first?.header("Cache-Control"), "no-cache")
    }

    func testCustomerRequiresFreshExactRecord() async {
        let customerID = "00000000-0000-4000-8000-000000000201"
        let response = "{\"id\":\"\(customerID)\",\"organizationId\":\"\(organizationID)\",\"name\":\"Private customer\",\"archived\":false,\"createdAt\":\"2026-10-01T12:00:00Z\",\"updatedAt\":\"2026-10-01T12:00:00Z\"}"
        let api = APIClient(session: URLProtocolFixture.session([.init(200, response)]), baseURL: "https://app.thorbis.com")
        let model = ScopedRecordFavorites(defaults: defaults())
        model.bind(scope(api)); XCTAssertTrue(model.toggle(.customer, id: customerID))
        await model.refresh(api: api, canOpen: { _ in true }, isCurrent: { true })
        XCTAssertEqual(model.visible.map(\.title), ["Private customer"])
        XCTAssertEqual(URLProtocolFixture.recorded.first?.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testDeniedOfflineWrongOrganizationAndCapabilityNeverExposeNames() async {
        for reply in [URLProtocolFixture.Reply(403), URLProtocolFixture.offline,
                      .init(200, job(jobID, organization: "00000000-0000-4000-8000-000000000099")),
                      .init(200, job("00000000-0000-4000-8000-000000000102"))] {
            let api = APIClient(session: URLProtocolFixture.session([reply]), baseURL: "https://app.thorbis.com")
            let model = ScopedRecordFavorites(defaults: defaults())
            model.bind(scope(api)); XCTAssertTrue(model.toggle(.job, id: jobID))
            await model.refresh(api: api, canOpen: { _ in true }, isCurrent: { true })
            XCTAssertTrue(model.visible.isEmpty)
        }
        let api = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        let model = ScopedRecordFavorites(defaults: defaults())
        model.bind(scope(api)); XCTAssertTrue(model.toggle(.job, id: jobID))
        await model.refresh(api: api, canOpen: { _ in false }, isCurrent: { true })
        XCTAssertTrue(model.visible.isEmpty)
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
    }

    func testDifferentActorWorkspaceAndOriginHaveIndependentFavorites() async {
        let saved = defaults()
        let api = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        let otherAPI = APIClient(session: URLProtocolFixture.session([]), baseURL: "http://localhost:3000")
        let model = ScopedRecordFavorites(defaults: saved)
        let original = scope(api)
        model.bind(original); XCTAssertTrue(model.toggle(.job, id: jobID))
        model.bind(scope(api, actor: "different")); XCTAssertTrue(model.entries.isEmpty)
        model.bind(scope(api, organization: "different")); XCTAssertTrue(model.entries.isEmpty)
        model.bind(scope(otherAPI)); XCTAssertTrue(model.entries.isEmpty)
        model.bind(original); XCTAssertEqual(model.entries.map(\.id), [jobID])
        let relaunched = ScopedRecordFavorites(defaults: saved)
        relaunched.bind(original)
        XCTAssertEqual(relaunched.entries.map(\.id), [jobID])
        XCTAssertTrue(relaunched.visible.isEmpty, "Restored IDs require a fresh read before names appear")
    }

    func testSameIdentityNewSessionClearsPreviouslyVisibleNames() async {
        let api = APIClient(session: URLProtocolFixture.session([.init(200, job(jobID))]), baseURL: "https://app.thorbis.com")
        let model = ScopedRecordFavorites(defaults: defaults())
        let original = scope(api)
        model.bind(original); XCTAssertTrue(model.toggle(.job, id: jobID))
        await model.refresh(api: api, canOpen: { _ in true }, isCurrent: { true })
        XCTAssertEqual(model.visible.count, 1)
        model.bind(scope(api))
        XCTAssertTrue(model.visible.isEmpty)
        XCTAssertEqual(model.entries.map(\.id), [jobID])
    }

    func testOnlyOwningApiAndSessionEpochsRetireFavorites() async {
        let api = APIClient(session: URLProtocolFixture.session([.init(200, job(jobID))]), baseURL: "https://app.thorbis.com")
        let model = ScopedRecordFavorites(defaults: defaults())
        let context = scope(api)
        model.bind(context); XCTAssertTrue(model.toggle(.job, id: jobID))
        await model.refresh(api: api, canOpen: { _ in true }, isCurrent: { true })
        XCTAssertEqual(model.visible.count, 1)
        model.retireAPI(origin: context.origin, generation: UUID(), savedCopyRevision: context.savedCopyRevision)
        model.retireAPI(origin: "https://other.example", generation: context.apiGeneration, savedCopyRevision: context.savedCopyRevision)
        model.retireSession(generation: UUID(), authority: context.authorityRevision)
        XCTAssertEqual(model.visible.count, 1, "Unrelated clients cannot clear the active favorite")
        model.retireSession(generation: context.sessionGeneration, authority: context.authorityRevision)
        XCTAssertTrue(model.visible.isEmpty)
        XCTAssertTrue(model.entries.isEmpty)
        model.bind(context)
        XCTAssertEqual(model.entries.map(\.id), [jobID])
        model.retireAPI(origin: context.origin, generation: context.apiGeneration, savedCopyRevision: context.savedCopyRevision)
        XCTAssertTrue(model.entries.isEmpty, "The owning API epoch clears its bound context")
    }

    func testDelayedResponseCannotPublishAfterAuthorityChanges() async throws {
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let api = APIClient(session: URLProtocolFixture.session([.init(200, job(jobID), gate: gate)]), baseURL: "https://app.thorbis.com")
        let model = ScopedRecordFavorites(defaults: defaults())
        let original = scope(api)
        model.bind(original); XCTAssertTrue(model.toggle(.job, id: jobID))
        let task = Task { await model.refresh(api: api, canOpen: { _ in true }, isCurrent: { true }) }
        for _ in 0..<100 where URLProtocolFixture.recorded.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        model.bind(scope(api, actor: "other"))
        gate.release(); await task.value
        XCTAssertTrue(model.visible.isEmpty)
    }
}
