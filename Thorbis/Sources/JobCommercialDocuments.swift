import Foundation

/// Customer identity alone never establishes that a document belongs to this job.
struct JobDocumentScope: Equatable {
    let jobID: String
    let organizationID: String
    let customerID: String
    var originEstimateID: String? = nil

    func contains(_ invoice: InvoiceRecord) -> Bool {
        invoice.jobId == jobID && invoice.organizationId == organizationID && invoice.customerId == customerID
    }

    func contains(_ estimate: EstimateRecord, requestedID: String) -> Bool {
        estimate.id == requestedID && estimate.organizationId == organizationID && estimate.customerId == customerID
    }
}

struct JobDocumentRead<Record> {
    let scope: JobDocumentScope
    let records: [Record]
    /// Successfully read, identity-checked documents with a currently verified association.
    let freshIDs: Set<String>
    let isComplete: Bool
    let issue: String?

    fileprivate init(scope: JobDocumentScope, records: [Record], freshIDs: Set<String>, isComplete: Bool, kind: String) {
        self.scope = scope
        self.records = records
        self.freshIDs = freshIDs
        self.isComplete = isComplete
        issue = isComplete ? nil : "Couldn't load all \(kind) for this job. Some records may need a refresh."
    }
}

extension JobDocumentRead where Record == InvoiceRecord {
    /// The footer follows actionable paper; a recent paid deposit cannot hide an older balance.
    func preferredInvoice(id: String?) -> InvoiceRecord? {
        let available = records.filter { freshIDs.contains($0.id) && scope.contains($0) }
        if let chosen = available.first(where: { $0.id == id }), chosen.status == "draft" || Self.isOwed(chosen) {
            return chosen
        }
        return available.first(where: Self.isOwed)
            ?? available.first(where: { $0.status == "draft" })
            ?? available.first(where: { $0.id == id })
            ?? available.first
    }

    func replacing(_ invoice: InvoiceRecord) -> Self {
        guard scope.contains(invoice), let index = records.firstIndex(where: { $0.id == invoice.id }) else { return self }
        var updated = records
        updated[index] = invoice
        return .init(scope: scope, records: updated, freshIDs: freshIDs.union([invoice.id]), isComplete: isComplete, kind: "invoices")
    }

    private static func isOwed(_ invoice: InvoiceRecord) -> Bool {
        guard invoice.status == "issued", invoice.currency == "USD", invoice.amountPaid >= 0,
              invoice.lines.allSatisfy({ $0.unitPrice.currency == invoice.currency && $0.unitPrice.amount >= 0 }),
              let total = paperLinesTotal(invoice.lines) else { return false }
        return total > invoice.amountPaid
    }
}

@MainActor
enum JobDocumentsLoader {
    static func estimates(scope: JobDocumentScope, api: APIClient,
                          retaining previous: JobDocumentRead<EstimateRecord>?,
                          isCurrent: @escaping @MainActor () -> Bool) async -> JobDocumentRead<EstimateRecord>? {
        guard isCurrent(), !Task.isCancelled else { return nil }
        let retained = previous?.scope == scope ? previous?.records ?? [] : []
        var ids = scope.originEstimateID.map { [$0] } ?? []
        var complete = true
        var linksRead = false
        do {
            let links = try await api.fieldJobEstimateLinks(scope.jobID)
            guard isCurrent(), !Task.isCancelled else { return nil }
            linksRead = true
            for link in links {
                guard link.jobId == scope.jobID else { complete = false; continue }
                ids.append(link.estimateId)
            }
        } catch is CancellationError { return nil }
        catch {
            guard isCurrent(), !Task.isCancelled else { return nil }
            if denied(error) {
                return .init(scope: scope, records: [], freshIDs: [], isComplete: false, kind: "estimates")
            }
            complete = false
        }

        var records: [EstimateRecord] = []
        var fresh = Set<String>()
        for id in unique(ids) {
            guard isCurrent(), !Task.isCancelled else { return nil }
            do {
                let record = try await api.fieldEstimate(id)
                guard isCurrent(), !Task.isCancelled else { return nil }
                guard scope.contains(record, requestedID: id) else { complete = false; continue }
                records.append(record)
                fresh.insert(record.id)
            } catch is CancellationError { return nil }
            catch {
                guard isCurrent(), !Task.isCancelled else { return nil }
                complete = false
                if !denied(error), let old = retained.first(where: { $0.id == id && scope.contains($0, requestedID: id) }) {
                    records.append(old)
                }
            }
        }
        if !linksRead {
            // Last-known rows stay visible as stale, never silently reduced to an origin-only success.
            let present = Set(records.map(\.id))
            records += retained.filter { !present.contains($0.id) && scope.contains($0, requestedID: $0.id) }
        }
        guard isCurrent(), !Task.isCancelled else { return nil }
        return .init(scope: scope, records: records, freshIDs: fresh, isComplete: complete, kind: "estimates")
    }

    static func invoices(scope: JobDocumentScope, api: APIClient, knownIDs: [String],
                         retaining previous: JobDocumentRead<InvoiceRecord>?,
                         isCurrent: @escaping @MainActor () -> Bool) async -> JobDocumentRead<InvoiceRecord>? {
        guard isCurrent(), !Task.isCancelled else { return nil }
        do {
            do {
                let incoming = try await api.fieldJobInvoices(scope.jobID)
                guard isCurrent(), !Task.isCancelled else { return nil }
                let mine = incoming.filter(scope.contains)
                // Empty is authoritative here; cached IDs must not resurrect deleted/unlinked paper.
                return invoiceRead(scope, mine, complete: mine.count == incoming.count)
            } catch let problem as Problem where problem.status == 404 || problem.status == 405 {
                let organizationRows = try await api.fieldInvoices()
                guard isCurrent(), !Task.isCancelled else { return nil }
                var mine = organizationRows.filter(scope.contains)
                let seen = Set(organizationRows.map(\.id))
                for id in unique(knownIDs) where !seen.contains(id) {
                    guard isCurrent(), !Task.isCancelled else { return nil }
                    do {
                        let record = try await api.fieldInvoice(id)
                        guard isCurrent(), !Task.isCancelled else { return nil }
                        if record.id == id && scope.contains(record) { mine.append(record) }
                    } catch is CancellationError { return nil }
                    catch {
                        guard isCurrent(), !Task.isCancelled else { return nil }
                        // Continue the other independent reads; compatibility is never complete.
                    }
                }
                guard isCurrent(), !Task.isCancelled else { return nil }
                return invoiceRead(scope, mine, complete: false)
            }
        } catch is CancellationError { return nil }
        catch {
            guard isCurrent(), !Task.isCancelled else { return nil }
            let retained = !denied(error) && previous?.scope == scope ? previous?.records.filter(scope.contains) ?? [] : []
            return .init(scope: scope, records: retained, freshIDs: [], isComplete: false, kind: "invoices")
        }
    }

    private static func invoiceRead(_ scope: JobDocumentScope, _ records: [InvoiceRecord], complete: Bool) -> JobDocumentRead<InvoiceRecord> {
        var seen = Set<String>()
        let ordered = records.filter { seen.insert($0.id).inserted }.sorted {
            $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt
        }
        return .init(scope: scope, records: ordered, freshIDs: Set(ordered.map(\.id)), isComplete: complete, kind: "invoices")
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func denied(_ error: Error) -> Bool {
        guard let status = (error as? Problem)?.status else { return false }
        return status == 401 || status == 403
    }
}
