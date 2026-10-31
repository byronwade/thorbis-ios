import Foundation

// Technician job flow (design.thorbis.com/technician-flow, TF-01..TF-12): the job screen always
// carries the one next step, in the order a tech works a call: on my way, arrived, start work,
// build the estimate, show it to the customer, create the invoice, collect, wrap up. Pure so the
// order and every skip can be tested without a server.

/// What the technician may do on this job, from the session's capabilities.
struct TechJobAbilities: Equatable {
    var createEstimate = false
    var sendEstimate = false
    var approveEstimate = false
    var createInvoice = false
    var viewInvoice = false
    var collectPayment = false
    var completeJob = false

    static let all = TechJobAbilities(createEstimate: true, sendEstimate: true, approveEstimate: true, createInvoice: true,
                                      viewInvoice: true, collectPayment: true, completeJob: true)
}

enum TechJobStep: Equatable {
    /// A status step the server allows next: en_route, arrived, in_progress or dispatched.
    case transition(String)
    case buildEstimate
    /// The estimate to hand the customer: a draft is issued first, then shown (TF-05).
    case showEstimate(id: String)
    case presentEstimates
    case createInvoice
    case reviewInvoice(id: String)
    case collect(invoiceID: String, due: Int, currency: String)
    case wrapUp

    /// TF-03: a verb and its object, in the words a tech says out loud.
    func title(resuming: Bool = false) -> String {
        switch self {
        case .transition(let target):
            switch target {
            case "en_route": "On my way"
            case "arrived": "Arrive"
            case "in_progress": resuming ? "Resume work" : "Start work"
            case "dispatched": "Dispatch"
            default: "Mark \(target.statusLabel.lowercased())"
            }
        case .buildEstimate: "Build estimate"
        case .showEstimate: "Show estimate to customer"
        case .presentEstimates: "Approve estimates"
        case .createInvoice: "Create invoice"
        case .reviewInvoice: "Review invoice"
        case .collect(_, let due, let currency): "Collect \(money(due, currency: currency))"
        case .wrapUp: "Wrap up job"
        }
    }

    var symbol: String {
        switch self {
        case .transition(let target):
            switch target {
            case "en_route": "location.fill"
            case "arrived": "mappin.and.ellipse"
            case "in_progress": "wrench.and.screwdriver"
            default: "paperplane"
            }
        case .buildEstimate: "doc.badge.plus"
        case .showEstimate, .presentEstimates: "person.crop.rectangle"
        case .createInvoice: "doc.plaintext"
        case .reviewInvoice: "doc.text.magnifyingglass"
        case .collect: "creditcard"
        case .wrapUp: "checkmark.seal"
        }
    }
}

enum TechJobFlow {
    /// Status steps that move the call forward, in the order they happen. Pause, reschedule and
    /// dispatch-back are never the next step (TF-04); they stay on the job as rows.
    static let forwardSteps = ["en_route", "arrived", "in_progress"]

    /// TF-01: the one next step on the job, or nil when nothing is left for the tech.
    /// - Parameters:
    ///   - status: the job's status as shown (a queued offline step counts).
    ///   - transitions: the status steps the server allows and this role may take.
    ///   - estimates/invoices: the job's own, once loaded; nil while still loading.
    static func nextStep(status: String, transitions: [String], estimates: [EstimateRecord]?,
                         invoices: [InvoiceRecord]?, can: TechJobAbilities) -> TechJobStep? {
        switch status {
        case "canceled": return nil
        case "in_progress", "completed": break
        default:
            // Before the work starts, the bar walks the visit: on my way, arrived, start (or resume).
            if let step = forwardSteps.first(where: transitions.contains) { return .transition(step) }
            if transitions.contains("dispatched") { return .transition("dispatched") }
            return nil
        }
        // Money steps need the job's paper; until it loads the bar waits rather than guess.
        guard let invoices = can.viewInvoice ? invoices : [], let estimates else { return nil }
        let live = invoices.filter { $0.status != "void" }

        if can.collectPayment, let owed = live.first(where: { $0.status == "issued" && (due($0) ?? 0) > 0 }), let amount = due(owed) {
            return .collect(invoiceID: owed.id, due: amount, currency: owed.currency)
        }
        if let draft = live.first(where: { $0.status == "draft" }) {
            return can.viewInvoice ? .reviewInvoice(id: draft.id) : nil
        }
        // A deposit or progress bill isn't the job's bill; only the completion invoice is.
        if live.contains(where: { $0.origin == "job_completion" }) {
            // Billed and settled, or owed in a way this role can't collect: closeout records why.
            return status == "completed" || !can.completeJob ? nil : .wrapUp
        }
        if status == "completed" { return nil }

        // Each sent estimate can represent independent work, even after another was approved.
        if estimates.contains(where: { $0.status == "sent" && canShow($0, can: can) }) {
            return .presentEstimates
        }
        // Not billed yet. Approved work becomes the invoice; otherwise the estimate comes first.
        if estimates.contains(where: { $0.status == "approved" }) {
            return can.createInvoice ? .createInvoice : (can.completeJob ? .wrapUp : nil)
        }
        if let pending = estimates.first(where: { $0.status == "draft" }),
           canShow(pending, can: can) {
            return .showEstimate(id: pending.id)
        }
        let allDeclined = !estimates.isEmpty && estimates.allSatisfy { $0.status == "declined" }
        // TF-07: a declined estimate still bills the trip; no estimate means build one first.
        if allDeclined, can.createInvoice { return .createInvoice }
        if estimates.isEmpty, can.createEstimate { return .buildEstimate }
        if can.createInvoice { return .createInvoice }
        return can.completeJob ? .wrapUp : nil
    }

    /// The customer can only be handed an estimate this role can issue and approve in person.
    static func canShow(_ estimate: EstimateRecord, can: TechJobAbilities) -> Bool {
        guard can.approveEstimate else { return false }
        let hasOptions = !(estimate.options ?? []).isEmpty
        switch estimate.status {
        case "draft": return can.sendEstimate
        case "sent": return !hasOptions || can.sendEstimate
        default: return false
        }
    }

    /// Balance due in cents, or nil when the lines can't be totalled exactly.
    static func due(_ invoice: InvoiceRecord) -> Int? {
        guard let total = paperLinesTotal(invoice.lines) else { return nil }
        return max(0, total - invoice.amountPaid)
    }
}
