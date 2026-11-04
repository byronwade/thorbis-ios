import Foundation
@preconcurrency import StripeTerminal

private struct BoundTapSettlementRequest: Encodable { let paymentIntentId: String }
private struct BoundTapOperationResponse: Decodable {
    let status: String
    let attemptId: String?
    let paymentIntentId: String?
    let amount: FieldMoney?
}
private struct BoundTapSettlementResponse: Decodable {
    let status: String
    let attemptId: String?
    let paymentId: String?
    let amount: FieldMoney?
}

/// Read-only qualification seam. It never collects a card or clears a receipt.
/// A matching payment row alone is not authoritative Stripe settlement proof.
@MainActor enum BoundTapRecoveryReconciler {
    // This cannot be enabled until the server contract, Keychain access
    // group, reader lifetime and process-coordination tests are qualified.
    private static let releaseQualified = false

    static func check(api: APIClient, session: SessionController, store: BoundTapRecoveryStoring) async throws -> BoundTapRecoveryResult {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.thorbis.field") else {
            throw BoundTapFlowError.recoveryUnavailable
        }
        let lease: BoundTapProcessLease
        do { lease = try BoundTapProcessLease.acquire(path: container.path) }
        catch BoundTapProcessLeaseError.busy { return .restartRequired }
        defer { lease.close() }
        guard var receipt = try store.load() else { return .pending }
        guard session.phase == .ready, session.user?.id == receipt.actorID,
              session.activeOrganization?.id == receipt.organizationID,
              session.can("invoice.payment.create", feature: "payments"),
              api.normalizedOrigin == receipt.origin else { return .otherAccount }
        let sessionGeneration = session.generation, authority = session.authorityRevision
        let apiGeneration = api.requestGeneration, scope = api.savedCopyScope, scopeRevision = api.savedCopyScopeRevision
        let current: @MainActor () -> Bool = {
            session.phase == .ready && session.user?.id == receipt.actorID && session.activeOrganization?.id == receipt.organizationID &&
            session.generation == sessionGeneration && session.authorityRevision == authority &&
            session.can("invoice.payment.create", feature: "payments") &&
            api.requestGeneration == apiGeneration && api.normalizedOrigin == receipt.origin &&
            api.savedCopyScope == scope && api.savedCopyScopeRevision == scopeRevision
        }
        let invoicePath = try api.financialPath("/v1/invoices", id: receipt.invoiceID, suffix: "")
        if receipt.attemptID == nil {
            guard let operationID = receipt.operationID, UUID(uuidString: operationID) != nil else { return .unknownAttempt }
            let operationPath = invoicePath + "/card-present-operations/\(operationID)"
            let operation: APIRead<BoundTapOperationResponse> = try await api.sendWithProvenance(operationPath, requireFresh: true)
            guard current(), fresh(operation.provenance, path: operationPath, generation: apiGeneration,
                                   origin: receipt.origin, scope: scope, scopeRevision: scopeRevision),
                  operation.value.status == "found",
                  let recovered = BoundTapRecoveryManager.recovered(marker: receipt, attemptID: operation.value.attemptId,
                      intentID: operation.value.paymentIntentId, amount: operation.value.amount?.amount, currency: operation.value.amount?.currency),
                  try store.load() == receipt else { return .pending }
            receipt = recovered
            try store.save(receipt)
        }
        guard let attemptID = receipt.attemptID, UUID(uuidString: attemptID) != nil, let intentID = receipt.paymentIntentID,
              let expectedAmount = receipt.amount, let currency = receipt.currency else { return .unknownAttempt }
        let settlement: BoundTapSettlementResponse = try await api.send("POST",
            try api.financialPath("/v1/invoices", id: receipt.invoiceID, suffix: "/card-present-attempts/\(attemptID)/reconciliation"),
            body: BoundTapSettlementRequest(paymentIntentId: intentID))
        guard current(), settlement.status == "settled", settlement.attemptId == attemptID,
              let paymentID = settlement.paymentId, UUID(uuidString: paymentID) != nil,
              settlement.amount?.amount == expectedAmount, settlement.amount?.currency == currency else { return .pending }
        let invoice: APIRead<InvoiceRecord> = try await api.sendWithProvenance(invoicePath, requireFresh: true)
        guard current(), fresh(invoice.provenance, path: invoicePath, generation: apiGeneration,
                               origin: receipt.origin, scope: scope, scopeRevision: scopeRevision) else { return .pending }
        let history = try await api.fieldPaymentsWithProvenance(receipt.invoiceID, requireFresh: true)
        guard current(), !history.pages.isEmpty,
              history.pages.allSatisfy({ fresh($0, path: invoicePath + "/payments", generation: apiGeneration,
                                              origin: receipt.origin, scope: scope, scopeRevision: scopeRevision) }) else { return .pending }
        var records: [BoundTapReconciliationRecord] = []
        for item in history.payments {
            let refunded = item.refundedAmount ?? (item.status == .refunded ? item.amount.amount : 0)
            guard refunded >= 0, refunded <= item.amount.amount else { return .pending }
            let received = item.amount.amount - refunded
            if item.status == .refunded && received != 0 { return .pending }
            if let net = item.netAmount {
                guard net.currency == item.amount.currency, net.amount == received else { return .pending }
            } else if refunded != 0 && item.status != .refunded { return .pending }
            records.append(.init(id: item.id, invoiceID: item.invoiceId, organizationID: item.organizationId,
                                 idempotencyKey: item.idempotencyKey, amount: item.amount.amount, net: received,
                                 currency: item.amount.currency, method: item.method, status: item.status.rawValue))
        }
        let snapshot = BoundTapReconciliationSnapshot(origin: receipt.origin, actorID: receipt.actorID,
            organizationID: invoice.value.organizationId, invoiceID: invoice.value.id,
            invoiceAmountPaid: invoice.value.amountPaid, currency: invoice.value.currency,
            authorized: current(), freshAndComplete: true, records: records)
        guard BoundTapReconciliation.matches(receipt: receipt, snapshot: snapshot),
              snapshot.records.contains(where: { $0.id == paymentID && $0.idempotencyKey == "tap:\(receipt.invoiceID):\(attemptID)" }),
              current(), try store.load() == receipt else { return .pending }
        // This process must not own an SDK whose late callbacks can outlive
        // cancellation. The cross-process lease excludes cooperating writers.
        return try BoundTapGuardedRelease.apply(enabled: releaseQualified, verified: true,
            sdkInitialized: Terminal.isInitialized(), current: current, lease: lease, store: store, expected: receipt)
    }

    private static func fresh(_ value: APIReadProvenance, path: String, generation: UUID, origin: String,
                              scope: String?, scopeRevision: UUID) -> Bool {
        value.path == path && value.generation == generation && APIClient.normalizedOrigin(value.origin) == origin &&
        value.savedCopyScope == scope && value.savedCopyScopeRevision == scopeRevision &&
        value.source == .urlSession(cacheBypassed: true)
    }
}
