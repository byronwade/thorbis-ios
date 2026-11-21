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
            // Paper F2 "Driving": the commit reads "I've arrived".
            case "arrived": "I've arrived"
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
    /// How far along the visit each status is. Paused sits with arrived so the bar offers Resume.
    private static let forwardRank = ["scheduled": 0, "dispatched": 0, "en_route": 1, "arrived": 2, "paused": 2, "in_progress": 3]

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
            // The server also allows stepping back (arrived lists en_route), so only a step
            // after the current one is the next one: never "On my way" once the tech is there.
            let reached = forwardRank[status] ?? 0
            if let step = forwardSteps.first(where: { transitions.contains($0) && (forwardRank[$0] ?? 0) > reached }) {
                return .transition(step)
            }
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

// MARK: Nothing locked by stage

extension TechJobFlow {
    /// The money moves the bar keeps one tap away at every stage, beside its one next step: what
    /// is owed, then the estimate to show the customer, or a new estimate when there is none to
    /// show. Whatever the bar's own step already is, is left out. A canceled job offers nothing.
    static func sideSteps(status: String, primary: TechJobStep?, estimates: [EstimateRecord]?,
                          invoices: [InvoiceRecord]?, can: TechJobAbilities) -> [TechJobStep] {
        guard status != "canceled" else { return [] }
        var steps: [TechJobStep] = []
        if can.viewInvoice, can.collectPayment, let invoices,
           let owed = invoices.first(where: { $0.status == "issued" && (due($0) ?? 0) > 0 }), let amount = due(owed) {
            steps.append(.collect(invoiceID: owed.id, due: amount, currency: owed.currency))
        }
        if let estimates {
            if estimates.contains(where: { $0.status == "sent" && canShow($0, can: can) }) {
                steps.append(.presentEstimates)
            } else if let draft = estimates.first(where: { $0.status == "draft" && canShow($0, can: can) }) {
                steps.append(.showEstimate(id: draft.id))
            } else if can.createEstimate, !["scheduled", "dispatched", "en_route"].contains(status) {
                // Before arriving nobody is pricing work; "+" still starts an estimate from there.
                steps.append(.buildEstimate)
            }
        }
        return steps.filter { $0 != primary }
    }
}

extension TechJobStep {
    /// The short words for a step riding beside the bar's commit ("Collect $340.00", "Show estimate").
    var sideTitle: String {
        switch self {
        case .buildEstimate: "New estimate"
        case .showEstimate, .presentEstimates: "Show estimate"
        default: title()
        }
    }
}

/// One thing "Add to job" can offer (Paper 22's rows, plus the money moves a tech reaches for
/// at any stage).
enum JobAddKind: String, Equatable, CaseIterable {
    case estimate, showEstimate, invoice, openInvoice, payment, plan, photo, note, contact
}

/// What "Add to job" offers. The server refuses none of these by job stage (only a canceled job
/// is closed to them), so the stage never hides a row: only the role and what the job already has.
enum JobAddOffer {
    struct Inputs: Equatable {
        var status = "scheduled"
        var canCreateEstimate = false
        /// The job has estimates and this person may hand them to the customer.
        var canShowEstimates = false
        /// No invoice on the job yet, and this person may make one.
        var canCreateInvoice = false
        /// The job has an invoice this person may open.
        var canOpenInvoice = false
        /// Something is owed on an issued invoice and this person may take the payment.
        var canCollect = false
        var canAddMedia = false
        var canAddNote = false
        var canAddContact = false
        /// The workspace sells a maintenance plan, this person may change the customer, and the
        /// customer isn't on one yet.
        var canAddPlan = false
    }

    static func rows(_ inputs: Inputs) -> (billing: [JobAddKind], onTheJob: [JobAddKind]) {
        var billing: [JobAddKind] = []
        var onTheJob: [JobAddKind] = []
        let open = inputs.status != "canceled"
        if open {
            if inputs.canCreateEstimate { billing.append(.estimate) }
            if inputs.canShowEstimates { billing.append(.showEstimate) }
            if inputs.canCreateInvoice { billing.append(.invoice) } else if inputs.canOpenInvoice { billing.append(.openInvoice) }
            if inputs.canCollect { billing.append(.payment) }
            if inputs.canAddPlan { billing.append(.plan) }
            if inputs.canAddMedia { onTheJob.append(.photo) }
        }
        // A note and a contact are records about the job and its customer; they stay on a canceled job.
        if inputs.canAddNote { onTheJob.append(.note) }
        if inputs.canAddContact { onTheJob.append(.contact) }
        return (billing, onTheJob)
    }
}

/// "Add to job › Maintenance plan": offered to someone who may change the customer, when the
/// workspace sells at least one plan and the customer isn't already a member. Online only.
enum JobAddPlan {
    static func canOffer(canEditCustomer: Bool, plans: Int, isMember: Bool?, offline: Bool) -> Bool {
        canEditCustomer && plans > 0 && isMember != true && !offline
    }
}

/// When the visit's two "something is wrong" moves are offered.
enum JobVisitGates {
    /// Running late is a text about the arrival, so it is offered until the tech has arrived.
    static func canSendRunningLate(status: String, hasSchedule: Bool) -> Bool {
        hasSchedule && ["scheduled", "dispatched", "en_route"].contains(status)
    }

    /// Can't start records a follow-up for the office. The server takes one on any job that isn't
    /// canceled; it only makes sense before the work has started.
    static func canReportCantStart(status: String, canEditJob: Bool) -> Bool {
        canEditJob && ["scheduled", "dispatched", "en_route", "arrived"].contains(status)
    }
}

/// The office's description on the visit's cards: long words fold to a few lines with "Show more".
enum JobDescriptionFold {
    static let foldedLines = 4
    /// Roughly what four lines hold on a phone; a line break counts as a line of its own.
    static func isLong(_ text: String) -> Bool {
        text.count > 180 || text.split(separator: "\n", omittingEmptySubsequences: false).count > foldedLines
    }
}
