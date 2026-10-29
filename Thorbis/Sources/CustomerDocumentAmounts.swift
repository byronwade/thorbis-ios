import Foundation

/// Display-only breakdown of canonical document lines, using exact minor units.
struct CustomerDocumentAmounts: Equatable {
    let subtotal: Int
    let credits: Int
    let total: Int
    let paid: Int
    let due: Int

    init?(lines: [FieldLine], currency: String, amountPaid: Int = 0) {
        guard !currency.isEmpty, amountPaid >= 0 else { return nil }
        var charges = 0
        var adjustments = 0
        for line in lines {
            guard line.quantity > 0, line.unitPrice.currency == currency else { return nil }
            let (amount, productOverflow) = line.quantity.multipliedReportingOverflow(by: line.unitPrice.amount)
            guard !productOverflow else { return nil }
            if amount < 0 {
                let (next, overflow) = adjustments.addingReportingOverflow(amount)
                guard !overflow else { return nil }
                adjustments = next
            } else {
                let (next, overflow) = charges.addingReportingOverflow(amount)
                guard !overflow else { return nil }
                charges = next
            }
        }
        let (final, overflow) = charges.addingReportingOverflow(adjustments)
        guard !overflow, final >= 0 else { return nil }
        subtotal = charges
        credits = adjustments
        total = final
        paid = amountPaid
        due = amountPaid >= final ? 0 : final - amountPaid
    }
}
