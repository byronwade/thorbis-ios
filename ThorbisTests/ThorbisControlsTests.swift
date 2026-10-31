import XCTest
@testable import Thorbis

/// The custom control system keeps its state in small value types so the rules are testable
/// without driving the UI.
final class ThorbisControlsTests: XCTestCase {

    // MARK: ThorbisMenu

    func testMenuSelectFiresActionAndDismisses() {
        var fired = false
        var model = ThorbisMenuModel()
        model.isPresented = true
        let item = ThorbisMenuItem("Delete", role: .destructive) { fired = true }
        model.select(item)
        XCTAssertTrue(fired, "selecting a row runs its action")
        XCTAssertFalse(model.isPresented, "a menu dismisses after a choice")
    }

    func testMenuItemCarriesSelectionAndRole() {
        let item = ThorbisMenuItem("Keep", icon: "checkmark", isSelected: true) {}
        XCTAssertTrue(item.isSelected)
        XCTAssertEqual(item.icon, "checkmark")
        XCTAssertNil(item.role)
    }

    func testStatusPickerRowsCarryTheToneOfWhereTheJobGoes() {
        // The status picker leads each move with the glyph of the status it leads to.
        let moves = ["en_route", "arrived", "in_progress", "paused", "completed", "scheduled"]
        let rows = moves.map { ThorbisMenuItem($0, status: StatusTone(jobStatus: $0)) {} }
        XCTAssertEqual(rows.map(\.status), [.dispatched, .inProgress, .inProgress, .inProgress, .done, .scheduled])
        XCTAssertNil(ThorbisMenuItem("Plain", icon: "clock") {}.status, "rows without a status keep their icon")
    }

    func testConfirmActionCarriesDestructiveRoleAndFires() {
        var fired = false
        let action = ThorbisConfirmAction("Remove", role: .destructive) { fired = true }
        XCTAssertEqual(action.role, .destructive)
        action.action()
        XCTAssertTrue(fired)
    }

    // MARK: DisplayOptions (drives the filter/display sheet)

    func testDisplayOptionsDefaults() {
        let opts = DisplayOptions()
        XCTAssertEqual(opts.grouping, .status)
        XCTAssertEqual(opts.grouping.label, "Status")
        XCTAssertEqual(opts.ordering, .recent)
        XCTAssertEqual(opts.ordering.label, "Last updated")
        XCTAssertTrue(opts.showCompleted)
    }

    func testDisplayOptionsChangeGrouping() {
        var opts = DisplayOptions()
        opts.grouping = .assignee
        XCTAssertEqual(opts.grouping.label, "Assignee")
        XCTAssertNotEqual(opts, DisplayOptions())
    }

    func testGroupingLabelsAreStableForEveryCase() {
        let labels = DisplayOptions.Grouping.allCases.map(\.label)
        XCTAssertEqual(labels, ["Status", "Assignee", "Date", "None"])
    }
}
