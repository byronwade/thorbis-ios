import Foundation

/// Frozen commercial facts from the revision endpoint, distinct from the live aggregate.
struct CustomerIssuedEstimateRevision: Decodable, Equatable {
    let id: String
    let estimateId: String
    let organizationId: String
    let customerId: String
    let locationId: String?
    let revisionNumber: Int
    let status: String
    let title: String
    let lines: [FieldLine]
    let options: [FieldEstimateOption]?
    let totalAmount: Int
    let currency: String

    fileprivate func validate(for expected: EstimateRecord) throws {
        guard UUID(uuidString: id) != nil,
              estimateId == expected.id, organizationId == expected.organizationId,
              customerId == expected.customerId, locationId == expected.locationId,
              revisionNumber == expected.currentRevisionNumber, status == "issued"
        else { throw customerReviewUnavailable() }
    }

    fileprivate func validate(action: PublicEstimateAction, paperHash: String) throws {
        guard action.kind == "estimate", action.signingOffered,
              action.contentHash == paperHash, paperHash.count >= 15,
              action.revisionNumber == revisionNumber, action.title == title,
              action.currency == currency, Int(exactly: action.totalAmount) == totalAmount,
              action.nonce?.isEmpty == false,
              action.consentText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              action.consentVersion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else { throw customerReviewUnavailable() }

        let offered = action.options ?? []
        let reviewed = options ?? []
        guard offered.count == reviewed.count,
              Set(reviewed.map(\.id)).count == reviewed.count,
              zip(offered, reviewed).allSatisfy({ actual, expected in
                  actual.id == expected.id && actual.title == expected.title
                      && actual.description == expected.description && actual.currency == expected.currency
                      && Int(exactly: actual.totalAmount) == expected.totalAmount
              })
        else { throw customerReviewUnavailable() }

        if reviewed.isEmpty {
            guard let scope = action.scopeLines, scope.count == lines.count,
                  zip(scope, lines).allSatisfy({ actual, expected in
                      actual.id == expected.id && actual.description == expected.description
                          && Int(exactly: actual.quantity) == expected.quantity
                          && Int(exactly: actual.unitPrice) == expected.unitPrice.amount
                          && expected.unitPrice.currency == currency
                  })
            else { throw customerReviewUnavailable() }
        }
    }
}

private func customerReviewUnavailable() -> Problem {
    Problem(title: "This estimate changed or can't be signed here.", status: 409,
            detail: "Ask your technician to reopen the current estimate.")
}

private struct CustomerReviewPaper: Decodable {
    struct Source: Decodable { let type: String; let id: String }
    struct Snapshot: Decodable {
        struct Content: Decodable {
            struct Revision: Decodable { let number: Int }
            let revision: Revision
        }
        let content: Content
    }
    let source: Source
    let contentHash: String
    let snapshot: Snapshot
}

@MainActor
extension APIClient {
    func customerIssuedEstimateRevision(for expected: EstimateRecord) async throws -> CustomerIssuedEstimateRevision {
        let generation = requestGeneration
        try checkCustomerReviewRequest(generation)
        guard let number = expected.currentRevisionNumber, number > 0 else { throw customerReviewUnavailable() }
        let current = try await fieldEstimate(expected.id)
        try checkCustomerReviewRequest(generation)
        guard current.id == expected.id, current.organizationId == expected.organizationId,
              current.customerId == expected.customerId, current.locationId == expected.locationId,
              current.status == "sent", current.currentRevisionNumber == number
        else { throw customerReviewUnavailable() }

        let path = try financialPath("/v1/estimates", id: expected.id, suffix: "/revisions/\(number)")
        let revision: CustomerIssuedEstimateRevision = try await send("GET", path)
        try checkCustomerReviewRequest(generation)
        try revision.validate(for: expected)
        return revision
    }

    /// The customer reviewed this immutable revision before this paper/token chain begins.
    func openInPersonEstimateApproval(_ revision: CustomerIssuedEstimateRevision) async throws -> (token: String, action: PublicEstimateAction) {
        struct Empty: Encodable {}
        struct Mint: Encodable { let revisionNumber: Int; let contentHash: String }
        struct Link: Decodable { let token: String }
        let generation = requestGeneration
        try checkCustomerReviewRequest(generation)
        guard revision.status == "issued" else { throw customerReviewUnavailable() }
        let paper: CustomerReviewPaper = try await send("POST", financialPath("/v1/estimates", id: revision.estimateId, suffix: "/commercial-documents"), body: Empty())
        try checkCustomerReviewRequest(generation)
        guard paper.source.type == "estimate", paper.source.id == revision.estimateId,
              paper.snapshot.content.revision.number == revision.revisionNumber,
              paper.contentHash.count >= 15
        else { throw customerReviewUnavailable() }

        let link: Link = try await send("POST", financialPath("/v1/estimates", id: revision.estimateId, suffix: "/action-tokens"),
                                        body: Mint(revisionNumber: revision.revisionNumber, contentHash: paper.contentHash))
        try checkCustomerReviewRequest(generation)
        let action = try await publicDocumentAction(token: link.token)
        try checkCustomerReviewRequest(generation)
        try revision.validate(action: action, paperHash: paper.contentHash)
        return (link.token, action)
    }

    private func checkCustomerReviewRequest(_ generation: UUID) throws {
        try Task.checkCancellation()
        guard generation == requestGeneration else { throw CancellationError() }
    }
}
