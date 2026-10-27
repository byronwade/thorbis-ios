import XCTest
@testable import Thorbis

@MainActor
final class MenuLayoutTests: XCTestCase {
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
}
