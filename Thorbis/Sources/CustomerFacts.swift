import Foundation

/// v2 Record room, "every fact appears once": whether a customer's own address, phone or email is
/// already shown by one of their locations or contacts, so the details panel can leave it out.
/// Compares loosely (digits for phones; case, spacing and punctuation for the rest) and never hides
/// a value that appears nowhere else.
enum CustomerFacts {
    static func phone(_ value: String, isIn others: [String]) -> Bool {
        let digits = lastTen(value)
        guard digits.count >= 7 else { return false }
        return others.contains { lastTen($0) == digits }
    }

    static func email(_ value: String, isIn others: [String]) -> Bool {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return false }
        return others.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }
    }

    static func address(_ value: String, isIn others: [String]) -> Bool {
        let key = squash(value)
        guard !key.isEmpty else { return false }
        return others.contains { squash($0) == key }
    }

    /// The last ten digits, so "+1 (555) 010-0413" and "555-010-0413" match.
    private static func lastTen(_ value: String) -> String { String(value.filter(\.isNumber).suffix(10)) }

    private static func squash(_ value: String) -> String {
        value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}
