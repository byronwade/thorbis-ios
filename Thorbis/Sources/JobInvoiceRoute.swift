import Foundation

/// Identifies the exact job invoice and authority under which its detail was opened.
/// This is navigation context only; it never establishes server-side job membership.
struct JobInvoiceRoute: Hashable {
    let jobID: String
    let invoiceID: String
    let organizationID: String
    let customerID: String
    let actorID: String
    let sessionGeneration: UUID
    let authorityRevision: UUID
    let presentationID: UUID
    let apiGeneration: UUID
    let apiOrigin: String

    func matches(jobID: String, organizationID: String, customerID: String,
                 actorID: String, sessionGeneration: UUID, authorityRevision: UUID,
                 presentationID: UUID, apiGeneration: UUID, apiOrigin: String) -> Bool {
        self.jobID == jobID && self.organizationID == organizationID && self.customerID == customerID &&
        self.actorID == actorID && self.sessionGeneration == sessionGeneration && self.authorityRevision == authorityRevision &&
        self.presentationID == presentationID && self.apiGeneration == apiGeneration && self.apiOrigin == apiOrigin
    }
}

/// A cancelled gesture or a non-top/multiple pop must not select an invoice.
enum JobInvoiceRouteTransition {
    /// Reports invoice routes removed by a native Back operation, including a multi-level pop.
    /// A push, cancellation or replacement of the surviving prefix never yields a return.
    static func completedPops<Route: Equatable>(from old: [Route], to new: [Route],
                                                invoice: (Route) -> JobInvoiceRoute?) -> [JobInvoiceRoute] {
        guard old.count > new.count, old.prefix(new.count).elementsEqual(new) else { return [] }
        return old.dropFirst(new.count).compactMap(invoice)
    }

    static func completedPop<Route: Equatable>(from old: [Route], to new: [Route],
                                               invoice: (Route) -> JobInvoiceRoute?) -> JobInvoiceRoute? {
        guard old.count == new.count + 1, old.dropLast().elementsEqual(new), let last = old.last else { return nil }
        return invoice(last)
    }
}
