import Foundation

/// Held integration seam. No app screen calls this yet. A successful response
/// here is not a job-membership proof and does not authorize an offline copy.
struct FencedInvoiceRead {
    let read: APIRead<InvoiceRecord>
    let receipt: InvoiceReadFence.Receipt
}

@MainActor
extension APIClient {
    func fieldFencedInvoice(_ scope: InvoiceReadFence.Scope, fence: InvoiceReadFence) async throws -> FencedInvoiceRead {
        guard scope.resource == "invoice", UUID(uuidString: scope.actor) != nil,
              UUID(uuidString: scope.organization) != nil, UUID(uuidString: scope.invoice) != nil,
              normalizedOrigin == Self.normalizedOrigin(scope.origin),
              savedCopyScope == SavedCopies.scope(actorID: scope.actor, organizationID: scope.organization) else {
            throw InvoiceReadFence.Failure.invalidScope
        }
        let generation = requestGeneration
        let scopeRevision = savedCopyScopeRevision
        // Do not create the transport task until a pending hold is durable.
        let attempt = try fence.begin(scope)
        do {
            let read = try await SavedCopies.$liveOnly.withValue(true) {
                try await SavedCopies.$suppressWrite.withValue(true) {
                    try await fieldInvoiceWithProvenance(scope.invoice)
                }
            }
            try Task.checkCancellation()
            guard let finalURL = read.finalResponseURL,
                  var finalComponents = URLComponents(url: finalURL, resolvingAgainstBaseURL: false),
                  finalComponents.user == nil, finalComponents.password == nil else {
                throw InvoiceReadFence.Failure.invalidScope
            }
            finalComponents.path = ""
            finalComponents.query = nil
            finalComponents.fragment = nil
            guard generation == requestGeneration, scopeRevision == savedCopyScopeRevision,
                  normalizedOrigin == Self.normalizedOrigin(scope.origin),
                  finalComponents.url.flatMap({ Self.normalizedOrigin($0.absoluteString) }) == normalizedOrigin,
                  read.provenance.generation == generation,
                  read.provenance.savedCopyScope == SavedCopies.scope(actorID: scope.actor, organizationID: scope.organization),
                  read.provenance.savedCopyScopeRevision == scopeRevision,
                  Self.normalizedOrigin(read.provenance.origin) == normalizedOrigin,
                  read.provenance.path == "/v1/invoices/\(scope.invoice)", read.provenance.cursor == nil,
                  read.provenance.source == .urlSession(cacheBypassed: true),
                  read.value.id.lowercased() == scope.invoice.lowercased(),
                  read.value.organizationId.lowercased() == scope.organization.lowercased() else {
                throw InvoiceReadFence.Failure.invalidScope
            }
            guard case let .committed(receipt) = try attempt.finish(.liveSuccess(read.rawData)) else {
                throw InvoiceReadFence.Failure.storage
            }
            return FencedInvoiceRead(read: read, receipt: receipt)
        } catch {
            let status = (error as? Problem)?.status
            // Unknown/cancelled outcomes cannot restore an older grant. A
            // received resource denial remains denied even if the UI moved on.
            let outcome: InvoiceReadFence.Outcome = status.map { [401, 403, 404].contains($0) } == true ? .denied : .uncertain
            _ = try? attempt.finish(outcome)
            throw error
        }
    }
}
