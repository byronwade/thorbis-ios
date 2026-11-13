import Combine
import Foundation

/// One sheet owns one job invoice and the model that will record its payment.
struct JobInvoicePaymentRoute: Identifiable {
    let invoice: InvoiceRecord
    let model: InvoicePaymentCollectionModel
    let scope: JobDocumentScope
    let authorityToken: [String]
    let reference: String
    var id: String { invoice.id }

    func belongs(to current: JobDocumentScope) -> Bool {
        scope.jobID == current.jobID && scope.organizationID == current.organizationID &&
            scope.customerID == current.customerID && current.contains(invoice)
    }

    @MainActor static func make(requestedID: String, selectedID: String?, selected: InvoiceRecord?,
                     loadedID: String?, model: InvoicePaymentCollectionModel?,
                     scope: JobDocumentScope, authorityToken: [String] = [],
                     reference: String? = nil) -> Self? {
        guard selectedID == requestedID, loadedID == requestedID,
              let selected, selected.id == requestedID, scope.contains(selected),
              let model, let actual = model.invoice, actual.id == requestedID,
              scope.contains(actual), model.canRecordPayment else { return nil }
        return Self(invoice: actual, model: model, scope: scope, authorityToken: authorityToken,
                    reference: reference ?? "INV-\(actual.id.suffix(4).uppercased())")
    }
}

/// Keep short familiar references when possible; expand them to distinguish this job's invoices.
enum JobInvoiceReferences {
    static func reference(for id: String, among ids: [String]) -> String {
        let key = id.uppercased()
        let others = Set(ids.map { $0.uppercased() }).subtracting([key])
        var length = min(4, key.count)
        while length < key.count && others.contains(where: { $0.hasSuffix(String(key.suffix(length))) }) {
            length += 1
        }
        return "INV-\(key.suffix(length))"
    }
}

/// A recovery hint belongs only to the API and saved-copy scope that received the request.
enum JobInvoiceRecoveryContext {
    static func matches(origin: String?, savedCopyRevision: UUID, currentOrigin: String?, currentSavedCopyRevision: UUID) -> Bool {
        origin == currentOrigin && savedCopyRevision == currentSavedCopyRevision
    }
}

/// A direct action only for the exact, freshly listed invoice on this job.
enum JobInvoiceDirectPayment {
    /// Only shortcut selection when the entire scoped list is known and fresh.
    static func singleStep(invoices: [InvoiceRecord], scope: JobDocumentScope, freshIDs: Set<String>,
                           isComplete: Bool, canCollect: Bool) -> TechJobStep? {
        guard isComplete, canCollect,
              invoices.allSatisfy({ scope.contains($0) && freshIDs.contains($0.id) }) else { return nil }
        let steps = invoices.compactMap { step(invoice: $0, scope: scope, freshIDs: freshIDs, canCollect: canCollect) }
        return steps.count == 1 ? steps[0] : nil
    }

    static func step(invoice: InvoiceRecord, scope: JobDocumentScope, freshIDs: Set<String>,
                     canCollect: Bool) -> TechJobStep? {
        guard canCollect, freshIDs.contains(invoice.id), scope.contains(invoice), invoice.status == "issued",
              let due = TechJobFlow.due(invoice), due > 0 else { return nil }
        return .collect(invoiceID: invoice.id, due: due, currency: invoice.currency)
    }
}

/// Multiple job entry points may ask for the same model while its first read
/// is in flight. Wait for that read instead of treating its loading state as a refusal.
@MainActor
final class JobInvoicePaymentLoads {
    private struct Flight {
        let token: UUID
        let model: InvoicePaymentCollectionModel
        let task: Task<Void, Never>
    }
    private var flights: [ObjectIdentifier: Flight] = [:]

    func load(_ model: InvoicePaymentCollectionModel) async {
        let key = ObjectIdentifier(model)
        if let flight = flights[key] {
            await flight.task.value
            return
        }
        let token = UUID()
        let task = Task {
            if !(await model.waitForCurrentLoad()) { await model.load() }
            // Another owner can start a read between the first check and load().
            _ = await model.waitForCurrentLoad()
        }
        flights[key] = Flight(token: token, model: model, task: task)
        await task.value
        if flights[key]?.token == token { flights[key] = nil }
    }
}

/// Shared by the job and its customer presentation. Only the latest read may publish or update memory.
@MainActor
final class JobDocumentCollections: ObservableObject {
    @Published private(set) var estimates: JobDocumentRead<EstimateRecord>?
    @Published private(set) var invoices: JobDocumentRead<InvoiceRecord>?
    @Published private(set) var canLoadMoreEstimates = false
    @Published private(set) var loadingEstimatePage = false
    @Published private(set) var estimatePageError: String?
    @Published private(set) var estimatePageNeedsRefresh = false
    private var estimatePager: JobEstimateMembershipPager?
    private var estimatePagerScope: JobDocumentScope?
    private var estimatePageCommitted = false
    private var estimateRequest = UUID()
    private var invoiceRequest = UUID()
    func isLoadingEstimates(for scope: JobDocumentScope?) -> Bool {
        loadingEstimatePage && estimatePagerScope == scope
    }

    func clearEstimates() { estimateRequest = UUID(); estimates = nil; estimatePager = nil; estimatePagerScope = nil; canLoadMoreEstimates = false; loadingEstimatePage = false; estimatePageError = nil; estimatePageNeedsRefresh = false }
    func clearInvoices() { invoiceRequest = UUID(); invoices = nil }
    func reset() { clearEstimates(); clearInvoices() }
    func replaceInvoice(_ invoice: InvoiceRecord) { invoices = invoices?.replacing(invoice) }

    /// Keep the job's known documents visible while requiring a fresh membership and record read.
    func markEstimatesStale(scope: JobDocumentScope, updated: EstimateRecord? = nil, requestedID: String? = nil) {
        guard let read = estimates, read.scope == scope else { return }
        estimateRequest = UUID()
        estimatePager = nil; estimatePagerScope = nil; canLoadMoreEstimates = false; loadingEstimatePage = false; estimatePageError = nil; estimatePageNeedsRefresh = false
        var records = read.records
        if let updated, let requestedID, scope.contains(updated, requestedID: requestedID),
           let index = records.firstIndex(where: { $0.id == requestedID }) {
            records[index] = updated
        }
        estimates = .init(scope: read.scope, records: records, freshIDs: [], isComplete: false,
                          unavailableIDs: read.unavailableIDs, kind: "estimates")
    }

    @discardableResult
    func loadEstimates(scope: JobDocumentScope, api: APIClient,
                       onPartial: @escaping @MainActor (JobDocumentRead<EstimateRecord>) -> Void = { _ in },
                       isCurrent: @escaping @MainActor () -> Bool) async -> Bool {
        guard isCurrent(), !Task.isCancelled else { return false }
        estimatePager = nil; estimatePagerScope = nil; canLoadMoreEstimates = false; loadingEstimatePage = false; estimatePageError = nil; estimatePageNeedsRefresh = false
        let request = UUID()
        estimateRequest = request
        let current: @MainActor () -> Bool = { self.estimateRequest == request && isCurrent() }
        guard let read = await JobDocumentsLoader.estimates(scope: scope, api: api, retaining: estimates, isCurrent: current, onPartial: { partial in
            guard current(), !Task.isCancelled, partial.scope == scope else { return }
            onPartial(partial)
        }),
              current(), !Task.isCancelled else { return false }
        estimates = read
        return true
    }

    /// The job sheet reads one membership page at a time. A partial scan is never
    /// a complete set for creation, totals, or customer authorization.
    @discardableResult
    func loadFirstEstimatePage(scope: JobDocumentScope, api: APIClient,
                               retainExisting: Bool = false,
                               isCurrent: @escaping @MainActor () -> Bool) async -> Bool {
        guard isCurrent(), !Task.isCancelled else { return false }
        estimateRequest = UUID()
        estimatePager = JobEstimateMembershipPager(jobID: scope.jobID); estimatePagerScope = scope
        canLoadMoreEstimates = true; loadingEstimatePage = false; estimatePageError = nil; estimatePageNeedsRefresh = false
        // Retain only this job's old rows as read-only until the new first page commits.
        let retained = retainExisting && estimates?.scope == scope ? estimates : nil
        estimatePageCommitted = false
        estimates = retained.map { .init(scope: scope, records: $0.records, freshIDs: [], isComplete: false,
                                         unavailableIDs: $0.unavailableIDs, kind: "estimates") }
        return await loadNextEstimatePage(scope: scope, api: api, isCurrent: isCurrent)
    }

    @discardableResult
    func loadNextEstimatePage(scope: JobDocumentScope, api: APIClient,
                              isCurrent: @escaping @MainActor () -> Bool) async -> Bool {
        guard isCurrent(), !Task.isCancelled, !loadingEstimatePage, canLoadMoreEstimates, !estimatePageNeedsRefresh,
              estimatePagerScope == scope, let pager = estimatePager else { return false }
        let request = estimateRequest
        let current: @MainActor () -> Bool = { self.estimateRequest == request && self.estimatePagerScope == scope && isCurrent() }
        loadingEstimatePage = true; estimatePageError = nil
        defer { if estimateRequest == request { loadingEstimatePage = false } }
        var prepared: JobDocumentRead<EstimateRecord>?
        do {
            try await pager.loadNext(isCurrent: current, beforeCommit: { candidate in
                var ids = candidate.estimateIDs
                if let origin = scope.originEstimateID, !ids.contains(where: { $0.caseInsensitiveCompare(origin) == .orderedSame }) { ids.insert(origin, at: 0) }
                guard let read = await JobDocumentsLoader.estimatesForPage(scope: scope, api: api, ids: ids,
                    previous: self.estimatePageCommitted ? self.estimates : nil, membershipFresh: candidate.pagesUsedOnlyFreshResponses,
                    membershipComplete: candidate.scanReachedEnd && candidate.pagesUsedOnlyFreshResponses,
                    retainingOnFailure: self.estimatePageCommitted ? [] : (self.estimates?.records ?? []),
                    isCurrent: current), current(), !Task.isCancelled else { throw CancellationError() }
                prepared = read
            }, onCommit: { candidate in
                guard let read = prepared else { return }
                let more = !candidate.scanReachedEnd
                let healthy = candidate.pagesUsedOnlyFreshResponses && read.unavailableIDs.isEmpty && read.records.allSatisfy { read.freshIDs.contains($0.id) }
                self.estimates = .init(scope: scope, records: read.records, freshIDs: read.freshIDs,
                    isComplete: read.isComplete, unavailableIDs: read.unavailableIDs, kind: "estimates", pendingPage: more && healthy)
                self.canLoadMoreEstimates = more
                self.estimatePageCommitted = true
                self.estimatePageNeedsRefresh = !healthy
                if !healthy { self.estimatePageError = read.issue ?? "Some estimates need a refresh." }
            }) { cursor in
                let response: APIRead<JobEstimateLinkPage>
                do { response = try await SavedCopies.$liveOnly.withValue(true) {
                    try await api.fieldJobEstimateLinkPage(scope.jobID, cursor: cursor, isCurrent: current)
                } }
                catch let problem as Problem where problem.status == nil && problem.title == "Network error" {
                    response = try await api.fieldJobEstimateLinkPage(scope.jobID, cursor: cursor, isCurrent: current)
                }
                return .init(links: response.value.items, nextCursor: response.value.nextCursor,
                             isAuthoritative: response.provenance.source == .urlSession(cacheBypassed: true))
            }
            return true
        } catch {
            if estimateRequest == request && !isCurrent() { clearEstimates(); return false }
            if current() {
                if let problem = error as? Problem, problem.status == 401 || problem.status == 403 {
                    estimates = nil; estimatePager = nil; estimatePagerScope = nil; canLoadMoreEstimates = false
                }
                estimatePageError = "Couldn't load estimates. Try again."
            }
            return false
        }
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
            // OF-04: the job's invoices as last seen, so an offline closeout still counts cash and check.
            JobDetailCache.save(invoices: read.records, jobID: scope.jobID)
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
    static func currentComplete(scope: JobDocumentScope?, readScope: JobDocumentScope?, complete: Bool, authorityCurrent: Bool) -> Bool {
        guard let scope, let readScope else { return false }
        return scope == readScope && complete && authorityCurrent
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
    let approvedUnavailable: Bool

    init?(records: [EstimateRecord], complete: Bool) {
        guard complete else { return nil }
        var sums: [String: [String: Int]] = [:]
        var options = 0
        var unavailable = false
        for record in records {
            // Neither missing alternatives nor an option list identifies accepted work.
            if record.status == "approved", record.options == nil || record.options?.isEmpty == false {
                unavailable = true
                if record.options?.isEmpty == false { options += 1 }
                continue
            }
            if record.options?.isEmpty == false { options += 1; continue }
            guard ["approved", "sent"].contains(record.status) else { continue }
            let currency = record.lines.first?.unitPrice.currency ?? "USD"
            guard currency.utf8.count == 3, currency.utf8.allSatisfy({ (65...90).contains($0) }) else { return nil }
            guard let amounts = CustomerDocumentAmounts(lines: record.lines, currency: currency) else { return nil }
            let sum = (sums[record.status]?[currency] ?? 0).addingReportingOverflow(amounts.total)
            guard !sum.overflow else { return nil }
            sums[record.status, default: [:]][currency] = sum.partialValue
        }
        if unavailable { sums.removeValue(forKey: "approved") }
        amounts = sums.keys.sorted().flatMap { status in
            sums[status]!.keys.sorted().map { Amount(status: status, currency: $0, cents: sums[status]![$0]!) }
        }
        optionCount = options
        approvedUnavailable = unavailable
        if amounts.isEmpty && optionCount == 0 && !approvedUnavailable { return nil }
    }
}

struct JobDocumentRead<Record> {
    let scope: JobDocumentScope
    let records: [Record]
    /// Successfully read, identity-checked documents with a currently verified association.
    let freshIDs: Set<String>
    let isComplete: Bool
    let isLoadingMore: Bool
    let issue: String?
    /// Verified association, but no safe document contents were available to display.
    let unavailableIDs: [String]

    fileprivate init(scope: JobDocumentScope, records: [Record], freshIDs: Set<String>, isComplete: Bool,
                     unavailableIDs: [String] = [], kind: String, loadingMore: Bool = false, pendingPage: Bool = false) {
        self.scope = scope
        self.records = records
        self.freshIDs = freshIDs
        self.isComplete = isComplete
        self.isLoadingMore = loadingMore
        self.unavailableIDs = unavailableIDs
        issue = isComplete || loadingMore || pendingPage ? nil : "Couldn't load all \(kind) for this job. Some records may need a refresh."
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
    /// Actor-isolated per-index slots preserve link order even when reads finish out of order.
    @MainActor private final class EstimateDetails {
        struct Slot {
            let record: EstimateRecord?
            let fresh: Bool
            let failed: Bool
            let rejected: Bool
        }
        let ids: [String]
        let scope: JobDocumentScope
        let api: APIClient
        let retained: [EstimateRecord]
        let retainedByID: [String: EstimateRecord]
        let linksSaved: Bool
        let isCurrent: @MainActor () -> Bool
        let onPartial: @MainActor (JobDocumentRead<EstimateRecord>) -> Void
        let includeRetained: Bool
        var slots: [Slot?]
        var completed = 0

        init(ids: [String], scope: JobDocumentScope, api: APIClient, retained: [EstimateRecord],
             linksSaved: Bool, includeRetained: Bool, isCurrent: @escaping @MainActor () -> Bool,
             onPartial: @escaping @MainActor (JobDocumentRead<EstimateRecord>) -> Void) {
            self.ids = ids; self.scope = scope; self.api = api; self.retained = retained
            self.retainedByID = retained.reduce(into: [:]) { result, record in
                if result[record.id] == nil, scope.contains(record, requestedID: record.id) { result[record.id] = record }
            }
            self.linksSaved = linksSaved; self.isCurrent = isCurrent
            self.includeRetained = includeRetained; self.onPartial = onPartial
            self.slots = Array(repeating: nil, count: ids.count)
        }

        func fetch(_ index: Int) async {
            guard isCurrent(), !Task.isCancelled else { return }
            let id = ids[index]
            do {
                let response: APIRead<EstimateRecord>
                do {
                    response = try await SavedCopies.$liveOnly.withValue(true) { try await api.fieldEstimateWithProvenance(id, saveIfCurrent: isCurrent) }
                } catch let problem as Problem where problem.status == nil && problem.title == "Network error" {
                    // A previously saved record may still be shown, but never authorizes a decision.
                    guard isCurrent(), !Task.isCancelled else { return }
                    response = try await api.fieldEstimateWithProvenance(id, saveIfCurrent: isCurrent)
                }
                let record = response.value
                guard isCurrent(), !Task.isCancelled else { return }
                guard scope.contains(record, requestedID: id) else {
                    slots[index] = .init(record: nil, fresh: false, failed: true, rejected: true)
                    publishPartial(); return
                }
                let fresh: Bool
                if case .urlSession(cacheBypassed: true) = response.provenance.source { fresh = !linksSaved }
                else { fresh = false }
                slots[index] = .init(record: record, fresh: fresh, failed: false, rejected: false)
                publishPartial()
            } catch is CancellationError { return }
            catch {
                guard isCurrent(), !Task.isCancelled else { return }
                let mayRetain = JobDocumentsLoader.canRetain(after: error)
                let old = mayRetain ? retainedByID[id] : nil
                slots[index] = .init(record: old, fresh: false, failed: true, rejected: !mayRetain)
                publishPartial()
            }
        }

        private func publishPartial() {
            completed += 1
            guard completed < ids.count, (completed == 4 || completed.isMultiple(of: 20)),
                  isCurrent(), !Task.isCancelled else { return }
            var rows: [EstimateRecord] = []; var fresh = Set<String>(); var unavailable: [String] = []
            var rejected = Set<String>()
            for (index, slot) in slots.enumerated() {
                if let slot {
                    if slot.rejected { rejected.insert(ids[index]) }
                    if let record = slot.record {
                        rows.append(record); if slot.fresh { fresh.insert(record.id) }
                    } else { unavailable.append(ids[index]) }
                } else if let old = retainedByID[ids[index]] {
                    rows.append(old)
                }
            }
            if includeRetained {
                let present = Set(rows.map(\.id))
                rows += retained.filter { !present.contains($0.id) && !rejected.contains($0.id) && scope.contains($0, requestedID: $0.id) }
            }
            onPartial(.init(scope: scope, records: rows, freshIDs: fresh, isComplete: false,
                            unavailableIDs: unavailable, kind: "estimates", loadingMore: true))
        }
    }

    /// Fetch only the newly requested membership page; keep previously loaded pages in order.
    static func estimatesForPage(scope: JobDocumentScope, api: APIClient, ids: [String],
                                 previous: JobDocumentRead<EstimateRecord>?, membershipFresh: Bool,
                                 membershipComplete: Bool,
                                 retainingOnFailure: [EstimateRecord] = [],
                                 isCurrent: @escaping @MainActor () -> Bool,
                                 onPartial: @escaping @MainActor (JobDocumentRead<EstimateRecord>) -> Void = { _ in }) async -> JobDocumentRead<EstimateRecord>? {
        guard isCurrent(), !Task.isCancelled else { return nil }
        let old = previous?.scope == scope ? previous : nil
        let present = Set((old?.records.map(\.id) ?? []) + (old?.unavailableIDs ?? []))
        let incoming = unique(ids).filter { !present.contains($0) }
        let details = EstimateDetails(ids: incoming, scope: scope, api: api, retained: retainingOnFailure,
                                      linksSaved: !membershipFresh, includeRetained: false,
                                      isCurrent: isCurrent, onPartial: { page in
            guard isCurrent(), !Task.isCancelled else { return }
            let records = (old?.records ?? []) + page.records
            let fresh = membershipFresh ? (old?.freshIDs ?? []).union(page.freshIDs) : []
            onPartial(.init(scope: scope, records: records, freshIDs: fresh, isComplete: false,
                            unavailableIDs: (old?.unavailableIDs ?? []) + page.unavailableIDs,
                            kind: "estimates", loadingMore: true))
        })
        await runBoundedMainActorOperations(count: incoming.count, limit: 4) { index in await details.fetch(index) }
        guard isCurrent(), !Task.isCancelled else { return nil }
        var records = old?.records ?? []
        var fresh = old?.freshIDs ?? []
        var unavailable = old?.unavailableIDs ?? []
        var failed = false
        for (index, slot) in details.slots.enumerated() {
            guard let slot else { return nil }
            if slot.failed { failed = true }
            if let record = slot.record {
                records.append(record)
                if slot.fresh { fresh.insert(record.id) }
            } else { unavailable.append(incoming[index]) }
        }
        if !membershipFresh { fresh.removeAll() }
        return .init(scope: scope, records: records, freshIDs: fresh,
                     isComplete: membershipComplete && membershipFresh && !failed && unavailable.isEmpty &&
                         records.allSatisfy { fresh.contains($0.id) },
                     unavailableIDs: unavailable, kind: "estimates")
    }

    static func estimates(scope: JobDocumentScope, api: APIClient,
                          retaining previous: JobDocumentRead<EstimateRecord>?,
                          isCurrent: @escaping @MainActor () -> Bool,
                          onPartial: @escaping @MainActor (JobDocumentRead<EstimateRecord>) -> Void = { _ in }) async -> JobDocumentRead<EstimateRecord>? {
        guard isCurrent(), !Task.isCancelled else { return nil }
        let retained = previous?.scope == scope ? previous?.records ?? [] : []
        var ids = scope.originEstimateID.map { [$0] } ?? []
        var complete = true
        var linksRead = false
        var linksSaved = false
        do {
            let links: [JobEstimateLink]
            do {
                links = try await SavedCopies.$liveOnly.withValue(true) {
                    try await api.fieldJobEstimateLinks(scope.jobID, isCurrent: isCurrent)
                }
            } catch let problem as Problem where problem.status == nil && problem.title == "Network error" {
                guard isCurrent(), !Task.isCancelled else { return nil }
                // Offline membership is useful for reading but cannot authorize a complete set.
                links = try await api.fieldJobEstimateLinks(scope.jobID, isCurrent: isCurrent)
                linksSaved = true
                complete = false
            }
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
        let orderedIDs = unique(ids)
        let details = EstimateDetails(ids: orderedIDs, scope: scope, api: api, retained: retained,
                                      linksSaved: linksSaved, includeRetained: !linksRead,
                                      isCurrent: isCurrent, onPartial: onPartial)
        await runBoundedMainActorOperations(count: orderedIDs.count, limit: 4) { index in
            await details.fetch(index)
        }
        guard isCurrent(), !Task.isCancelled else { return nil }
        for (index, slot) in details.slots.enumerated() {
            guard let slot else { return nil }
            if slot.failed { complete = false }
            if !slot.fresh { complete = false }
            if slot.rejected { rejected.insert(orderedIDs[index]) }
            if let record = slot.record {
                records.append(record)
                if slot.fresh { fresh.insert(record.id) }
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
                if api.savedCopyDate("/v1/jobs/\(scope.jobID)/invoices") != nil {
                    // Saved on this phone: shown to read, never treated as fresh enough to collect on.
                    return invoiceRead(scope, mine, freshIDs: [], complete: mine.count == incoming.count)
                }
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
