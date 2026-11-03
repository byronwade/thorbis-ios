import XCTest
@testable import Thorbis

@MainActor private final class OwnerTransportStore: CustomerQuarantineStore {
    var records: [CustomerQuarantineScope: CustomerQuarantineState] = [:]
    func read(_ scope: CustomerQuarantineScope) throws -> CustomerQuarantineState? { records[scope] }
    func write(_ state: CustomerQuarantineState, for scope: CustomerQuarantineScope) throws { records[scope] = state }
}

@MainActor final class CustomerGuardedOwnerTransportTests: XCTestCase {
    func testFirstCustomerReadUsesRealLiveOnlyAndNamespacedTransport() async throws {
        let scope = try CustomerQuarantineScope(actorID: "abcdefab-0000-4000-8000-000000000001", organizationID: "abcdefab-0000-4000-8000-000000000002", origin: "https://app.thorbis.com", customerID: "abcdefab-0000-4000-8000-000000000003")
        let authority = CustomerQuarantineAuthority(actorID: scope.actorID, organizationID: scope.organizationID, origin: scope.origin, policyVersion: 1, serverGeneration: "test", capabilities: ["customer.view"], features: ["core_crm": true], deadline: Date().addingTimeInterval(3600))
        let owner = CustomerGuardedReadOwner<Int>(quarantine: CustomerQuarantine(store: OwnerTransportStore()))
        let api = APIClient(session: URLProtocolFixture.session([.init(200, #"{"items":[]}"#), .init(200, #"{"items":[]}"#)]), baseURL: scope.origin)
        api.savedCopyScope = "guarded-owner-test-\(UUID())"
        try await owner.refresh(scope: scope, authority: authority, sessionID: UUID(), isCurrent: { true }) {
            XCTAssertTrue(SavedCopies.liveOnly, "The real API must receive the ticket's live-only policy")
            XCTAssertNotNil(SavedCopies.customerNamespace, "The real API must receive the ticket's scoped namespace")
            let page = try await api.fieldCustomerHistory(scope.customerID)
            // Synthetic evidence exercises the subsequent cache-eligible ticket;
            // it does not prove a complete customer compilation.
            return CustomerGuardedValue(value: page.items.count, evidence: .completeLive)
        }
        let request = try XCTUnwrap(URLProtocolFixture.recorded.first)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.header("Cache-Control"), "no-cache")
        try await SavedCopies.$liveOnly.withValue(true) {
            try await owner.refresh(scope: scope, authority: authority, sessionID: UUID(), isCurrent: { true }) {
                XCTAssertTrue(SavedCopies.liveOnly, "The owner must preserve an outer live-only requirement")
                let page = try await api.fieldCustomerHistory(scope.customerID)
                return CustomerGuardedValue(value: page.items.count, evidence: .limitedLive)
            }
        }
        let nested = try XCTUnwrap(URLProtocolFixture.recorded.last)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
        XCTAssertEqual(nested.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(nested.header("Cache-Control"), "no-cache")
    }
}
