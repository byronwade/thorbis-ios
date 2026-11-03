import Combine
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
