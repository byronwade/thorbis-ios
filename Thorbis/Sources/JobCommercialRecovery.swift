import Foundation

/// What the closeout checklist offers for one blocked requirement (web job-commercial-recovery.tsx).
/// The server's `nextAction` names the exact domain action; this only turns it into words and,
/// where the phone can do it, one button. Each command reauthorizes on the server.
enum CloseoutNextStep: Equatable {
    /// No completion invoice is linked yet: create (or find) it through Invoicing's idempotent command.
    case createInvoice
    /// The completion invoice exists and still owes money: open it to collect.
    case collectPayment
    /// A billing schedule owns the remainder; it is settled from the schedule, not a job invoice.
    case openBilling
    /// Satisfied by the unpaid follow-up fields further down the screen.
    case recordUnpaid
    /// Done elsewhere on the job (a note, photos, a signature, a check), so only words.
    case hint(String)

    init?(_ requirement: FieldCloseoutRequirement) {
        guard requirement.outcome == "blocked", let action = requirement.nextAction else { return nil }
        let fromSchedule = requirement.commercialSource == "schedule"
        switch action {
        case "reconcile_commercial_state": self = fromSchedule ? .openBilling : .createInvoice
        case "collect_payment": self = fromSchedule ? .openBilling : .collectPayment
        case "record_unpaid_disposition": self = .recordUnpaid
        case "add_job_note": self = .hint("Add a note on the job.")
        case "add_job_photo": self = .hint("Add photos on the job.")
        case "collect_customer_authorization": self = .hint("Get the customer's signature on the invoice.")
        default:
            if action.hasPrefix("acknowledge_check:") { self = .hint("Confirm it below.") } else { return nil }
        }
    }

    var detail: String? {
        switch self {
        case .createInvoice: "No invoice is linked to this job yet."
        case .collectPayment: "The invoice still has a balance."
        case .openBilling: "This balance is on a billing schedule."
        case .recordUnpaid: "Collect payment, or record why it stays unpaid below."
        case .hint(let text): text
        }
    }

    var buttonTitle: String? {
        switch self {
        case .createInvoice: "Create invoice"
        case .collectPayment, .recordUnpaid: "Collect payment"
        case .openBilling: "Open billing"
        case .hint: nil
        }
    }

    /// The capabilities the server will check, used only to decide whether to offer the button.
    var capabilities: [String] {
        switch self {
        case .createInvoice: ["invoice.create", "invoice.view"]
        case .collectPayment, .openBilling, .recordUnpaid: ["invoice.view"]
        case .hint: []
        }
    }
}
