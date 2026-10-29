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
    let photos: [CustomerJobGroup<MediaAssetRecord>]
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
        history: [CustomerHistoryEntry]
    ) -> CustomerJobCompilation {
        let jobIDs = Set(jobs.map(\.id))
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
            photos: groups { (mediaByJob[$0.id] ?? []).filter { $0.kind == "photo" && !$0.archived } },
            notes: groups { notesByJob[$0.id] ?? [] },
            documents: groups { (mediaByJob[$0.id] ?? []).filter { $0.kind != "photo" && !$0.archived } },
            estimates: groups { estimatesOn[$0.id] ?? [] },
            invoices: groups { invoicesOn[$0.id] ?? [] },
            activity: groups { activityOn[$0.id] ?? [] },
            accountActivity: account,
            estimatesOffJob: estimatesOff,
            invoicesOffJob: invoicesOff
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

/// Which money records this person is allowed to compile onto the customer.
/// Photos, notes, and documents stay available when estimates or invoices are not.
struct CustomerRecordAccess: Equatable, Sendable {
    var estimates: Bool
    var invoices: Bool
    static let all = CustomerRecordAccess(estimates: true, invoices: true)
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
    static func load(customerID: String, api: APIClient, access: CustomerRecordAccess = .all) async throws -> CustomerJobCompilation {
        let jobs = try await api.fieldJobs(customerID: customerID)
        let contacts = try await api.fieldContacts(customerID)
        let locations = try await api.fieldLocations(customerID)
        let estimates = access.estimates ? try await api.fieldEstimates(customerID: customerID) : []
        var invoices = access.invoices ? try await api.fieldInvoices(customerID: customerID) : []
        var seenInvoices = Set(invoices.map(\.id))
        var notesByJob: [String: [JobNoteRecord]] = [:]
        var mediaByJob: [String: [MediaAssetRecord]] = [:]
        var linksByJob: [String: [JobEstimateLink]] = [:]
        for job in jobs {
            notesByJob[job.id] = try await api.fieldNotes(job.id)
            mediaByJob[job.id] = try await api.fieldMedia(job.id)
            if access.estimates {
                linksByJob[job.id] = try await api.fieldJobEstimateLinks(job.id)
            }
            if access.invoices {
                for invoice in try await jobInvoices(job.id, api: api) where seenInvoices.insert(invoice.id).inserted {
                    invoices.append(invoice)
                }
            }
        }
        var history: [CustomerHistoryEntry] = []
        var cursor: String?
        var seen = Set<String>()
        repeat {
            let page = try await api.fieldCustomerHistory(customerID, cursor: cursor)
            history.append(contentsOf: page.items)
            cursor = page.nextCursor
            if let cursor, cursor.isEmpty || !seen.insert(cursor).inserted { break }
        } while cursor != nil
        return CustomerJobCompilation.assemble(
            jobs: jobs,
            contacts: contacts,
            locations: locations,
            notesByJob: notesByJob,
            mediaByJob: mediaByJob,
            estimates: estimates,
            linksByJob: linksByJob,
            invoices: invoices,
            history: history
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
