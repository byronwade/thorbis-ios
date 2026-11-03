import Foundation

/// One job's share of a customer-wide collection. Empty jobs are left out so the
/// groups a person sees are the jobs that actually hold something.
struct CustomerJobGroup<Item: Equatable>: Equatable {
    let jobID: String
    let title: String
    let items: [Item]
    var count: Int { items.count }
}

/// Photos, notes, documents, estimates, invoices, and activity gathered from every
/// job for one customer. Each list stays grouped by the job it came from.
struct CustomerJobCompilation: Equatable {
    let contacts: [CustomerContactRecord]
    let locations: [ServiceLocationRecord]
    let photos: [CustomerJobGroup<JobPhotoSource>]
    let notes: [CustomerJobGroup<JobNoteRecord>]
    let documents: [CustomerJobGroup<MediaAssetRecord>]
    let estimates: [CustomerJobGroup<EstimateRecord>]
    let invoices: [CustomerJobGroup<InvoiceRecord>]
    var activity: [CustomerJobGroup<CustomerHistoryEntry>]
    /// History that names a contact, a location, or a payment, which the customer
    /// history payload does not attach to a job.
    var accountActivity: [CustomerHistoryEntry]
    var activityCursor: String?
    var activitySeenCursors: Set<String>
    let activityJobs: [JobRecord]
    let activityEstimateJobs: [String: String]
    let activityInvoices: [String: InvoiceRecord]
    let estimatesOffJob: [EstimateRecord]
    let invoicesOffJob: [InvoiceRecord]

    /// A job media read failed or returned an asset outside that job/workspace.
    let mediaIncompleteJobIDs: Set<String>
    let documentIncompleteJobIDs: Set<String>
    let jobsAccessible: Bool
    let estimatesAccessible: Bool
    let invoicesAccessible: Bool
    let identityIncomplete: Bool
    let notesIncomplete: Bool
    let estimatesIncomplete: Bool
    let invoicesIncomplete: Bool
    var activityIncomplete: Bool

    var photoCount: Int { photos.reduce(0) { $0 + $1.count } }
    var noteCount: Int { notes.reduce(0) { $0 + $1.count } }
    var documentCount: Int { documents.reduce(0) { $0 + $1.count } }
    var estimateCount: Int { estimates.reduce(0) { $0 + $1.count } + estimatesOffJob.count }
    var invoiceCount: Int { invoices.reduce(0) { $0 + $1.count } + invoicesOffJob.count }
    var activityCount: Int { activity.reduce(0) { $0 + $1.count } }

    static func assemble(
        jobs: [JobRecord],
        contacts: [CustomerContactRecord],
        locations: [ServiceLocationRecord],
        notesByJob: [String: [JobNoteRecord]],
        mediaByJob: [String: [MediaAssetRecord]],
        estimates: [EstimateRecord],
        linksByJob: [String: [JobEstimateLink]],
        invoices: [InvoiceRecord],
        history: [CustomerHistoryEntry],
        legacyPhotosByJob: [String: [JobPhotoRecord]] = [:],
        mediaIncompleteJobIDs: Set<String> = [],
        documentIncompleteJobIDs: Set<String> = [],
        jobsAccessible: Bool = true,
        estimatesAccessible: Bool = true,
        invoicesAccessible: Bool = true,
        identityIncomplete: Bool = false,
        notesIncomplete: Bool = false,
        estimatesIncomplete: Bool = false,
        invoicesIncomplete: Bool = false,
        activityIncomplete: Bool = false,
        activityCursor: String? = nil
    ) -> CustomerJobCompilation {
        let jobIDs = Set(jobs.map(\.id))
        var incomplete = mediaIncompleteJobIDs
        var documentsIncomplete = documentIncompleteJobIDs
        var verifiedMedia: [String: [MediaAssetRecord]] = [:]
        var verifiedLegacy: [String: [JobPhotoRecord]] = [:]
        for job in jobs {
            let received = mediaByJob[job.id] ?? []
            let verified = received.filter { $0.jobId == job.id && $0.organizationId == job.organizationId }
            if verified.count != received.count { incomplete.insert(job.id); documentsIncomplete.insert(job.id) }
            verifiedMedia[job.id] = verified
            let receivedLegacy = legacyPhotosByJob[job.id] ?? []
            let legacy = verified.count == received.count ? receivedLegacy.filter { $0.jobId == job.id && $0.organizationId == job.organizationId } : []
            if legacy.count != receivedLegacy.count { incomplete.insert(job.id) }
            verifiedLegacy[job.id] = legacy
            if JobPhotoMerge.hasConflictingMetadata(modern: verified, legacy: legacy,
                                                   organizationID: job.organizationId, jobID: job.id) {
                incomplete.insert(job.id)
            }
        }
        var estimateJob: [String: String] = [:]
        for job in jobs {
            if let estimateID = job.estimateId, estimateJob[estimateID] == nil {
                estimateJob[estimateID] = job.id
            }
            for link in linksByJob[job.id] ?? [] where estimateJob[link.estimateId] == nil {
                estimateJob[link.estimateId] = job.id
            }
        }
        let invoiceByID = Dictionary(invoices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func groups<Item: Equatable>(_ items: (JobRecord) -> [Item]) -> [CustomerJobGroup<Item>] {
            jobs.compactMap { job in
                let rows = items(job)
                return rows.isEmpty ? nil : CustomerJobGroup(jobID: job.id, title: job.title, items: rows)
            }
        }

        var estimatesOn: [String: [EstimateRecord]] = [:]
        var estimatesOff: [EstimateRecord] = []
        for estimate in estimates {
            if let jobID = estimateJob[estimate.id], jobIDs.contains(jobID) {
                estimatesOn[jobID, default: []].append(estimate)
            } else {
                estimatesOff.append(estimate)
            }
        }
        var invoicesOn: [String: [InvoiceRecord]] = [:]
        var invoicesOff: [InvoiceRecord] = []
        for invoice in invoices {
            if let jobID = invoice.jobId, jobIDs.contains(jobID) {
                invoicesOn[jobID, default: []].append(invoice)
            } else {
                invoicesOff.append(invoice)
            }
        }
        var activityOn: [String: [CustomerHistoryEntry]] = [:]
        var account: [CustomerHistoryEntry] = []
        for entry in history {
            if let jobID = jobID(for: entry, jobs: jobIDs, estimateJob: estimateJob, invoices: invoiceByID) {
                activityOn[jobID, default: []].append(entry)
            } else {
                account.append(entry)
            }
        }
        return CustomerJobCompilation(
            contacts: contacts,
            locations: locations,
            photos: groups { job in
                JobPhotoMerge.combine(modern: verifiedMedia[job.id] ?? [], legacy: verifiedLegacy[job.id] ?? [],
                                      organizationID: job.organizationId, jobID: job.id)
            },
            notes: groups { notesByJob[$0.id] ?? [] },
            documents: groups { (verifiedMedia[$0.id] ?? []).filter { $0.kind != "photo" && !$0.archived } },
            estimates: groups { estimatesOn[$0.id] ?? [] },
            invoices: groups { invoicesOn[$0.id] ?? [] },
            activity: groups { activityOn[$0.id] ?? [] },
            accountActivity: account,
            activityCursor: activityCursor?.isEmpty == false ? activityCursor : nil,
            activitySeenCursors: Set(activityCursor.flatMap { $0.isEmpty ? nil : $0 }.map { [$0] } ?? []),
            activityJobs: jobs,
            activityEstimateJobs: estimateJob,
            activityInvoices: invoiceByID,
            estimatesOffJob: estimatesOff,
            invoicesOffJob: invoicesOff,
            mediaIncompleteJobIDs: incomplete,
            documentIncompleteJobIDs: documentsIncomplete,
            jobsAccessible: jobsAccessible,
            estimatesAccessible: estimatesAccessible,
            invoicesAccessible: invoicesAccessible,
            identityIncomplete: identityIncomplete,
            notesIncomplete: notesIncomplete,
            estimatesIncomplete: estimatesIncomplete,
            invoicesIncomplete: invoicesIncomplete,
            activityIncomplete: activityIncomplete || activityCursor == ""
        )
    }

    /// Add one accepted page without reloading the customer's other records.
    /// Identical visible events may be distinct: the server omits event IDs.
    mutating func appendActivityPage(_ page: CustomerHistoryPage) {
        let invalidContinuation = page.nextCursor.map { $0.isEmpty || activitySeenCursors.contains($0) } ?? false
        var byJob: [String: [CustomerHistoryEntry]] = [:]
        for group in activity { byJob[group.jobID, default: []].append(contentsOf: group.items) }
        let jobIDs = Set(activityJobs.map(\.id))
        for entry in page.items {
            if let id = Self.jobID(for: entry, jobs: jobIDs, estimateJob: activityEstimateJobs, invoices: activityInvoices) {
                byJob[id, default: []].append(entry)
            } else {
                accountActivity.append(entry)
            }
        }
        activity = activityJobs.compactMap { job in
            guard let entries = byJob[job.id], !entries.isEmpty else { return nil }
            return CustomerJobGroup(jobID: job.id, title: job.title, items: entries)
        }
        activityCursor = invalidContinuation ? nil : page.nextCursor
        if invalidContinuation { activityIncomplete = true }
        else if let next = page.nextCursor { activitySeenCursors.insert(next) }
    }

    static func jobID(
        for entry: CustomerHistoryEntry,
        jobs: Set<String>,
        estimateJob: [String: String],
        invoices: [String: InvoiceRecord]
    ) -> String? {
        switch entry.kind {
        case "job":
            return jobs.contains(entry.subjectId) ? entry.subjectId : nil
        case "estimate":
            return estimateJob[entry.subjectId]
        case "invoice":
            if let jobID = invoices[entry.subjectId]?.jobId, jobs.contains(jobID) { return jobID }
            return nil
        default:
            return nil
        }
    }
}

/// Which collections this person is allowed to compile onto the customer.
/// Customer estimates, invoices, and history still load when jobs are closed.
/// Photos, notes, and documents stay available when estimates or invoices are not.
struct CustomerRecordAccess: Equatable, Sendable {
    var jobs: Bool
    var estimates: Bool
    var invoices: Bool

    init(jobs: Bool = true, estimates: Bool, invoices: Bool) {
        self.jobs = jobs
        self.estimates = estimates
        self.invoices = invoices
    }

    static let all = CustomerRecordAccess(jobs: true, estimates: true, invoices: true)
}

/// The invoice name used on the customer record. The status alone collides when two invoices share it.
enum CustomerRecordLabel {
    static func invoice(_ invoice: InvoiceRecord) -> String {
        "INV-\(invoice.id.suffix(4).uppercased()) · \(invoice.status.statusLabel)"
    }
}

@MainActor
enum CustomerJobCompilationLoader {
    /// Loads the customer's jobs, then each job's notes, media, and the estimate links and invoices
    /// this person can read. There is no customer-wide media or notes route; the groups are built from the job routes.
    static func load(customerID: String, organizationID: String, api: APIClient,
                     access: CustomerRecordAccess = .all,
                     isCurrent: @escaping @MainActor @Sendable () -> Bool = { true }) async throws -> CustomerJobCompilation {
        let requestGeneration = api.requestGeneration
        try requireCurrent(api, generation: requestGeneration, isCurrent: isCurrent)
        let receivedJobs = access.jobs ? try await api.fieldJobs(customerID: customerID, isCurrent: isCurrent) : []
        try requireCurrent(api, generation: requestGeneration, isCurrent: isCurrent)
        let jobs = receivedJobs.filter { $0.customerId == customerID && $0.organizationId == organizationID }
        let receivedContacts = try await api.fieldContacts(customerID)
        try requireCurrent(api, generation: requestGeneration, isCurrent: isCurrent)
        let contacts = receivedContacts.filter { $0.customerId == customerID && $0.organizationId == organizationID }
        let receivedLocations = try await api.fieldLocations(customerID)
        try requireCurrent(api, generation: requestGeneration, isCurrent: isCurrent)
        let locations = receivedLocations.filter { $0.customerId == customerID && $0.organizationId == organizationID }
        let identityIncomplete = jobs.count != receivedJobs.count || contacts.count != receivedContacts.count || locations.count != receivedLocations.count
        let receivedEstimates = access.estimates ? try await api.fieldEstimates(customerID: customerID, isCurrent: isCurrent) : []
        try requireCurrent(api, generation: requestGeneration, isCurrent: isCurrent)
        let estimates = receivedEstimates.filter { $0.customerId == customerID && $0.organizationId == organizationID }
        var estimatesIncomplete = estimates.count != receivedEstimates.count
        let receivedInvoices = access.invoices ? try await api.fieldInvoices(customerID: customerID, isCurrent: isCurrent) : []
        try requireCurrent(api, generation: requestGeneration, isCurrent: isCurrent)
        var invoices = receivedInvoices.filter { $0.customerId == customerID && $0.organizationId == organizationID }
        var invoicesIncomplete = invoices.count != receivedInvoices.count
        var notesIncomplete = false
        let estimateIDs = Set(estimates.map(\.id))
        var seenInvoices = Set(invoices.map(\.id))
        var notesByJob: [String: [JobNoteRecord]] = [:]
        var mediaByJob: [String: [MediaAssetRecord]] = [:]
        var linksByJob: [String: [JobEstimateLink]] = [:]
        var mediaIncompleteJobIDs = Set<String>()
        var documentIncompleteJobIDs = Set<String>()
        try requireCurrent(api, generation: requestGeneration, isCurrent: isCurrent)
        let jobReads = try await mapJobs(jobs) { job in
            try requireCurrent(api, generation: requestGeneration, isCurrent: isCurrent)
            return try await readJob(job, api: api, access: access, generation: requestGeneration, isCurrent: isCurrent)
        }
        for (job, read) in zip(jobs, jobReads) {
            let notes = read.notes.filter { $0.organizationId == organizationID && $0.jobId == job.id }
            if notes.count != read.notes.count { notesIncomplete = true }
            notesByJob[job.id] = notes
            if let media = read.media {
                mediaByJob[job.id] = media
            } else {
                mediaIncompleteJobIDs.insert(job.id)
                documentIncompleteJobIDs.insert(job.id)
            }
            let links = read.links.filter { $0.jobId == job.id && estimateIDs.contains($0.estimateId) }
            if links.count != read.links.count { estimatesIncomplete = true }
            if access.estimates { linksByJob[job.id] = links }
            for invoice in read.invoices {
                guard invoice.organizationId == organizationID && invoice.customerId == customerID && invoice.jobId == job.id else {
                    invoicesIncomplete = true
                    continue
                }
                if seenInvoices.insert(invoice.id).inserted { invoices.append(invoice) }
            }
        }
        try requireCurrent(api, generation: requestGeneration, isCurrent: isCurrent)
        let history = try await api.fieldCustomerHistory(customerID)
        try requireCurrent(api, generation: requestGeneration, isCurrent: isCurrent)
        var legacyPhotosByJob: [String: [JobPhotoRecord]] = [:]
        // Only an archived-inclusive media read permits a legacy photo fallback.
        let photoJobs = jobs.filter { mediaByJob[$0.id] != nil }
        let photoReads = try await mapJobs(photoJobs) { job in
            try requireCurrent(api, generation: requestGeneration, isCurrent: isCurrent)
            do {
                let photos = try await api.fieldPhotos(job.id)
                try requireCurrent(api, generation: requestGeneration, isCurrent: isCurrent)
                return PhotoRead(photos: photos)
            } catch is CancellationError {
                throw CancellationError()
            } catch let problem as Problem where problem.status == 401 {
                throw problem
            } catch {
                return PhotoRead(photos: nil)
            }
        }
        for (job, read) in zip(photoJobs, photoReads) {
            if let photos = read.photos { legacyPhotosByJob[job.id] = photos }
            else { mediaIncompleteJobIDs.insert(job.id) }
        }
        try requireCurrent(api, generation: requestGeneration, isCurrent: isCurrent)
        return CustomerJobCompilation.assemble(
            jobs: jobs,
            contacts: contacts,
            locations: locations,
            notesByJob: notesByJob,
            mediaByJob: mediaByJob,
            estimates: estimates,
            linksByJob: linksByJob,
            invoices: invoices,
            history: history.items,
            legacyPhotosByJob: legacyPhotosByJob,
            mediaIncompleteJobIDs: mediaIncompleteJobIDs,
            documentIncompleteJobIDs: documentIncompleteJobIDs,
            jobsAccessible: access.jobs,
            estimatesAccessible: access.estimates,
            invoicesAccessible: access.invoices,
            identityIncomplete: identityIncomplete,
            notesIncomplete: notesIncomplete,
            estimatesIncomplete: estimatesIncomplete,
            invoicesIncomplete: invoicesIncomplete,
            activityCursor: history.nextCursor
        )
    }

    /// Results are merged in the original job order, regardless of completion order.
    /// Keep the fan-out bounded so a large customer cannot flood the service.
    private static func mapJobs<Value: Sendable>(
        _ jobs: [JobRecord],
        operation: @escaping @MainActor @Sendable (JobRecord) async throws -> Value
    ) async throws -> [Value] {
        // Small profiles do not need parallel fan-out.
        if jobs.count <= 2 {
            var values: [Value] = []
            for job in jobs { try Task.checkCancellation(); values.append(try await operation(job)) }
            return values
        }
        return try await withThrowingTaskGroup(of: (Int, Value).self) { group in
            var next = 0
            var values: [(Int, Value)] = []
            func submit(_ index: Int) {
                let job = jobs[index]
                group.addTask { (index, try await operation(job)) }
            }
            while next < min(4, jobs.count) { submit(next); next += 1 }
            while let result = try await group.next() {
                try Task.checkCancellation()
                values.append(result)
                if next < jobs.count { submit(next); next += 1 }
            }
            return values.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    // DTO snapshots cross the task-group boundary; API calls remain main-actor isolated.
    private struct JobRead: Sendable {
        let notes: [JobNoteRecord]
        let media: [MediaAssetRecord]?
        let links: [JobEstimateLink]
        let invoices: [InvoiceRecord]
    }
    private struct PhotoRead: Sendable { let photos: [JobPhotoRecord]? }

    private static func requireCurrent(_ api: APIClient, generation: UUID, isCurrent: @MainActor () -> Bool) throws {
        try Task.checkCancellation()
        guard api.requestGeneration == generation, isCurrent() else { throw CancellationError() }
    }

    private static func readJob(_ job: JobRecord, api: APIClient, access: CustomerRecordAccess, generation: UUID,
                                isCurrent: @MainActor () -> Bool) async throws -> JobRead {
        try requireCurrent(api, generation: generation, isCurrent: isCurrent)
        let notes = try await api.fieldNotes(job.id)
        try requireCurrent(api, generation: generation, isCurrent: isCurrent)
        let media: [MediaAssetRecord]?
        do { media = try await api.fieldMedia(job.id, includeArchived: true, isCurrent: isCurrent) }
        catch is CancellationError { throw CancellationError() }
        catch let problem as Problem where problem.status == 401 { throw problem }
        catch { media = nil }
        try requireCurrent(api, generation: generation, isCurrent: isCurrent)
        let links = access.estimates ? try await api.fieldJobEstimateLinks(job.id, isCurrent: isCurrent) : []
        try requireCurrent(api, generation: generation, isCurrent: isCurrent)
        let invoices = access.invoices ? try await jobInvoices(job.id, api: api, isCurrent: isCurrent) : []
        try requireCurrent(api, generation: generation, isCurrent: isCurrent)
        return JobRead(notes: notes, media: media, links: links, invoices: invoices)
    }

    /// The organization invoice list is empty for a technician who can still read the job.
    /// A server without this route (404 or 405) keeps the customer list. Any other failure still fails the load.
    private static func jobInvoices(_ jobID: String, api: APIClient, isCurrent: @MainActor () -> Bool) async throws -> [InvoiceRecord] {
        do {
            return try await api.fieldJobInvoices(jobID, isCurrent: isCurrent)
        } catch let problem as Problem where problem.status == 404 || problem.status == 405 {
            return []
        }
    }
}
