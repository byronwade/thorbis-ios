import Foundation

/// A presentation-only summary. The original catalog description remains unchanged.
enum PriceBookPresentation {
    static func readableDescription(_ description: String) -> String {
        // Only the known demo import reconciliation suffix is presentation metadata.
        // Other bracketed text and the original stored value stay untouched.
        let pattern = #"\s*\[thorbis-plumbing-demo-v1:(?:material|service)-[0-9]{3}\]$"#
        guard let range = description.range(of: pattern, options: .regularExpression) else { return description }
        return String(description[..<range.lowerBound])
    }

    static func title(_ description: String) -> String {
        let readable = readableDescription(description)
        let text = readable.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return readable != description ? "Untitled item" : description }
        let lineEnd = text.firstIndex(where: \.isNewline) ?? text.endIndex
        let firstLine = String(text[..<lineEnd])
        // Only the known demo import has a reliable title-then-description format.
        // Other companies' text can contain abbreviations and other punctuation.
        if readable != description, let sentenceEnd = firstLine.range(of: ". ") {
            return String(firstLine[..<sentenceEnd.upperBound]).trimmingCharacters(in: .whitespaces)
        }
        return firstLine
    }
}
