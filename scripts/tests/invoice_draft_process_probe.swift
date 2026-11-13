import Foundation
import CryptoKit
import Darwin

@main struct InvoiceDraftProcessProbe {
    static func main() async throws {
        let args = CommandLine.arguments
        let domain = InvoiceFenceDomain(origin: "https://app.thorbis.com", organizationID: "00000000-0000-4000-8000-000000000001", invoiceID: "00000000-0000-4000-8000-000000000002")
        let scope = InvoiceIdleCaptureIdentity(domain: domain, actorID: "00000000-0000-4000-8000-000000000003", customerID: "00000000-0000-4000-8000-000000000004", jobID: nil)
        let key = SymmetricKey(data: Data(repeating: 42, count: 32)) // Synthetic probe key only.
        if args.count == 4 && args[1] == "child" {
            let owner = UUID(uuidString: args[3])!
            let fence = try InvoiceTransactionFence(path: args[2])
            let identity = InvoiceEditorAuthorityIdentity(actorID: scope.actorID, organizationID: domain.organizationID, origin: domain.origin, sessionGeneration: UUID(), authorityRevision: UUID())
            let writer = InvoiceSerialDraftWriter(fence: fence, identity: scope, authority: identity, owner: owner)
            var gate = InvoiceEditorRetirementGate(identity: identity, scope: scope, owner: owner)
            let sequence = gate.reserveEdit()!
            let sealed = try InvoiceDraftCipher.seal(Data("synthetic unfinished edit".utf8), identity: scope, owner: owner, sequence: sequence, key: key)
            precondition(gate.bind(sealed))
            let receipt = try await writer.capture(sealed, authority: identity)
            gate.acknowledge(receipt)
            precondition(gate.retirement == .durable)
            // Terminate without Swift cleanup after the store has acknowledged the commit.
            kill(getpid(), SIGKILL)
            preconditionFailure("kill returned")
        }
        let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("invoice-process-\(UUID().uuidString).sqlite").path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let owner = UUID(), child = Process()
        child.executableURL = URL(fileURLWithPath: args[0])
        child.arguments = ["child", path, owner.uuidString]
        try child.run(); child.waitUntilExit()
        precondition(child.terminationReason == .uncaughtSignal && child.terminationStatus == SIGKILL)
        let reopened = try InvoiceTransactionFence(path: path)
        let stored = try reopened.recoverIdle(identity: scope)!
        precondition(stored.owner == owner && stored.sequence == 1)
        let raw = try InvoiceDraftCipher.open(stored.bytes, identity: scope, owner: owner, sequence: stored.sequence, key: key)
        precondition(raw == Data("synthetic unfinished edit".utf8))
        print("invoice draft: acknowledged encrypted snapshot survived child process termination")
    }
}
