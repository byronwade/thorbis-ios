import Foundation

/// Mirrors the advertised v2 server contract. A false or unavailable capability
/// keeps the established limits; this type never truncates the draft text.
enum CommercialDescriptionPolicy {
    enum Kind { case estimate, invoice }
    enum Problem: Error, LocalizedError, Equatable {
        case unavailable, lineTooLong, totalTooLong, tooManyBreaks, tooManyRows, unsupportedCharacters
        var errorDescription: String? {
            switch self {
            case .unavailable: "Connect to a workspace that supports long descriptions before saving. Your text is still here."
            case .lineTooLong: "An item description can contain up to 4,000 characters. Your text is still here."
            case .totalTooLong: "These descriptions are too long to save together. Your text is still here."
            case .tooManyBreaks: "These descriptions have too many line breaks to save together. Your text is still here."
            case .tooManyRows: "This document has too many items to save with long descriptions. Your text is still here."
            case .unsupportedCharacters: "Long descriptions can't yet include some characters, including emoji. Your text is still here."
            }
        }
    }
    private static let extras = Set("€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ".unicodeScalars.map(\.value))

    static func isExtended(_ descriptions: [String], kind: Kind) -> Bool {
        descriptions.contains { text in
            switch kind {
            case .estimate: text.utf16.count > 200
            case .invoice: text.unicodeScalars.count > 211
            }
        }
    }

    static func problem(_ descriptions: [String], kind: Kind, optionCount: Int = 0,
                        capabilityVerified: Bool) -> Problem? {
        let trimmed = descriptions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard isExtended(trimmed, kind: kind) else { return nil }
        guard capabilityVerified else { return .unavailable }
        guard trimmed.count + optionCount <= 500 else { return .tooManyRows }
        var total = 0
        var breaks = 0
        for text in trimmed {
            guard text.utf16.count <= 4_000 else { return .lineTooLong }
            total += text.utf16.count
            var previousCR = false
            for scalar in text.unicodeScalars {
                let value = scalar.value
                let supported = value == 10 || value == 13 || (32...126).contains(value) ||
                    ((161...255).contains(value) && value != 173) || extras.contains(value)
                guard supported else { return .unsupportedCharacters }
                if value == 13 || (value == 10 && !previousCR) { breaks += 1 }
                previousCR = value == 13
            }
        }
        if total > 50_000 { return .totalTooLong }
        if breaks > 2_500 { return .tooManyBreaks }
        return nil
    }
}
