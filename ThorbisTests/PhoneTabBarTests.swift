import XCTest
@testable import Thorbis

/// The iPhone bottom bar: which places each role gets, and whether the bar is on.
@MainActor
final class PhoneTabBarTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "phone-tabbar-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testEachRoleGetsItsFourPlaces() {
        XCTAssertEqual(PhoneTabs.tabs(role: .technician, opens: { _ in true }), [.schedule, .jobs, .customers, .inbox])
        XCTAssertEqual(PhoneTabs.tabs(role: .office, opens: { _ in true }), [.schedule, .jobs, .customers, .inbox])
        XCTAssertEqual(PhoneTabs.tabs(role: .owner, opens: { _ in true }), [.home, .schedule, .jobs, .money])
    }

    func testAPlaceThePersonCannotOpenIsFilledFromTheRolesNextMainPlace() {
        // A technician without Messages: Time clock (next in Paper 29N's main rows) fills the gap.
        XCTAssertEqual(PhoneTabs.tabs(role: .technician, opens: { $0 != .inbox }), [.schedule, .jobs, .customers, .timeClock])
        // An owner without Money: Reports, then nothing else is missing.
        XCTAssertEqual(PhoneTabs.tabs(role: .owner, opens: { $0 != .money }), [.home, .schedule, .jobs, .reports])
        // Office never gets the Dashboard in the bar; it stays first in More.
        let office = PhoneTabs.tabs(role: .office, opens: { $0 != .customers })
        XCTAssertFalse(office.contains(.home))
        XCTAssertEqual(office, [.schedule, .jobs, .inbox, .money])
    }

    func testABarNeverListsAPlaceThatCannotOpenOrRepeatsOne() {
        let none = PhoneTabs.tabs(role: .technician, opens: { _ in false })
        XCTAssertEqual(none, [], "Only More is left")
        let some = PhoneTabs.tabs(role: .owner, opens: { [.schedule, .jobs].contains($0) })
        XCTAssertEqual(some, [.schedule, .jobs])
        for role in [WorkRole.technician, .office, .owner] {
            let tabs = PhoneTabs.tabs(role: role, opens: { _ in true })
            XCTAssertEqual(Set(tabs).count, tabs.count)
            XCTAssertLessThanOrEqual(tabs.count, PhoneTabs.maxPlaces)
        }
    }

    func testIPhoneDefaultsToTheBottomBarAndIPadToTheSidebar() {
        XCTAssertEqual(PhoneNavigationStyle.resolve(saved: nil, isPad: false, preview: false, previewFlag: nil), .bottomBar)
        XCTAssertEqual(PhoneNavigationStyle.resolve(saved: nil, isPad: true, preview: false, previewFlag: nil), .sidebar)
        XCTAssertEqual(PhoneNavigationStyle.resolve(saved: "bottomBar", isPad: true, preview: false, previewFlag: nil), .sidebar,
                       "iPad keeps its sidebar whatever was saved")
        XCTAssertEqual(PhoneNavigationStyle.resolve(saved: "sidebar", isPad: false, preview: false, previewFlag: nil), .sidebar)
        XCTAssertEqual(PhoneNavigationStyle.resolve(saved: "nonsense", isPad: false, preview: false, previewFlag: nil), .bottomBar)
        // The design preview keeps the sidebar unless asked for the bar.
        XCTAssertEqual(PhoneNavigationStyle.resolve(saved: nil, isPad: false, preview: true, previewFlag: nil), .sidebar)
        XCTAssertEqual(PhoneNavigationStyle.resolve(saved: nil, isPad: false, preview: true, previewFlag: "bottom"), .bottomBar)
    }

    func testTheChoiceIsSavedPerDeviceAndRespected() {
        let store = defaults()
        let layout = MenuLayout(defaults: store, isPad: false, preview: false)
        XCTAssertEqual(layout.navigationStyle, .bottomBar, "Existing installs get the bar too")
        layout.navigationStyle = .sidebar
        XCTAssertEqual(MenuLayout(defaults: store, isPad: false, preview: false).navigationStyle, .sidebar)
        XCTAssertNil(store.data(forKey: "thorbis.menuLayout.v1"), "The menu layout is not touched")
        layout.navigationStyle = .bottomBar
        XCTAssertEqual(MenuLayout(defaults: store, isPad: false, preview: false).navigationStyle, .bottomBar)
    }

    func testThePreviewNeverSavesItsChoice() {
        let store = defaults()
        let layout = MenuLayout(defaults: store, isPad: false, preview: true, previewFlag: "bottom")
        XCTAssertEqual(layout.navigationStyle, .bottomBar)
        layout.navigationStyle = .sidebar
        XCTAssertNil(store.string(forKey: PhoneNavigationStyle.key))
    }

    func testAnOlderSavedLayoutStillDecodesBesideTheChoice() throws {
        let store = defaults()
        store.set(try JSONEncoder().encode(["tabs": ["estimates", "invoices"], "hidden": ["reports"]]), forKey: "thorbis.menuLayout.v1")
        store.set("sidebar", forKey: PhoneNavigationStyle.key)
        let layout = MenuLayout(defaults: store, isPad: false, preview: false)
        XCTAssertEqual(layout.tabs, [.estimates, .invoices])
        XCTAssertEqual(layout.hidden, [.reports])
        XCTAssertEqual(layout.navigationStyle, .sidebar)
        // The bar's places come from the role, never from an old saved tab list.
        XCTAssertEqual(PhoneTabs.tabs(role: .technician, opens: { _ in true }), [.schedule, .jobs, .customers, .inbox])
    }

    // The menu panel's bottom corners follow the screen's own curve, 8 in, so the phone's rounded
    // corner never cuts them; a square-cornered phone keeps Paper's 30.
    func testMenuPanelBottomCornersFollowTheScreen() {
        XCTAssertEqual(DrawerPanel.bottomRadius(topInset: 59), 47)
        XCTAssertEqual(DrawerPanel.bottomRadius(topInset: 62), 47)
        XCTAssertEqual(DrawerPanel.bottomRadius(topInset: 47), 36)
        XCTAssertEqual(DrawerPanel.bottomRadius(topInset: 20), 30)
    }
}
