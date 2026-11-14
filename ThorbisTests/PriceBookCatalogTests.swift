import Combine
import CryptoKit
import XCTest
import Security
@testable import Thorbis

@MainActor
final class PriceBookCatalogTests: XCTestCase {
    private let testAuthority = PriceBookAuthority(actorID: "fixture-actor", policyVersion: 1,
                                                   generation: "fixture-scope", revision: UUID())

    func testMarkerStoreSupportsDeviceOnlyKeychainOperations() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "com.thorbis.field.price-book-diagnostic",
                                    kSecAttrAccount as String: UUID().uuidString]
        var lookup = query
        lookup[kSecReturnData as String] = true
        var value: CFTypeRef?
        let read = SecItemCopyMatching(lookup as CFDictionary, &value)
        var item = query
        item[kSecValueData as String] = Data([1])
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let add = SecItemAdd(item as CFDictionary, nil)
        let remove = SecItemDelete(query as CFDictionary)
        XCTAssertEqual(read, errSecItemNotFound, "Keychain read status: \(read)")
        XCTAssertEqual(add, errSecSuccess, "Keychain add status: \(add)")
        XCTAssertEqual(remove, errSecSuccess, "Keychain delete status: \(remove)")
    }

    func testFirstPageIsUsableWhileLaterPageIsStillLoadingWithoutCachingPartialData() async throws {
        let org = UUID().uuidString.lowercased()
        defer { removeOwnCache(org) }
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try page([(1, "First page")], cursor: id(9000))),
                          .init(200, try page([(2, "Later page")]), gate: gate)])
        let catalog = PriceBookCatalog()
        let task = Task { await catalog.refresh(api: api, organizationID: org, sessionGeneration: UUID(), authority: testAuthority, force: true) }
        try await waitForRequests(2)
        XCTAssertEqual(catalog.items.map(\.id), [id(1)], "The first page should be usable before later pages arrive")
        XCTAssertTrue(catalog.loading)
        XCTAssertTrue(catalog.isPartial)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL(org).path), "A partial page is not a complete offline cache")
        gate.release()
        await task.value
        XCTAssertEqual(catalog.items.map(\.id), [id(1), id(2)])
        XCTAssertFalse(catalog.loading)
        XCTAssertFalse(catalog.isPartial)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL(org).path))
    }

    func testFailedLaterPageKeepsPartialItemsButNeverWritesCompleteCache() async throws {
        let org = UUID().uuidString.lowercased()
        defer { removeOwnCache(org) }
        let api = client([.init(200, try page([(1, "First page")], cursor: id(9000))),
                          .init(503, "{}")])
        let catalog = PriceBookCatalog()
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: UUID(), authority: testAuthority, force: true)
        XCTAssertEqual(catalog.items.map(\.id), [id(1)])
        XCTAssertTrue(catalog.isPartial)
        XCTAssertNotNil(catalog.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL(org).path))
    }

    func testFirstPageRemainsStableUntilCompleteCatalogIsReady() async throws {
        let org = UUID().uuidString.lowercased()
        defer { removeOwnCache(org) }
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let rows: (ClosedRange<Int>) -> [(Int, String)] = { range in
            range.map { ($0, "Catalog item \($0)") }
        }
        let api = client([.init(200, try page(rows(1...200), cursor: id(9000))),
                          .init(200, try page(rows(201...400), cursor: id(9001))),
                          .init(200, try page(rows(401...600)), gate: gate)])
        let catalog = PriceBookCatalog()
        let refresh = Task { await catalog.refresh(api: api, organizationID: org, sessionGeneration: UUID(), authority: testAuthority, force: true) }
        try await waitForRequests(3)
        XCTAssertEqual(catalog.items.count, 200, "Do not reorder visible results or reindex on each page")
        XCTAssertEqual(catalog.items.first?.id, id(1))
        XCTAssertEqual(catalog.items.last?.id, id(200))
        XCTAssertTrue(catalog.isPartial)
        gate.release()
        await refresh.value
        XCTAssertEqual(catalog.items.count, 600)
        XCTAssertEqual(catalog.index.search("item 600").first?.id, id(600))
        XCTAssertFalse(catalog.isPartial)
    }

    func testRefreshingCompleteCacheDoesNotReplaceItWithAPartialPage() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org) }
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try page([(1, "Saved item")])),
                          .init(200, try page([(2, "New first page")], cursor: id(9000))),
                          .init(200, try page([(3, "New last page")]), gate: gate)])
        let catalog = PriceBookCatalog()
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        let saved = try Data(contentsOf: cacheURL(org))
        let refresh = Task { await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true) }
        try await waitForRequests(3)
        XCTAssertEqual(catalog.items.map(\.id), [id(1)])
        XCTAssertFalse(catalog.isPartial)
        XCTAssertEqual(try Data(contentsOf: cacheURL(org)), saved)
        gate.release()
        await refresh.value
        XCTAssertEqual(catalog.items.map(\.id), [id(2), id(3)])
    }

    func testAnEmptyCompleteCacheDoesNotHideNewlyLoadedItems() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org) }
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try page([])),
                          .init(200, try page([(1, "New item")], cursor: id(9000))),
                          .init(200, try page([(2, "Later item")]), gate: gate)])
        let catalog = PriceBookCatalog()
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        let savedEmpty = try Data(contentsOf: cacheURL(org))
        let refresh = Task { await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true) }
        try await waitForRequests(3)
        XCTAssertEqual(catalog.items.map(\.id), [id(1)])
        XCTAssertTrue(catalog.isPartial)
        XCTAssertEqual(try Data(contentsOf: cacheURL(org)), savedEmpty)
        gate.release()
        await refresh.value
    }

    func testVerifiedScopeComparisonRejectsIdentityAndAuthorityChanges() {
        let org = UUID().uuidString.lowercased(), session = UUID()
        let original = PriceBookCatalogContext(organizationID: org, sessionGeneration: session, authority: testAuthority)
        let same = PriceBookAuthority(actorID: testAuthority.actorID, policyVersion: testAuthority.policyVersion,
                                      generation: testAuthority.generation, revision: UUID())
        XCTAssertTrue(original.hasSameVerifiedScope(as: .init(organizationID: org, sessionGeneration: session, authority: same)))
        let changed = [
            PriceBookAuthority(actorID: "other", policyVersion: testAuthority.policyVersion, generation: testAuthority.generation, revision: UUID()),
            PriceBookAuthority(actorID: testAuthority.actorID, policyVersion: testAuthority.policyVersion + 1, generation: testAuthority.generation, revision: UUID()),
            PriceBookAuthority(actorID: testAuthority.actorID, policyVersion: testAuthority.policyVersion, generation: "different", revision: UUID()),
        ]
        for authority in changed {
            XCTAssertFalse(original.hasSameVerifiedScope(as: .init(organizationID: org, sessionGeneration: session, authority: authority)))
        }
        XCTAssertFalse(original.hasSameVerifiedScope(as: .init(organizationID: org, sessionGeneration: session, authority: nil)))
        XCTAssertFalse(original.hasSameVerifiedScope(as: .init(organizationID: org, sessionGeneration: UUID(), authority: same)))
        XCTAssertFalse(original.hasSameVerifiedScope(as: .init(organizationID: UUID().uuidString, sessionGeneration: session, authority: same)))
    }

    func testUnchangedVerifiedScopeReusesCompleteRecentCatalogAfterAuthorityRevision() async throws {
        let org = UUID().uuidString.lowercased(), session = UUID()
        defer { removeOwnCache(org) }
        let api = client([.init(200, try page([(1, "Existing catalog")]))])
        let catalog = PriceBookCatalog()
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: session, authority: testAuthority, force: true)
        let refreshed = PriceBookAuthority(actorID: testAuthority.actorID, policyVersion: testAuthority.policyVersion,
                                           generation: testAuthority.generation, revision: UUID())
        let next = PriceBookCatalogContext(organizationID: org, sessionGeneration: session, authority: refreshed)
        XCTAssertFalse(catalog.isCurrent(next, api: api), "Do not accept the new revision before revalidation is adopted")
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: session, authority: refreshed)
        XCTAssertTrue(catalog.isCurrent(next, api: api))
        XCTAssertEqual(catalog.items.map(\.id), [id(1)])
        XCTAssertNil(catalog.error)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1, "A harmless authority revision should not redownload a fresh complete catalog")
    }

    func testAdoptingAnUnchangedAuthorityRevisionNotifiesCatalogObservers() async throws {
        let org = UUID().uuidString.lowercased(), session = UUID()
        defer { removeOwnCache(org) }
        let api = client([.init(200, try page([(1, "Existing catalog")]))])
        let catalog = PriceBookCatalog()
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: session, authority: testAuthority, force: true)
        var notifications = 0
        let observation = catalog.objectWillChange.sink { notifications += 1 }
        let refreshed = PriceBookAuthority(actorID: testAuthority.actorID, policyVersion: testAuthority.policyVersion,
                                           generation: testAuthority.generation, revision: UUID())
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: session, authority: refreshed)
        withExtendedLifetime(observation) {}
        XCTAssertGreaterThan(notifications, 0, "Views need to learn that the strict current context was adopted")
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
    }

    func testAuthorityRevisionRetiresAnInFlightPartialCatalog() async throws {
        let org = UUID().uuidString.lowercased(), session = UUID()
        defer { removeOwnCache(org) }
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try page([(1, "Old partial")], cursor: id(9000))),
                          .init(200, try page([(2, "Old later")]), gate: gate),
                          .init(200, try page([(3, "New scope read")]))])
        let catalog = PriceBookCatalog()
        let first = Task { await catalog.refresh(api: api, organizationID: org, sessionGeneration: session, authority: testAuthority, force: true) }
        try await waitForRequests(2)
        let refreshed = PriceBookAuthority(actorID: testAuthority.actorID, policyVersion: testAuthority.policyVersion,
                                           generation: testAuthority.generation, revision: UUID())
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: session, authority: refreshed, force: true)
        gate.release()
        await first.value
        XCTAssertEqual(catalog.items.map(\.id), [id(3)])
        XCTAssertEqual(URLProtocolFixture.recorded.count, 3)
    }

    func testChangedAPIGenerationDoesNotLeavePartialItemsVisibleDuringNewRead() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org) }
        let oldGate = URLProtocolFixture.Gate(), newGate = URLProtocolFixture.Gate()
        defer { oldGate.release(); newGate.release() }
        let api = client([.init(200, try page([(1, "Old scope")], cursor: id(9000))),
                          .init(200, try page([(2, "Old later")]), gate: oldGate),
                          .init(200, try page([(3, "New scope")]), gate: newGate)])
        let catalog = PriceBookCatalog()
        let old = Task { await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true) }
        try await waitForRequests(2)
        XCTAssertEqual(catalog.items.map(\.id), [id(1)])
        api.invalidateRequests()
        let context = PriceBookCatalogContext(organizationID: org, sessionGeneration: generation, authority: testAuthority)
        XCTAssertFalse(catalog.isCurrent(context, api: api), "An old partial page must not be selectable even before refresh runs")
        let next = Task { await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true) }
        try await waitForRequests(3)
        XCTAssertTrue(catalog.items.isEmpty, "Old partial items must not remain visible in a new request scope")
        newGate.release(); oldGate.release()
        await next.value; await old.value
        XCTAssertEqual(catalog.items.map(\.id), [id(3)])
    }

    func testCachedCatalogFromAnotherOriginIsNotShown() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org) }
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try page([(1, "Production item")])),
                          .init(200, try page([(2, "Local item")]), gate: gate)])
        let catalog = PriceBookCatalog()
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        api.baseURL = "http://localhost:4321"
        XCTAssertFalse(catalog.isCurrent(.init(organizationID: org, sessionGeneration: generation, authority: testAuthority), api: api))
        let refresh = Task { await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true) }
        try await waitForRequests(2)
        XCTAssertTrue(catalog.items.isEmpty, "A new API origin must not show the other environment's saved items")
        gate.release()
        await refresh.value
        XCTAssertEqual(catalog.items.map(\.id), [id(2)])
    }

    func testCompleteSnapshotIsNotSelectableImmediatelyAfterAPIGenerationChanges() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org) }
        let api = client([.init(200, try page([(1, "Old authority")]))])
        let catalog = PriceBookCatalog()
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        let context = PriceBookCatalogContext(organizationID: org, sessionGeneration: generation, authority: testAuthority)
        XCTAssertTrue(catalog.isCurrent(context, api: api))
        api.invalidateRequests()
        XCTAssertFalse(catalog.isCurrent(context, api: api), "A retired request generation must not expose even a complete snapshot")
    }

    func testNewSessionDoesNotSeePriorSessionsUnscopedDiskCache() async throws {
        let org = UUID().uuidString.lowercased()
        defer { removeOwnCache(org) }
        let otherAuthority = PriceBookAuthority(actorID: "another-actor", policyVersion: 1,
                                                generation: "another-scope", revision: UUID())
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try page([(1, "Prior actor")])) ,
                          .init(200, try page([(2, "New actor")]), gate: gate)])
        let catalog = PriceBookCatalog()
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: UUID(), authority: testAuthority, force: true)
        let next = Task { await catalog.refresh(api: api, organizationID: org, sessionGeneration: UUID(), authority: otherAuthority, force: true) }
        try await waitForRequests(2)
        XCTAssertTrue(catalog.items.isEmpty, "An organization-only file cannot authorize a new actor")
        gate.release()
        await next.value
    }

    func testRetiredGenerationHidesCompleteSnapshotUntilFreshRead() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org) }
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try page([(1, "Saved item")])),
                          .init(200, try page([(2, "Updated item")]), gate: gate)])
        let catalog = PriceBookCatalog()
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        api.invalidateRequests()
        let refresh = Task { await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority) }
        try await waitForRequests(2)
        XCTAssertTrue(catalog.items.isEmpty)
        XCTAssertFalse(catalog.isPartial)
        gate.release()
        await refresh.value
        XCTAssertEqual(catalog.items.map(\.id), [id(2)])
    }

    func testExternalDenialRetiresMatchingCatalogAndItsSavedCopy() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org) }
        let api = client([.init(200, try page([(1, "Formerly authorized")]))])
        let catalog = PriceBookCatalog(markDenialOverride: { _, _, _ in false })
        let context = PriceBookCatalogContext(organizationID: org, sessionGeneration: generation, authority: testAuthority)
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        XCTAssertTrue(catalog.isCurrent(context, api: api))
        XCTAssertTrue(catalog.recordExternalDenial(organizationID: org, origin: try XCTUnwrap(api.normalizedOrigin), authority: testAuthority, status: 403))
        XCTAssertTrue(catalog.items.isEmpty)
        XCTAssertFalse(catalog.isCurrent(context, api: api))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL(org).path))
        let offline = client([URLProtocolFixture.offline])
        let reopened = PriceBookCatalog()
        await reopened.refresh(api: offline, organizationID: org, sessionGeneration: UUID(), authority: testAuthority, force: true)
        XCTAssertTrue(reopened.items.isEmpty)
    }

    func testExternalDenialDoesNotRetireDifferentActorOrEraseItsCache() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org) }
        let api = client([.init(200, try page([(1, "Other actor catalog")]))])
        let catalog = PriceBookCatalog(markDenialOverride: { _, _, _ in true })
        let context = PriceBookCatalogContext(organizationID: org, sessionGeneration: generation, authority: testAuthority)
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        let saved = try Data(contentsOf: cacheURL(org))
        let other = PriceBookAuthority(actorID: "another-actor", policyVersion: testAuthority.policyVersion, generation: testAuthority.generation, revision: UUID())
        XCTAssertTrue(catalog.recordExternalDenial(organizationID: org, origin: try XCTUnwrap(api.normalizedOrigin), authority: other, status: 403))
        XCTAssertTrue(catalog.isCurrent(context, api: api))
        XCTAssertEqual(catalog.items.map(\.id), [id(1)])
        XCTAssertEqual(try Data(contentsOf: cacheURL(org)), saved)
    }

    func testExternalDenialDoesNotRetireOtherOrganizationOrOrigin() async throws {
        let org = UUID().uuidString.lowercased(), otherOrg = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org); removeOwnCache(otherOrg) }
        let api = client([.init(200, try page([(1, "Current item")]))])
        let catalog = PriceBookCatalog(markDenialOverride: { _, _, _ in true })
        let context = PriceBookCatalogContext(organizationID: org, sessionGeneration: generation, authority: testAuthority)
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        let saved = try Data(contentsOf: cacheURL(org))
        let origin = try XCTUnwrap(api.normalizedOrigin)
        XCTAssertTrue(catalog.recordExternalDenial(organizationID: otherOrg, origin: origin, authority: testAuthority, status: 401))
        XCTAssertTrue(catalog.recordExternalDenial(organizationID: org, origin: "http://localhost:4321", authority: testAuthority, status: 403))
        XCTAssertTrue(catalog.isCurrent(context, api: api))
        XCTAssertEqual(catalog.items.map(\.id), [id(1)])
        XCTAssertEqual(try Data(contentsOf: cacheURL(org)), saved)
    }

    func testExternalDenialCancelsInFlightMatchingCatalog() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID(), gate = URLProtocolFixture.Gate()
        defer { gate.release(); removeOwnCache(org) }
        let api = client([.init(200, try page([(1, "Late item")]), gate: gate)])
        let catalog = PriceBookCatalog(markDenialOverride: { _, _, _ in false })
        let task = Task { await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true) }
        try await waitForRequests(1)
        XCTAssertTrue(catalog.recordExternalDenial(organizationID: org, origin: try XCTUnwrap(api.normalizedOrigin), authority: testAuthority, status: 403))
        gate.release()
        await task.value
        XCTAssertTrue(catalog.items.isEmpty)
        XCTAssertFalse(catalog.isCurrent(.init(organizationID: org, sessionGeneration: generation, authority: testAuthority), api: api))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL(org).path), "A denied in-flight response must not recreate the cache")
    }

    func testExternalDenialStorageFailureIsReportedAndRemainsBlockedInMemory() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org) }
        let api = client([.init(200, try page([(1, "Old item")])), URLProtocolFixture.offline])
        let catalog = PriceBookCatalog(removeCacheFile: { _ in false }, markDenialOverride: { _, _, _ in false })
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        XCTAssertFalse(catalog.recordExternalDenial(organizationID: org, origin: try XCTUnwrap(api.normalizedOrigin), authority: testAuthority, status: 403))
        XCTAssertTrue(catalog.denialPersistenceFailure)
        XCTAssertTrue(catalog.items.isEmpty)
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: UUID(), authority: testAuthority, force: true)
        XCTAssertTrue(catalog.items.isEmpty, "An unpersisted denial must not restore the old file in this process")
    }

    func testNonAuthorizationErrorDoesNotRetireCatalog() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org) }
        let api = client([.init(200, try page([(1, "Still authorized")]))])
        let catalog = PriceBookCatalog()
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        XCTAssertFalse(catalog.recordExternalDenial(organizationID: org, origin: try XCTUnwrap(api.normalizedOrigin), authority: testAuthority, status: 400))
        XCTAssertEqual(catalog.items.map(\.id), [id(1)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL(org).path))
    }

    func testForbiddenRefreshHidesCompleteCacheAndBlocksSelection() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org) }
        let api = client([.init(200, try page([(1, "Formerly authorized")])), .init(403, "{}")])
        let catalog = PriceBookCatalog()
        let context = PriceBookCatalogContext(organizationID: org, sessionGeneration: generation, authority: testAuthority)
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        XCTAssertTrue(catalog.isCurrent(context, api: api))
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        XCTAssertTrue(catalog.items.isEmpty)
        XCTAssertFalse(catalog.isCurrent(context, api: api))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL(org).path), "Denied cache cannot return on offline relaunch")
    }

    func testForbiddenCacheCannotReturnOfflineWhenFileDeletionFails() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org) }
        let api = client([.init(200, try page([(1, "Denied item")])), .init(403, "{}")])
        let catalog = PriceBookCatalog(removeCacheFile: { _ in false }) // Simulate an I/O deletion failure.
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL(org).path))
        let offline = client([URLProtocolFixture.offline])
        let reopened = PriceBookCatalog()
        let session = UUID()
        await reopened.refresh(api: offline, organizationID: org, sessionGeneration: session, authority: testAuthority, force: true)
        XCTAssertTrue(reopened.items.isEmpty, "A failed file deletion must not restore denied items")
        XCTAssertFalse(reopened.isCurrent(.init(organizationID: org, sessionGeneration: session, authority: testAuthority), api: offline))
    }

    func testMarkerWriteFailureFallsBackToDeletingSavedCatalog() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org) }
        let api = client([.init(200, try page([(1, "Old item")])), .init(403, "{}")])
        let catalog = PriceBookCatalog(markDenialOverride: { _, _, _ in false })
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        XCTAssertFalse(catalog.denialPersistenceFailure)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL(org).path))
    }

    func testBothInvalidationWritesFailBlocksSelectionAndReportsStorageFailure() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org) }
        let api = client([.init(200, try page([(1, "Old item")])), .init(403, "{}")])
        let catalog = PriceBookCatalog(removeCacheFile: { _ in false }, markDenialOverride: { _, _, _ in false })
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        XCTAssertTrue(catalog.denialPersistenceFailure)
        XCTAssertTrue(catalog.items.isEmpty)
        XCTAssertFalse(catalog.isCurrent(.init(organizationID: org, sessionGeneration: generation, authority: testAuthority), api: api))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL(org).path))
    }

    func testBothInvalidationsFailDoesNotRestoreDeniedFileAfterSessionChange() async throws {
        let org = UUID().uuidString.lowercased()
        defer { removeOwnCache(org) }
        let api = client([.init(200, try page([(1, "Old item")])), .init(403, "{}"), URLProtocolFixture.offline])
        let catalog = PriceBookCatalog(removeCacheFile: { _ in false }, markDenialOverride: { _, _, _ in false })
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: UUID(), authority: testAuthority, force: true)
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: UUID(), authority: testAuthority, force: true)
        XCTAssertTrue(catalog.denialPersistenceFailure)
        let newSession = UUID()
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: newSession, authority: testAuthority, force: true)
        XCTAssertTrue(catalog.items.isEmpty)
        XCTAssertFalse(catalog.isCurrent(.init(organizationID: org, sessionGeneration: newSession, authority: testAuthority), api: api))
    }

    func testCompletedAuthorizedRetryReplacesDeniedCacheAndRestoresOfflineUse() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org) }
        let api = client([.init(200, try page([(1, "Denied item")])), .init(403, "{}"),
                          .init(200, try page([(2, "New authorized item")]))])
        let catalog = PriceBookCatalog(removeCacheFile: { _ in false })
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        let offline = client([URLProtocolFixture.offline])
        let reopened = PriceBookCatalog()
        await reopened.refresh(api: offline, organizationID: org, sessionGeneration: UUID(), authority: testAuthority, force: true)
        XCTAssertEqual(reopened.items.map(\.id), [id(2)])
    }

    func testSuccessfulRetryAfterForbiddenCanShowNewAuthorizedItems() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org) }
        let api = client([.init(403, "{}"), .init(200, try page([(2, "Authorized again")]))])
        let catalog = PriceBookCatalog()
        let context = PriceBookCatalogContext(organizationID: org, sessionGeneration: generation, authority: testAuthority)
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        XCTAssertFalse(catalog.isCurrent(context, api: api))
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        XCTAssertTrue(catalog.isCurrent(context, api: api))
        XCTAssertEqual(catalog.items.map(\.id), [id(2)])
    }

    func testForbiddenLaterPageHidesPartialItemsAndBlocksSelection() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org) }
        let api = client([.init(200, try page([(1, "Formerly authorized")], cursor: id(9000))), .init(403, "{}")])
        let catalog = PriceBookCatalog()
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        XCTAssertTrue(catalog.items.isEmpty)
        XCTAssertFalse(catalog.isCurrent(.init(organizationID: org, sessionGeneration: generation, authority: testAuthority), api: api))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL(org).path))
    }

    func testMatchingAuthorityCanUseScopedCacheAfterOfflineRelaunch() async throws {
        let org = UUID().uuidString.lowercased()
        defer { removeOwnCache(org) }
        let online = client([.init(200, try page([(1, "Offline item")]))])
        let first = PriceBookCatalog()
        await first.refresh(api: online, organizationID: org, sessionGeneration: UUID(), authority: testAuthority, force: true)
        let offline = client([URLProtocolFixture.offline])
        let restored = PriceBookCatalog()
        let session = UUID()
        let restoredAuthority = PriceBookAuthority(actorID: testAuthority.actorID,
            policyVersion: testAuthority.policyVersion, generation: testAuthority.generation, revision: UUID())
        await restored.refresh(api: offline, organizationID: org, sessionGeneration: session, authority: restoredAuthority, force: true)
        XCTAssertEqual(restored.items.map(\.id), [id(1)])
        XCTAssertTrue(restored.isCurrent(.init(organizationID: org, sessionGeneration: session, authority: restoredAuthority), api: offline))
        XCTAssertNotNil(restored.error)
    }

    func testChangedPolicyDoesNotReuseOfflineCatalog() async throws {
        let org = UUID().uuidString.lowercased()
        defer { removeOwnCache(org) }
        let online = client([.init(200, try page([(1, "Old policy")]))])
        let first = PriceBookCatalog()
        await first.refresh(api: online, organizationID: org, sessionGeneration: UUID(), authority: testAuthority, force: true)
        let changed = PriceBookAuthority(actorID: testAuthority.actorID, policyVersion: 2,
                                         generation: "changed-scope", revision: UUID())
        let offline = client([URLProtocolFixture.offline])
        let restored = PriceBookCatalog()
        await restored.refresh(api: offline, organizationID: org, sessionGeneration: UUID(), authority: changed, force: true)
        XCTAssertTrue(restored.items.isEmpty)
    }

    func testLegacyCacheWithoutOriginIsNotTrusted() async throws {
        let org = UUID().uuidString.lowercased()
        defer { removeOwnCache(org) }
        let file = cacheURL(org)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacy = """
        [{"id":"\(id(1))","description":"Unscoped item","unit":"flat","kind":"service","taxClassification":"taxable","sellPrice":{"amount":10000,"currency":"USD"},"revision":4}]
        """
        try Data(legacy.utf8).write(to: file)
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try page([(2, "Current item")]), gate: gate)])
        let catalog = PriceBookCatalog()
        let refresh = Task { await catalog.refresh(api: api, organizationID: org, sessionGeneration: UUID(), authority: testAuthority, force: true) }
        try await waitForRequests(1)
        XCTAssertTrue(catalog.items.isEmpty, "A cache without origin provenance must not be exposed")
        XCTAssertTrue(catalog.needsScopedRefresh)
        gate.release()
        await refresh.value
        XCTAssertEqual(catalog.items.map(\.id), [id(2)])
        XCTAssertFalse(catalog.needsScopedRefresh)
    }

    func testAPIScopeChangeBeforeSharedLoadStartsCannotFillThePreviousWorkspaceCache() async throws {
        let org = UUID().uuidString.lowercased()
        defer { removeOwnCache(org) }
        let api = client([.init(200, try page([(1,"Changed workspace")]))])
        let catalog = PriceBookCatalog()
        var invalidated = false
        let observation = catalog.$loading.sink { loading in
            if loading && !invalidated {
                invalidated = true
                api.invalidateRequests()
            }
        }
        defer { observation.cancel() }
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: UUID(), authority: testAuthority, force: true)
        XCTAssertTrue(catalog.items.isEmpty)
        XCTAssertFalse(catalog.loading)
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty, "A load handed to a changed API scope must not start a request")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL(org).path))
    }

    func testCancellingInitialCallerDoesNotStrandSameScopeRefresh() async throws {
        let org = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(org) }
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try page([(1,"Shared catalog")]), gate: gate)])
        let catalog = PriceBookCatalog()
        let first = Task { await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true) }
        try await waitForRequests(1)
        let release = Task {
            first.cancel()
            gate.release()
        }
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        await release.value
        await first.value
        XCTAssertEqual(catalog.items.map(\.id), [id(1)])
        XCTAssertFalse(catalog.loading)
        XCTAssertNil(catalog.error)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        XCTAssertTrue(String(decoding: try Data(contentsOf: cacheURL(org)), as: UTF8.self).contains("Shared catalog"))
    }

    func testRefreshLoadsAllPagesAndDeduplicatesIDs() async throws {
        let org = UUID().uuidString.lowercased()
        defer { removeOwnCache(org) }
        let api = client([.init(200, try page([(1,"Drain inspection"),(2,"Valve replacement")], cursor: id(9000))),
                          .init(200, try page([(2,"Valve replacement"),(3,"Later page service")]))])
        let catalog = PriceBookCatalog()
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: UUID(), authority: testAuthority, force: true)
        XCTAssertEqual(catalog.items.map(\.id), [id(1),id(2),id(3)])
        XCTAssertEqual(catalog.index.search("later page").map(\.id), [id(3)])
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
        XCTAssertFalse(catalog.loading)
        XCTAssertNil(catalog.error)
    }

    func testLatePriorOrganizationRefreshCannotReplaceCurrentCatalog() async throws {
        let a = UUID().uuidString.lowercased(), b = UUID().uuidString.lowercased()
        defer { removeOwnCache(a); removeOwnCache(b) }
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try page([(1,"Old workspace")]), gate: gate), .init(200, try page([(2,"Current workspace")]))])
        let catalog = PriceBookCatalog()
        let old = Task { await catalog.refresh(api: api, organizationID: a, sessionGeneration: UUID(), authority: testAuthority, force: true) }
        try await waitForRequests(1)
        await catalog.refresh(api: api, organizationID: b, sessionGeneration: UUID(), authority: testAuthority, force: true)
        gate.release()
        await old.value
        XCTAssertEqual(catalog.organizationID, b)
        XCTAssertEqual(catalog.items.map(\.id), [id(2)])
        XCTAssertFalse(catalog.loading)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL(a).path))
    }

    func testLatePriorGenerationRefreshCannotReplaceCurrentCatalogForSameOrganization() async throws {
        let org = UUID().uuidString.lowercased()
        defer { removeOwnCache(org) }
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try page([(1,"Previous session")]), gate: gate), .init(200, try page([(2,"Current session")]))])
        let catalog = PriceBookCatalog()
        let old = Task { await catalog.refresh(api: api, organizationID: org, sessionGeneration: UUID(), authority: testAuthority, force: true) }
        try await waitForRequests(1)
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: UUID(), authority: testAuthority, force: true)
        gate.release()
        await old.value
        XCTAssertEqual(catalog.items.map(\.id), [id(2)])
        XCTAssertFalse(catalog.loading)
        XCTAssertNil(catalog.error)
        let saved = try Data(contentsOf: cacheURL(org))
        XCTAssertTrue(String(decoding: saved, as: UTF8.self).contains("Current session"))
        XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains("Previous session"))
    }

    func testReturningToSameScopeCannotPublishAnOlderRequest() async throws {
        let a = UUID().uuidString.lowercased(), b = UUID().uuidString.lowercased(), generation = UUID()
        defer { removeOwnCache(a); removeOwnCache(b) }
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try page([(1,"First A read")]), gate: gate),
                          .init(200, try page([(2,"B read")])), .init(200, try page([(3,"New A read")]))])
        let catalog = PriceBookCatalog()
        let old = Task { await catalog.refresh(api: api, organizationID: a, sessionGeneration: generation, authority: testAuthority, force: true) }
        try await waitForRequests(1)
        await catalog.refresh(api: api, organizationID: b, sessionGeneration: generation, authority: testAuthority, force: true)
        await catalog.refresh(api: api, organizationID: a, sessionGeneration: generation, authority: testAuthority, force: true)
        gate.release()
        await old.value
        XCTAssertEqual(catalog.items.map(\.id), [id(3)])
        XCTAssertFalse(catalog.loading)
        XCTAssertTrue(String(decoding: try Data(contentsOf: cacheURL(a)), as: UTF8.self).contains("New A read"))
    }

    func testLeavingWorkspaceWhileReadIsPendingCannotResurrectItsCatalog() async throws {
        let org = UUID().uuidString.lowercased()
        defer { removeOwnCache(org) }
        let gate = URLProtocolFixture.Gate()
        defer { gate.release() }
        let api = client([.init(200, try page([(1,"Left workspace")]), gate: gate)])
        let catalog = PriceBookCatalog()
        let old = Task { await catalog.refresh(api: api, organizationID: org, sessionGeneration: UUID(), authority: testAuthority, force: true) }
        try await waitForRequests(1)
        await catalog.refresh(api: api, organizationID: nil, sessionGeneration: UUID(), authority: testAuthority, force: true)
        gate.release()
        await old.value
        XCTAssertNil(catalog.organizationID)
        XCTAssertTrue(catalog.items.isEmpty)
        XCTAssertFalse(catalog.loading)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL(org).path))
    }

    func testUnfinishedRefreshKeepsTheLastCompleteCatalogAndCache() async throws {
        let org = UUID().uuidString.lowercased()
        defer { removeOwnCache(org) }
        var replies: [URLProtocolFixture.Reply] = [.init(200, try page([(1,"Previous complete catalog")]))]
        for n in 0..<PriceBookCatalog.maximumPages {
            replies.append(.init(200, try page([(100+n,"Unfinished page \(n)")], cursor: id(9000+n))))
        }
        let api = client(replies)
        let catalog = PriceBookCatalog()
        let generation = UUID()
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        let saved = try Data(contentsOf: cacheURL(org))
        await catalog.refresh(api: api, organizationID: org, sessionGeneration: generation, authority: testAuthority, force: true)
        XCTAssertEqual(catalog.items.map(\.id), [id(1)])
        XCTAssertNotNil(catalog.error)
        XCTAssertFalse(catalog.loading)
        XCTAssertEqual(try Data(contentsOf: cacheURL(org)), saved)
    }

    private func client(_ replies: [URLProtocolFixture.Reply]) -> APIClient {
        APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")
    }
    private func id(_ n: Int) -> String { String(format: "00000000-0000-4000-8000-%012d", n) }
    private func page(_ rows: [(Int,String)], cursor: String? = nil) throws -> String {
        let items: [[String: Any]] = rows.map { n, title in
            let uuid = id(n)
            return ["id": uuid, "resourceId": "price_book_items", "label": title,
                    "fields": ["price_book_items.id": uuid, "price_book_items.current_revision": 4,
                               "price_book_items.description": title, "price_book_items.unit": "flat",
                               "price_book_items.sell_price_amount": 10000, "price_book_items.currency": "USD",
                               "price_book_items.tax_classification": "taxable", "price_book_items.kind": "service"]]
        }
        let value: [String: Any] = ["schemaVersion": 1, "resourceId": "price_book_items", "purpose": "collection",
                                   "localMode": "complete", "items": items, "nextCursor": cursor as Any? ?? NSNull(),
                                   "planId": "test", "viewId": NSNull()]
        return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }
    private func waitForRequests(_ count: Int) async throws {
        for _ in 0..<300 {
            if URLProtocolFixture.recorded.count >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected request count \(count), got \(URLProtocolFixture.recorded.count)")
    }
    private func cacheURL(_ org: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PriceBook", isDirectory: true).appendingPathComponent("\(org).json")
    }
    private func removeOwnCache(_ org: String) { try? FileManager.default.removeItem(at: cacheURL(org)) }
}

// Isolated experiment only: these types are compiled into the test target, never the app.
private struct LeasePrototypeScope: Codable, Hashable {
    let actor: String
    let organization: String
    let origin: String
    let generation: String
    let policyVersion: Int
    init(actor: String, organization: String, origin: String, generation: String, policyVersion: Int = 1) {
        self.actor = actor; self.organization = organization; self.origin = origin
        self.generation = generation; self.policyVersion = policyVersion
    }
}

@MainActor
final class PriceBookOfflineLeasePrototypeTests: XCTestCase {
    private let scope = LeasePrototypeScope(actor: "actor", organization: "org", origin: "https://example.test", generation: "1")
    private let now = Date(timeIntervalSince1970: 1000)

    private func fixture() throws -> LeasePrototypeStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lease-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return LeasePrototypeStore(root: root)
    }

    func testCompleteAuthorizedSnapshotSurvivesReopeningButExpires() throws {
        let store = try fixture()
        let coordinator = LeasePrototype(store: store)
        let token = try XCTUnwrap(coordinator.begin(scope))
        XCTAssertTrue(coordinator.commit(token, payload: Data("catalog".utf8), deadline: now.addingTimeInterval(30), now: now))
        XCTAssertEqual(LeasePrototype(store: store).read(scope, now: now), Data("catalog".utf8))
        XCTAssertNil(LeasePrototype(store: store).read(scope, now: now.addingTimeInterval(30)))
    }

    func testDirtyBarrierSurvivesRestartAndDenial() throws {
        let store = try fixture()
        let coordinator = LeasePrototype(store: store)
        let first = try XCTUnwrap(coordinator.begin(scope))
        XCTAssertTrue(coordinator.commit(first, payload: Data("old".utf8), deadline: now.addingTimeInterval(30), now: now))
        _ = try XCTUnwrap(coordinator.begin(scope)) // A denial or crash occurs after request starts.
        XCTAssertNil(LeasePrototype(store: store).read(scope, now: now))
    }

    func testFailedBarrierDoesNotPermitRequestAndUncertainWriteStaysDirty() throws {
        let store = try fixture()
        let coordinator = LeasePrototype(store: store)
        let first = try XCTUnwrap(coordinator.begin(scope))
        XCTAssertTrue(coordinator.commit(first, payload: Data("old".utf8), deadline: now.addingTimeInterval(30), now: now))
        store.failure = .beforeLease
        XCTAssertNil(coordinator.begin(scope), "Caller must not start the request when the barrier fails")
        XCTAssertEqual(LeasePrototype(store: store).read(scope, now: now), Data("old".utf8))
        store.failure = .afterLease
        XCTAssertNil(coordinator.begin(scope))
        XCTAssertNil(LeasePrototype(store: store).read(scope, now: now))
    }

    func testSnapshotOrCleanWriteFailureCannotRestoreOfflineData() throws {
        for failure in [LeasePrototypeStore.Failure.beforeSnapshot, .afterSnapshot, .beforeLease] {
            let store = try fixture()
            let coordinator = LeasePrototype(store: store)
            let token = try XCTUnwrap(coordinator.begin(scope))
            store.failure = failure
            XCTAssertFalse(coordinator.commit(token, payload: Data("new".utf8), deadline: now.addingTimeInterval(30), now: now))
            XCTAssertNil(LeasePrototype(store: store).read(scope, now: now))
        }
    }

    func testScopeIsolationLegacyDataAndStaleTransactions() throws {
        let store = try fixture()
        let coordinator = LeasePrototype(store: store)
        try store.writeLegacy(scope, payload: Data("legacy".utf8))
        XCTAssertNil(coordinator.read(scope, now: now))
        let stale = try XCTUnwrap(coordinator.begin(scope))
        let current = try XCTUnwrap(coordinator.begin(scope))
        XCTAssertFalse(coordinator.commit(stale, payload: Data("stale".utf8), deadline: now.addingTimeInterval(30), now: now))
        XCTAssertTrue(coordinator.commit(current, payload: Data("fresh".utf8), deadline: now.addingTimeInterval(30), now: now))
        for other in [LeasePrototypeScope(actor: "other", organization: "org", origin: scope.origin, generation: "1"), LeasePrototypeScope(actor: "actor", organization: "other", origin: scope.origin, generation: "1"), LeasePrototypeScope(actor: "actor", organization: "org", origin: "https://other.test", generation: "1"), LeasePrototypeScope(actor: "actor", organization: "org", origin: scope.origin, generation: "2")] {
            XCTAssertNil(coordinator.read(other, now: now))
        }
        XCTAssertEqual(coordinator.read(scope, now: now), Data("fresh".utf8))
    }

    func testOldSnapshotWithSamePayloadCannotMatchNewLeaseNonce() throws {
        let store = try fixture()
        let coordinator = LeasePrototype(store: store)
        let first = try XCTUnwrap(coordinator.begin(scope))
        XCTAssertTrue(coordinator.commit(first, payload: Data("same".utf8), deadline: now.addingTimeInterval(30), now: now))
        let old = try store.snapshot(scope)
        let second = try XCTUnwrap(coordinator.begin(scope))
        XCTAssertTrue(coordinator.commit(second, payload: Data("same".utf8), deadline: now.addingTimeInterval(30), now: now))
        try store.writeSnapshot(old)
        XCTAssertNil(LeasePrototype(store: store).read(scope, now: now))
    }

    func testUncertainCleanWriteHasNoSuccessAcknowledgement() throws {
        let store = try fixture()
        let coordinator = LeasePrototype(store: store)
        let token = try XCTUnwrap(coordinator.begin(scope))
        store.failure = .afterLease
        XCTAssertFalse(coordinator.commit(token, payload: Data("authorized".utf8), deadline: now.addingTimeInterval(30), now: now))
        // The write may already have reached disk; this is safe only because a
        // complete authorized response preceded it and its binding validates.
        XCTAssertEqual(LeasePrototype(store: store).read(scope, now: now), Data("authorized".utf8))
    }

    func testKeychainLeaseIsScopedAndMissingMarkerFailsClosed() throws {
        let service = "com.thorbis.field.test-only-lease.\(UUID().uuidString)"
        let base = try fixture()
        let store = LeasePrototypeStore(root: base.root, keychainService: service)
        addTeardownBlock { store.deleteTestKeychainItems() }
        let coordinator = LeasePrototype(store: store)
        let token = try XCTUnwrap(coordinator.begin(scope))
        XCTAssertTrue(coordinator.commit(token, payload: Data("catalog".utf8), deadline: now.addingTimeInterval(30), now: now))
        XCTAssertEqual(store.testKeychainLookupStatus(scope), errSecSuccess, "The lease must really be in Keychain")
        let other = LeasePrototypeScope(actor: "other", organization: scope.organization, origin: scope.origin, generation: scope.generation)
        XCTAssertEqual(store.testKeychainLookupStatus(other), errSecItemNotFound)
        XCTAssertEqual(LeasePrototype(store: store).read(scope, now: now), Data("catalog".utf8))
        XCTAssertEqual(store.deleteTestKeychainMarker(scope), errSecSuccess)
        XCTAssertNil(LeasePrototype(store: store).read(scope, now: now), "A file alone is never authorization")
    }

    func testKeychainDirtyMarkerAndFailedWritesPreserveCorrectOfflineOutcome() throws {
        let service = "com.thorbis.field.test-only-lease.\(UUID().uuidString)"
        let base = try fixture()
        let store = LeasePrototypeStore(root: base.root, keychainService: service)
        addTeardownBlock { store.deleteTestKeychainItems() }
        let coordinator = LeasePrototype(store: store)
        let first = try XCTUnwrap(coordinator.begin(scope))
        XCTAssertTrue(coordinator.commit(first, payload: Data("old".utf8), deadline: now.addingTimeInterval(30), now: now))
        store.failure = .beforeLease
        XCTAssertNil(coordinator.begin(scope)) // no request may be issued
        XCTAssertEqual(LeasePrototype(store: store).read(scope, now: now), Data("old".utf8))
        store.failure = .afterLease
        XCTAssertNil(coordinator.begin(scope))
        XCTAssertNil(LeasePrototype(store: store).read(scope, now: now), "Dirty Keychain state survives reopening")
        store.failure = .none
        let next = try XCTUnwrap(coordinator.begin(scope))
        store.failure = .afterSnapshot
        XCTAssertFalse(coordinator.commit(next, payload: Data("new".utf8), deadline: now.addingTimeInterval(30), now: now))
        XCTAssertNil(LeasePrototype(store: store).read(scope, now: now))
    }

    func testKeychainScopesIncludePolicyAndLegacyNeedsAuthorization() throws {
        let service = "com.thorbis.field.test-only-lease.\(UUID().uuidString)"
        let base = try fixture()
        let store = LeasePrototypeStore(root: base.root, keychainService: service)
        addTeardownBlock { store.deleteTestKeychainItems() }
        let coordinator = LeasePrototype(store: store)
        try store.writeLegacy(scope, payload: Data("legacy".utf8))
        XCTAssertNil(coordinator.read(scope, now: now))
        let token = try XCTUnwrap(coordinator.begin(scope))
        XCTAssertTrue(coordinator.commit(token, payload: Data("fresh".utf8), deadline: now.addingTimeInterval(30), now: now))
        let nextPolicy = LeasePrototypeScope(actor: scope.actor, organization: scope.organization, origin: scope.origin, generation: scope.generation, policyVersion: 2)
        XCTAssertNil(coordinator.read(nextPolicy, now: now))
        XCTAssertEqual(store.testKeychainLookupStatus(nextPolicy), errSecItemNotFound)
        XCTAssertEqual(coordinator.read(scope, now: now), Data("fresh".utf8))
    }

    func testMismatchedSnapshotAndInvalidDeadlineFailClosed() throws {
        let store = try fixture()
        let coordinator = LeasePrototype(store: store)
        let token = try XCTUnwrap(coordinator.begin(scope))
        XCTAssertFalse(coordinator.commit(token, payload: Data("data".utf8), deadline: now, now: now))
        XCTAssertNil(coordinator.read(scope, now: now))
        let valid = try XCTUnwrap(coordinator.begin(scope))
        XCTAssertTrue(coordinator.commit(valid, payload: Data("data".utf8), deadline: now.addingTimeInterval(30), now: now))
        try store.writeLegacy(scope, payload: Data("tampered".utf8))
        XCTAssertNil(coordinator.read(scope, now: now))
    }
}

private struct LeasePrototypeRecord: Codable, Equatable {
    let scope: LeasePrototypeScope
    let transaction: UUID
    let nonce: UUID?
    let digest: Data?
    let deadline: Date?
}

private struct LeasePrototypeSnapshot: Codable {
    let scope: LeasePrototypeScope
    let nonce: UUID
    let payload: Data
}

// This fixture is deliberately independent of the application's real storage.
private final class LeasePrototypeStore {
    enum Failure { case none, beforeLease, afterLease, beforeSnapshot, afterSnapshot }
    enum StoreError: Error { case injected, keychain(OSStatus) }
    let root: URL
    var failure: Failure = .none
    let keychainService: String?
    init(root: URL, keychainService: String? = nil) { self.root = root; self.keychainService = keychainService }

    private func testKeychainQuery(_ scope: LeasePrototypeScope) -> [String: Any] {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let bytes = (try? encoder.encode(scope)) ?? Data()
        let account = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService ?? "",
                kSecAttrAccount as String: account]
    }
    func testKeychainLookupStatus(_ scope: LeasePrototypeScope) -> OSStatus {
        SecItemCopyMatching(testKeychainQuery(scope) as CFDictionary, nil)
    }
    func deleteTestKeychainMarker(_ scope: LeasePrototypeScope) -> OSStatus {
        SecItemDelete(testKeychainQuery(scope) as CFDictionary)
    }
    func deleteTestKeychainItems() {
        guard let keychainService, keychainService.hasPrefix("com.thorbis.field.test-only-lease.") else { return }
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService] as CFDictionary)
    }

    private func path(_ scope: LeasePrototypeScope, _ kind: String) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let digest = SHA256.hash(data: try encoder.encode(scope)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("\(digest)-\(kind)")
    }
    func lease(_ scope: LeasePrototypeScope) throws -> LeasePrototypeRecord {
        let data: Data
        if keychainService != nil {
            var query = testKeychainQuery(scope)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let value = result as? Data else { throw StoreError.keychain(status) }
            data = value
        } else {
            data = try Data(contentsOf: path(scope, "lease"))
        }
        return try JSONDecoder().decode(LeasePrototypeRecord.self, from: data)
    }
    func snapshot(_ scope: LeasePrototypeScope) throws -> LeasePrototypeSnapshot {
        try JSONDecoder().decode(LeasePrototypeSnapshot.self, from: Data(contentsOf: path(scope, "snapshot")))
    }
    func writeLease(_ record: LeasePrototypeRecord) throws {
        if failure == .beforeLease { throw StoreError.injected }
        let data = try JSONEncoder().encode(record)
        if keychainService != nil {
            let query = testKeychainQuery(record.scope)
            let changes = [kSecValueData as String: data]
            var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
            if status == errSecItemNotFound {
                var item = query
                item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(item as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw StoreError.keychain(status) }
        } else {
            try data.write(to: path(record.scope, "lease"), options: .atomic)
        }
        if failure == .afterLease { throw StoreError.injected }
        guard try lease(record.scope) == record else { throw StoreError.injected }
    }
    func writeSnapshot(_ snapshot: LeasePrototypeSnapshot) throws {
        if failure == .beforeSnapshot { throw StoreError.injected }
        try JSONEncoder().encode(snapshot).write(to: path(snapshot.scope, "snapshot"), options: [.atomic, .completeFileProtection])
        if failure == .afterSnapshot { throw StoreError.injected }
        let check = try self.snapshot(snapshot.scope)
        guard check.scope == snapshot.scope, check.nonce == snapshot.nonce, check.payload == snapshot.payload else { throw StoreError.injected }
    }
    func writeLegacy(_ scope: LeasePrototypeScope, payload: Data) throws {
        try payload.write(to: path(scope, "snapshot"), options: .atomic)
    }
}

// A caller may issue a network request only after begin returns a token. The
// coordinator assumes one serialized owner and a complete, authorized response.
@MainActor
private final class LeasePrototype {
    struct Token { let scope: LeasePrototypeScope; let id: UUID }
    private let store: LeasePrototypeStore
    init(store: LeasePrototypeStore) { self.store = store }
    func begin(_ scope: LeasePrototypeScope) -> Token? {
        let token = Token(scope: scope, id: UUID())
        do {
            try store.writeLease(.init(scope: scope, transaction: token.id, nonce: nil, digest: nil, deadline: nil))
            return token
        } catch { return nil }
    }
    func commit(_ token: Token, payload: Data, deadline: Date, now: Date) -> Bool {
        guard deadline.timeIntervalSinceReferenceDate.isFinite, now.timeIntervalSinceReferenceDate.isFinite, deadline > now,
              let lease = try? store.lease(token.scope), lease.scope == token.scope,
              lease.transaction == token.id, lease.nonce == nil, lease.digest == nil, lease.deadline == nil else { return false }
        let nonce = UUID()
        let snapshot = LeasePrototypeSnapshot(scope: token.scope, nonce: nonce, payload: payload)
        do {
            try store.writeSnapshot(snapshot)
            let digest = Data(SHA256.hash(data: payload))
            try store.writeLease(.init(scope: token.scope, transaction: token.id, nonce: nonce, digest: digest, deadline: deadline))
            return true
        } catch { return false }
    }
    func read(_ scope: LeasePrototypeScope, now: Date) -> Data? {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              let lease = try? store.lease(scope), lease.scope == scope,
              let nonce = lease.nonce, let digest = lease.digest, let deadline = lease.deadline,
              deadline.timeIntervalSinceReferenceDate.isFinite, now < deadline,
              let snapshot = try? store.snapshot(scope), snapshot.scope == scope,
              snapshot.nonce == nonce, Data(SHA256.hash(data: snapshot.payload)) == digest else { return nil }
        return snapshot.payload
    }
}
