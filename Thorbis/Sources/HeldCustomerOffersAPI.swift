import Foundation

private struct CustomerOfferDiscoveryRequest: Encodable {
    let revisionNumber: Int
    let optionId: String?
}
private struct CustomerOfferQuoteRequest: Encodable {
    let revisionNumber: Int
    let optionId: String?
    let selections: [CustomerOfferSelection]
}

@MainActor
extension APIClient {
    func heldAvailableOffers(token: String, revisionNumber: Int, optionID: String?, currentAuthority: @escaping @MainActor () -> Bool) async throws -> CustomerAvailableOffers {
        let generation = requestGeneration
        try Task.checkCancellation()
        guard currentAuthority() else { throw CancellationError() }
        let result: CustomerAvailableOffers = try await sendPublic("POST", PublicEstimateActionLink.apiPath(token: token, action: "available-offers"),
            body: CustomerOfferDiscoveryRequest(revisionNumber: revisionNumber, optionId: optionID))
        try Task.checkCancellation()
        guard generation == requestGeneration, currentAuthority() else { throw CancellationError() }
        return result
    }

    func heldOfferQuote(token: String, revisionNumber: Int, optionID: String?, selections: [CustomerOfferSelection], currentAuthority: @escaping @MainActor () -> Bool) async throws -> CustomerOfferQuote {
        let generation = requestGeneration
        try Task.checkCancellation()
        guard currentAuthority() else { throw CancellationError() }
        let result: CustomerOfferQuote = try await sendPublic("POST", PublicEstimateActionLink.apiPath(token: token, action: "offer-quotes"),
            body: CustomerOfferQuoteRequest(revisionNumber: revisionNumber, optionId: optionID, selections: selections))
        try Task.checkCancellation()
        guard generation == requestGeneration, currentAuthority() else { throw CancellationError() }
        return result
    }
}
