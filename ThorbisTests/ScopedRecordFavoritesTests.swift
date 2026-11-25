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
        XCTAssertTrue(model.set(.job, id: jobID, favorite: true))
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
        model.bind(scope(api)); XCTAssertTrue(model.set(.customer, id: customerID, favorite: true))
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
            model.bind(scope(api)); XCTAssertTrue(model.set(.job, id: jobID, favorite: true))
            await model.refresh(api: api, canOpen: { _ in true }, isCurrent: { true })
            XCTAssertTrue(model.visible.isEmpty)
        }
        let api = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        let model = ScopedRecordFavorites(defaults: defaults())
        model.bind(scope(api)); XCTAssertTrue(model.set(.job, id: jobID, favorite: true))
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
        model.bind(original); XCTAssertTrue(model.set(.job, id: jobID, favorite: true))
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
        model.bind(original); XCTAssertTrue(model.set(.job, id: jobID, favorite: true))
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
        model.bind(context); XCTAssertTrue(model.set(.job, id: jobID, favorite: true))
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

    func testUnrelatedClientInvalidationDoesNotRetireSharedContext() {
        let first = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        let second = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        let context = scope(first)
        let shared = ScopedRecordFavorites.shared
        shared.bind(context)
        defer { shared.bind(nil) }
        second.invalidateRequests()
        XCTAssertTrue(shared.isBound(to: context))
        first.invalidateRequests()
        XCTAssertFalse(shared.isBound(to: context))
    }

    func testAddingTwiceKeepsOneEntryAndWritesNothingNew() async {
        let saved = defaults()
        let api = APIClient(session: URLProtocolFixture.session([.init(200, job(jobID))]), baseURL: "https://app.thorbis.com")
        let model = ScopedRecordFavorites(defaults: saved)
        model.bind(scope(api))
        XCTAssertTrue(model.set(.job, id: jobID, favorite: true))
        await model.refresh(api: api, canOpen: { _ in true }, isCurrent: { true })
        XCTAssertEqual(model.visible.map(\.title), ["Private job"])
        let stored = saved.data(forKey: ScopedRecordFavorites.storageKey)
        XCTAssertTrue(model.set(.job, id: jobID.uppercased(), favorite: true), "Already saved: the store holds what was asked")
        XCTAssertEqual(model.entries.map(\.id), [jobID])
        XCTAssertEqual(model.visible.map(\.title), ["Private job"], "A no-op keeps the names already checked")
        XCTAssertEqual(saved.data(forKey: ScopedRecordFavorites.storageKey), stored)
        XCTAssertEqual(ScopedRecordFavorites(defaults: saved).entriesAfterBinding(scope(api)).map(\.id), [jobID])
    }

    func testRemovingAMissingEntryChangesNothing() {
        let saved = defaults()
        let api = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        let secondID = "00000000-0000-4000-8000-000000000102"
        let model = ScopedRecordFavorites(defaults: saved)
        let context = scope(api)
        model.bind(context)
        XCTAssertTrue(model.set(.job, id: secondID, favorite: false), "Not saved: the store already holds what was asked")
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertNil(saved.data(forKey: ScopedRecordFavorites.storageKey), "Nothing is written for a no-op")
        XCTAssertTrue(model.set(.job, id: jobID, favorite: true))
        let stored = saved.data(forKey: ScopedRecordFavorites.storageKey)
        XCTAssertTrue(model.set(.job, id: secondID, favorite: false))
        XCTAssertTrue(model.set(.customer, id: jobID, favorite: false), "The same id as another kind is a different record")
        XCTAssertEqual(model.entries, [.init(kind: .job, id: jobID)])
        XCTAssertEqual(saved.data(forKey: ScopedRecordFavorites.storageKey), stored)
        XCTAssertTrue(model.set(.job, id: jobID, favorite: false))
        XCTAssertTrue(model.entries.isEmpty, "Remove removes")
        XCTAssertTrue(model.set(.job, id: jobID, favorite: false))
        XCTAssertTrue(model.entries.isEmpty, "Removing again does not add it back")
    }

    /// The defect a fresh iPad launch exposed: the row read "Add" before the store was bound, and
    /// binding then toggling removed the saved favorite. Adding after the bind must keep it.
    func testAddAfterBindingAScopeThatAlreadyHasTheEntryKeepsIt() {
        let saved = defaults()
        let api = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        let context = scope(api)
        let earlier = ScopedRecordFavorites(defaults: saved)
        earlier.bind(context); XCTAssertTrue(earlier.set(.job, id: jobID, favorite: true))
        let relaunched = ScopedRecordFavorites(defaults: saved)
        XCTAssertFalse(relaunched.set(.job, id: jobID, favorite: true), "Unbound, nothing can be added or removed")
        relaunched.bind(context)
        XCTAssertTrue(relaunched.set(.job, id: jobID, favorite: true))
        XCTAssertEqual(relaunched.entries.map(\.id), [jobID])
        XCTAssertEqual(ScopedRecordFavorites(defaults: saved).entriesAfterBinding(context).map(\.id), [jobID],
                       "The saved favorite survives the add")
    }

    func testSetKeepsActorWorkspaceAndOriginApart() {
        let saved = defaults()
        let api = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        let otherAPI = APIClient(session: URLProtocolFixture.session([]), baseURL: "http://localhost:3000")
        let model = ScopedRecordFavorites(defaults: saved)
        let original = scope(api)
        model.bind(original); XCTAssertTrue(model.set(.job, id: jobID, favorite: true))
        for other in [scope(api, actor: "different"), scope(api, organization: "different"), scope(otherAPI)] {
            model.bind(other)
            XCTAssertTrue(model.entries.isEmpty)
            XCTAssertTrue(model.set(.job, id: jobID, favorite: false), "Another owner holds no such favorite")
            XCTAssertTrue(model.set(.customer, id: jobID, favorite: true))
            XCTAssertEqual(model.entries, [.init(kind: .customer, id: jobID)])
        }
        model.bind(original)
        XCTAssertEqual(model.entries, [.init(kind: .job, id: jobID)], "Other owners' changes never touch this one's")
        model.bind(nil)
        XCTAssertFalse(model.set(.job, id: jobID, favorite: false), "With no scope nothing is removed")
        model.bind(original)
        XCTAssertEqual(model.entries.map(\.id), [jobID])
    }

    func testCapabilityLossPurgesEarlierResultsDuringMultiRecordRefresh() async throws {
        let secondID = "00000000-0000-4000-8000-000000000102"
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let api = APIClient(session: URLProtocolFixture.session([.init(200, job(jobID)), .init(200, job(secondID), gate: gate)]), baseURL: "https://app.thorbis.com")
        let model = ScopedRecordFavorites(defaults: defaults())
        model.bind(scope(api)); XCTAssertTrue(model.set(.job, id: jobID, favorite: true)); XCTAssertTrue(model.set(.job, id: secondID, favorite: true))
        var permitted = true
        let task = Task { await model.refresh(api: api, canOpen: { _ in permitted }, isCurrent: { true }) }
        for _ in 0..<100 where URLProtocolFixture.recorded.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
        XCTAssertEqual(model.visible.count, 1)
        permitted = false
        gate.release(); await task.value
        XCTAssertTrue(model.visible.isEmpty, "Previously published titles must disappear when capability is lost")
    }

    func testDelayedResponseCannotPublishAfterCapabilityRevocation() async throws {
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let api = APIClient(session: URLProtocolFixture.session([.init(200, job(jobID), gate: gate)]), baseURL: "https://app.thorbis.com")
        let model = ScopedRecordFavorites(defaults: defaults())
        model.bind(scope(api)); XCTAssertTrue(model.set(.job, id: jobID, favorite: true))
        var permitted = true
        let task = Task { await model.refresh(api: api, canOpen: { _ in permitted }, isCurrent: { true }) }
        for _ in 0..<100 where URLProtocolFixture.recorded.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        permitted = false
        gate.release(); await task.value
        XCTAssertTrue(model.visible.isEmpty)
    }

    func testDelayedResponseCannotPublishAfterAuthorityChanges() async throws {
        let gate = URLProtocolFixture.Gate(); defer { gate.release() }
        let api = APIClient(session: URLProtocolFixture.session([.init(200, job(jobID), gate: gate)]), baseURL: "https://app.thorbis.com")
        let model = ScopedRecordFavorites(defaults: defaults())
        let original = scope(api)
        model.bind(original); XCTAssertTrue(model.set(.job, id: jobID, favorite: true))
        let task = Task { await model.refresh(api: api, canOpen: { _ in true }, isCurrent: { true }) }
        for _ in 0..<100 where URLProtocolFixture.recorded.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        model.bind(scope(api, actor: "other"))
        gate.release(); await task.value
        XCTAssertTrue(model.visible.isEmpty)
    }
}

private extension ScopedRecordFavorites {
    /// What a fresh store reads for this scope: a relaunch's view of the saved favorites.
    func entriesAfterBinding(_ scope: Scope) -> [Entry] {
        bind(scope)
        return entries
    }
}
