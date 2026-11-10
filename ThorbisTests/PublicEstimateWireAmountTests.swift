import XCTest
@testable import Thorbis

final class PublicEstimateWireAmountTests: XCTestCase {
    private func payload(_ amount: String) -> Data {
        Data("""
        {"kind":"estimate","title":"Estimate","status":"sent","revisionNumber":1,"contentHash":"issued-content-hash","allowedActions":["approve"],"nonce":"nonce","totalAmount":\(amount),"currency":"USD"}
        """.utf8)
    }

    func testAcceptsIntegralDecimalAndSafeBoundary() throws {
        XCTAssertEqual(try JSONDecoder().decode(PublicEstimateAction.self, from: payload("4200.0")).totalAmount, 4200)
        XCTAssertEqual(try JSONDecoder().decode(PublicEstimateAction.self, from: payload("9007199254740991")).totalAmount, 9_007_199_254_740_991)
    }

    func testRejectsFractionalAndUnsafeWireValuesBeforeDoubleRounding() {
        for value in ["4200.5", "9007199254740991.1", "9007199254740992", "-1"] {
            XCTAssertThrowsError(try JSONDecoder().decode(PublicEstimateAction.self, from: payload(value)), value)
        }
    }
    func testScopeQuantityAndSignedDiscountWireValues() throws {
        let makeLine: (String, String) -> Data = { quantity, price in
            Data("""
            {"id":"line","description":"Discount","quantity":\(quantity),"unitPrice":\(price)}
            """.utf8)
        }
        let decoder = JSONDecoder()
        let discount = try decoder.decode(PublicEstimateAction.ScopeLine.self, from: makeLine("1.0", "-500.0"))
        XCTAssertEqual(discount.unitPrice, -500)
        XCTAssertEqual(discount.quantity, 1)
        for quantity in ["0", "1.5", "100001", "9007199254740991.1"] {
            XCTAssertThrowsError(try decoder.decode(PublicEstimateAction.ScopeLine.self, from: makeLine(quantity, "100")), quantity)
        }
        XCTAssertThrowsError(try decoder.decode(PublicEstimateAction.ScopeLine.self, from: makeLine("1", "9007199254740991.1")))
    }

    func testOptionalPatchRejectsBadAmountAndAllowsMissing() throws {
        let decoder = JSONDecoder()
        XCTAssertNil(try decoder.decode(PublicEstimateActionPatch.self, from: Data("{}".utf8)).totalAmount)
        XCTAssertThrowsError(try decoder.decode(PublicEstimateActionPatch.self, from: Data(#"{"totalAmount":9007199254740991.1}"#.utf8)))
    }

}
