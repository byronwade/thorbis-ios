import Foundation

enum MoneyInput {
    static func cents(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[0-9]{1,7}(\.[0-9]{1,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let minor = decimal * 100
        guard minor >= 0, minor <= 100_000_000 else { return nil }
        return NSDecimalNumber(decimal: minor).intValue
    }
}
