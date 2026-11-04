import Foundation

@main struct TestCart {
  static func main() throws {
    let session = UUID(), api = UUID()
    let authority = CustomerOfferAuthorityScope(actorID: "actor", organizationID: "org", sessionGeneration: session, apiGeneration: api, origin: "https://example.test")
    func allowed(actor: String? = "actor", organization: String? = "org", sessionID: UUID? = nil, apiID: UUID? = nil,
                 origin: String? = "https://example.test", view: Bool = true, approve: Bool = true, job: Bool = true) -> Bool {
      authority.permits(actorID: actor, organizationID: organization, sessionGeneration: sessionID ?? session, apiGeneration: apiID ?? api,
        origin: origin, sessionReady: true, canViewEstimate: view, canApprove: approve, canViewJob: job)
    }
    precondition(allowed() && !allowed(actor: "other") && !allowed(organization: "other"))
    precondition(!allowed(sessionID: UUID()) && !allowed(apiID: UUID()) && !allowed(origin: "https://other.test"))
    precondition(!allowed(view: false) && !allowed(approve: false) && !allowed(job: false))
    let inputs = [CustomerSelectedAmount(currency: "USD", base: 900, quoteCurrency: "USD", quoteAmount: 1400, quoteUsable: true),
      CustomerSelectedAmount(currency: "USD", base: 300, quoteCurrency: nil, quoteAmount: nil, quoteUsable: true),
      CustomerSelectedAmount(currency: "CAD", base: 200, quoteCurrency: nil, quoteAmount: nil, quoteUsable: true)]
    let totals = customerSelectedTotals(inputs)!
    precondition(totals.count == 2 && totals[0].currency == "CAD" && totals[0].amount == 200 && totals[1].amount == 1700)
    precondition(customerSelectedTotals([.init(currency: "USD", base: 900, quoteCurrency: "USD", quoteAmount: 1400, quoteUsable: false)]) == nil)
    precondition(customerSelectedTotals([.init(currency: "USD", base: 900, quoteCurrency: "CAD", quoteAmount: 1400, quoteUsable: true)]) == nil)
    precondition(customerSelectedTotals([.init(currency: "USD", base: Int.max, quoteCurrency: nil, quoteAmount: nil, quoteUsable: true),
      .init(currency: "USD", base: 1, quoteCurrency: nil, quoteAmount: nil, quoteUsable: true)]) == nil)
    let offer = "018f0000-aaaa-7000-8000-000000000011"
    let hash = "sha256:" + String(repeating: "a", count: 64)
    let data = """
    {"contractVersion":1,"revisionNumber":1,"contentHash":"\(hash)","currency":"USD","offers":[{"id":"\(offer)","title":"Upgrade","description":"Extra","quantityPolicy":{"min":1,"max":3,"step":1},"totalAmount":500,"lines":[{"description":"Extra work","quantity":2,"unitPrice":250,"totalAmount":500}]}]}
    """.data(using: .utf8)!
    let available = try JSONDecoder().decode(CustomerAvailableOffers.self, from: data)
    var cart = CustomerOfferCart(revisionNumber: 1, contentHash: hash, optionID: nil)
    precondition(cart.install(available, ticket: cart.ticket))
    precondition(!cart.setQuantity(4, for: offer))
    precondition(cart.setQuantity(2, for: offer))
    let captured = cart.ticket
    let identity = "sha256:" + String(repeating: "b", count: 64)
    let quoteData = """
    {"contractVersion":1,"id":"018f0000-aaaa-7000-8000-000000000012","identity":"\(identity)","quoteIdentity":"\(identity)","expiresAt":"2099-01-01T00:00:00.000Z","currency":"USD","totalAmount":2000,"base":{"totalAmount":1000,"lines":[{"description":"Base","quantity":1,"unitPrice":1000,"totalAmount":1000}]},"addOns":[{"id":"\(offer)","title":"Upgrade","description":"Extra","quantity":2,"totalAmount":1000,"lines":[{"description":"Extra work","quantity":4,"unitPrice":250,"totalAmount":1000}]}]}
    """.data(using: .utf8)!
    let quote = try JSONDecoder().decode(CustomerOfferQuote.self, from: quoteData)
    let emptyQuoteData = String(data: quoteData, encoding: .utf8)!
      .replacingOccurrences(of: "\"totalAmount\":2000,\"base\":{\"totalAmount\":1000", with: "\"totalAmount\":1000,\"base\":{\"totalAmount\":0")
      .replacingOccurrences(of: "\"lines\":[{\"description\":\"Base\",\"quantity\":1,\"unitPrice\":1000,\"totalAmount\":1000}]", with: "\"lines\":[]")
    let incomplete = try JSONDecoder().decode(CustomerOfferQuote.self, from: Data(emptyQuoteData.utf8))
    precondition(!cart.install(incomplete, ticket: captured, now: Date()))
    let generation = UUID()
    let reviewed = CustomerOfferReview(quote: quote, selections: cart.selections, token: "token", revisionNumber: 1, contentHash: hash, optionID: nil, generation: generation)
    let afterExpiry = Date(timeIntervalSince1970: 4_200_000_000)
    precondition(!customerOfferDecisionCanSubmit(reviewed, now: afterExpiry, hasExactPriorAttempt: false))
    precondition(customerOfferDecisionCanSubmit(reviewed, now: afterExpiry, hasExactPriorAttempt: true))
    precondition(reviewed.matches(token: "token", revisionNumber: 1, contentHash: hash, optionID: nil, generation: generation))
    precondition(!reviewed.matches(token: "different", revisionNumber: 1, contentHash: hash, optionID: nil, generation: generation))
    precondition(!reviewed.matches(token: "token", revisionNumber: 2, contentHash: hash, optionID: nil, generation: generation))
    precondition(!reviewed.matches(token: "token", revisionNumber: 1, contentHash: hash, optionID: nil, generation: UUID()))
    let discountedData = String(data: quoteData, encoding: .utf8)!
      .replacingOccurrences(of: "\"totalAmount\":2000,\"base\":{\"totalAmount\":1000", with: "\"totalAmount\":1900,\"base\":{\"totalAmount\":900")
      .replacingOccurrences(of: "\"description\":\"Base\",\"quantity\":1,\"unitPrice\":1000,\"totalAmount\":1000}", with: "\"description\":\"Base\",\"quantity\":1,\"unitPrice\":1000,\"totalAmount\":1000},{\"description\":\"Discount\",\"quantity\":1,\"unitPrice\":-100,\"totalAmount\":-100}")
    let discounted = try JSONDecoder().decode(CustomerOfferQuote.self, from: Data(discountedData.utf8))
    var discountCart = cart
    precondition(discountCart.install(discounted, ticket: captured, now: Date()))
    precondition(discountCart.quote?.totalAmount == 1900)
    precondition(cart.install(quote, ticket: captured, now: Date()))
    precondition(customerEstimatePresentedTotal(base: 1000, review: CustomerOfferReview(quote: quote, selections: cart.selections, token: "token", revisionNumber: 1, contentHash: hash, optionID: nil, generation: UUID())) == 2000)
    precondition(customerEstimatePresentedTotal(base: 1000, review: nil) == 1000)
    precondition(cart.setQuantity(3, for: offer) && cart.quote == nil)
    precondition(!cart.install(quote, ticket: captured, now: Date()))
    precondition(!cart.install(quote, ticket: cart.ticket, now: Date()))
    cart.retire()
    precondition(cart.offers.isEmpty && cart.selections.isEmpty)
    print("held customer cart state checks passed")
  }
}
