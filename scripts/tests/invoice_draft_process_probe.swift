import Foundation
import CryptoKit
import Darwin

@main struct InvoiceDraftProcessProbe {
    static func main() async throws {
        let args = CommandLine.arguments
        let domain = InvoiceFenceDomain(origin: "https://app.thorbis.com", organizationID: "00000000-0000-4000-8000-000000000001", invoiceID: "00000000-0000-4000-8000-000000000002")
        let scope = InvoiceIdleCaptureIdentity(domain: domain, actorID: "00000000-0000-4000-8000-000000000003", customerID: "00000000-0000-4000-8000-000000000004", jobID: nil)
        let key = SymmetricKey(data: Data(repeating: 42, count: 32)) // Synthetic probe key only.
        if args.count == 5 && args[1] == "child-ambiguous-commit" {
            let owner = UUID(uuidString: args[3])!
            let fence = try InvoiceTransactionFence(path: args[2])
            let identity = InvoiceEditorAuthorityIdentity(actorID: scope.actorID, organizationID: domain.organizationID, origin: domain.origin, sessionGeneration: UUID(), authorityRevision: UUID())
            let writer = InvoiceSerialDraftWriter(fence: fence, identity: scope, authority: identity, owner: owner)
            var gate = InvoiceEditorRetirementGate(identity: identity, scope: scope, owner: owner)
            let sequence = gate.reserveEdit()!
            let sealed = try InvoiceDraftCipher.seal(Data("ambiguous edit".utf8), identity: scope, owner: owner, sequence: sequence, key: key)
            precondition(gate.bind(sealed))
            do { _ = try await writer.capture(sealed, authority: identity); preconditionFailure("ambiguous result acknowledged") } catch { gate.fail(sequence) }
            precondition(gate.retirement == .failed)
            do { _ = try await writer.capture(sealed, authority: identity); preconditionFailure("held writer retried") } catch { }
            return
        }
        if args.count == 5 && args[1] == "child-before-commit" {
            let owner = UUID(uuidString: args[3])!
            let fence = try InvoiceTransactionFence(path: args[2])
            let sealed = try InvoiceDraftCipher.seal(Data("uncommitted edit".utf8), identity: scope, owner: owner, sequence: 2, key: key)
            _ = try fence.capture(identity: scope, owner: owner, expectedVersion: 1, sequence: 2, bytes: sealed.ciphertext)
            preconditionFailure("test hook did not terminate child")
        }
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
        let interrupted = Process()
        interrupted.executableURL = URL(fileURLWithPath: args[0])
        interrupted.arguments = ["child-before-commit", path, owner.uuidString, "--invoice-fence-test-kill-before-commit"]
        try interrupted.run(); interrupted.waitUntilExit()
        precondition(interrupted.terminationReason == .uncaughtSignal && interrupted.terminationStatus == SIGKILL)
        let after = try InvoiceTransactionFence(path: path).recoverIdle(identity: scope)!
        precondition(after.sequence == 1 && after.bytes == stored.bytes)
        let ambiguousPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("invoice-ambiguous-\(UUID().uuidString).sqlite").path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: ambiguousPath + suffix) } }
        let ambiguousOwner = UUID(), ambiguous = Process()
        ambiguous.executableURL = URL(fileURLWithPath: args[0])
        ambiguous.arguments = ["child-ambiguous-commit", ambiguousPath, ambiguousOwner.uuidString, "--invoice-fence-test-ambiguous-after-commit"]
        try ambiguous.run(); ambiguous.waitUntilExit()
        precondition(ambiguous.terminationReason == .exit && ambiguous.terminationStatus == 0)
        let ambiguousStored = try InvoiceTransactionFence(path: ambiguousPath).recoverIdle(identity: scope)!
        let ambiguousRaw = try InvoiceDraftCipher.open(ambiguousStored.bytes, identity: scope, owner: ambiguousOwner, sequence: 1, key: key)
        precondition(ambiguousRaw == Data("ambiguous edit".utf8))
        print("invoice draft: prior snapshot survives interruption; live writer holds after simulated lost local acknowledgment")
    }
}
