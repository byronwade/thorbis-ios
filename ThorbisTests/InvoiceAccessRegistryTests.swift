import XCTest
@testable import Thorbis

@MainActor
final class InvoiceAccessRegistryTests: XCTestCase {
    func testScopeIsUnavailableWithoutVerifiedActorOrValidOrigin() {
        let api = APIClient(baseURL: "https://app.thorbis.com")
        XCTAssertNil(InvoiceAccessRegistry.shared.scope(api: api, invoiceID: UUID().uuidString))
        api.savedCopyScope = UUID().uuidString
        api.baseURL = "not an origin"
        XCTAssertNil(InvoiceAccessRegistry.shared.scope(api: api, invoiceID: UUID().uuidString))
    }

    func testDenialIsScopedAndChangesVersionEvenWhenAlreadyDenied() throws {
        let a = APIClient(baseURL: "https://app.thorbis.com")
        let b = APIClient(baseURL: "https://app.thorbis.com")
        a.savedCopyScope = UUID().uuidString
        b.savedCopyScope = UUID().uuidString
        let id = UUID().uuidString
        let owner = InvoiceAccessRegistry.shared
        let aScope = try XCTUnwrap(owner.scope(api: a, invoiceID: id))
        let bScope = try XCTUnwrap(owner.scope(api: b, invoiceID: id))
        let before = owner.version(aScope)
        owner.deny(aScope)
        XCTAssertTrue(owner.isDenied(aScope))
        XCTAssertFalse(owner.isDenied(bScope))
        XCTAssertNotEqual(before, owner.version(aScope))
        let first = owner.version(aScope)
        owner.deny(aScope)
        XCTAssertNotEqual(first, owner.version(aScope))
    }
}
