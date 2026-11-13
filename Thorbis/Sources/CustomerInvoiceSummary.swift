import Foundation

/// A server-produced customer presentation. It is not a signed invoice.
struct CustomerInvoiceSummary: Decodable, Sendable {
    struct Line: Decodable, Sendable {
        let id: String
        let description: String
        let quantity: Int
        let unitPrice: FieldMoney
    }

    let kind: String
    let presentationVersion: Int
    let presentationScopeId: String
    let isSignedDocument: Bool
    let issuedSnapshotId: String?
    let organizationId: String
    let customerId: String
    let invoiceId: String
    let jobId: String?
    let linesRevision: Int
    let status: String
    let currency: String
    let lines: [Line]
    let totalAmount: Int
    let amountPaid: Int
    let balanceDue: Int

    /// Identity and arithmetic only. The caller must also prove current session,
    /// permission, request generation and a fresh server response before display.
    func matches(scope: JobDocumentScope, invoiceID: String, linesRevision expectedRevision: Int) -> Bool {
        guard kind == "customer_invoice_presentation", presentationVersion == 1, !isSignedDocument,
              organizationId == scope.organizationID, customerId == scope.customerID,
              jobId == scope.jobID, invoiceId == invoiceID, linesRevision == expectedRevision,
              expectedRevision > 0,
              presentationScopeId == "invoice:\(invoiceID):lines:\(expectedRevision):customer:v1",
              currency == "USD", ["draft", "issued", "paid", "void"].contains(status),
              lines.count <= 500, totalAmount >= 0, amountPaid >= 0, amountPaid <= totalAmount,
              (status == "draft" ? issuedSnapshotId == nil : issuedSnapshotId.flatMap(UUID.init(uuidString:)) != nil) else { return false }
        var total = 0
        var ids = Set<String>()
        for line in lines {
            guard !line.id.isEmpty, ids.insert(line.id).inserted, line.quantity > 0,
                  line.unitPrice.currency == currency else { return false }
            let (extended, overflow) = line.unitPrice.amount.multipliedReportingOverflow(by: line.quantity)
            guard !overflow else { return false }
            let (next, sumOverflow) = total.addingReportingOverflow(extended)
            guard !sumOverflow else { return false }
            total = next
        }
        guard total == totalAmount else { return false }
        if status == "draft" && amountPaid != 0 { return false }
        let expectedDue = status == "void" ? 0 : totalAmount - amountPaid
        let fullyPaid = totalAmount > 0 && amountPaid == totalAmount
        guard status != "paid" || fullyPaid, status != "issued" || !fullyPaid else { return false }
        return balanceDue == expectedDue
    }
}

@MainActor
extension APIClient {
    /// Fetches the server's separate customer view, never a saved invoice copy.
    func customerInvoiceSummary(scope: JobDocumentScope, invoiceID: String, linesRevision: Int,
                                currentAuthority: @escaping @MainActor () -> Bool) async throws -> CustomerInvoiceSummary {
        let generation = requestGeneration
        let savedScope = savedCopyScopeRevision
        let origin = normalizedOrigin
        func check() throws {
            try Task.checkCancellation()
            guard generation == requestGeneration, savedScope == savedCopyScopeRevision,
                  origin != nil, origin == normalizedOrigin, currentAuthority() else { throw CancellationError() }
        }
        try check()
        let path = try financialPath("/v1/invoices", id: invoiceID, suffix: "/customer-presentation")
        let summary: CustomerInvoiceSummary = try await send("GET", path, requireFresh: true)
        try check()
        guard summary.matches(scope: scope, invoiceID: invoiceID, linesRevision: linesRevision) else {
            throw Problem(title: "This invoice summary couldn't be verified", status: 409,
                          detail: "Ask your technician to refresh the invoice.")
        }
        return summary
    }
}
