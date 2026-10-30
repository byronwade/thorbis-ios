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
    let activity: [CustomerJobGroup<CustomerHistoryEntry>]
    /// History that names a contact, a location, or a payment, which the customer
    /// history payload does not attach to a job.
    let accountActivity: [CustomerHistoryEntry]
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
    let activityIncomplete: Bool

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
        activityIncomplete: Bool = false
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
            activityIncomplete: activityIncomplete
        )
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
    static func load(customerID: String, organizationID: String, api: APIClient, access: CustomerRecordAccess = .all) async throws -> CustomerJobCompilation {
        let receivedJobs = access.jobs ? try await api.fieldJobs(customerID: customerID) : []
        let jobs = receivedJobs.filter { $0.customerId == customerID && $0.organizationId == organizationID }
        let receivedContacts = try await api.fieldContacts(customerID)
        let contacts = receivedContacts.filter { $0.customerId == customerID && $0.organizationId == organizationID }
        let receivedLocations = try await api.fieldLocations(customerID)
        let locations = receivedLocations.filter { $0.customerId == customerID && $0.organizationId == organizationID }
        let identityIncomplete = jobs.count != receivedJobs.count || contacts.count != receivedContacts.count || locations.count != receivedLocations.count
        let receivedEstimates = access.estimates ? try await api.fieldEstimates(customerID: customerID) : []
        let estimates = receivedEstimates.filter { $0.customerId == customerID && $0.organizationId == organizationID }
        var estimatesIncomplete = estimates.count != receivedEstimates.count
        let receivedInvoices = access.invoices ? try await api.fieldInvoices(customerID: customerID) : []
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
        for job in jobs {
            let receivedNotes = try await api.fieldNotes(job.id)
            let notes = receivedNotes.filter { $0.organizationId == organizationID && $0.jobId == job.id }
            if notes.count != receivedNotes.count { notesIncomplete = true }
            notesByJob[job.id] = notes
            do {
                mediaByJob[job.id] = try await api.fieldMedia(job.id, includeArchived: true)
            } catch is CancellationError {
                throw CancellationError()
            } catch let problem as Problem where problem.status == 401 {
                throw problem
            } catch {
                mediaIncompleteJobIDs.insert(job.id)
                documentIncompleteJobIDs.insert(job.id)
            }
            if access.estimates {
                let receivedLinks = try await api.fieldJobEstimateLinks(job.id)
                let links = receivedLinks.filter { $0.jobId == job.id && estimateIDs.contains($0.estimateId) }
                if links.count != receivedLinks.count { estimatesIncomplete = true }
                linksByJob[job.id] = links
            }
            if access.invoices {
                for invoice in try await jobInvoices(job.id, api: api) {
                    guard invoice.organizationId == organizationID && invoice.customerId == customerID && invoice.jobId == job.id else {
                        invoicesIncomplete = true
                        continue
                    }
                    if seenInvoices.insert(invoice.id).inserted { invoices.append(invoice) }
                }
            }
        }
        var history: [CustomerHistoryEntry] = []
        var cursor: String?
        var seen = Set<String>()
        var activityIncomplete = false
        repeat {
            let page = try await api.fieldCustomerHistory(customerID, cursor: cursor)
            history.append(contentsOf: page.items)
            cursor = page.nextCursor
            if let cursor, cursor.isEmpty || !seen.insert(cursor).inserted {
                activityIncomplete = true
                break
            }
        } while cursor != nil
        var legacyPhotosByJob: [String: [JobPhotoRecord]] = [:]
        for job in jobs {
            // Without the archived-inclusive list, a legacy row could resurrect an archived photo.
            guard mediaByJob[job.id] != nil else { continue }
            do {
                legacyPhotosByJob[job.id] = try await api.fieldPhotos(job.id)
            } catch is CancellationError {
                throw CancellationError()
            } catch let problem as Problem where problem.status == 401 {
                throw problem
            } catch {
                mediaIncompleteJobIDs.insert(job.id)
            }
        }
        return CustomerJobCompilation.assemble(
            jobs: jobs,
            contacts: contacts,
            locations: locations,
            notesByJob: notesByJob,
            mediaByJob: mediaByJob,
            estimates: estimates,
            linksByJob: linksByJob,
            invoices: invoices,
            history: history,
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
            activityIncomplete: activityIncomplete
        )
    }

    /// The organization invoice list is empty for a technician who can still read the job.
    /// A server without this route (404 or 405) keeps the customer list. Any other failure still fails the load.
    private static func jobInvoices(_ jobID: String, api: APIClient) async throws -> [InvoiceRecord] {
        do {
            return try await api.fieldJobInvoices(jobID)
        } catch let problem as Problem where problem.status == 404 || problem.status == 405 {
            return []
        }
    }
}
