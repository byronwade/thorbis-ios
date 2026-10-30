import Foundation

/// Policy for a returned job invoice. The caller must independently verify server membership,
/// session authority and payment-model eligibility before passing a successful result.
struct JobInvoiceReturnState {
    private enum Phase {
        case idle
        case refreshing(route: JobInvoiceRoute, requestID: UUID)
        case ready(route: JobInvoiceRoute)
        case unavailable(route: JobInvoiceRoute)
    }

    private var phase: Phase = .idle

    var collectibleInvoiceID: String? {
        guard case let .ready(route) = phase else { return nil }
        return route.invoiceID
    }

    @discardableResult
    mutating func begin(_ route: JobInvoiceRoute) -> UUID {
        let requestID = UUID()
        phase = .refreshing(route: route, requestID: requestID)
        return requestID
    }

    mutating func finish(requestID: UUID, scopeValid: Bool, fresh: Bool,
                         actualInvoiceID: String?, canCollect: Bool) {
        guard case let .refreshing(route, currentRequestID) = phase, currentRequestID == requestID else { return }
        if scopeValid && fresh && actualInvoiceID == route.invoiceID && canCollect {
            phase = .ready(route: route)
        } else {
            phase = .unavailable(route: route)
        }
    }

    mutating func invalidate() { phase = .idle }
}
