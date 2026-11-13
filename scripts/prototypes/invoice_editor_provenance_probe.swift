import Foundation

@main struct Probe {
    static func main() {
        let source = InvoiceDraftOrigin(actor: "a", organization: "o", origin: "https://one", invoice: "i", customer: "c", job: "j", revision: 4)
        var state = InvoiceDraftSafety(source: source)
        let same = InvoiceDraftOrigin(actor: "a", organization: "o", origin: "https://one", invoice: "i", customer: "c", job: "j", revision: 4)
        precondition(state.canExpose(current: same, authorized: true))
        precondition(!state.canExpose(current: same, authorized: false))
        let other = InvoiceDraftOrigin(actor: "a", organization: "o", origin: "https://two", invoice: "i", customer: "c", job: "j", revision: 4)
        precondition(!state.canExpose(current: other, authorized: true))
        let otherActor = InvoiceDraftOrigin(actor: "b", organization: "o", origin: "https://one", invoice: "i", customer: "c", job: "j", revision: 4)
        let otherCustomer = InvoiceDraftOrigin(actor: "a", organization: "o", origin: "https://one", invoice: "i", customer: "x", job: "j", revision: 4)
        let otherJob = InvoiceDraftOrigin(actor: "a", organization: "o", origin: "https://one", invoice: "i", customer: "c", job: "k", revision: 4)
        precondition(!state.canExpose(current: otherActor, authorized: true))
        precondition(!state.canExpose(current: otherCustomer, authorized: true))
        precondition(!state.canExpose(current: otherJob, authorized: true))
        precondition(!state.canExpose(current: nil, authorized: true))
        let newer = InvoiceDraftOrigin(actor: "a", organization: "o", origin: "https://one", invoice: "i", customer: "c", job: "j", revision: 5)
        precondition(state.canExpose(current: newer, authorized: true), "a conflict must retain a readable draft")
        precondition(!state.canWrite(current: newer, authorized: true))
        precondition(state.startWrite(current: same, authorized: true))
        precondition(!state.canWrite(current: same, authorized: true))
        state.writeResultUncertain()
        precondition(!state.canWrite(current: same, authorized: true))
        precondition(!state.canWrite(current: same, authorized: true), "uncertain outcome must stay fenced")
        print("invoice provenance and uncertainty probe passed")
    }
}
