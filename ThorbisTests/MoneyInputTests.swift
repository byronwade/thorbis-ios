import XCTest
@testable import Thorbis

final class MoneyInputTests: XCTestCase {
    func testExactMinorUnitsWithoutFloatingPointRounding() {
        XCTAssertEqual(MoneyInput.cents("0.01"), 1)
        XCTAssertEqual(MoneyInput.cents("19.99"), 1999)
        XCTAssertEqual(MoneyInput.cents("1000000.00"), 100000000)
        XCTAssertNil(MoneyInput.cents("1.001"))
        XCTAssertNil(MoneyInput.cents("1000000.01"))
        XCTAssertNil(MoneyInput.cents("-1.00"))
        XCTAssertNil(MoneyInput.cents("1e5"))
        XCTAssertNil(MoneyInput.cents("invalid"))
    }
}
