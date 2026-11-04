import Foundation

/// Matches the customer name, the familiar short reference, or the invoice ID.
enum InvoiceReferenceSearch {
    static func matches(query: String, invoiceID: String, customerName: String) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        let reference = "INV-\(invoiceID.suffix(4).uppercased())"
        let rawID = term.uppercased().hasPrefix("INV-") ? String(term.dropFirst(4)) : term
        return customerName.localizedCaseInsensitiveContains(term) ||
            reference.localizedCaseInsensitiveContains(term) ||
            (!rawID.isEmpty && invoiceID.localizedCaseInsensitiveContains(rawID))
    }
}
