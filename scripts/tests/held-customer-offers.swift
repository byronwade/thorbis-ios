import Foundation

@main struct TestCart {
  static func main() throws {
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
    {"id":"018f0000-aaaa-7000-8000-000000000012","identity":"\(identity)","quoteIdentity":"\(identity)","expiresAt":"2099-01-01T00:00:00.000Z","currency":"USD","totalAmount":2000,"base":{"totalAmount":1000,"lines":[{"description":"Base","quantity":1,"unitPrice":1000,"totalAmount":1000}]},"addOns":[{"id":"\(offer)","title":"Upgrade","description":"Extra","quantity":2,"totalAmount":1000,"lines":[{"description":"Extra work","quantity":4,"unitPrice":250,"totalAmount":1000}]}]}
    """.data(using: .utf8)!
    let quote = try JSONDecoder().decode(CustomerOfferQuote.self, from: quoteData)
    precondition(cart.install(quote, ticket: captured, now: Date()))
    precondition(cart.setQuantity(3, for: offer) && cart.quote == nil)
    precondition(!cart.install(quote, ticket: captured, now: Date()))
    precondition(!cart.install(quote, ticket: cart.ticket, now: Date()))
    cart.retire()
    precondition(cart.offers.isEmpty && cart.selections.isEmpty)
    print("held customer cart state checks passed")
  }
}
