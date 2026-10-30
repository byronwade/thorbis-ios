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

/// Customer-facing invoice headline; never infers a payment from a zero balance.
struct CustomerInvoiceBalanceSummary: Equatable {
    let title: String
    let amount: Int?

    init(title: String, amount: Int?) { self.title = title; self.amount = amount }

    init(status: String, fresh: Bool, amounts: CustomerDocumentAmounts, historyReconciled: Bool) {
        if !fresh {
            self.init(title: status == "void" ? "Last known status: Voided" : "Last known balance",
                      amount: status == "void" ? nil : amounts.due)
        } else if status == "void" {
            self.init(title: "Voided invoice", amount: nil)
        } else if status == "draft" {
            self.init(title: "Draft total", amount: amounts.total)
        } else if amounts.due > 0 {
            self.init(title: "Amount due", amount: amounts.due)
        } else if status == "paid", amounts.paid > 0, historyReconciled {
            self.init(title: "Paid in full", amount: 0)
        } else {
            self.init(title: "No balance due", amount: 0)
        }
    }
}
