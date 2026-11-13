import Foundation
import CryptoKit

@main struct InvoiceSerialCaptureProbe {
    static func main() async throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("invoice-serial-\(UUID().uuidString).sqlite").path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let domain = InvoiceFenceDomain(origin: "https://app.thorbis.com", organizationID: "00000000-0000-4000-8000-000000000001", invoiceID: "00000000-0000-4000-8000-000000000002")
        let scope = InvoiceIdleCaptureIdentity(domain: domain, actorID: "00000000-0000-4000-8000-000000000003", customerID: "00000000-0000-4000-8000-000000000004", jobID: nil)
        let fence = try InvoiceTransactionFence(path: path)
        let identity = InvoiceEditorAuthorityIdentity(actorID: scope.actorID, organizationID: domain.organizationID, origin: domain.origin, sessionGeneration: UUID(), authorityRevision: UUID())
        let owner = UUID(), key = SymmetricKey(size: .bits256)
        let writer = InvoiceSerialDraftWriter(fence: fence, identity: scope, authority: identity, owner: owner)
        var gate = InvoiceEditorRetirementGate(identity: identity, scope: scope, owner: owner)
        let first = gate.reserveEdit()!
        let firstSeal = try InvoiceDraftCipher.seal(Data("raw first".utf8), identity: scope, owner: owner, sequence: first, key: key)
        precondition(gate.bind(firstSeal))
        let latest = gate.reserveEdit()!
        let rawLatest = Data("raw latest".utf8)
        let latestSeal = try InvoiceDraftCipher.seal(rawLatest, identity: scope, owner: owner, sequence: latest, key: key)
        precondition(gate.bind(latestSeal))
        let latestReceipt = try await writer.capture(latestSeal, authority: identity)
        gate.acknowledge(latestReceipt)
        precondition(gate.retirement == .durable)
        let rebound = try InvoiceDraftCipher.seal(Data("different".utf8), identity: scope, owner: owner, sequence: latest, key: key)
        precondition(!gate.bind(rebound), "An acknowledged sequence cannot be rebound")
        precondition(gate.retirement == .failed, "A rejected changed payload must not look durable")
        do { _ = try await writer.capture(firstSeal, authority: identity); preconditionFailure("older write accepted") } catch { }
        let stored = try fence.recoverIdle(identity: scope)!
        precondition(stored.sequence == latest && stored.bytes == latestSeal.ciphertext && stored.bytes.range(of: rawLatest) == nil)
        let reopened = try InvoiceTransactionFence(path: path)
        let reopenedWriter = InvoiceSerialDraftWriter(fence: reopened, identity: scope, authority: identity, owner: owner)
        let recovered = try await reopenedWriter.recover(authority: identity, authorized: true)!
        var failedGate = InvoiceEditorRetirementGate(identity: identity, scope: scope, owner: owner)
        let failed = failedGate.reserveEdit()!; failedGate.fail(failed)
        precondition(failedGate.restore(recovered, current: identity, authorized: true) == nil && failedGate.retirement == .failed)
        var recoveredGate = InvoiceEditorRetirementGate(identity: identity, scope: scope, owner: owner)
        let recoveredBytes = recoveredGate.restore(recovered, current: identity, authorized: true)!
        let opened = try InvoiceDraftCipher.open(recoveredBytes, identity: scope, owner: owner, sequence: latest, key: key)
        precondition(opened == rawLatest && recoveredGate.retirement == .durable)
        let afterRestart = recoveredGate.reserveEdit()!
        let afterRestartSeal = try InvoiceDraftCipher.seal(Data("after restart".utf8), identity: scope, owner: owner, sequence: afterRestart, key: key)
        precondition(recoveredGate.bind(afterRestartSeal))
        let afterRestartReceipt = try await reopenedWriter.capture(afterRestartSeal, authority: identity)
        recoveredGate.acknowledge(afterRestartReceipt)
        precondition(recoveredGate.retirement == .durable)
        let afterRestartStored = try reopened.recoverIdle(identity: scope)!
        precondition(afterRestartStored.sequence == afterRestart && afterRestartStored.bytes == afterRestartSeal.ciphertext)
        let wrongOwnerWriter = InvoiceSerialDraftWriter(fence: reopened, identity: scope, authority: identity, owner: UUID())
        do { _ = try await wrongOwnerWriter.recover(authority: identity, authorized: true); preconditionFailure("wrong owner recovered") } catch { }
        let otherDomain = InvoiceFenceDomain(origin: domain.origin, organizationID: domain.organizationID, invoiceID: "00000000-0000-4000-8000-000000000005")
        let otherScope = InvoiceIdleCaptureIdentity(domain: otherDomain, actorID: scope.actorID, customerID: scope.customerID, jobID: nil)
        let otherOwner = UUID()
        let otherWriter = InvoiceSerialDraftWriter(fence: fence, identity: otherScope, authority: identity, owner: otherOwner)
        var wrongScopeGate = InvoiceEditorRetirementGate(identity: identity, scope: scope, owner: owner)
        let requested = wrongScopeGate.reserveEdit()!
        let ownSeal = try InvoiceDraftCipher.seal(Data("same".utf8), identity: scope, owner: owner, sequence: requested, key: key)
        precondition(wrongScopeGate.bind(ownSeal))
        let otherSeal = try InvoiceDraftCipher.seal(Data("same".utf8), identity: otherScope, owner: otherOwner, sequence: requested, key: key)
        precondition(!wrongScopeGate.bind(otherSeal))
        let wrongScopeReceipt = try await otherWriter.capture(otherSeal, authority: identity)
        wrongScopeGate.acknowledge(wrongScopeReceipt)
        precondition(wrongScopeGate.retirement == .pending)
        let thirdDomain = InvoiceFenceDomain(origin: domain.origin, organizationID: domain.organizationID, invoiceID: "00000000-0000-4000-8000-000000000006")
        let thirdScope = InvoiceIdleCaptureIdentity(domain: thirdDomain, actorID: scope.actorID, customerID: scope.customerID, jobID: nil)
        let thirdOwner = UUID()
        let thirdWriter = InvoiceSerialDraftWriter(fence: fence, identity: thirdScope, authority: identity, owner: thirdOwner)
        var digestGate = InvoiceEditorRetirementGate(identity: identity, scope: thirdScope, owner: thirdOwner)
        let digestSequence = digestGate.reserveEdit()!
        let expectedSeal = try InvoiceDraftCipher.seal(Data("expected".utf8), identity: thirdScope, owner: thirdOwner, sequence: digestSequence, key: key)
        let differentSeal = try InvoiceDraftCipher.seal(Data("different".utf8), identity: thirdScope, owner: thirdOwner, sequence: digestSequence, key: key)
        precondition(digestGate.bind(expectedSeal))
        let mismatchedReceipt = try await thirdWriter.capture(differentSeal, authority: identity)
        digestGate.acknowledge(mismatchedReceipt)
        precondition(digestGate.retirement == .pending)
        let changed = InvoiceEditorAuthorityIdentity(actorID: identity.actorID, organizationID: identity.organizationID, origin: identity.origin, sessionGeneration: UUID(), authorityRevision: identity.authorityRevision)
        precondition(!gate.mayDisplay(identity: changed, authorized: true))
        let newer = gate.reserveEdit()!
        let newerSeal = try InvoiceDraftCipher.seal(Data("newer".utf8), identity: scope, owner: owner, sequence: newer, key: key)
        precondition(gate.bind(newerSeal))
        do { _ = try await writer.capture(newerSeal, authority: changed); preconditionFailure("stale authority accepted") } catch { }
        precondition(gate.retirement == .pending)
        _ = try fence.begin(domain: domain, owner: owner, expectedVersion: afterRestartStored.version, kind: .directUnknown, command: Data("unresolved legacy write".utf8))
        do { _ = try await writer.capture(newerSeal, authority: identity); preconditionFailure("pending legacy write ignored") } catch { }
        gate.fail(newer)
        precondition(gate.retirement == .failed)
        print("invoice serial capture: encrypted sequence, scope receipt and retirement checks passed")
    }
}
