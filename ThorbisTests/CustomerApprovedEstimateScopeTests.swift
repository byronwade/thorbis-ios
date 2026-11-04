import XCTest
@testable import Thorbis

@MainActor
final class CustomerApprovedEstimateScopeTests: XCTestCase {
    func testApprovedScopeRejectsWrongRevisionAndTenant() throws {
        let record = try decode(EstimateRecord.self, #"{"id":"00000000-0000-4000-8000-000000000101","organizationId":"00000000-0000-4000-8000-000000000102","customerId":"00000000-0000-4000-8000-000000000103","createdByUserId":"00000000-0000-4000-8000-000000000104","status":"approved","currentRevisionNumber":2,"title":"Repair","lines":[],"createdAt":"2026-11-04T00:00:00Z","updatedAt":"2026-11-04T00:00:00Z"}"#)
        let scope = try decode(CustomerApprovedEstimateScope.self, #"{"estimateId":"00000000-0000-4000-8000-000000000101","organizationId":"00000000-0000-4000-8000-000000000102","customerId":"00000000-0000-4000-8000-000000000103","revisionId":"00000000-0000-4000-8000-000000000105","revisionNumber":2,"title":"Repair","currency":"USD","totalAmount":1000,"lines":[{"id":"00000000-0000-4000-8000-000000000106","description":"Materials","quantity":1,"unitPrice":{"amount":1000,"currency":"USD"}}]}"#)
        XCTAssertTrue(scope.matches(record))
        let newerJSON = #"{"id":"00000000-0000-4000-8000-000000000101","organizationId":"00000000-0000-4000-8000-000000000102","customerId":"00000000-0000-4000-8000-000000000103","createdByUserId":"00000000-0000-4000-8000-000000000104","status":"approved","currentRevisionNumber":3,"title":"Repair","lines":[],"createdAt":"2026-11-04T00:00:00Z","updatedAt":"2026-11-04T00:00:00Z"}"#
        XCTAssertFalse(scope.matches(try decode(EstimateRecord.self, newerJSON)))
    }
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
}
