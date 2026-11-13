import Foundation

/// Held prototype: provenance must be captured when the invoice is read, not when an editor opens.
struct InvoiceDraftOrigin: Equatable {
    let actor: String
    let organization: String
    let origin: String
    let invoice: String
    let customer: String
    let job: String?
    let revision: Int
}

/// Conservative policy only; the caller must supply genuinely verified source and authority.
struct InvoiceDraftSafety {
    enum WriteState { case idle, sending, uncertain }
    let source: InvoiceDraftOrigin
    private(set) var writeState: WriteState = .idle

    func canExpose(current: InvoiceDraftOrigin?, authorized: Bool) -> Bool {
        guard authorized, let current else { return false }
        return current.actor == source.actor && current.organization == source.organization &&
            current.origin == source.origin && current.invoice == source.invoice &&
            current.customer == source.customer && current.job == source.job
    }

    func canWrite(current: InvoiceDraftOrigin?, authorized: Bool) -> Bool {
        canExpose(current: current, authorized: authorized) && current == source && writeState == .idle
    }

    mutating func startWrite(current: InvoiceDraftOrigin?, authorized: Bool) -> Bool {
        guard canWrite(current: current, authorized: authorized) else { return false }
        writeState = .sending
        return true
    }

    mutating func writeResultUncertain() {
        guard writeState == .sending else { return }
        writeState = .uncertain
    }
}
