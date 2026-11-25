import Foundation

/// What the phone says its alerts are about. Everyone assigned a job gets New job assigned and
/// Job rescheduled. Payment received goes only to owners and dispatchers who may view the invoice
/// (the server's staff-push.ts planPaymentReceivedPush, recipients from listOfficeMembers in
/// adapters.ts). The phone knows capabilities, not roles, so payments are named only for people
/// who could be one, and always with who gets them.
enum AlertWords {
    /// Could this person be sent Payment received? Technicians may view invoices on their own
    /// jobs, so invoice.view alone is not enough; job.cancel is held by owners, admins, office
    /// managers and dispatchers. No invoicing-feature check: the server sends without one.
    static func includesPayments(capabilities: Set<String>) -> Bool {
        capabilities.contains("invoice.view") && capabilities.contains("job.cancel")
    }

    /// My notifications and the Device access row.
    static func summary(payments: Bool) -> String {
        payments
            ? "New jobs and schedule changes. Payments received, for owners and dispatchers"
            : "New jobs and schedule changes"
    }

    /// The join screen's Notifications row, next to Turn on.
    static func joinSummary(payments: Bool) -> String {
        payments ? "New jobs and changes. Payments for owners and dispatchers" : "New jobs and changes"
    }

    /// The points on the notification explainer before the system asks.
    static func primerPoints(payments: Bool) -> [String] {
        payments
            ? ["New jobs", "Schedule changes", "Payments received, for owners and dispatchers", "The morning digest, if you turn it on"]
            : ["New jobs", "Schedule changes", "The morning digest, if you turn it on"]
    }
}
