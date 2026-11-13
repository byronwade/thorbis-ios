import XCTest
@testable import Thorbis

final class CustomerInvoiceSummaryContractTests: XCTestCase {
    private let scope = JobDocumentScope(jobID: "job-1", organizationID: "org-1", customerID: "customer-1")
    private func decode(_ changes: [String: Any] = [:]) throws -> CustomerInvoiceSummary {
        var payload: [String: Any] = [
            "kind": "customer_invoice_presentation", "presentationVersion": 1,
            "presentationScopeId": "invoice:invoice-1:lines:2:customer:v1", "isSignedDocument": false,
            "issuedSnapshotId": "00000000-0000-4000-8000-000000000001", "organizationId": "org-1", "customerId": "customer-1",
            "invoiceId": "invoice-1", "jobId": "job-1", "linesRevision": 2,
            "status": "issued", "currency": "USD", "totalAmount": 10000, "amountPaid": 2500,
            "balanceDue": 7500, "lines": [["id": "line-1", "description": "Materials", "quantity": 1,
                                              "unitPrice": ["amount": 10000, "currency": "USD"]]]
        ]
        changes.forEach { payload[$0.key] = $0.value }
        return try JSONDecoder().decode(CustomerInvoiceSummary.self, from: JSONSerialization.data(withJSONObject: payload))
    }
    func testAcceptsOnlyMatchingUnsignedScopedPresentationWithReconciledAmounts() throws {
        XCTAssertTrue(try decode().matches(scope: scope, invoiceID: "invoice-1", linesRevision: 2))
        for override in [["organizationId": "other"], ["customerId": "other"], ["jobId": "other"],
                         ["invoiceId": "other"], ["linesRevision": 3], ["presentationVersion": 2],
                         ["kind": "invoice"], ["isSignedDocument": true], ["issuedSnapshotId": NSNull()], ["issuedSnapshotId": "invalid"],
                         ["totalAmount": 1], ["balanceDue": 1], ["currency": "EUR"]] as [[String: Any]] {
            XCTAssertFalse(try decode(override).matches(scope: scope, invoiceID: "invoice-1", linesRevision: 2))
        }
        XCTAssertFalse(try decode(["status": "draft", "amountPaid": 0, "balanceDue": 10000]).matches(scope: scope, invoiceID: "invoice-1", linesRevision: 2))
        XCTAssertFalse(try decode(["status": "paid", "totalAmount": 0, "amountPaid": 0, "balanceDue": 0, "lines": []]).matches(scope: scope, invoiceID: "invoice-1", linesRevision: 2))
        XCTAssertFalse(try decode(["status": "issued", "amountPaid": 10000, "balanceDue": 0]).matches(scope: scope, invoiceID: "invoice-1", linesRevision: 2))
    }
}
