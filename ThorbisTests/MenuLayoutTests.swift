import XCTest
@testable import Thorbis

@MainActor
final class MenuLayoutTests: XCTestCase {
    func testSavedWorkBarReflectsMediaAndRefusedWorkWithoutInventingAWarningCount() {
        func state(total: Int, attention: Int = 0, sending: Bool = false, warning: Bool = false) -> SavedWorkSnapshot {
            .init(groups: [], totalCount: total, attentionCount: attention, pendingCount: total - attention,
                  isSending: sending, hasListingWarning: warning)
        }
        XCTAssertNil(AppBottomBar.Sync.savedWork(state(total: 0)))
        XCTAssertEqual(AppBottomBar.Sync.savedWork(state(total: 2)), .waiting(2))
        XCTAssertEqual(AppBottomBar.Sync.savedWork(state(total: 2, sending: true)), .syncing(2))
        XCTAssertEqual(AppBottomBar.Sync.savedWork(state(total: 3, attention: 1)), .needsReview(1))
        XCTAssertEqual(AppBottomBar.Sync.savedWork(state(total: 0, warning: true)), .needsChecking)
        XCTAssertEqual(AppBottomBar.Sync.savedWork(state(total: 2, warning: true)), .needsChecking)
    }
    private func defaults() -> UserDefaults {
        let name = "menu-layout-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testStartsWithThePaperDock() {
        let layout = MenuLayout(defaults: defaults())
        XCTAssertEqual(layout.tabs, [.schedule, .jobs, .customers])
        XCTAssertTrue(layout.isDefault)
    }

    func testTabsAreCappedAndPersisted() {
        let store = defaults()
        let layout = MenuLayout(defaults: store)
        layout.addTab(.invoices)
        layout.addTab(.money)
        XCTAssertEqual(layout.tabs, [.schedule, .jobs, .customers, .invoices])
        layout.hidden.insert(.reports)
        let reloaded = MenuLayout(defaults: store)
        XCTAssertEqual(reloaded.tabs, [.schedule, .jobs, .customers, .invoices])
        XCTAssertEqual(reloaded.hidden, [.reports])
    }

    func testAddingAHiddenItemToTheTabBarShowsIt() {
        let layout = MenuLayout(defaults: defaults())
        layout.hidden.insert(.inbox)
        layout.addTab(.inbox)
        XCTAssertFalse(layout.hidden.contains(.inbox))
    }

    func testUnknownIdsFromAnotherVersionAreIgnored() throws {
        let store = defaults()
        store.set(try JSONEncoder().encode(["tabs": ["jobs", "dispatchBoard", "jobs"], "hidden": ["nope", "team"]]),
                  forKey: "thorbis.menuLayout.v1")
        let layout = MenuLayout(defaults: store)
        XCTAssertEqual(layout.tabs, [.jobs])
        XCTAssertEqual(layout.hidden, [.team])
        layout.reset()
        XCTAssertTrue(layout.isDefault)
    }

    func testEveryMoreItemOpensSomewhere() {
        for item in MenuItem.allCases where ![.schedule, .jobs, .customers].contains(item) {
            XCTAssertNotNil(item.route, item.rawValue)
        }
    }

    func testCompanyLayoutIdsMapToMenuItems() throws {
        XCTAssertEqual(MenuItem(serverTab: "revenue"), .money)
        XCTAssertEqual(MenuItem.money.serverID, "revenue")
        XCTAssertEqual(MenuItem(serverTab: "priceBook"), .priceBook)
        XCTAssertNil(MenuItem(serverTab: "more"))
        let json = #"{"tabs":["jobs","revenue","more"],"hiddenTabs":[],"moreMenu":[{"id":"reports","hidden":true},{"id":"future","hidden":true}],"jobTabs":["overview"],"version":3,"updatedAt":"2026-10-27T19:00:00Z","updatedBy":"u"}"#
        let layout = try JSONDecoder().decode(CompanyMobileLayout.self, from: Data(json.utf8))
        XCTAssertEqual(layout.tabs.compactMap(MenuItem.init(serverTab:)), [.jobs, .money])
        XCTAssertEqual(layout.moreMenu?.filter(\.hidden).compactMap { MenuItem(serverTab: $0.id) }, [.reports])
    }

    func testPhoneMenuListsTabBarPlacesFirstThenTheRest() {
        let places = AppMenuContent.places(
            tabs: [.schedule, .jobs, .customers],
            hidden: [.team],
            permitted: { $0 != .notices }
        )
        XCTAssertEqual(Array(places.prefix(3)), [.schedule, .jobs, .customers])
        XCTAssertEqual(places.filter { $0 == .schedule }.count, 1)
        XCTAssertTrue(places.contains(.estimates))
        XCTAssertTrue(places.contains(.priceBook))
        XCTAssertFalse(places.contains(.team), "Hidden places stay out of the menu")
        XCTAssertFalse(places.contains(.notices), "Places the role cannot open stay out")
    }

    func testArrangingMovesPlacesBetweenBarAndMenuAndPersistsTheOrder() {
        let store = defaults()
        let layout = MenuLayout(defaults: store)
        // Customers dragged below the divider, Invoices and Estimates dragged up into the bar.
        layout.arrange(bar: [.jobs, .invoices, .schedule, .estimates, .reports],
                       menu: [.customers, .priceBook], permitted: { _ in true })
        XCTAssertEqual(layout.tabs, [.jobs, .invoices, .schedule, .estimates], "The bar keeps at most four")
        XCTAssertEqual(Array(layout.menuOrder.prefix(3)), [.reports, .customers, .priceBook],
                       "What does not fit spills to the top of the menu")
        let reloaded = MenuLayout(defaults: store)
        XCTAssertEqual(reloaded.tabs, layout.tabs)
        XCTAssertEqual(reloaded.menuOrder, layout.menuOrder)
        let menu = AppMenuContent.menu(tabs: reloaded.tabs, hidden: [], order: reloaded.menuOrder, permitted: { _ in true })
        XCTAssertEqual(Array(menu.prefix(3)), [.reports, .customers, .priceBook])
        XCTAssertEqual(Set(menu).count, menu.count)
        XCTAssertTrue(menu.contains(.attention), "Places not yet arranged still show")
    }

    func testArrangingKeepsTabsThisRoleCannotSee() {
        let layout = MenuLayout(defaults: defaults())
        layout.arrange(bar: [.jobs], menu: [.schedule], permitted: { $0 != .customers })
        XCTAssertEqual(layout.tabs, [.jobs, .customers])
    }
}
