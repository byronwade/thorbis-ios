import Foundation

/// Public estimate amounts are USD cents. Validate JSON as Decimal before converting
/// to Double so an invalid fractional wire value cannot round into an integer.
private func checkedPublicEstimateInteger(_ value: Decimal, range: ClosedRange<Decimal>, codingPath: [CodingKey]) throws -> Double {
    var original = value
    var rounded = Decimal()
    NSDecimalRound(&rounded, &original, 0, .plain)
    guard rounded == value, range.contains(value) else {
        throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Invalid public estimate amount or quantity"))
    }
    return NSDecimalNumber(decimal: value).doubleValue
}

@propertyWrapper
struct PublicEstimateAmount: Decodable, Equatable {
    var wrappedValue: Double
    init(wrappedValue: Double) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(Decimal.self)
        wrappedValue = try checkedPublicEstimateInteger(value, range: 0...9_007_199_254_740_991, codingPath: decoder.codingPath)
    }
}
@propertyWrapper
struct PublicEstimateSignedAmount: Decodable, Equatable {
    var wrappedValue: Double
    init(wrappedValue: Double) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(Decimal.self)
        wrappedValue = try checkedPublicEstimateInteger(value, range: -9_007_199_254_740_991...9_007_199_254_740_991, codingPath: decoder.codingPath)
    }
}
@propertyWrapper
struct PublicEstimateQuantity: Decodable, Equatable {
    var wrappedValue: Double
    init(wrappedValue: Double) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(Decimal.self)
        wrappedValue = try checkedPublicEstimateInteger(value, range: 1...100_000, codingPath: decoder.codingPath)
    }
}
@propertyWrapper
struct OptionalPublicEstimateAmount: Decodable {
    var wrappedValue: Double?
    init(wrappedValue: Double?) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { wrappedValue = nil; return }
        wrappedValue = try checkedPublicEstimateInteger(container.decode(Decimal.self), range: 0...9_007_199_254_740_991, codingPath: decoder.codingPath)
    }
}
extension KeyedDecodingContainer {
    func decode(_ type: OptionalPublicEstimateAmount.Type, forKey key: Key) throws -> OptionalPublicEstimateAmount {
        try decodeIfPresent(type, forKey: key) ?? OptionalPublicEstimateAmount(wrappedValue: nil)
    }
}

enum PublicEstimateMoney {
    static let maximum = 9_007_199_254_740_991
    static func validated(_ value: Double) -> Int? {
        guard value.isFinite, let integer = Int(exactly: value), integer >= -maximum, integer <= maximum else { return nil }
        return integer
    }
    static func lineTotal(quantity: Double, unitPrice: Double) -> Int? {
        guard let count = Int(exactly: quantity), (1...100_000).contains(count), let price = validated(unitPrice) else { return nil }
        let (amount, overflow) = price.multipliedReportingOverflow(by: count)
        guard !overflow, (-maximum...maximum).contains(amount) else { return nil }
        return amount
    }
    static func format(_ value: Double, currency: String) -> String? {
        guard currency == "USD", let cents = validated(value) else { return nil }
        return format(cents: cents)
    }
    static func format(cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let dollars = NSDecimalNumber(value: cents).dividing(by: NSDecimalNumber(value: 100))
        return formatter.string(from: dollars) ?? "Amount unavailable"
    }
}
