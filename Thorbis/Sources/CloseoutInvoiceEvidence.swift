import Foundation

/// Resolves the invoice records closeout uses to judge queued payments.
enum CloseoutInvoiceEvidence {
    static func resolve<Record>(listed: [Record]?, paidHere: [String],
                                id: (Record) -> String,
                                cached: (String) -> Record?,
                                equivalent: (Record, Record) -> Bool,
                                valid: (Record) -> Bool = { _ in true }) -> [Record]? {
        guard let listed else { return nil }
        let extra = Set(paidHere.filter { candidate in !listed.contains { candidate == id($0) } })
        let additional = extra.compactMap(cached)
        guard additional.count == extra.count,
              Set(additional.map(id)) == extra else { return nil }
        var resolved: [Record] = []
        for record in listed {
            if let individual = cached(id(record)) {
                guard id(individual) == id(record), equivalent(record, individual) else { return nil }
            }
            resolved.append(record)
        }
        let records = resolved + additional
        guard records.allSatisfy(valid) else { return nil }
        return records
    }

    struct PendingPayment {
        let actorID: String
        let organizationID: String
        let jobID: String?
        let invoiceID: String
        let method: String
        let amount: Int
    }

    static func hasUnassociatedPayments(_ jobIDs: [String?]) -> Bool { jobIDs.contains { $0 == nil } }

    static func pendingAmounts(_ payments: [PendingPayment], actorID: String, organizationID: String,
                               jobID: String, invoiceID: String) -> [Int]? {
        guard payments.allSatisfy({ $0.actorID == actorID && $0.organizationID == organizationID &&
            $0.jobID == jobID && $0.invoiceID == invoiceID &&
            ($0.method == "cash" || $0.method == "check") && $0.amount > 0 }) else { return nil }
        return payments.map(\.amount)
    }

    /// Recorded amounts might already be included in the invoice balance; only pending
    /// amounts can safely cover that balance without a matching projection proof.
    static func covers(due: Int, pending: [Int], recorded: [Int]) -> Bool {
        guard due > 0, let pendingTotal = sum(pending) else { return false }
        return pendingTotal >= due
    }

    static func sum(_ amounts: [Int]) -> Int? {
        var total = 0
        for amount in amounts {
            guard amount >= 0 else { return nil }
            let (next, overflow) = total.addingReportingOverflow(amount)
            guard !overflow else { return nil }
            total = next
        }
        return total
    }
}
