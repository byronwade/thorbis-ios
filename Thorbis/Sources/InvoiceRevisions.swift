import SwiftUI

// One invoice per job: an approved estimate is added to the job's invoice, an issued invoice can
// still change, a closed job can be reopened. Each is behind a server feature flag and online only.
// The server owns every amount here; this file sends the request and shows what comes back.

// MARK: - Reopen a completed job (flag `job_reopen`)

/// `POST /v1/jobs/{id}/reopen`. `expectedCompletedAt` is the job's `completedAt` exactly as read.
struct JobReopenRequest: Encodable, Equatable {
    let expectedCompletedAt: String
    let reason: String?
}

enum JobReopen {
    static let flag = "job_reopen"
    static let reasonLimit = 2_000
    static let reasonTooLong = "That reason is too long. Make it shorter."

    /// Shown only on a completed job, to someone who may complete jobs, with nothing waiting to send.
    static func canOffer(status: String, completedAt: String?, flagOn: Bool, canComplete: Bool,
                         hasPendingChange: Bool, serverSaysOff: Bool = false) -> Bool {
        flagOn && !serverSaysOff && canComplete && !hasPendingChange && status == "completed" && completedAt?.isEmpty == false
    }

    /// The body to send, or nil when the job has no completion time or the reason is too long.
    static func request(completedAt: String?, reason: String) -> JobReopenRequest? {
        guard let completedAt, !completedAt.isEmpty else { return nil }
        let typed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed.utf16.count <= reasonLimit else { return nil }
        return JobReopenRequest(expectedCompletedAt: completedAt, reason: typed.isEmpty ? nil : typed)
    }
}

/// What a refused reopen means for the person, from the server's answer.
enum JobReopenFailure: Equatable {
    /// The server has reopening off: hide the action.
    case unavailable
    case notAllowed
    case notFound
    case canceled
    /// The job changed since it was read: read it again and let them retry.
    case changed
    case invalid
    case other(String)

    static func of(_ error: Error) -> JobReopenFailure {
        guard let problem = error as? Problem else { return .other(error.localizedDescription) }
        switch (problem.status, problem.code) {
        case (409, "job_canceled"): return .canceled
        case (409, "job_completion_changed"): return .changed
        default: break
        }
        switch problem.status {
        case 403: return problem.category == "feature_unavailable" || problem.code == "feature_unavailable" ? .unavailable : .notAllowed
        case 404: return .notFound
        case 400, 422: return .invalid
        default: return .other(problem.localizedDescription)
        }
    }

    var message: String {
        switch self {
        case .unavailable: "Reopening jobs isn\u{2019}t turned on yet."
        case .notAllowed: "You can\u{2019}t reopen this job. Ask the office."
        case .notFound: "This job can\u{2019}t be found. It may have been removed."
        case .canceled: "This job was canceled, so it can\u{2019}t be reopened."
        case .changed: "This job changed. Try again."
        case .invalid: "Check the reason and try again."
        case .other(let message): message
        }
    }

    /// The job on screen is out of date: read it again.
    var reloadsJob: Bool { self == .changed || self == .canceled }
}

// MARK: - Invoice versions

struct InvoiceRevisionBilledEstimate: Decodable, Hashable, Sendable {
    let estimateId: String
    let estimateRevisionNumber: Int?
}

struct InvoiceRevisionAuthorization: Decodable, Hashable, Sendable {
    let id: String
    let signerName: String
    let signedAt: String
}

/// One version of an invoice (`GET /v1/invoices/{id}/revisions`): the whole invoice as it stood.
struct InvoiceRevisionRecord: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let linesRevision: Int
    /// "created", "estimate_added" or "lines_edited".
    let kind: String
    let billedEstimates: [InvoiceRevisionBilledEstimate]
    let lines: [FieldLine]
    let previousTotal: FieldMoney?
    let total: FieldMoney
    let invoiceStatus: String?
    let revisedByUserId: String?
    let revisedAt: String
    let authorization: InvoiceRevisionAuthorization?

    private enum CodingKeys: String, CodingKey {
        case id, linesRevision, kind, billedEstimates, lines, previousTotal, total, invoiceStatus, revisedByUserId, revisedAt, authorization
    }

    init(id: String, linesRevision: Int, kind: String, billedEstimates: [InvoiceRevisionBilledEstimate] = [], lines: [FieldLine] = [],
         previousTotal: FieldMoney? = nil, total: FieldMoney, invoiceStatus: String? = nil, revisedByUserId: String? = nil,
         revisedAt: String, authorization: InvoiceRevisionAuthorization? = nil) {
        self.id = id; self.linesRevision = linesRevision; self.kind = kind; self.billedEstimates = billedEstimates
        self.lines = lines; self.previousTotal = previousTotal; self.total = total; self.invoiceStatus = invoiceStatus
        self.revisedByUserId = revisedByUserId; self.revisedAt = revisedAt; self.authorization = authorization
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        linesRevision = try values.decode(Int.self, forKey: .linesRevision)
        kind = try values.decode(String.self, forKey: .kind)
        billedEstimates = try values.decodeIfPresent([InvoiceRevisionBilledEstimate].self, forKey: .billedEstimates) ?? []
        lines = try values.decodeIfPresent([FieldLine].self, forKey: .lines) ?? []
        previousTotal = try values.decodeIfPresent(FieldMoney.self, forKey: .previousTotal)
        total = try values.decode(FieldMoney.self, forKey: .total)
        invoiceStatus = try values.decodeIfPresent(String.self, forKey: .invoiceStatus)
        revisedByUserId = try values.decodeIfPresent(String.self, forKey: .revisedByUserId)
        revisedAt = try values.decode(String.self, forKey: .revisedAt)
        authorization = try values.decodeIfPresent(InvoiceRevisionAuthorization.self, forKey: .authorization)
    }
}

struct InvoiceRevisionPage: Decodable {
    let invoiceId: String
    let currentLinesRevision: Int
    let currentRevisionSigned: Bool
    let items: [InvoiceRevisionRecord]
    let nextCursor: String?
}

/// Every version of one invoice, oldest first as the server lists them.
struct InvoiceRevisionHistory: Equatable {
    let invoiceId: String
    let currentLinesRevision: Int
    let currentRevisionSigned: Bool
    let items: [InvoiceRevisionRecord]
}

struct InvoiceApprovedEstimateRequest: Encodable, Equatable {
    let estimateId: String
    let expectedLinesRevision: Int
}

@MainActor
extension APIClient {
    /// Online only: never queued. Answers the job, working again (or unchanged if it already was).
    func reopenFieldJob(_ id: String, request: JobReopenRequest) async throws -> JobRecord {
        guard UUID(uuidString: id) != nil else { throw Problem(title: "Invalid record ID", status: nil, detail: id) }
        return try await send("POST", "/v1/jobs/\(id)/reopen", body: request)
    }

    /// Adds an approved estimate's lines to the job's invoice. Safe to repeat: the server answers
    /// the unchanged invoice when this estimate is already on it.
    func addApprovedEstimate(toInvoice id: String, request: InvoiceApprovedEstimateRequest) async throws -> InvoiceRecord {
        guard UUID(uuidString: request.estimateId) != nil else {
            throw Problem(title: "Invalid record ID", status: nil, detail: request.estimateId)
        }
        return try await send("POST", financialPath("/v1/invoices", id: id, suffix: "/approved-estimates"), body: request)
    }

    func fieldInvoiceRevisionPage(_ id: String, cursor: String? = nil, limit: Int = 50) async throws -> InvoiceRevisionPage {
        try await send("GET", financialPath("/v1/invoices", id: id, suffix: "/revisions"),
                       queryItems: [URLQueryItem(name: "limit", value: String(limit))], cursor: cursor, requireFresh: true)
    }

    /// All versions, read live so "already on the invoice" is never answered from an old copy.
    func fieldInvoiceRevisions(_ id: String) async throws -> InvoiceRevisionHistory {
        var items: [InvoiceRevisionRecord] = []
        var cursor: String?
        var seen = Set<String>()
        var last: InvoiceRevisionPage
        repeat {
            try Task.checkCancellation()
            last = try await fieldInvoiceRevisionPage(id, cursor: cursor)
            items.append(contentsOf: last.items)
            cursor = last.nextCursor
            if let cursor, cursor.isEmpty || !seen.insert(cursor).inserted {
                throw Problem(title: "Pagination cursor loop", status: nil, detail: "Repeated or empty cursor")
            }
        } while cursor != nil
        return InvoiceRevisionHistory(invoiceId: last.invoiceId, currentLinesRevision: last.currentLinesRevision,
                                      currentRevisionSigned: last.currentRevisionSigned, items: items)
    }
}

// MARK: - Words

enum InvoiceRevisionWords {
    static let flag = "invoice_revisions"
    static let staleMessage = "This invoice changed. Check it and try again."

    /// The confirm before an invoice is issued. With invoice revisions on its lines can still be
    /// changed afterwards, so it must not say they become final.
    static func issueConfirm(flagOn: Bool) -> String {
        flagOn ? "Issue this invoice? The customer can be sent this invoice. You can still change it later."
               : "Issue this invoice? Its line items will become final."
    }

    /// Plain words for a refusal the server names with a code; nil when the code is not one of ours.
    static func message(code: String?) -> String? {
        switch code {
        case "invoice_lines_revision_stale": staleMessage
        case "estimate_already_billed": "This estimate is already on the invoice."
        case "estimate_not_approved_for_job": "Only an approved estimate for this job can be added."
        case "invoice_total_below_paid": "That would make the invoice less than what\u{2019}s been paid."
        case "invoice_collection_in_progress": "A card payment is in progress. Finish or cancel it, then try again."
        case "invoice_financing_in_progress": "Financing is in progress on this invoice."
        case "invoice_billing_history_unknown": "Add these lines by hand; this older invoice can\u{2019}t take an estimate."
        case "job_canceled": "This job was canceled, so its invoice can\u{2019}t change."
        case "invoice_not_revisable": "This invoice can\u{2019}t be changed anymore."
        case "invoice_not_job_invoice": "This isn\u{2019}t the job\u{2019}s invoice, so an estimate can\u{2019}t be added to it."
        case "invoice_line_limit": "This invoice is full. Remove a line, then try again."
        case "invoice_total_negative": "That would make the invoice total less than zero."
        case "estimate_not_reconciled": "This estimate isn\u{2019}t ready yet. Open it, check it, then try again."
        case "invoice_revision_price_book_attachment_unsupported":
            "Add this as a typed line; price book items can\u{2019}t be added to an issued invoice yet."
        case "invoice_revisions_unavailable": "Changing a sent invoice isn\u{2019}t turned on yet."
        default: nil
        }
    }

    /// What the line editor shows for a failed save: our words for a named refusal, else the server's.
    static func lineEditMessage(_ error: Error) -> String {
        if let problem = error as? Problem, problem.status == 403, problem.category == "authorization" {
            // The server names the permission ("not permitted: invoice.discount (out_of_scope)").
            // Taking money off an invoice is a discount, which a technician's role does not hold.
            return problem.detail?.contains("invoice.discount") == true ? lowerTotalRefused : roleRefused
        }
        guard let problem = error as? Problem, problem.status == 409, let words = message(code: problem.code) else {
            return error.localizedDescription
        }
        return words
    }

    static let lowerTotalRefused = "Your role can\u{2019}t lower an invoice total. Put the lines back, or ask your office to take it off."
    static let roleRefused = "Your role can\u{2019}t change this invoice. Ask your office."

    /// A 409 the latest invoice would not fix (reloading and saving again gets the same answer),
    /// so the editor does not offer "Review latest invoice" for it. Every other 409 keeps the offer.
    static func lineEditKeepsEdits(_ error: Error) -> Bool {
        guard let problem = error as? Problem, problem.status == 409 else { return false }
        return ["invoice_total_below_paid", "invoice_collection_in_progress", "invoice_financing_in_progress",
                "invoice_revision_price_book_attachment_unsupported", "invoice_revisions_unavailable",
                "invoice_line_limit", "invoice_total_negative"].contains(problem.code ?? "")
    }

    /// Lines can change on a draft, and on an issued or paid invoice once revisions are on.
    static func linesEditable(status: String, flagOn: Bool) -> Bool {
        status == "draft" || (flagOn && (status == "issued" || status == "paid"))
    }

    static func kindWord(_ kind: String) -> String {
        switch kind {
        case "created": "Created"
        case "estimate_added": "Estimate added"
        case "lines_edited": "Lines changed"
        default: "Changed"
        }
    }

    /// "$420.00 → $780.00" when the total moved, else the one total.
    static func amounts(_ item: InvoiceRevisionRecord) -> String {
        let now = money(item.total.amount, currency: item.total.currency)
        guard let before = item.previousTotal, before != item.total else { return now }
        return "\(money(before.amount, currency: before.currency)) \u{2192} \(now)"
    }

    static func when(_ raw: String, timeZone: TimeZone = .current, locale: Locale = .current) -> String? {
        guard let date = JobFiltering.date(raw) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    /// "Estimate added · $420.00 → $780.00 · Nov 20, 2:14 PM".
    static func row(_ item: InvoiceRevisionRecord, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        [kindWord(item.kind), amounts(item), when(item.revisedAt, timeZone: timeZone, locale: locale)]
            .compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    static let unsignedNote = "The customer hasn\u{2019}t signed this version"

    /// The quiet "hasn't signed this version" line: an issued invoice whose current version is
    /// unsigned while an earlier one was signed. Never for a draft, a void or an out-of-date read.
    static func showsUnsignedNote(status: String, linesRevision: Int, history: InvoiceRevisionHistory?) -> Bool {
        guard let history, status != "draft", status != "void", history.currentLinesRevision == linesRevision,
              !history.currentRevisionSigned else { return false }
        return history.items.contains { $0.authorization != nil && $0.linesRevision < linesRevision }
    }
}

// MARK: - Adding an approved estimate to the job's invoice

enum InvoiceEstimateBilling {
    /// The job's one invoice: its completion invoice, else its first invoice that is not a deposit
    /// and not void. Nil when the job has none.
    static func jobInvoice(_ invoices: [InvoiceRecord], jobID: String) -> InvoiceRecord? {
        let live = invoices.filter { $0.jobId == jobID && $0.status != "void" && !$0.isDeposit }
        return live.first(where: { $0.origin == "job_completion" }) ?? live.first
    }

    /// Estimates the server says are on the invoice, across every version.
    static func billedEstimateIDs(_ history: InvoiceRevisionHistory) -> Set<String> {
        Set(history.items.flatMap { $0.billedEstimates.map(\.estimateId) })
    }

    /// Whether this estimate is known to be on the invoice. `billed` is nil when the versions
    /// could not be read; the invoice's own lines and source still count, and past that the offer
    /// stays and the server's `estimate_already_billed` answer settles it.
    static func isBilled(estimateID: String, invoice: InvoiceRecord, billed: Set<String>?) -> Bool {
        if billed?.contains(estimateID) == true { return true }
        if invoice.sourceEstimateId == estimateID { return true }
        return invoice.lines.contains { $0.source?.kind == "estimate" && $0.source?.estimateId == estimateID }
    }

    static func canOffer(estimate: EstimateRecord, invoice: InvoiceRecord?, billed: Set<String>?,
                         flagOn: Bool, canEditInvoice: Bool, serverSaysOff: Bool = false) -> Bool {
        guard flagOn, !serverSaysOff, canEditInvoice, estimate.status == "approved",
              let invoice, invoice.status != "void", invoice.customerId == estimate.customerId else { return false }
        return !isBilled(estimateID: estimate.id, invoice: invoice, billed: billed)
    }
}

/// What a refused "Add to invoice" means, from the server's answer.
enum InvoiceEstimateAddFailure: Equatable {
    /// The invoice changed: read it again and try once more before saying so.
    case stale
    case alreadyBilled
    /// The server has this off: hide the action.
    case unavailable
    case notAllowed
    case message(String)

    static func of(_ error: Error) -> InvoiceEstimateAddFailure {
        guard let problem = error as? Problem else { return .message(error.localizedDescription) }
        if problem.status == 403 {
            return problem.category == "feature_unavailable" || problem.code == "feature_unavailable" ? .unavailable : .notAllowed
        }
        if problem.status == 409 {
            switch problem.code {
            case "invoice_lines_revision_stale": return .stale
            case "estimate_already_billed": return .alreadyBilled
            default: break
            }
            if let words = InvoiceRevisionWords.message(code: problem.code) { return .message(words) }
        }
        if problem.status == 404 { return .message("This invoice can\u{2019}t be found. Pull down to refresh.") }
        return .message(problem.localizedDescription)
    }

    var message: String {
        switch self {
        case .stale: InvoiceRevisionWords.staleMessage
        case .alreadyBilled: InvoiceRevisionWords.message(code: "estimate_already_billed") ?? ""
        case .unavailable: "Adding an estimate to an invoice isn\u{2019}t turned on yet."
        case .notAllowed: "You can\u{2019}t change this invoice. Ask the office."
        case .message(let words): words
        }
    }
}

/// Remembers each estimate's last status so an approval that happens while the job is open is
/// offered once. An estimate first seen already approved is never offered here.
struct EstimateApprovalWatcher: Equatable {
    private(set) var known: [String: String] = [:]
    private(set) var offered: Set<String> = []

    /// Returns the estimates that just became approved, each at most once.
    mutating func observe(_ estimates: [(id: String, status: String)]) -> [String] {
        var fresh: [String] = []
        for estimate in estimates {
            if let before = known[estimate.id], before != "approved", estimate.status == "approved",
               offered.insert(estimate.id).inserted {
                fresh.append(estimate.id)
            }
            known[estimate.id] = estimate.status
        }
        return fresh
    }
}

/// One "add this estimate to that invoice" question, however it was reached.
struct EstimateInvoiceOffer: Identifiable, Equatable {
    let estimate: EstimateRecord
    let invoice: InvoiceRecord
    /// Asked right after the customer approved, rather than from an "Add to invoice" tap.
    var afterApproval = false
    var id: String { "\(estimate.id)|\(invoice.id)" }

    var title: String { afterApproval ? "Add this to the invoice?" : "Add to the invoice?" }
    var message: String {
        let name = estimate.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let what = name.isEmpty ? "This estimate\u{2019}s lines" : "The lines from \u{201C}\(name)\u{201D}"
        return "\(what) go on this job\u{2019}s invoice."
    }
}

@MainActor
final class EstimateInvoiceAdder: ObservableObject {
    /// Estimates on each invoice, from its versions. An invoice missing here could not be read.
    @Published private(set) var billedByInvoice: [String: Set<String>] = [:]
    @Published private(set) var addingEstimateID: String?
    @Published var failure: String?
    /// The server answered that the feature is off: every entry point hides.
    @Published private(set) var serverSaysOff = false
    @Published private(set) var added = 0

    func billed(on invoice: InvoiceRecord?) -> Set<String>? {
        invoice.flatMap { billedByInvoice[$0.id] }
    }

    /// Reads which estimates are on the invoice. A failed read leaves it unknown, so the action
    /// is still offered and the server decides.
    func loadBilled(invoiceID: String, api: APIClient) async {
        guard let history = try? await api.fieldInvoiceRevisions(invoiceID), !Task.isCancelled else { return }
        var billed = InvoiceEstimateBilling.billedEstimateIDs(history)
        if let known = billedByInvoice[invoiceID] { billed.formUnion(known) }
        billedByInvoice[invoiceID] = billed
    }

    /// Sends the add. On a stale invoice it reads the invoice again and tries once more. Returns
    /// the invoice as the server now has it, or nil with `failure` set.
    func add(_ offer: EstimateInvoiceOffer, api: APIClient) async -> InvoiceRecord? {
        guard addingEstimateID == nil else { return nil }
        addingEstimateID = offer.estimate.id
        defer { addingEstimateID = nil }
        failure = nil
        var invoice = offer.invoice
        for attempt in 0..<2 {
            do {
                let updated = try await api.addApprovedEstimate(
                    toInvoice: invoice.id,
                    request: .init(estimateId: offer.estimate.id, expectedLinesRevision: invoice.linesRevision))
                billedByInvoice[invoice.id, default: []].insert(offer.estimate.id)
                added += 1
                return updated
            } catch is CancellationError {
                return nil
            } catch {
                let failed = InvoiceEstimateAddFailure.of(error)
                switch failed {
                case .stale where attempt == 0:
                    guard let latest = try? await api.liveFieldInvoice(invoice.id) else {
                        failure = failed.message
                        return nil
                    }
                    invoice = latest
                    continue
                case .alreadyBilled:
                    billedByInvoice[invoice.id, default: []].insert(offer.estimate.id)
                case .unavailable:
                    serverSaysOff = true
                default: break
                }
                failure = failed.message
                return nil
            }
        }
        return nil
    }
}

/// The confirm every "Add to invoice" entry point shares, so an estimate is never added silently.
struct EstimateInvoiceOfferConfirm: ViewModifier {
    @Binding var offer: EstimateInvoiceOffer?
    @ObservedObject var adder: EstimateInvoiceAdder
    let onAdded: (InvoiceRecord) -> Void
    @EnvironmentObject private var api: APIClient

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.success, trigger: adder.added)
            .thorbisConfirm(item: $offer, title: { $0.title }, message: { $0.message },
                            cancelTitle: "Not now") { offer in
                [ThorbisConfirmAction("Add to invoice") {
                    Task { if let updated = await adder.add(offer, api: api) { onAdded(updated) } }
                }]
            }
    }
}

/// "Add to invoice" as a row of the job's estimates card, under the approved estimate it adds.
struct EstimateAddToInvoiceRow: View {
    let estimate: EstimateRecord
    @ObservedObject var adder: EstimateInvoiceAdder
    let action: () -> Void

    var body: some View {
        let busy = adder.addingEstimateID == estimate.id
        Button(action: action) {
            HStack(spacing: 12) {
                PaperIcon(.jobPlus, size: 18, color: Theme.brandText).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(busy ? "Adding\u{2026}" : "Add to invoice").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.brandText)
                    Text("Put it on the job\u{2019}s invoice").font(Theme.font(14)).foregroundStyle(Theme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(adder.addingEstimateID != nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Asks before adding this estimate\u{2019}s lines to the invoice")
        .accessibilityIdentifier("job-estimate-add-to-invoice-\(estimate.id)")
    }
}

/// The estimate's own page: finds the job's invoice and offers "Add to invoice" when this approved
/// estimate is not on it yet. Draws nothing when the flag is off or there is nothing to add to.
struct EstimateAddToInvoiceCard: View {
    let estimate: EstimateRecord
    let jobID: String
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @StateObject private var adder = EstimateInvoiceAdder()
    @State private var invoice: InvoiceRecord?
    @State private var offer: EstimateInvoiceOffer?
    @State private var justAdded = false

    private var enabled: Bool {
        session.isFeatureOn(InvoiceRevisionWords.flag) && estimate.status == "approved"
            && session.can("invoice.view", feature: "invoicing") && session.can("invoice.edit", feature: "invoicing")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear.frame(width: 0, height: 0)
            if enabled, let invoice {
                if justAdded {
                    Label("On the invoice", systemImage: "checkmark.circle")
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.success)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 4)
                        .accessibilityIdentifier("estimate-on-invoice")
                } else if InvoiceEstimateBilling.canOffer(estimate: estimate, invoice: invoice, billed: adder.billed(on: invoice),
                                                          flagOn: true, canEditInvoice: true, serverSaysOff: adder.serverSaysOff) {
                    Button { offer = EstimateInvoiceOffer(estimate: estimate, invoice: invoice) } label: {
                        Text(adder.addingEstimateID == nil ? "Add to invoice" : "Adding\u{2026}")
                            .paperButton(.secondary, tone: .tinted, fills: true)
                    }
                    .buttonStyle(PressStyle())
                    .disabled(adder.addingEstimateID != nil)
                    .accessibilityHint("Asks before adding this estimate\u{2019}s lines to the job\u{2019}s invoice")
                    .accessibilityIdentifier("estimate-add-to-invoice")
                }
                if let failure = adder.failure { ErrorBanner(message: failure, outer: 0) }
            }
        }
        .task(id: "\(estimate.id)|\(estimate.status)|\(jobID)|\(session.generation)|\(enabled)") { await load() }
        .modifier(EstimateInvoiceOfferConfirm(offer: $offer, adder: adder) { updated in
            invoice = updated
            justAdded = true
        })
    }

    private func load() async {
        guard enabled else { invoice = nil; return }
        guard let invoices = try? await api.fieldJobInvoices(jobID), !Task.isCancelled,
              let found = InvoiceEstimateBilling.jobInvoice(invoices, jobID: jobID) else { return }
        await adder.loadBilled(invoiceID: found.id, api: api)
        guard !Task.isCancelled else { return }
        invoice = found
    }
}

// MARK: - Changes on the invoice

/// "Changes": every version of the invoice, newest first, one plain row each; a row opens that
/// version's lines. Hidden when the read is refused or the server has no such route.
struct InvoiceChangesSection: View {
    let invoice: InvoiceRecord
    let reference: String
    var onLoaded: (InvoiceRevisionHistory?) -> Void = { _ in }
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var history: InvoiceRevisionHistory?
    @State private var opened: InvoiceRevisionRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear.frame(width: 0, height: 0)
            if let history, !history.items.isEmpty {
                SectionHeader(title: "Changes", count: history.items.count > 1 ? history.items.count : nil)
                VStack(alignment: .leading, spacing: 0) {
                    let newestFirst = Array(history.items.reversed())
                    ForEach(newestFirst) { item in
                        Button { opened = item } label: { row(item) }
                            .buttonStyle(RowPressStyle())
                            .overlay(alignment: .top) { if item.id != newestFirst.first?.id { WellDivider(leading: 16) } }
                            .accessibilityHint("Shows this version\u{2019}s lines")
                            .accessibilityIdentifier("invoice-change-\(item.linesRevision)")
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("invoice-changes")
        .task(id: "\(invoice.id)|\(invoice.linesRevision)|\(invoice.customerAuthorization?.id ?? "")|\(session.generation)") { await load() }
        .thorbisDestination(item: $opened) { item in
            InvoiceRevisionLinesView(item: item, reference: reference)
        }
    }

    private func row(_ item: InvoiceRevisionRecord) -> some View {
        let when = InvoiceRevisionWords.when(item.revisedAt)
        let signed = item.authorization.map { "Signed by \($0.signerName)" }
        let detail = [when, signed].compactMap { $0 }.joined(separator: " \u{00B7} ")
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(InvoiceRevisionWords.kindWord(item.kind)) \u{00B7} \(InvoiceRevisionWords.amounts(item))")
                    .font(Theme.font(15)).foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !detail.isEmpty {
                    Text(detail).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        // The history only exists once the server keeps invoice versions; until then asking for it
        // would be one wasted request on every invoice.
        guard session.isFeatureOn("invoice_revisions"), session.can("invoice.view", feature: "invoicing") else {
            history = nil
            onLoaded(nil)
            return
        }
        do {
            let read = try await api.fieldInvoiceRevisions(invoice.id)
            guard !Task.isCancelled, read.invoiceId == invoice.id else { return }
            history = read
            onLoaded(read)
        } catch is CancellationError {
        } catch {
            // A refusal, an older server or no signal: no section, and nothing claimed about it.
            guard !Task.isCancelled else { return }
            history = nil
            onLoaded(nil)
        }
    }
}

/// One version of an invoice: what changed, when, and every line as it stood then.
struct InvoiceRevisionLinesView: View {
    let item: InvoiceRevisionRecord
    let reference: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reference).font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.muted)
                    Text(InvoiceRevisionWords.kindWord(item.kind)).font(Theme.heading()).tracking(-0.56)
                        .foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    let facts = [InvoiceRevisionWords.amounts(item), InvoiceRevisionWords.when(item.revisedAt)].compactMap { $0 }
                    Text(facts.joined(separator: " \u{00B7} ")).font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.gutter - PaperCardMetrics.margin)
                if let signed = item.authorization {
                    Label("Signed by \(signed.signerName)\(JobFiltering.date(signed.signedAt).map { " \u{00B7} " + $0.stampLabel() } ?? "")",
                          systemImage: "signature")
                        .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.success)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
                EstimateDetailView.LinesCard(label: "Line items", lines: item.lines, totalLabel: "Total",
                                             total: item.total.amount, currency: item.total.currency)
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 14).padding(.bottom, 28)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("invoice-change-detail")
    }
}
