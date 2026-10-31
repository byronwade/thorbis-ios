import SwiftUI
import UIKit

// MARK: - Server Search Gateway

/// One result from the server's Search Gateway (`GET /v1/search`, packages/query SearchResult).
struct ServerSearchResult: Decodable, Identifiable, Hashable {
    struct Highlight: Decodable, Hashable {
        let field: String
        let snippet: String
    }
    let sourceId: String
    let resultType: String
    let entityId: String
    let title: String
    let subtitle: String?
    let status: String?
    /// Which fields matched (schema 2). Optional so an older gateway still decodes.
    var highlights: [Highlight]? = nil
    var id: String { "\(sourceId):\(entityId)" }
}

struct ServerSearchPage: Decodable {
    let items: [ServerSearchResult]
    let nextCursor: String?
    let completeness: String?
}

extension APIClient {
    /// The Search Gateway pages with `nextCursor`. Keep asking until it stops, and refuse a blank or repeated cursor.
    func search(_ query: String, limit: Int = 25) async throws -> ServerSearchPage {
        let generation = requestGeneration
        var items: [ServerSearchResult] = []
        var cursor: String?
        var seen = Set<String>()
        var completeness: String?
        let queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(limit))]
        repeat {
            try Task.checkCancellation()
            guard generation == requestGeneration else { throw CancellationError() }
            let page: ServerSearchPage = try await send("GET", "/v1/search", queryItems: queryItems, cursor: cursor)
            items.append(contentsOf: page.items)
            completeness = page.completeness
            cursor = page.nextCursor
            if let cursor, cursor.isEmpty || !seen.insert(cursor).inserted {
                throw Problem(title: "Pagination cursor loop", status: nil, detail: "Repeated or empty cursor")
            }
        } while cursor != nil
        return ServerSearchPage(items: items, nextCursor: nil, completeness: completeness)
    }
}

// MARK: - Where results lead

/// What the bottom search leads with before anything is typed: records of the place showing.
enum SearchFocus: Equatable {
    case jobs, customers, none

    /// The bar's current place (a `MenuItem` raw value) to the records it is about.
    static func of(place: String?) -> SearchFocus {
        switch place.flatMap(MenuItem.init(rawValue:)) {
        case .jobs, .schedule, .attention, .home: .jobs
        case .customers: .customers
        default: .none
        }
    }

    /// Recently opened records split into the place's kind first and everything else after, each
    /// keeping its newest-first order. With no focus, everything is "rest" in the original order.
    func split(_ items: [RecentItems.Item]) -> (relevant: [RecentItems.Item], rest: [RecentItems.Item]) {
        let kind: RecentItems.Item.Kind? = switch self { case .jobs: .job; case .customers: .customer; case .none: nil }
        guard let kind else { return ([], items) }
        return (items.filter { $0.kind == kind }, items.filter { $0.kind != kind })
    }
}

/// Where a search result leads, for callers that push it themselves.
enum SearchDestination {
    case job(Job)
    case customer(Customer)
    case route(PaperRoute)
}

/// Something search can start instead of open: a create, Settings, or a place. The host builds
/// these from what it already offers this person (its + menu, its places), so search never
/// widens what a role may do.
struct SearchAction: Identifiable {
    let id: String
    let title: String
    var subtitle: String? = nil
    let symbol: String
    /// Lower-case words that find it ("book", "new job").
    let keywords: [String]
    let run: () -> Void

    /// Typed words that begin one of its keywords, or the whole keyword. Two letters at least.
    func matches(_ text: String) -> Bool {
        let typed = text.lowercased()
        guard typed.count >= 2 else { return false }
        return keywords.contains { $0.hasPrefix(typed) || (typed.count >= 4 && $0.contains(typed)) }
            || title.lowercased().hasPrefix(typed)
    }

    func isExact(_ text: String) -> Bool {
        let typed = text.lowercased()
        return keywords.contains(typed) || title.lowercased() == typed
    }

    /// The creates, Settings and places every search host offers, gated by the host's own lists.
    static func standard(creates: [(title: String, symbol: String, run: () -> Void)], settings: (() -> Void)?,
                         places: [MenuItem], openPlace: @escaping (MenuItem) -> Void) -> [SearchAction] {
        var actions: [SearchAction] = creates.map { create in
            switch create.title {
            case "New job":
                SearchAction(id: "new-job", title: "Book a job", subtitle: "New job", symbol: create.symbol,
                             keywords: ["book", "book a job", "book job", "new job", "create job", "add job"], run: create.run)
            case "New estimate":
                SearchAction(id: "new-estimate", title: "New estimate", symbol: create.symbol,
                             keywords: ["new estimate", "create estimate", "estimate", "quote", "new quote"], run: create.run)
            case "New customer":
                SearchAction(id: "new-customer", title: "New customer", symbol: create.symbol,
                             keywords: ["new customer", "add customer", "create customer", "customer", "new client"], run: create.run)
            default:
                SearchAction(id: create.title, title: create.title, symbol: create.symbol, keywords: [create.title.lowercased()], run: create.run)
            }
        }
        if let settings {
            actions.append(SearchAction(id: "settings", title: "Settings", subtitle: "Account, appearance and sign out",
                                        symbol: "gearshape", keywords: ["settings", "preferences", "account", "sign out", "log out", "profile"],
                                        run: settings))
        }
        actions += places.map { place in
            SearchAction(id: "place-\(place.rawValue)", title: place.title, subtitle: place.subtitle ?? "Go to \(place.title)",
                         symbol: place.symbol, keywords: place.searchKeywords, run: { openPlace(place) })
        }
        return actions
    }
}

extension MenuItem {
    /// Words a tech might type to go to this place.
    var searchKeywords: [String] {
        var words = [title.lowercased(), tabTitle.lowercased()]
        switch self {
        case .schedule: words += ["today", "my day", "calendar"]
        case .money: words += ["revenue"]
        case .attention: words += ["overdue", "unpaid"]
        case .priceBook: words += ["pricebook", "catalog", "parts"]
        case .team: words += ["permissions", "people"]
        default: break
        }
        return words
    }
}

// MARK: - Matching

/// What was typed, in the shapes a tech types it: words, and the digits of a phone or number.
struct SearchTerms: Equatable {
    let text: String
    let words: [String]
    let digits: String
    /// Only digits and phone punctuation ("(916) 555-0412", "5550412"), with three digits at least.
    let phoneShaped: Bool

    init(_ raw: String) {
        text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        digits = text.filter(\.isNumber)
        let punctuation = Set("()-+. ")
        phoneShaped = digits.count >= 3 && text.allSatisfy { $0.isNumber || punctuation.contains($0) }
    }

    var isEmpty: Bool { text.isEmpty }

    /// Every typed word appears in one of the fields.
    func matches(_ fields: [String?]) -> Bool {
        !words.isEmpty && words.allSatisfy { word in fields.contains { Self.field($0, has: word) } }
    }

    /// One or two letters ("AC") must start a word, so "backup" doesn't answer "ac"; longer
    /// words match anywhere ("birch" in "Birchwood").
    static func field(_ field: String?, has word: String) -> Bool {
        guard let field else { return false }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        guard word.count <= 2 else { return field.range(of: word, options: options) != nil }
        return field.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0.range(of: word, options: options.union(.anchored)) != nil }
    }

    /// The typed digits run through the phone number, whatever its formatting.
    func matchesPhone(_ phone: String?) -> Bool {
        guard phoneShaped, let phone else { return false }
        return phone.filter(\.isNumber).contains(digits)
    }

    /// The whole number, ignoring the country code: what makes a phone match certain.
    func isWholePhone(_ phone: String?) -> Bool {
        guard phoneShaped, digits.count >= 7, let phone else { return false }
        let number = phone.filter(\.isNumber)
        // A local seven-digit number, or the whole number with or without its country code.
        return number == digits || (number.count > digits.count && number.hasSuffix(digits))
            || (digits.count > number.count && digits.hasSuffix(number) && number.count >= 10)
    }

    /// "JOB-2214", "job 2214" or "2214" for a record number.
    func isReference(_ reference: String) -> Bool {
        let typed = text.uppercased().replacingOccurrences(of: " ", with: "-")
        if typed == reference.uppercased() { return true }
        guard let number = reference.split(separator: "-").last else { return false }
        return typed == String(number) && typed.count >= 4
    }

    /// Words worth marking in a row; a phone's digits are matched across formatting, so not marked.
    var marks: [String] { phoneShaped ? [] : words }
}

/// One row search can show: what it is, how it reads, where it leads.
struct SearchHit: Identifiable {
    enum Target {
        case open(SearchDestination)
        case run(SearchAction)
        /// A result the phone has no screen for (help, settings pages, payments): shown, not opened.
        case none
    }
    let id: String
    var leading: PaperRowLeading = .none
    let title: String
    var subtitle: String? = nil
    var status: StatusWord? = nil
    var amount: String? = nil
    var dimmed = false
    let target: Target
}

struct SearchGroup: Identifiable {
    let id: String
    let title: String
    var hits: [SearchHit]
}

struct SearchResults {
    var top: SearchHit?
    var groups: [SearchGroup] = []
    var all: [SearchHit] { (top.map { [$0] } ?? []) + groups.flatMap(\.hits) }
    var isEmpty: Bool { top == nil && groups.allSatisfy(\.hits.isEmpty) }
}

/// Builds grouped results from the server's answer and what this phone already holds. Pure, so
/// what a search shows depends only on its inputs.
@MainActor
struct SearchResultsBuilder {
    let terms: SearchTerms
    let jobs: [Job]
    let customers: [Customer]
    let customerRecords: [CustomerRecord]
    let estimates: [EstimateRecord]
    let invoices: [InvoiceRecord]
    let street: (Job) -> String?
    let server: [ServerSearchResult]?
    let phoneMatch: Customer?
    let actions: [SearchAction]
    let canJobs: Bool
    let canCustomers: Bool
    let canEstimates: Bool
    let canInvoices: Bool

    private func customerName(_ id: String?) -> String {
        customers.first { $0.id == id }?.name ?? customerRecords.first { $0.id == id }?.name ?? "Customer"
    }
    private func record(_ id: String?) -> CustomerRecord? { customerRecords.first { $0.id == id } }

    // MARK: Rows

    func jobHit(_ job: Job) -> SearchHit {
        let place = street(job)
        let customer = customerName(job.customerId)
        // Street first (BYR-1593): the problem follows; with no site the job title leads.
        let subtitle = place == nil ? "\(customer) · \(job.shortRef)" : "\(job.title) · \(customer) · \(job.shortRef)"
        return SearchHit(id: "job:\(job.id)", title: place ?? job.title, subtitle: subtitle,
                         status: StatusWord(jobStatus: job.status), dimmed: ["completed", "canceled"].contains(job.status),
                         target: .open(.job(job)))
    }

    func customerHit(_ customer: Customer) -> SearchHit {
        let record = record(customer.id)
        let detail = [record?.phone, record?.address].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        return SearchHit(id: "customer:\(customer.id)", title: customer.name, subtitle: detail.isEmpty ? nil : detail,
                         target: .open(.customer(customer)))
    }

    func estimateHit(_ estimate: EstimateRecord) -> SearchHit {
        SearchHit(id: "estimate:\(estimate.id)", title: estimate.title,
                  subtitle: "\(customerName(estimate.customerId)) · \(Self.estimateRef(estimate.id))",
                  status: StatusWord(documentStatus: estimate.status),
                  amount: paperLinesTotal(estimate.lines).map { money($0, currency: estimate.lines.first?.unitPrice.currency ?? "USD") },
                  target: .open(.route(.estimate(estimate.id))))
    }

    func invoiceHit(_ invoice: InvoiceRecord) -> SearchHit {
        let total = paperLinesTotal(invoice.lines)
        // MF-04: an unpaid invoice shows what's owed now.
        let shown = invoice.status == "issued" ? total.map { max(0, $0 - invoice.amountPaid) } : total
        return SearchHit(id: "invoice:\(invoice.id)", title: customerName(invoice.customerId),
                         subtitle: Self.invoiceRef(invoice.id), status: StatusWord(documentStatus: invoice.status),
                         amount: shown.map { money($0, currency: invoice.currency) },
                         target: .open(.route(.invoice(invoice.id))))
    }

    func actionHit(_ action: SearchAction) -> SearchHit {
        SearchHit(id: "action:\(action.id)", leading: .icon(action.symbol), title: action.title, subtitle: action.subtitle,
                  target: .run(action))
    }

    /// A server result the phone holds no copy of: its own words, opened by id.
    func serverHit(_ result: ServerSearchResult) -> SearchHit {
        let tint = result.status.flatMap { result.resultType == "job" ? StatusWord.jobTint($0) : StatusWord.documentTint($0) }
        let status = result.status.map { result.resultType == "job" ? StatusWord(text: $0.statusLabel, tint: tint) : StatusWord(documentStatus: $0) }
        let target: SearchHit.Target = switch result.resultType {
        case "job": .open(.route(.job(result.entityId)))
        case "customer": .open(.customer(Customer(id: result.entityId, name: result.title, archived: nil, createdAt: nil)))
        case "estimate": .open(.route(.estimate(result.entityId)))
        case "invoice": .open(.route(.invoice(result.entityId)))
        case "billing_schedule": .open(.route(.billingSchedule(result.entityId)))
        default: .none
        }
        return SearchHit(id: "\(result.resultType):\(result.entityId)", title: result.title, subtitle: result.subtitle,
                         status: status, target: target)
    }

    static func estimateRef(_ id: String) -> String { "EST-\(id.suffix(4).uppercased())" }
    static func invoiceRef(_ id: String) -> String { "INV-\(id.suffix(4).uppercased())" }

    // MARK: Local matches

    func localJobs() -> [Job] {
        guard canJobs else { return [] }
        let matched = jobs.filter { job in
            let record = record(job.customerId)
            return terms.matches([job.title, job.shortRef, street(job), customerName(job.customerId), record?.address])
                || terms.matchesPhone(record?.phone)
        }
        // A number typed exactly leads, then open work before finished, newest first.
        return matched.sorted { left, right in
            let leftRef = terms.isReference(left.shortRef), rightRef = terms.isReference(right.shortRef)
            if leftRef != rightRef { return leftRef }
            let leftDone = ["completed", "canceled"].contains(left.status), rightDone = ["completed", "canceled"].contains(right.status)
            if leftDone != rightDone { return !leftDone }
            return (left.updatedAt ?? "") > (right.updatedAt ?? "")
        }
    }

    func localCustomers() -> [Customer] {
        guard canCustomers else { return [] }
        var seen = Set<String>()
        var found: [Customer] = []
        for record in customerRecords where !record.archived {
            if terms.matches([record.name, record.address, record.phone, record.email]) || terms.matchesPhone(record.phone) {
                seen.insert(record.id)
                found.append(customers.first { $0.id == record.id }
                             ?? Customer(id: record.id, name: record.name, archived: record.archived, createdAt: record.createdAt))
            }
        }
        // Technicians have no directory; the names their jobs need still match.
        for customer in customers where customer.archived != true && !seen.contains(customer.id) && terms.matches([customer.name]) {
            found.append(customer)
        }
        let typed = terms.text.lowercased()
        return found.sorted { left, right in
            let leftLead = left.name.lowercased().hasPrefix(typed), rightLead = right.name.lowercased().hasPrefix(typed)
            if leftLead != rightLead { return leftLead }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    func localEstimates() -> [EstimateRecord] {
        guard canEstimates else { return [] }
        return estimates.filter { terms.matches([$0.title, Self.estimateRef($0.id), customerName($0.customerId), $0.status.statusLabel]) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func localInvoices() -> [InvoiceRecord] {
        guard canInvoices else { return [] }
        return invoices.filter { terms.matches([Self.invoiceRef($0.id), customerName($0.customerId),
                                                $0.status == "issued" ? "Unpaid" : $0.status.statusLabel]) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: Build

    func build() -> SearchResults {
        guard !terms.isEmpty else { return SearchResults() }
        var jobHits: [SearchHit] = [], customerHits: [SearchHit] = [], estimateHits: [SearchHit] = [], invoiceHits: [SearchHit] = []
        var otherGroups: [String: [SearchHit]] = [:]
        var shown = Set<String>()
        func add(_ hit: SearchHit, to list: inout [SearchHit]) {
            guard shown.insert(hit.id).inserted else { return }
            list.append(hit)
        }

        let localJobs = localJobs(), localCustomers = localCustomers()
        let localEstimates = localEstimates(), localInvoices = localInvoices()

        // The company-wide answer leads in its own order; this phone's copies fill in the rows
        // (street, amount) and add what the server's index does not cover (street, phone digits).
        for result in server ?? [] {
            switch result.resultType {
            case "job":
                if let job = jobs.first(where: { $0.id == result.entityId }) { add(jobHit(job), to: &jobHits) }
                else { add(serverHit(result), to: &jobHits) }
            case "customer":
                if let customer = customers.first(where: { $0.id == result.entityId }) { add(customerHit(customer), to: &customerHits) }
                else if let record = record(result.entityId) {
                    add(customerHit(Customer(id: record.id, name: record.name, archived: record.archived, createdAt: record.createdAt)), to: &customerHits)
                } else { add(serverHit(result), to: &customerHits) }
            case "estimate":
                if let estimate = estimates.first(where: { $0.id == result.entityId }) { add(estimateHit(estimate), to: &estimateHits) }
                else { add(serverHit(result), to: &estimateHits) }
            case "invoice":
                if let invoice = invoices.first(where: { $0.id == result.entityId }) { add(invoiceHit(invoice), to: &invoiceHits) }
                else { add(serverHit(result), to: &invoiceHits) }
            default:
                var list = otherGroups[result.resultType] ?? []
                add(serverHit(result), to: &list)
                otherGroups[result.resultType] = list
            }
        }
        if let phoneMatch { add(customerHit(phoneMatch), to: &customerHits) }
        localJobs.forEach { add(jobHit($0), to: &jobHits) }
        localCustomers.forEach { add(customerHit($0), to: &customerHits) }
        localEstimates.forEach { add(estimateHit($0), to: &estimateHits) }
        localInvoices.forEach { add(invoiceHit($0), to: &invoiceHits) }
        let actionHits = actions.filter { $0.matches(terms.text) }.map(actionHit)

        var results = SearchResults()
        results.top = topHit(jobs: localJobs, customers: localCustomers, estimates: localEstimates, invoices: localInvoices,
                             recordHits: jobHits.count + customerHits.count + estimateHits.count + invoiceHits.count,
                             only: (jobHits + customerHits + estimateHits + invoiceHits).first)
        let top = results.top?.id
        func without(_ hits: [SearchHit]) -> [SearchHit] { hits.filter { $0.id != top } }
        results.groups = [
            SearchGroup(id: "job", title: "Jobs", hits: without(jobHits)),
            SearchGroup(id: "customer", title: "Customers", hits: without(customerHits)),
            SearchGroup(id: "estimate", title: "Estimates", hits: without(estimateHits)),
            SearchGroup(id: "invoice", title: "Invoices", hits: without(invoiceHits)),
            SearchGroup(id: "action", title: "Places and actions", hits: without(actionHits)),
        ] + otherGroups.keys.sorted().map { SearchGroup(id: $0, title: Self.label($0), hits: otherGroups[$0] ?? []) }
        results.groups.removeAll { $0.hits.isEmpty }
        return results
    }

    /// A top hit only when the match is certain: an exact command, record number, whole phone
    /// number or name, or a single record. The server's score has no fixed scale, so it never decides.
    private func topHit(jobs: [Job], customers: [Customer], estimates: [EstimateRecord], invoices: [InvoiceRecord],
                        recordHits: Int, only: SearchHit?) -> SearchHit? {
        if let action = actions.first(where: { $0.isExact(terms.text) }) { return actionHit(action) }
        if let job = jobs.first(where: { terms.isReference($0.shortRef) }) { return jobHit(job) }
        if let estimate = estimates.first(where: { terms.isReference(Self.estimateRef($0.id)) }) { return estimateHit(estimate) }
        if let invoice = invoices.first(where: { terms.isReference(Self.invoiceRef($0.id)) }) { return invoiceHit(invoice) }
        if let phoneMatch { return customerHit(phoneMatch) }
        let wholePhone = customers.filter { terms.isWholePhone(record($0.id)?.phone) }
        if wholePhone.count == 1, let customer = wholePhone.first { return customerHit(customer) }
        let named = customers.filter { $0.name.caseInsensitiveCompare(terms.text) == .orderedSame }
        if named.count == 1, let customer = named.first { return customerHit(customer) }
        return recordHits == 1 ? only : nil
    }

    static func label(_ type: String) -> String {
        switch type {
        case "job": "Jobs"
        case "customer": "Customers"
        case "estimate": "Estimates"
        case "invoice": "Invoices"
        case "billing_schedule": "Billing schedules"
        case "payment": "Payments"
        case "location": "Locations"
        default: type.statusLabel
        }
    }
}

// MARK: - State

/// Search's state, owned by the place that shows it (the phone's bar, the iPad sheet) so the bar's
/// field and Return reach the same results.
@MainActor
final class SearchModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { selection = nil } }
    }
    /// The row the iPad's arrow keys have moved to; Return opens it (or the top hit when nil).
    @Published var selection: Int?
    @Published fileprivate(set) var server: [ServerSearchResult] = []
    @Published fileprivate(set) var serverQuery = ""
    @Published fileprivate(set) var serverFailed = false
    @Published fileprivate(set) var searching = false
    /// The customer whose whole phone number was typed, from the server's exact lookup.
    @Published fileprivate(set) var phoneMatch: (query: String, customer: Customer)?
    /// Records this phone holds (live, or the saved copy without signal). Nil until read; a list
    /// that could not be read stays nil, so search never calls a missing list empty.
    @Published fileprivate(set) var customerRecords: [CustomerRecord]?
    @Published fileprivate(set) var estimates: [EstimateRecord]?
    @Published fileprivate(set) var invoices: [InvoiceRecord]?
    @Published private(set) var submits = 0
    let addresses = JobAddressBook()
    private var loadedFor: String?

    /// Return in the field.
    func submit() { submits += 1 }

    /// Each time search opens, its lists are read again once (a quick repeat read is reused).
    func opened() { loadedFor = nil }

    func loadRecords(api: APIClient, session: SessionController, store: Store) async {
        let identity = "\(session.user?.id ?? "")|\(session.activeOrganization?.id ?? "")|\(session.generation)"
        guard loadedFor != identity else { return }
        loadedFor = identity
        let canCustomers = session.can("customer.view", feature: "core_crm")
        let canEstimates = session.can("estimate.view", feature: "estimates")
        let canInvoices = session.can("invoice.view", feature: "invoicing")
        async let customerRead: [CustomerRecord]? = canCustomers ? try? await api.fieldCustomers() : nil
        async let estimateRead: [EstimateRecord]? = canEstimates ? try? await api.fieldEstimates() : nil
        async let invoiceRead: [InvoiceRecord]? = canInvoices ? try? await api.fieldInvoices() : nil
        let (customers, estimates, invoices) = await (customerRead, estimateRead, invoiceRead)
        guard loadedFor == identity else { return }
        if let customers { customerRecords = customers }
        if let estimates { self.estimates = estimates }
        if let invoices { self.invoices = invoices }
        if canCustomers {
            await addresses.load(Array(store.jobs.prefix(60)), api: api, organizationID: session.activeOrganization?.id,
                                 identity: identity)
        }
    }

    /// The company-wide search, after a pause in typing. A whole phone number also asks the
    /// exact phone lookup the intake form uses, so the right customer can lead.
    func runServer(_ text: String, api: APIClient, session: SessionController) async {
        guard !text.isEmpty, !session.isOffline else { return }
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        let terms = SearchTerms(text)
        let lookPhone = terms.phoneShaped && terms.digits.count >= 7 && session.can("customer.view", feature: "core_crm")
        async let phone: CustomerPhoneLookup? = lookPhone ? try? await api.lookupCustomer(phone: text) : nil
        do {
            let page = try await api.search(text)
            let lookup = await phone
            guard !Task.isCancelled else { return }
            server = page.items
            serverQuery = text
            serverFailed = false
            if case .found(let customer) = lookup { phoneMatch = (text, customer) } else { phoneMatch = nil }
        } catch is CancellationError {
        } catch {
            _ = await phone
            guard !Task.isCancelled else { return }
            serverFailed = true
        }
    }
}

// MARK: - View

/// Paper 76, redesigned 2026-10-31: one field, a top hit when the match is certain, then Jobs,
/// Customers, Estimates, Invoices and Places and actions, each on one panel. The server's Search
/// Gateway searches the whole company; this phone's saved jobs, customers and documents answer
/// at once and when there is no signal.
struct PaperGlobalSearch: View {
    var embedded = false
    /// Set by the iPhone's bottom search: the bar's field owns the text, and a picked result is
    /// handed back to push on the current place instead of inside this view.
    var model: SearchModel? = nil
    var openResult: ((SearchDestination) -> Void)? = nil
    /// Words to start with, from a Siri or Shortcuts search.
    var initialQuery = ""
    /// The place the bottom search opened over; its records lead the empty-query list.
    var focus: SearchFocus = .none
    /// Creates, Settings and places the host offers this person.
    var actions: [SearchAction] = []
    @StateObject private var own = SearchModel()

    var body: some View {
        let active = model ?? own
        SearchScreen(model: active, addresses: active.addresses, embedded: embedded, openResult: openResult,
                     initialQuery: initialQuery, focus: focus, actions: actions)
    }
}

private struct SearchScreen: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var addresses: JobAddressBook
    let embedded: Bool
    let openResult: ((SearchDestination) -> Void)?
    let initialQuery: String
    let focus: SearchFocus
    let actions: [SearchAction]
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var recents = RecentItems.shared
    @State private var path = NavigationPath()
    /// Groups opened past their first rows with "Show all".
    @State private var expanded: Set<String> = []
    private static let groupLimit = 5

    private var terms: SearchTerms { SearchTerms(model.query) }
    private var offline: Bool { session.isOffline }
    private var serverAnswered: Bool { !model.serverFailed && !offline && model.serverQuery == terms.text && !terms.isEmpty }
    /// Waiting on the server for these words; this phone's matches show meanwhile.
    private var waiting: Bool { !offline && !model.serverFailed && !terms.isEmpty && model.serverQuery != terms.text }

    private var results: SearchResults {
        SearchResultsBuilder(
            terms: terms, jobs: store.jobs, customers: store.customers, customerRecords: model.customerRecords ?? [],
            estimates: model.estimates ?? [], invoices: model.invoices ?? [], street: addresses.street,
            server: serverAnswered ? model.server : nil,
            phoneMatch: model.phoneMatch.flatMap { $0.query == terms.text ? $0.customer : nil },
            actions: actions,
            canJobs: session.can("job.view", feature: "jobs"), canCustomers: session.can("customer.view", feature: "core_crm"),
            canEstimates: session.can("estimate.view", feature: "estimates"), canInvoices: session.can("invoice.view", feature: "invoicing")
        ).build()
    }

    var body: some View {
        if openResult != nil {
            content
                .foregroundStyle(Theme.foreground)
                .scrollDismissesKeyboard(.interactively)
        } else {
            NavigationStack(path: $path) {
                content
                    .foregroundStyle(Theme.foreground)
                    .background(Theme.background)
                    .safeAreaInset(edge: .top, spacing: 0) { sheetField }
                    .navigationTitle("Search")
                    .navigationBarTitleDisplayMode(.inline)
                    .task {
                        if model.query.isEmpty, !initialQuery.isEmpty { model.query = initialQuery }
                    }
                    .toolbar {
                        if !embedded {
                            ThorbisToolbarItem(placement: .confirmationAction, prominent: true) { Button("Done") { dismiss() } }
                        }
                    }
                    .paperDestinations()
            }
        }
    }

    /// The sheet's field (iPad ⌘F). A Thorbis field rather than the system bar so the arrow keys
    /// can move through the results while the cursor stays in it.
    private var sheetField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            SearchKeyField(text: $model.query, placeholder: "Jobs, customers, phone, invoice number",
                           focusOnAppear: !embedded, onSubmit: openSelected, onMove: move)
                .frame(height: 44)
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
        .padding(.horizontal, PaperCardMetrics.margin).padding(.vertical, 8)
        .background(Theme.background)
    }

    // MARK: Opening

    private func go(_ destination: SearchDestination) {
        if let openResult { return openResult(destination) }
        switch destination {
        case .job(let job): path.append(job)
        case .customer(let customer): path.append(customer)
        case .route(let route): path.append(route)
        }
    }

    private func open(_ hit: SearchHit) {
        switch hit.target {
        case .none: return
        case .open(let destination):
            if !terms.isEmpty { recents.recordSearch(terms.text) }
            go(destination)
        case .run(let action):
            if !terms.isEmpty { recents.recordSearch(terms.text) }
            action.run()
        }
    }

    /// The hits Return and the arrow keys walk, in the order they show.
    private var visibleHits: [SearchHit] {
        if terms.isEmpty { return emptyGroups.flatMap(\.hits) }
        let built = results
        return (built.top.map { [$0] } ?? []) + built.groups.flatMap { visible($0) }
    }

    private func openSelected() {
        let hits = visibleHits.filter { if case .none = $0.target { false } else { true } }
        guard !hits.isEmpty else { return }
        let index = min(model.selection ?? 0, hits.count - 1)
        open(hits[index])
    }

    private func move(_ step: Int) {
        let count = visibleHits.filter { if case .none = $0.target { false } else { true } }.count
        guard count > 0 else { return }
        let next = (model.selection ?? -1) + step
        model.selection = max(0, min(count - 1, next))
    }

    private func isSelected(_ hit: SearchHit) -> Bool {
        guard let selection = model.selection else { return false }
        let hits = visibleHits.filter { if case .none = $0.target { false } else { true } }
        return hits.indices.contains(selection) && hits[selection].id == hit.id
    }

    // MARK: Content

    private var content: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if terms.isEmpty { emptyQuery } else { typed }
                }
                .padding(.horizontal, PaperCardMetrics.margin)
                .padding(.top, 8).padding(.bottom, 24)
            }
            .onChange(of: model.selection) { _, selection in
                guard let selection else { return }
                let hits = visibleHits.filter { if case .none = $0.target { false } else { true } }
                if hits.indices.contains(selection) { withAnimation(.easeOut(duration: 0.12)) { reader.scrollTo(hits[selection].id) } }
            }
        }
        .task(id: terms.text) {
            await model.runServer(terms.text, api: api, session: session)
        }
        // Read once per opening, so recent jobs lead with their street and typing answers at once.
        .task(id: "records|\(session.generation)") {
            await model.loadRecords(api: api, session: session, store: store)
        }
        .onChange(of: model.submits) { openSelected() }
    }

    @ViewBuilder private var typed: some View {
        let built = results
        if offline || model.serverFailed {
            savedNote
        }
        if let top = built.top {
            PaperSection("Top hit") { row(top) }
        }
        ForEach(built.groups) { group in
            let shown = visible(group)
            PaperSection(title: group.title, count: group.hits.count) {
                ForEach(shown) { hit in row(hit) }
                if shown.count < group.hits.count {
                    Button { expanded.insert(group.id) } label: {
                        Text("Show all \(group.hits.count)").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, PaperCardMetrics.inset).contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
            } accessory: { EmptyView() }
        }
        if waiting || model.searching {
            VStack(alignment: .leading, spacing: 0) {
                Text("Searching…").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4).frame(minHeight: 28)
                PaperCard { SkeletonRows(count: built.isEmpty ? 3 : 2, leading: false, inset: PaperCardMetrics.inset) }
                    .accessibilityLabel("Searching")
            }
        } else if built.isEmpty {
            PaperEmptyState.search(terms.text)
        }
    }

    private func visible(_ group: SearchGroup) -> [SearchHit] {
        expanded.contains(group.id) ? group.hits : Array(group.hits.prefix(Self.groupLimit))
    }

    /// No signal (or the company search failed): what answers is this phone's saved copy, and
    /// lists that were never saved here say so rather than reading as "no results".
    private var savedNote: some View {
        let missing = [
            session.can("estimate.view", feature: "estimates") && model.estimates == nil ? "estimates" : nil,
            session.can("invoice.view", feature: "invoicing") && model.invoices == nil ? "invoices" : nil,
        ].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 2) {
            Label(offline ? "Saved on this phone · no signal" : "Saved on this phone · company search is unavailable",
                  systemImage: "iphone")
                .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
            if !missing.isEmpty {
                Text("\(missing.joined(separator: " and ").prefix(1).uppercased() + missing.joined(separator: " and ").dropFirst()) aren't saved on this phone yet.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func row(_ hit: SearchHit) -> some View {
        let selected = isSelected(hit)
        let label = PaperListRow(leading: hit.leading, title: hit.title, subtitle: hit.subtitle, dimmed: hit.dimmed,
                                 highlight: terms.marks) {
            if hit.amount != nil || hit.status != nil {
                VStack(alignment: .trailing, spacing: 4) {
                    if let amount = hit.amount {
                        Text(amount).font(Theme.moneyFont(.line, regular: false)).foregroundStyle(Theme.foreground)
                    }
                    if let status = hit.status { status }
                }
            }
        }
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.brandSurface).padding(4)
            }
        }
        return Group {
            if case .none = hit.target {
                label.opacity(0.6)
            } else {
                Button { open(hit) } label: { label }
                    .buttonStyle(RowPressStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .id(hit.id)
    }

    // MARK: Before anything is typed

    /// Recent records that still resolve to one this person can open.
    private var recentlyOpened: [(RecentItems.Item, SearchHit)] {
        let builder = emptyBuilder
        return recents.items.compactMap { item in
            switch item.kind {
            case .job:
                guard session.can("job.view", feature: "jobs"), let job = store.jobs.first(where: { $0.id == item.id }) else { return nil }
                return (item, builder.jobHit(job))
            case .customer:
                guard session.can("customer.view", feature: "core_crm"),
                      let customer = store.customers.first(where: { $0.id == item.id }) else { return nil }
                return (item, builder.customerHit(customer))
            }
        }
    }

    private var emptyBuilder: SearchResultsBuilder {
        SearchResultsBuilder(terms: SearchTerms(""), jobs: store.jobs, customers: store.customers,
                             customerRecords: model.customerRecords ?? [], estimates: [], invoices: [], street: addresses.street,
                             server: nil, phoneMatch: nil, actions: [], canJobs: true, canCustomers: true,
                             canEstimates: false, canInvoices: false)
    }

    /// Customers of the open jobs, newest job first, once each, skipping archived ones.
    private func activeCustomers(from jobs: [Job], excluding shown: Set<String>) -> [Customer] {
        var seen = shown
        return jobs.compactMap { job in
            guard let customerID = job.customerId, !seen.contains(customerID),
                  let customer = store.customers.first(where: { $0.id == customerID && $0.archived != true }) else { return nil }
            seen.insert(customer.id)
            return customer
        }.prefix(5).map { $0 }
    }

    /// The empty field's sections: recent searches, then the place's own records (recent jobs on
    /// Jobs, recent customers on Customers), then what this person opened last, like Mail and Maps.
    private var emptyGroups: [SearchGroup] {
        let builder = emptyBuilder
        var groups: [SearchGroup] = []
        let canViewJobs = session.can("job.view", feature: "jobs")
        let open = (canViewJobs ? store.jobs : []).filter { !["completed", "canceled"].contains($0.status) }
            .sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }.prefix(6)
        let searches = recents.searches.map { words in
            SearchHit(id: "search:\(words)", leading: .icon("clock.arrow.circlepath"), title: words,
                      target: .run(SearchAction(id: "search:\(words)", title: words, symbol: "clock", keywords: [], run: { model.query = words })))
        }
        if !searches.isEmpty { groups.append(SearchGroup(id: "searches", title: "Recent searches", hits: searches)) }
        let opened = recentlyOpened
        let split = focus.split(opened.map(\.0))
        let lead = opened.filter { split.relevant.contains($0.0) }.prefix(5)
        let rest = opened.filter { split.rest.contains($0.0) }.prefix(5)
        let leadJobIDs = Set(lead.compactMap { $0.0.kind == .job ? $0.0.id : nil })
        let openJobs = open.filter { !leadJobIDs.contains($0.id) }.map(builder.jobHit)
        if !lead.isEmpty {
            groups.append(SearchGroup(id: "lead", title: focus == .customers ? "Recent customers" : "Recent jobs", hits: lead.map(\.1)))
        }
        // On Customers, the people with open work follow the ones opened lately.
        if focus == .customers && session.can("customer.view", feature: "core_crm") {
            let active = activeCustomers(from: Array(open), excluding: Set(lead.map(\.0.id))).map(builder.customerHit)
            if !active.isEmpty { groups.append(SearchGroup(id: "active", title: "Customers with open jobs", hits: active)) }
        }
        // On Jobs the open jobs are the place's records too, so they follow its recents.
        if focus == .jobs && !openJobs.isEmpty { groups.append(SearchGroup(id: "open", title: "Open jobs", hits: openJobs)) }
        if !rest.isEmpty { groups.append(SearchGroup(id: "opened", title: "Recently opened", hits: rest.map(\.1))) }
        if focus != .jobs && !openJobs.isEmpty { groups.append(SearchGroup(id: "open", title: "Open jobs", hits: openJobs)) }
        return groups
    }

    @ViewBuilder private var emptyQuery: some View {
        let groups = emptyGroups
        if recents.searches.isEmpty && recents.items.isEmpty {
            PaperEmptyState(symbol: "magnifyingglass", title: "No recent searches",
                            message: "Find a job by street, a customer by name or phone, or an invoice by number.")
        }
        ForEach(groups) { group in
            PaperSection(title: group.title, count: nil) {
                ForEach(group.hits) { hit in row(hit) }
            } accessory: {
                if group.id == "searches" {
                    clearButton("Clear recent searches") { recents.clearSearches() }
                } else if group.id == "opened" || (group.id == "lead" && !groups.contains { $0.id == "opened" }) {
                    clearButton("Clear recently opened") { recents.clearOpened() }
                }
            }
        }
    }

    private func clearButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Clear").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - Field with arrow keys

/// A text field that hands Up and Down to search (to move through results) and Return to open
/// the selection, ahead of the text field's own cursor moves. Hardware keyboards only.
struct SearchKeyField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusOnAppear = true
    var onSubmit: () -> Void
    var onMove: (Int) -> Void

    final class KeyField: UITextField {
        var onMove: ((Int) -> Void)?
        override var keyCommands: [UIKeyCommand]? {
            let up = UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(moveUp))
            let down = UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(moveDown))
            up.wantsPriorityOverSystemBehavior = true
            down.wantsPriorityOverSystemBehavior = true
            return [up, down]
        }
        @objc private func moveUp() { onMove?(-1) }
        @objc private func moveDown() { onMove?(1) }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SearchKeyField
        init(_ parent: SearchKeyField) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> KeyField {
        let field = KeyField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont(name: "Inter-Regular", size: 16) ?? .systemFont(ofSize: 16))
        field.adjustsFontForContentSizeCategory = true
        field.textColor = UIColor(Theme.foreground)
        field.tintColor = UIColor(Theme.brandText)
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: UIColor(Theme.muted)])
        field.returnKeyType = .search
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.accessibilityLabel = "Search"
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.text = text
        if focusOnAppear { DispatchQueue.main.async { field.becomeFirstResponder() } }
        return field
    }

    func updateUIView(_ field: KeyField, context: Context) {
        context.coordinator.parent = self
        field.onMove = onMove
        if field.text != text { field.text = text }
    }
}
