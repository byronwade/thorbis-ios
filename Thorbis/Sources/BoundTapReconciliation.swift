import Foundation

struct BoundTapReconciliationRecord {
    let id: String
    let invoiceID: String
    let organizationID: String
    var idempotencyKey: String
    let amount: Int
    let net: Int
    let currency: String
    let method: String
    let status: String
}

struct BoundTapReconciliationSnapshot {
    let origin: String
    var actorID: String
    let organizationID: String
    let invoiceID: String
    var invoiceAmountPaid: Int
    let currency: String
    var authorized: Bool
    var freshAndComplete: Bool
    var records: [BoundTapReconciliationRecord]
}

enum BoundTapReconciliation {
    static func matches(receipt: BoundTapRecovery, snapshot: BoundTapReconciliationSnapshot) -> Bool {
        guard snapshot.authorized, snapshot.freshAndComplete,
              snapshot.origin == receipt.origin, snapshot.actorID == receipt.actorID,
              snapshot.organizationID == receipt.organizationID, snapshot.invoiceID == receipt.invoiceID,
              let attempt = receipt.attemptID, UUID(uuidString: attempt) != nil,
              let intent = receipt.paymentIntentID, !intent.isEmpty,
              let amount = receipt.amount, amount > 0, let currency = receipt.currency,
              currency == snapshot.currency else { return false }
        var ids = Set<String>()
        var total = 0
        var matched = 0
        for item in snapshot.records {
            guard ids.insert(item.id.lowercased()).inserted,
                  item.invoiceID == snapshot.invoiceID, item.organizationID == snapshot.organizationID,
                  item.currency == currency, item.amount > 0, item.net >= 0, item.net <= item.amount else { return false }
            let (next, overflow) = total.addingReportingOverflow(item.net)
            guard !overflow else { return false }
            total = next
            if item.idempotencyKey == "tap:\(receipt.invoiceID):\(attempt)" {
                guard item.method == "card", item.status == "recorded", item.amount == amount, item.net == amount else { return false }
                matched += 1
            }
        }
        return matched == 1 && total == snapshot.invoiceAmountPaid
    }
}
