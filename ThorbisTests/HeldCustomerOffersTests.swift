import XCTest
@testable import Thorbis

final class HeldCustomerOffersTests: XCTestCase {
    private let offerID = "018f0000-aaaa-7000-8000-000000000011"
    private var hash: String { "sha256:" + String(repeating: "a", count: 64) }
    private var identity: String { "sha256:" + String(repeating: "b", count: 64) }

    private func offers(version: Int = 1, revision: Int = 1) throws -> CustomerAvailableOffers {
        try JSONDecoder().decode(CustomerAvailableOffers.self, from: Data("""
        {"contractVersion":\(version),"revisionNumber":\(revision),"contentHash":"\(hash)","currency":"USD","offers":[{"id":"\(offerID)","title":"Upgrade","description":"Extra","quantityPolicy":{"min":1,"max":3,"step":1},"totalAmount":500,"lines":[{"description":"Extra work","quantity":2,"unitPrice":250,"totalAmount":500}]}]}
        """.utf8))
    }
    private func quote(total: Int = 2000, expires: String = "2099-01-01T00:00:00.000Z", name: String = "Upgrade") throws -> CustomerOfferQuote {
        try JSONDecoder().decode(CustomerOfferQuote.self, from: Data("""
        {"contractVersion":1,"id":"018f0000-aaaa-7000-8000-000000000012","identity":"\(identity)","quoteIdentity":"\(identity)","expiresAt":"\(expires)","currency":"USD","totalAmount":\(total),"base":{"totalAmount":1000,"lines":[{"description":"Base","quantity":1,"unitPrice":1000,"totalAmount":1000}]},"addOns":[{"id":"\(offerID)","title":"\(name)","description":"Extra","quantity":2,"totalAmount":1000,"lines":[{"description":"Extra work","quantity":4,"unitPrice":250,"totalAmount":1000}]}]}
        """.utf8))
    }
    func testOfferAuthorityRetiresOnActorWorkspaceOriginSessionOrCapabilityChange() {
        let sessionID = UUID(), apiID = UUID()
        let scope = CustomerOfferAuthorityScope(actorID: "actor", organizationID: "org", sessionGeneration: sessionID,
            apiGeneration: apiID, origin: "https://example.test")
        func check(actor: String? = "actor", org: String? = "org", session: UUID? = nil, api: UUID? = nil,
                   origin: String? = "https://example.test", ready: Bool = true, view: Bool = true,
                   approve: Bool = true, job: Bool = true) -> Bool {
            scope.permits(actorID: actor, organizationID: org, sessionGeneration: session ?? sessionID, apiGeneration: api ?? apiID,
                origin: origin, sessionReady: ready, canViewEstimate: view, canApprove: approve, canViewJob: job)
        }
        XCTAssertTrue(check())
        XCTAssertFalse(check(actor: "other")); XCTAssertFalse(check(org: "other"))
        XCTAssertFalse(check(session: UUID())); XCTAssertFalse(check(api: UUID())); XCTAssertFalse(check(origin: "https://other.test"))
        XCTAssertFalse(check(ready: false)); XCTAssertFalse(check(view: false)); XCTAssertFalse(check(approve: false)); XCTAssertFalse(check(job: false))
    }
    func testUnselectedByDefaultAndChangingQuantityRetiresReviewedQuote() throws {
        var cart = CustomerOfferCart(revisionNumber: 1, contentHash: hash, optionID: nil)
        XCTAssertTrue(cart.install(try offers(), ticket: cart.ticket))
        XCTAssertTrue(cart.selections.isEmpty)
        XCTAssertFalse(cart.setQuantity(4, for: offerID))
        XCTAssertTrue(cart.setQuantity(2, for: offerID))
        let ticket = cart.ticket
        XCTAssertTrue(cart.install(try quote(), ticket: ticket, now: Date()))
        XCTAssertTrue(cart.quoteIsCurrent(now: Date()))
        XCTAssertEqual(customerEstimatePresentedTotal(base: 1000, review: CustomerOfferReview(quote: try quote(), selections: cart.selections, token: "token", revisionNumber: 1, contentHash: hash, optionID: nil, generation: UUID())), 2000)
        XCTAssertEqual(customerEstimatePresentedTotal(base: 1000, review: nil), 1000)
        XCTAssertFalse(cart.quoteIsCurrent(now: Date(timeIntervalSince1970: 4_200_000_000)))
        XCTAssertTrue(cart.setQuantity(3, for: offerID))
        XCTAssertNil(cart.quote)
        XCTAssertFalse(cart.install(try quote(), ticket: ticket, now: Date()))
        XCTAssertFalse(cart.install(try quote(), ticket: cart.ticket, now: Date()))
    }
    func testAcceptanceMustMatchTheQuoteChoiceSignerAndTotal() throws {
        let generation = UUID()
        let selection = CustomerOfferSelection(offerId: offerID, quantity: 2)
        let reviewed = CustomerOfferReview(quote: try quote(), selections: [selection], token: "token", revisionNumber: 1,
            contentHash: hash, optionID: nil, generation: generation)
        func receipt(_ amount: Int, _ signer: String, _ quantity: Int) throws -> PublicEstimateAction.Acceptance {
            try JSONDecoder().decode(PublicEstimateAction.Acceptance.self, from: Data("""
            {"id":"018f0000-aaaa-7000-8000-000000000013","signerName":"\(signer)","acceptedAt":"2026-11-03T12:00:00Z","totalAmount":\(amount),"offerQuoteId":"018f0000-aaaa-7000-8000-000000000012","quoteIdentity":"\(identity)","selections":[{"offerId":"\(offerID)","quantity":\(quantity)}]}
            """.utf8))
        }
        let afterExpiry = Date(timeIntervalSince1970: 4_200_000_000)
        XCTAssertFalse(customerOfferDecisionCanSubmit(reviewed, now: afterExpiry, hasExactPriorAttempt: false))
        XCTAssertTrue(customerOfferDecisionCanSubmit(reviewed, now: afterExpiry, hasExactPriorAttempt: true))
        XCTAssertTrue(reviewed.matchesAcceptance(try receipt(2000, "Customer", 2), signerName: "Customer"))
        XCTAssertFalse(reviewed.matchesAcceptance(try receipt(1999, "Customer", 2), signerName: "Customer"))
        XCTAssertFalse(reviewed.matchesAcceptance(try receipt(2000, "Other", 2), signerName: "Customer"))
        XCTAssertFalse(reviewed.matchesAcceptance(try receipt(2000, "Customer", 1), signerName: "Customer"))
        XCTAssertFalse(reviewed.matchesAcceptance(nil, signerName: "Customer"))
        XCTAssertFalse(reviewed.matches(token: "token", revisionNumber: 1, contentHash: "different", optionID: nil, generation: generation))
        XCTAssertFalse(reviewed.matches(token: "token", revisionNumber: 1, contentHash: hash, optionID: offerID, generation: generation))
        XCTAssertFalse(reviewed.matches(token: "different", revisionNumber: 1, contentHash: hash, optionID: nil, generation: generation))
        XCTAssertFalse(reviewed.matches(token: "token", revisionNumber: 1, contentHash: hash, optionID: nil, generation: UUID()))
    }
    func testUnsupportedScopeTamperedTotalsAndExpiredQuoteFailClosed() throws {
        var cart = CustomerOfferCart(revisionNumber: 1, contentHash: hash, optionID: nil)
        XCTAssertFalse(cart.install(try offers(version: 2), ticket: cart.ticket))
        XCTAssertFalse(cart.install(try offers(revision: 2), ticket: cart.ticket))
        XCTAssertTrue(cart.install(try offers(), ticket: cart.ticket))
        XCTAssertTrue(cart.setQuantity(2, for: offerID))
        XCTAssertFalse(cart.install(try quote(total: 1999), ticket: cart.ticket, now: Date()))
        XCTAssertFalse(cart.install(try quote(name: "Changed"), ticket: cart.ticket, now: Date()))
        XCTAssertFalse(cart.install(try quote(expires: "2000-01-01T00:00:00.000Z"), ticket: cart.ticket, now: Date()))
        cart.retire()
        XCTAssertTrue(cart.offers.isEmpty)
        XCTAssertTrue(cart.selections.isEmpty)
        XCTAssertNil(cart.quote)
    }
}
