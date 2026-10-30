import Foundation

/// Current verified context supplied by the owning navigation stack and job view.
struct JobInvoiceReturnContext: Equatable {
    let jobID: String
    let organizationID: String
    let customerID: String
    let actorID: String
    let sessionGeneration: UUID
    let authorityRevision: UUID

    func contains(_ route: JobInvoiceRoute) -> Bool {
        route.matches(jobID: jobID, organizationID: organizationID, customerID: customerID,
                      actorID: actorID, sessionGeneration: sessionGeneration, authorityRevision: authorityRevision)
    }
}

/// Pure coordination policy. The app must provide live context, verified server membership,
/// and a matching payment model. This does not itself start navigation or network requests.
struct JobInvoiceReturnCoordinator {
    private var state = JobInvoiceReturnState()
    private var activeRoute: JobInvoiceRoute?
    private var activeRequest: UUID?

    mutating func completedPop<Route: Equatable>(from old: [Route], to new: [Route],
                                                  context: JobInvoiceReturnContext?,
                                                  invoice: (Route) -> JobInvoiceRoute?) -> UUID? {
        guard let route = JobInvoiceRouteTransition.completedPop(from: old, to: new, invoice: invoice) else { return nil }
        return begin(route, context: context)
    }

    mutating func begin(_ route: JobInvoiceRoute, context: JobInvoiceReturnContext?) -> UUID? {
        invalidate()
        guard let context, context.contains(route) else { return nil }
        activeRoute = route
        let request = state.begin(route)
        activeRequest = request
        return request
    }

    mutating func finish(requestID: UUID, context: JobInvoiceReturnContext?, fresh: Bool,
                         actualInvoiceID: String?, canCollect: Bool) {
        guard activeRequest == requestID, let route = activeRoute else { return }
        guard let context, context.contains(route) else { invalidate(); return }
        state.finish(requestID: requestID, scopeValid: true, fresh: fresh,
                     actualInvoiceID: actualInvoiceID, canCollect: canCollect)
        activeRequest = nil
    }

    func visibleInvoiceID(in context: JobInvoiceReturnContext?) -> String? {
        guard let route = activeRoute, let context, context.contains(route) else { return nil }
        return state.collectibleInvoiceID
    }

    mutating func collectibleInvoiceID(in context: JobInvoiceReturnContext?) -> String? {
        guard let route = activeRoute, let context, context.contains(route) else { invalidate(); return nil }
        return state.collectibleInvoiceID
    }

    mutating func invalidate() {
        state.invalidate()
        activeRoute = nil
        activeRequest = nil
    }
}
