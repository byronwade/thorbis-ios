import Foundation

/// A record an activity row can open. A call or message with no job and no contact stays closed,
/// and a payment stays closed until the row names both the invoice and the payment.
enum ActivityDestination: Equatable {
    case job(String)
    case estimate(String)
    case invoice(String)
    case media(jobID: String, assetID: String)
    case note(jobID: String, noteID: String)
    case payment(invoiceID: String, paymentID: String)
    case contact(customerID: String, contactID: String)
    case location(customerID: String, locationID: String)

    var route: PaperRoute {
        switch self {
        case .job(let id): .job(id)
        case .estimate(let id): .estimate(id)
        case .invoice(let id): .invoice(id)
        case .media(let jobID, let assetID): .media(jobID: jobID, assetID: assetID)
        case .note(let jobID, let noteID): .note(jobID: jobID, noteID: noteID)
        case .payment(let invoiceID, _): .invoice(invoiceID)
        case .contact(let customerID, let contactID): .contact(customerID: customerID, contactID: contactID)
        case .location(let customerID, let locationID): .location(customerID: customerID, locationID: locationID)
        }
    }
}

/// Identifiers a feed row already carries. Nothing here is invented to fill a gap.
struct ActivityFeedSubject: Equatable {
    var kind: String
    var subjectID: String?
    var jobID: String?
    var invoiceID: String?
    var customerID: String?

    init(kind: String, subjectID: String? = nil, jobID: String? = nil, invoiceID: String? = nil, customerID: String? = nil) {
        self.kind = kind
        self.subjectID = subjectID
        self.jobID = jobID
        self.invoiceID = invoiceID
        self.customerID = customerID
    }
}

enum ActivityDestinationMapping {
    static func destination(for subject: ActivityFeedSubject) -> ActivityDestination? {
        switch subject.kind.lowercased() {
        case "job", "status":
            return id(subject.jobID ?? subject.subjectID).map(ActivityDestination.job)
        case "estimate":
            return id(subject.subjectID).map(ActivityDestination.estimate)
        case "invoice", "created", "issued":
            return id(subject.invoiceID ?? subject.subjectID).map(ActivityDestination.invoice)
        case "photo", "media", "document":
            guard let jobID = id(subject.jobID), let assetID = id(subject.subjectID) else { return nil }
            return .media(jobID: jobID, assetID: assetID)
        case "note":
            guard let jobID = id(subject.jobID), let noteID = id(subject.subjectID) else { return nil }
            return .note(jobID: jobID, noteID: noteID)
        case "payment":
            guard let invoiceID = id(subject.invoiceID), let paymentID = id(subject.subjectID) else { return nil }
            return .payment(invoiceID: invoiceID, paymentID: paymentID)
        case "contact":
            guard let customerID = id(subject.customerID), let contactID = id(subject.subjectID) else { return nil }
            return .contact(customerID: customerID, contactID: contactID)
        case "location":
            guard let customerID = id(subject.customerID), let locationID = id(subject.subjectID) else { return nil }
            return .location(customerID: customerID, locationID: locationID)
        case "call", "message":
            if let jobID = id(subject.jobID) { return .job(jobID) }
            if let customerID = id(subject.customerID), let contactID = id(subject.subjectID) {
                return .contact(customerID: customerID, contactID: contactID)
            }
            return nil
        default:
            return nil
        }
    }

    /// Customer history names the subject and the customer. It does not name an invoice for a payment.
    static func customerHistory(_ entry: CustomerHistoryEntry, customerID: String) -> ActivityDestination? {
        destination(for: ActivityFeedSubject(kind: entry.kind, subjectID: entry.subjectId, customerID: customerID))
    }

    private static func id(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
