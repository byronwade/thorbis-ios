import Foundation

/// Held until the server's offer issuance, authorization and billing rollout is qualified.
enum CustomerOfferCapability {
    static let isEnabled = false
}

struct CustomerOfferAuthorityScope: Equatable {
    let actorID: String
    let organizationID: String
    let sessionGeneration: UUID
    let apiGeneration: UUID
    let origin: String

    func permits(actorID: String?, organizationID: String?, sessionGeneration: UUID, apiGeneration: UUID,
                 origin: String?, sessionReady: Bool, canViewEstimate: Bool, canApprove: Bool, canViewJob: Bool) -> Bool {
        !self.actorID.isEmpty && !self.organizationID.isEmpty && !self.origin.isEmpty && sessionReady &&
        self.actorID == actorID && self.organizationID == organizationID && self.sessionGeneration == sessionGeneration &&
        self.apiGeneration == apiGeneration && self.origin == origin && canViewEstimate && canApprove && canViewJob
    }
}

struct CustomerOfferSelection: Codable, Equatable, Hashable {
    let offerId: String
    let quantity: Int
}

struct CustomerOfferLine: Decodable, Equatable {
    let description: String
    let quantity: Int
    let unitPrice: Int
    let totalAmount: Int
}

struct CustomerAvailableOffer: Decodable, Equatable, Identifiable {
    struct QuantityPolicy: Decodable, Equatable {
        let min: Int
        let max: Int
        let step: Int

        func contains(_ quantity: Int) -> Bool {
            min > 0 && max >= min && step > 0 && quantity >= min && quantity <= max && (quantity - min) % step == 0
        }
    }
    let id: String
    let title: String
    let description: String
    let quantityPolicy: QuantityPolicy
    /// Server amount for the minimum offered quantity, in minor units.
    let totalAmount: Int
    let lines: [CustomerOfferLine]
}

struct CustomerAvailableOffers: Decodable, Equatable {
    let contractVersion: Int
    let revisionNumber: Int
    let contentHash: String
    let currency: String
    let optionId: String?
    let offers: [CustomerAvailableOffer]
}

struct CustomerOfferQuote: Decodable, Equatable {
    struct Base: Decodable, Equatable {
        let id: String?
        let title: String?
        let description: String?
        let totalAmount: Int
        let lines: [CustomerOfferLine]
    }
    struct AddOn: Decodable, Equatable {
        let id: String
        let title: String
        let description: String
        let quantity: Int
        let totalAmount: Int
        let lines: [CustomerOfferLine]
    }
    let contractVersion: Int
    let id: String
    let quoteIdentity: String
    let identity: String
    let expiresAt: String
    let currency: String
    let totalAmount: Int
    let base: Base
    let addOns: [AddOn]
}

struct CustomerOfferReview: Equatable {
    let quote: CustomerOfferQuote
    let selections: [CustomerOfferSelection]
    let token: String
    let revisionNumber: Int
    let contentHash: String
    let optionID: String?
    let generation: UUID

    func matches(token: String, revisionNumber: Int, contentHash: String, optionID: String?, generation: UUID) -> Bool {
        self.token == token && self.revisionNumber == revisionNumber && self.contentHash == contentHash &&
        self.optionID?.lowercased() == optionID?.lowercased() && self.generation == generation
    }
    func isCurrent(now: Date) -> Bool {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fractional.date(from: quote.expiresAt) ?? ISO8601DateFormatter().date(from: quote.expiresAt) else { return false }
        return date > now
    }
}

/// The server permits an identical already-submitted decision to replay after quote expiry.
func customerOfferDecisionCanSubmit(_ review: CustomerOfferReview, now: Date, hasExactPriorAttempt: Bool) -> Bool {
    hasExactPriorAttempt || review.isCurrent(now: now)
}

enum CustomerOfferReviewState: Equatable { case none, current, expired, changed, approved }

func customerOfferReviewState(_ review: CustomerOfferReview?, matchesScope: Bool, confirmed: Bool, now: Date) -> CustomerOfferReviewState {
    guard let review else { return .none }
    guard matchesScope else { return .changed }
    if confirmed { return .approved }
    return review.isCurrent(now: now) ? .current : .expired
}

struct CustomerSelectedAmount: Equatable {
    let currency: String
    let base: Int
    let quoteCurrency: String?
    let quoteAmount: Int?
    let quoteUsable: Bool
}

/// Nil means totals are unavailable; never substitute a base for an unusable quote.
func customerSelectedTotals(_ amounts: [CustomerSelectedAmount]) -> [(currency: String, amount: Int)]? {
    var totals: [String: Int] = [:]
    for amount in amounts {
        guard !amount.currency.isEmpty, amount.base >= 0 else { return nil }
        let value: Int
        if let quoteAmount = amount.quoteAmount {
            guard amount.quoteUsable, amount.quoteCurrency == amount.currency, quoteAmount >= 0 else { return nil }
            value = quoteAmount
        } else {
            guard amount.quoteCurrency == nil else { return nil }
            value = amount.base
        }
        let result = (totals[amount.currency] ?? 0).addingReportingOverflow(value)
        guard !result.overflow else { return nil }
        totals[amount.currency] = result.partialValue
    }
    return totals.sorted { $0.key < $1.key }.map { (currency: $0.key, amount: $0.value) }
}

func customerEstimatePresentedTotal(base: Int?, review: CustomerOfferReview?) -> Int? {
    review?.quote.totalAmount ?? base
}

/// A request ticket is retired on every changed selection or document scope.
struct CustomerOfferCart: Equatable {
    let revisionNumber: Int
    let contentHash: String
    let optionID: String?
    private(set) var offers: [CustomerAvailableOffer] = []
    private(set) var selections: [CustomerOfferSelection] = []
    private(set) var quote: CustomerOfferQuote?
    private(set) var ticket = UUID()

    mutating func install(_ result: CustomerAvailableOffers, ticket captured: UUID) -> Bool {
        guard captured == ticket, result.contractVersion == 1, result.revisionNumber == revisionNumber,
              result.contentHash == contentHash, result.currency == "USD",
              result.optionId?.lowercased() == optionID?.lowercased(), result.offers.count <= 50,
              Set(result.offers.map { $0.id.lowercased() }).count == result.offers.count,
              result.offers.allSatisfy({ UUID(uuidString: $0.id) != nil && !$0.title.isEmpty &&
                  $0.quantityPolicy.contains($0.quantityPolicy.min) && $0.totalAmount >= 0 && Self.validLines($0.lines, total: $0.totalAmount) })
        else { return false }
        if offers != result.offers {
            selections = []
            quote = nil
            ticket = UUID()
        }
        offers = result.offers
        return true
    }

    @discardableResult mutating func setQuantity(_ quantity: Int?, for id: String) -> Bool {
        guard let offer = offers.first(where: { $0.id.lowercased() == id.lowercased() }),
              quantity.map({ offer.quantityPolicy.contains($0) }) ?? true else { return false }
        let previous = selections.first { $0.offerId.lowercased() == id.lowercased() }?.quantity
        guard previous != quantity else { return true }
        selections.removeAll { $0.offerId.lowercased() == id.lowercased() }
        if let quantity { selections.append(.init(offerId: offer.id.lowercased(), quantity: quantity)) }
        selections.sort { $0.offerId < $1.offerId }
        quote = nil
        ticket = UUID()
        return true
    }

    mutating func install(_ result: CustomerOfferQuote, ticket captured: UUID, now: Date) -> Bool {
        guard captured == ticket, result.contractVersion == 1, UUID(uuidString: result.id) != nil, result.currency == "USD",
              result.identity == result.quoteIdentity, result.identity.range(of: "^sha256:[0-9a-f]{64}$", options: .regularExpression) != nil,
              let expiry = Self.expiryDate(result.expiresAt), expiry > now,
              result.base.id?.lowercased() == optionID?.lowercased(),
              Self.validLines(result.base.lines, total: result.base.totalAmount),
              result.addOns.count == selections.count,
              Set(result.addOns.map { $0.id.lowercased() }).count == result.addOns.count,
              result.addOns.allSatisfy({ item in
                  selections.contains { $0.offerId == item.id.lowercased() && $0.quantity == item.quantity } &&
                  offers.contains { $0.id.lowercased() == item.id.lowercased() && $0.title == item.title && $0.description == item.description } &&
                  Self.validLines(item.lines, total: item.totalAmount)
              }) else { return false }
        var total = result.base.totalAmount
        for item in result.addOns {
            let next = total.addingReportingOverflow(item.totalAmount)
            guard !next.overflow else { return false }
            total = next.partialValue
        }
        guard total == result.totalAmount, total >= 0 else { return false }
        quote = result
        return true
    }

    func quoteIsCurrent(now: Date) -> Bool {
        guard let quote, let expiry = Self.expiryDate(quote.expiresAt) else { return false }
        return expiry > now
    }

    mutating func invalidateQuote() { quote = nil; ticket = UUID() }
    mutating func retire() { quote = nil; offers = []; selections = []; ticket = UUID() }

    private static func expiryDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func validLines(_ lines: [CustomerOfferLine], total: Int) -> Bool {
        guard !lines.isEmpty else { return false }
        var sum = 0
        for line in lines {
            guard line.quantity > 0 else { return false }
            let product = line.unitPrice.multipliedReportingOverflow(by: line.quantity)
            guard !product.overflow, product.partialValue == line.totalAmount else { return false }
            let next = sum.addingReportingOverflow(line.totalAmount)
            guard !next.overflow else { return false }
            sum = next.partialValue
        }
        return sum == total
    }
}
