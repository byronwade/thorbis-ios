import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// What Spotlight may show for the signed-in person and workspace: job titles with their customer,
/// status and visit time, and customer names. Never notes, money or phone numbers.
/// Pure so the scoping rules can be tested without the system index.
enum SpotlightCatalog {
    struct Entry: Equatable {
        let identifier: String
        let title: String
        let detail: String
        let keywords: [String]
    }

    enum Target: Equatable {
        case job(String)
        case customer(String)
    }

    /// One domain per person and workspace, lowercased like `RecentItems`' owner key.
    static func scope(actorID: String?, organizationID: String?) -> String? {
        guard let actorID, let organizationID, !actorID.isEmpty, !organizationID.isEmpty else { return nil }
        return "thorbis.\(actorID.lowercased())|\(organizationID.lowercased())"
    }

    static func identifier(_ target: Target, scope: String) -> String {
        switch target {
        case .job(let id): "\(scope)#job#\(id)"
        case .customer(let id): "\(scope)#customer#\(id)"
        }
    }

    /// The record a tapped result names, only when it belongs to the current person and workspace.
    /// Deletion is asynchronous, so a result from a previous identity can still be tapped.
    static func target(identifier: String, scope: String?) -> Target? {
        guard let scope else { return nil }
        let parts = identifier.components(separatedBy: "#")
        guard parts.count == 3, parts[0] == scope, !parts[2].isEmpty else { return nil }
        switch parts[1] {
        case "job": return .job(parts[2])
        case "customer": return .customer(parts[2])
        default: return nil
        }
    }

    /// `streets` maps a job id to the street of its own service location: those jobs are titled
    /// street first, with the problem kept in the detail and keywords so it still matches.
    static func entries(jobs: [Job], customers: [Customer], scope: String?,
                        includeJobs: Bool, includeCustomers: Bool, streets: [String: String] = [:],
                        timeZone: TimeZone = .current, locale: Locale = .current) -> [Entry] {
        guard let scope else { return [] }
        var entries: [Entry] = []
        if includeJobs {
            let names = Dictionary(customers.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            for job in jobs {
                let customer = job.customerId.flatMap { names[$0] }
                let status = job.status.statusLabel
                let time = visitTime(job.scheduledFor, timeZone: timeZone, locale: locale)
                let street = streets[job.id]
                let detail = [street == nil ? nil : job.title, customer, status, time].compactMap { $0 }.filter { !$0.isEmpty }
                    .joined(separator: " · ")
                let keywords = [street == nil ? nil : job.title, customer, status, job.shortRef, "job"].compactMap { $0 }
                entries.append(Entry(identifier: identifier(.job(job.id), scope: scope), title: street ?? job.title, detail: detail,
                                     keywords: keywords))
            }
        }
        if includeCustomers {
            for customer in customers where customer.archived != true {
                entries.append(Entry(identifier: identifier(.customer(customer.id), scope: scope), title: customer.name,
                                     detail: "Customer", keywords: ["customer"]))
            }
        }
        return entries
    }

    /// An absolute time ("Oct 31 at 9:00 AM"): the index is rebuilt on refresh, so "Today" would go stale.
    static func visitTime(_ raw: String?, timeZone: TimeZone, locale: Locale) -> String? {
        guard let date = JobFiltering.date(raw) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMdjmm")
        return formatter.string(from: date)
    }
}

/// Keeps Core Spotlight in step with the verified identity: only one workspace is ever indexed,
/// everything is deleted on sign-out or a workspace switch, and each refresh replaces the items.
@MainActor
final class SpotlightIndex {
    static let shared = SpotlightIndex()

    /// Routes a tapped result; set by the app to the store's request properties.
    var onOpen: ((SpotlightCatalog.Target) -> Void)?
    private(set) var scope: String?
    private var pending: String?
    private var queue: Task<Void, Never>?
    private let scopeKey = "thorbis.spotlight.scope"
    private var enabled: Bool {
        #if DEBUG
        !PaperPreview.enabled
        #else
        true
        #endif
    }

    private init() {}

    func bind(actorID: String?, organizationID: String?) {
        let next = SpotlightCatalog.scope(actorID: actorID, organizationID: organizationID)
        // Another person or workspace: never re-index the previous one's lists or streets.
        if next != scope { last = nil; streets = [:] }
        guard enabled else { scope = next; return }
        let indexed = UserDefaults.standard.string(forKey: scopeKey)
        scope = next
        if next == nil || next != indexed {
            UserDefaults.standard.removeObject(forKey: scopeKey)
            enqueue { try? await CSSearchableIndex.default().deleteAllSearchableItems() }
        }
        if let pending {
            self.pending = nil
            if let target = SpotlightCatalog.target(identifier: pending, scope: next) { onOpen?(target) }
        }
    }

    func clear() {
        scope = nil
        pending = nil
        streets = [:]
        last = nil
        UserDefaults.standard.removeObject(forKey: scopeKey)
        guard enabled else { return }
        enqueue { try? await CSSearchableIndex.default().deleteAllSearchableItems() }
    }

    /// Streets of today's jobs, read from their own service locations; titles lead with them.
    private var streets: [String: String] = [:]
    private var last: (jobs: [Job], customers: [Customer], includeJobs: Bool, includeCustomers: Bool)?

    /// New street lines arrived: re-index the last lists with them.
    func update(streets: [String: String]) {
        guard streets != self.streets else { return }
        self.streets = streets
        if let last { replace(jobs: last.jobs, customers: last.customers, includeJobs: last.includeJobs, includeCustomers: last.includeCustomers) }
    }

    func replace(jobs: [Job], customers: [Customer], includeJobs: Bool, includeCustomers: Bool) {
        guard enabled, let scope else { return }
        last = (jobs, customers, includeJobs, includeCustomers)
        let items = SpotlightCatalog.entries(jobs: jobs, customers: customers, scope: scope,
                                             includeJobs: includeJobs, includeCustomers: includeCustomers,
                                             streets: streets).map { entry in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = entry.title
            attributes.contentDescription = entry.detail
            attributes.keywords = entry.keywords
            return CSSearchableItem(uniqueIdentifier: entry.identifier, domainIdentifier: scope, attributeSet: attributes)
        }
        enqueue { [weak self] in
            guard let self, self.scope == scope else { return }
            let index = CSSearchableIndex.default()
            try? await index.deleteSearchableItems(withDomainIdentifiers: [scope])
            // A sign-out or switch while deleting wins; its delete-all is queued behind this.
            guard self.scope == scope else { return }
            if (try? await index.indexSearchableItems(items)) != nil, self.scope == scope {
                UserDefaults.standard.set(scope, forKey: self.scopeKey)
            }
        }
    }

    /// A tapped result. Waits for the session to verify who is signed in on a cold launch.
    func open(identifier: String) {
        guard let scope else { pending = identifier; return }
        if let target = SpotlightCatalog.target(identifier: identifier, scope: scope) { onOpen?(target) }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task { @MainActor in await previous?.value; await work() }
    }
}
