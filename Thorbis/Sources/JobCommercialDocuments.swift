import Combine
import Foundation

/// Shared by the job and its customer presentation. Only the latest read may publish or update memory.
@MainActor
final class JobDocumentCollections: ObservableObject {
    @Published private(set) var estimates: JobDocumentRead<EstimateRecord>?
    @Published private(set) var invoices: JobDocumentRead<InvoiceRecord>?
    private var estimateRequest = UUID()
    private var invoiceRequest = UUID()

    func clearEstimates() { estimateRequest = UUID(); estimates = nil }
    func clearInvoices() { invoiceRequest = UUID(); invoices = nil }
    func reset() { clearEstimates(); clearInvoices() }
    func replaceInvoice(_ invoice: InvoiceRecord) { invoices = invoices?.replacing(invoice) }

    @discardableResult
    func loadEstimates(scope: JobDocumentScope, api: APIClient,
                       isCurrent: @escaping @MainActor () -> Bool) async -> Bool {
        guard isCurrent(), !Task.isCancelled else { return false }
        let request = UUID()
        estimateRequest = request
        let current: @MainActor () -> Bool = { self.estimateRequest == request && isCurrent() }
        guard let read = await JobDocumentsLoader.estimates(scope: scope, api: api, retaining: estimates, isCurrent: current),
              current(), !Task.isCancelled else { return false }
        estimates = read
        return true
    }

    @discardableResult
    func loadInvoices(scope: JobDocumentScope, api: APIClient,
                      isCurrent: @escaping @MainActor () -> Bool) async -> Bool {
        guard isCurrent(), !Task.isCancelled else { return false }
        let request = UUID()
        invoiceRequest = request
        let current: @MainActor () -> Bool = { self.invoiceRequest == request && isCurrent() }
        guard let read = await JobDocumentsLoader.invoices(scope: scope, api: api,
            knownIDs: JobInvoiceMemory.ids(scope.jobID), retaining: invoices, isCurrent: current),
              current(), !Task.isCancelled else { return false }
        invoices = read
        if read.isComplete {
            JobInvoiceMemory.replace(read.records.map(\.id), jobID: scope.jobID)
        } else {
            read.records.filter { read.freshIDs.contains($0.id) }.forEach { JobInvoiceMemory.remember($0.id, jobID: scope.jobID) }
        }
        return true
    }
}

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

enum JobEstimateCreation {
    static func canOpen(canCreate: Bool, canView: Bool, estimatesComplete: Bool) -> Bool {
        canCreate && (!canView || estimatesComplete)
    }
}

struct JobEstimateSummary {
    struct Amount: Equatable, Identifiable {
        let status: String
        let currency: String
        let cents: Int
        var id: String { "\(status):\(currency)" }
    }
    let amounts: [Amount]
    let optionCount: Int

    init?(records: [EstimateRecord], complete: Bool) {
        guard complete else { return nil }
        var sums: [String: [String: Int]] = [:]
        var options = 0
        for record in records {
            if record.options?.isEmpty == false { options += 1; continue }
            guard ["approved", "sent"].contains(record.status) else { continue }
            let currency = record.lines.first?.unitPrice.currency ?? "USD"
            guard currency.utf8.count == 3, currency.utf8.allSatisfy({ (65...90).contains($0) }) else { return nil }
            guard let amounts = CustomerDocumentAmounts(lines: record.lines, currency: currency) else { return nil }
            let sum = (sums[record.status]?[currency] ?? 0).addingReportingOverflow(amounts.total)
            guard !sum.overflow else { return nil }
            sums[record.status, default: [:]][currency] = sum.partialValue
        }
        amounts = sums.keys.sorted().flatMap { status in
            sums[status]!.keys.sorted().map { Amount(status: status, currency: $0, cents: sums[status]![$0]!) }
        }
        optionCount = options
        if amounts.isEmpty && optionCount == 0 { return nil }
    }
}

struct JobDocumentRead<Record> {
    let scope: JobDocumentScope
    let records: [Record]
    /// Successfully read, identity-checked documents with a currently verified association.
    let freshIDs: Set<String>
    let isComplete: Bool
    let issue: String?
    /// Verified association, but no safe document contents were available to display.
    let unavailableIDs: [String]

    fileprivate init(scope: JobDocumentScope, records: [Record], freshIDs: Set<String>, isComplete: Bool,
                     unavailableIDs: [String] = [], kind: String) {
        self.scope = scope
        self.records = records
        self.freshIDs = freshIDs
        self.isComplete = isComplete
        self.unavailableIDs = unavailableIDs
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
        guard invoice.status == "issued", invoice.currency == "USD",
              let amounts = CustomerDocumentAmounts(lines: invoice.lines, currency: invoice.currency,
                                                     amountPaid: invoice.amountPaid) else { return false }
        return amounts.due > 0
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
        var rejected = Set<String>()
        for id in unique(ids) {
            guard isCurrent(), !Task.isCancelled else { return nil }
            do {
                let record = try await api.fieldEstimate(id)
                guard isCurrent(), !Task.isCancelled else { return nil }
                guard scope.contains(record, requestedID: id) else {
                    complete = false
                    rejected.insert(id)
                    continue
                }
                records.append(record)
                fresh.insert(record.id)
            } catch is CancellationError { return nil }
            catch {
                guard isCurrent(), !Task.isCancelled else { return nil }
                complete = false
                if !canRetain(after: error) { rejected.insert(id) }
                if canRetain(after: error), let old = retained.first(where: { $0.id == id && scope.contains($0, requestedID: id) }) {
                    records.append(old)
                }
            }
        }
        if !linksRead {
            // Last-known rows stay visible as stale, never silently reduced to an origin-only success.
            let present = Set(records.map(\.id))
            records += retained.filter { !present.contains($0.id) && !rejected.contains($0.id) && scope.contains($0, requestedID: $0.id) }
        }
        guard isCurrent(), !Task.isCancelled else { return nil }
        let displayed = Set(records.map(\.id))
        return .init(scope: scope, records: records, freshIDs: fresh, isComplete: complete,
                     unavailableIDs: unique(ids).filter { !displayed.contains($0) }, kind: "estimates")
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
                return invoiceRead(scope, mine, freshIDs: Set(mine.map(\.id)), complete: mine.count == incoming.count)
            } catch let problem as Problem where problem.status == 404 || problem.status == 405 {
                let organizationRows = try await api.fieldInvoices()
                guard isCurrent(), !Task.isCancelled else { return nil }
                var mine = organizationRows.filter(scope.contains)
                var fresh = Set(mine.map(\.id))
                let retained = previous?.scope == scope ? previous?.records.filter(scope.contains) ?? [] : []
                let seen = Set(organizationRows.map(\.id))
                for id in unique(knownIDs + retained.map(\.id)) where !seen.contains(id) {
                    guard isCurrent(), !Task.isCancelled else { return nil }
                    do {
                        let record = try await api.fieldInvoice(id)
                        guard isCurrent(), !Task.isCancelled else { return nil }
                        if record.id == id && scope.contains(record) {
                            mine.append(record)
                            fresh.insert(record.id)
                        }
                    } catch is CancellationError { return nil }
                    catch {
                        guard isCurrent(), !Task.isCancelled else { return nil }
                        if canRetain(after: error), let old = retained.first(where: { $0.id == id }) { mine.append(old) }
                    }
                }
                guard isCurrent(), !Task.isCancelled else { return nil }
                return invoiceRead(scope, mine, freshIDs: fresh, complete: false)
            }
        } catch is CancellationError { return nil }
        catch {
            guard isCurrent(), !Task.isCancelled else { return nil }
            let retained = !denied(error) && previous?.scope == scope ? previous?.records.filter(scope.contains) ?? [] : []
            return .init(scope: scope, records: retained, freshIDs: [], isComplete: false, kind: "invoices")
        }
    }

    private static func invoiceRead(_ scope: JobDocumentScope, _ records: [InvoiceRecord], freshIDs: Set<String>, complete: Bool) -> JobDocumentRead<InvoiceRecord> {
        var seen = Set<String>()
        let ordered = records.filter { seen.insert($0.id).inserted }.sorted {
            $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt
        }
        return .init(scope: scope, records: ordered, freshIDs: freshIDs, isComplete: complete, kind: "invoices")
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func denied(_ error: Error) -> Bool {
        guard let status = (error as? Problem)?.status else { return false }
        return status == 401 || status == 403
    }

    private static func canRetain(after error: Error) -> Bool {
        guard let status = (error as? Problem)?.status else { return true }
        return status == 408 || status == 429 || (500...599).contains(status)
    }
}
