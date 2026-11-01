import SwiftUI
import UIKit
import XCTest
@testable import Thorbis

@MainActor
final class DynamicTypeLayoutTests: XCTestCase {
    func testPrimaryActionGrowsWithAccessibleText() {
        let button = PrimaryButton(title: "On my way", busy: false, action: {})
        let standard = measure(button, type: .large)
        let enlarged = measure(button, type: .accessibility5)
        XCTAssertGreaterThan(enlarged.height, standard.height)
    }

    func testRecordTabsGrowWithAccessibleText() {
        let tabs = PaperTabs(options: ["Overview", "Invoice"], selection: .constant("Overview"))
            .fixedSize(horizontal: false, vertical: true)
        XCTAssertGreaterThan(measure(tabs, type: .accessibility5).height, measure(tabs, type: .large).height)
    }

    func testLongChipWrapsInsteadOfOverflowingANarrowContainer() {
        let chip = Chip(text: "Member with a fifteen percent service discount")
        XCTAssertGreaterThan(measure(chip, width: 150).height, measure(chip, width: 600).height)
    }

    func testFlowRowConstrainsAnOversizedLabelBeforePlacingIt() {
        let row = FlowRow {
            Text("Service address and access instructions for the customer").font(.body)
        }
        XCTAssertGreaterThan(measure(row, width: 150).height, measure(row, width: 600).height)
    }

    private func measure<V: View>(_ view: V, type: DynamicTypeSize = .large, width: CGFloat = 320) -> CGSize {
        let host = UIHostingController(rootView: view.environment(\.dynamicTypeSize, type))
        return host.sizeThatFits(in: CGSize(width: width, height: 1_000))
    }
}
