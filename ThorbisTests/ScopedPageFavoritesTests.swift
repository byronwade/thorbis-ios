import XCTest
@testable import Thorbis

@MainActor
final class ScopedPageFavoritesTests: XCTestCase {
    private func scope(actor: String = "actor", organization: String = "org", origin: String = "https://app.thorbis.com") -> ScopedRecordFavorites.Scope {
        .init(actorID: actor, organizationID: organization, origin: origin, sessionGeneration: UUID(),
              authorityRevision: UUID(), apiGeneration: UUID(), savedCopyRevision: UUID())
    }

    func testPagesRemainIsolatedAcrossPersonWorkspaceOriginAndRelaunch() {
        let name = "page-favorites-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let first = scope()
        let model = ScopedPageFavorites(defaults: defaults)
        let jobs = ScopedPageFavorites.Page(kind: .menu, value: MenuItem.jobs.rawValue)
        let equipment = ScopedPageFavorites.Page(kind: .local, value: LocalWorkspaceSection.equipment.rawValue)
        model.bind(first)
        XCTAssertTrue(model.toggle(jobs, allowed: { _ in true }))
        XCTAssertTrue(model.toggle(equipment, allowed: { _ in true }))
        model.bind(scope(actor: "other")); XCTAssertTrue(model.pages.isEmpty)
        model.bind(scope(organization: "other")); XCTAssertTrue(model.pages.isEmpty)
        model.bind(scope(origin: "http://localhost:3000")); XCTAssertTrue(model.pages.isEmpty)
        let relaunched = ScopedPageFavorites(defaults: defaults)
        relaunched.bind(first)
        XCTAssertEqual(relaunched.pages, [jobs, equipment])
        relaunched.bind(nil); XCTAssertTrue(relaunched.pages.isEmpty)
    }

    func testUnknownAndUnauthorizedPagesNeverDisplayOrToggle() {
        let model = ScopedPageFavorites(defaults: UserDefaults(suiteName: "page-favorites-\(UUID())")!)
        let jobs = ScopedPageFavorites.Page(kind: .menu, value: MenuItem.jobs.rawValue)
        let unknown = ScopedPageFavorites.Page(kind: .menu, value: "https://outside.example")
        model.bind(scope())
        XCTAssertFalse(model.toggle(unknown, allowed: { _ in true }))
        XCTAssertFalse(model.toggle(jobs, allowed: { _ in false }))
        XCTAssertTrue(model.toggle(jobs, allowed: { _ in true }))
        XCTAssertTrue(model.visible(allowed: { _ in false }).isEmpty)
        XCTAssertEqual(model.visible(allowed: { _ in true }), [jobs])
    }

    func testOnlyMatchingEpochsRetireTheBoundPages() {
        let model = ScopedPageFavorites(defaults: UserDefaults(suiteName: "page-favorites-\(UUID())")!)
        let current = scope()
        let jobs = ScopedPageFavorites.Page(kind: .menu, value: MenuItem.jobs.rawValue)
        model.bind(current); XCTAssertTrue(model.toggle(jobs, allowed: { _ in true }))
        model.retireAPI(origin: current.origin, generation: UUID(), savedCopyRevision: current.savedCopyRevision)
        model.retireSession(generation: UUID(), authority: current.authorityRevision)
        XCTAssertEqual(model.pages, [jobs])
        model.retireSession(generation: current.sessionGeneration, authority: current.authorityRevision)
        XCTAssertTrue(model.pages.isEmpty)
        model.bind(current); XCTAssertEqual(model.pages, [jobs])
        model.retireAPI(origin: current.origin, generation: current.apiGeneration, savedCopyRevision: current.savedCopyRevision)
        XCTAssertTrue(model.pages.isEmpty)
    }
}
