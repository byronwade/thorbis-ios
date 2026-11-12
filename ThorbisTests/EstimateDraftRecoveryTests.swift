import XCTest
@testable import Thorbis

@MainActor
final class EstimateDraftRecoveryTests: XCTestCase {
    @MainActor final class Gate { var active: EstimateDraftRecovery.Lease? }
    actor PauseGate {
        var parked: CheckedContinuation<Void, Never>?
        var notification: CheckedContinuation<Void, Never>?
        var isParked = false
        func pause() async { await withCheckedContinuation { continuation in
            parked = continuation; isParked = true; notification?.resume(); notification = nil
        } }
        func wait() async { if isParked { return }; await withCheckedContinuation { notification = $0 } }
        func release() { parked?.resume(); parked = nil }
    }
    actor Calls { var count = 0; func next() -> Int { count += 1; return count } }
    actor ExpiringGate {
        var calls = 0
        func valid() -> Bool { calls += 1; return calls == 1 }
    }
    func testIsolationCollisionAndFailures() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = EstimateDraftRecovery.Owner(origin: "https://app.thorbis.com", organizationID: UUID(), actorID: UUID(), estimateID: UUID())
        let operation = UUID()
        func intent(_ title: String, version: Int = 3) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["contractVersion": 1, "operationId": operation.uuidString, "estimateId": owner.estimateID.uuidString, "expectedDraftVersion": version, "expectedRevisionNumber": 0, "title": title], options: [.sortedKeys])
        }
        let payload = try intent("First")
        let lease = EstimateDraftRecovery.Lease(owner: owner, sessionGeneration: UUID(), authorityRevision: UUID(), apiGeneration: UUID(), savedCopyRevision: UUID())
        let gate = Gate(); gate.active = lease
        let verify: @Sendable (EstimateDraftRecovery.Lease) async -> Bool = { value in await MainActor.run { gate.active == value } }
        let store = try EstimateDraftRecovery(directory: directory, isCurrent: verify)
        try await store.save(lease: lease, operationID: operation, payload: payload)
        let reopened = try EstimateDraftRecovery(directory: directory, isCurrent: verify)
        let first = try await reopened.load(lease: lease)
        XCTAssertEqual(first.first?.payload, payload)
        let newSession = EstimateDraftRecovery.Lease(owner: owner, sessionGeneration: UUID(), authorityRevision: UUID(), apiGeneration: UUID(), savedCopyRevision: UUID())
        gate.active = newSession
        do { _ = try await reopened.load(lease: lease); XCTFail("stale lease") } catch {}
        let restored = try await reopened.load(lease: newSession)
        XCTAssertEqual(restored.first?.payload, payload)
        let other = EstimateDraftRecovery.Owner(origin: owner.origin, organizationID: owner.organizationID, actorID: owner.actorID, estimateID: UUID())
        let otherLease = EstimateDraftRecovery.Lease(owner: other, sessionGeneration: UUID(), authorityRevision: UUID(), apiGeneration: UUID(), savedCopyRevision: UUID())
        gate.active = otherLease
        let empty = try await reopened.load(lease: otherLease)
        XCTAssertTrue(empty.isEmpty)
        let collision = try JSONSerialization.data(withJSONObject: ["contractVersion": 1, "operationId": operation.uuidString, "estimateId": other.estimateID.uuidString, "expectedDraftVersion": 3, "expectedRevisionNumber": 0])
        do { try await reopened.save(lease: otherLease, operationID: operation, payload: collision); XCTFail("collision") } catch {}
        gate.active = lease
        do { try await reopened.save(lease: lease, operationID: operation, payload: intent("Different")); XCTFail("conflict") } catch {}
        do { try await reopened.save(lease: lease, operationID: operation, payload: intent("Bad", version: -1)); XCTFail("invalid") } catch {}
        let failing = try EstimateDraftRecovery(directory: directory, isCurrent: verify, writeData: { _, _ in throw CocoaError(.fileWriteUnknown) })
        let newID = UUID()
        let newPayload = try JSONSerialization.data(withJSONObject: ["contractVersion": 1, "operationId": newID.uuidString, "estimateId": owner.estimateID.uuidString, "expectedDraftVersion": 3, "expectedRevisionNumber": 0])
        do { try await failing.save(lease: lease, operationID: newID, payload: newPayload); XCTFail("storage failure") } catch {}
        do { _ = try await failing.load(lease: lease); XCTFail("uncertain") } catch {}
        let expiring = ExpiringGate()
        let stale = try EstimateDraftRecovery(directory: directory, isCurrent: { _ in await expiring.valid() })
        do { _ = try await stale.load(lease: lease); XCTFail("authority changed during read") } catch EstimateDraftRecovery.Failure.unavailable {}
        let kept = try await reopened.load(lease: lease)
        XCTAssertEqual(kept.first?.payload, payload)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "json" }))
        let original = try Data(contentsOf: file)
        let entry = EstimateDraftRecovery.Entry(owner: owner, operationID: operation, payload: payload)
        try JSONEncoder().encode([entry, entry]).write(to: file)
        do { _ = try await reopened.load(lease: lease); XCTFail("duplicate") } catch EstimateDraftRecovery.Failure.corrupt {}
        let bad = EstimateDraftRecovery.Entry(owner: owner, operationID: UUID(), payload: payload)
        try JSONEncoder().encode([bad]).write(to: file)
        do { _ = try await reopened.load(lease: lease); XCTFail("identity mismatch") } catch EstimateDraftRecovery.Failure.corrupt {}
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        do { _ = try await reopened.load(lease: lease); XCTFail("unavailable") } catch EstimateDraftRecovery.Failure.unavailable {}
        try FileManager.default.removeItem(at: file)
        try original.write(to: file)
    }
    func testUncertainStateAfterAuthoritySuspension() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let owner = EstimateDraftRecovery.Owner(origin: "https://app.thorbis.com", organizationID: UUID(), actorID: UUID(), estimateID: UUID())
        let first = EstimateDraftRecovery.Lease(owner: owner, sessionGeneration: UUID(), authorityRevision: UUID(), apiGeneration: UUID(), savedCopyRevision: UUID())
        let otherOwner = EstimateDraftRecovery.Owner(origin: owner.origin, organizationID: UUID(), actorID: owner.actorID, estimateID: UUID())
        let second = EstimateDraftRecovery.Lease(owner: otherOwner, sessionGeneration: UUID(), authorityRevision: UUID(), apiGeneration: UUID(), savedCopyRevision: UUID())
        let gate = PauseGate()
        let firstCalls = Calls()
        let store = try EstimateDraftRecovery(directory: dir, isCurrent: { lease in
            if lease == first { if await firstCalls.next() == 2 { await gate.pause() } }; return true
        }, writeData: { _, _ in throw CocoaError(.fileWriteUnknown) })
        let paused = Task { try await store.load(lease: first) }
        await gate.wait()
        let id = UUID()
        let payload = try JSONSerialization.data(withJSONObject: ["contractVersion": 1, "operationId": id.uuidString, "estimateId": otherOwner.estimateID.uuidString, "expectedDraftVersion": 0, "expectedRevisionNumber": 0])
        do { try await store.save(lease: second, operationID: id, payload: payload); XCTFail("write should fail") } catch {}
        await gate.release()
        do { _ = try await paused.value; XCTFail("uncertain state must block read") } catch EstimateDraftRecovery.Failure.unavailable {}
        let cancelled = Task { try await store.load(lease: second) }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("cancelled read") } catch {}
    }

    func testLockReleaseAfterCancellation() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let owner = EstimateDraftRecovery.Owner(origin: "https://app.thorbis.com", organizationID: UUID(), actorID: UUID(), estimateID: UUID())
        let lease = EstimateDraftRecovery.Lease(owner: owner, sessionGeneration: UUID(), authorityRevision: UUID(), apiGeneration: UUID(), savedCopyRevision: UUID())
        let gate = PauseGate()
        let calls = Calls()
        let held = try EstimateDraftRecovery(directory: dir, isCurrent: { _ in
            if await calls.next() == 2 { await gate.pause() }; return true
        })
        let other = try EstimateDraftRecovery(directory: dir, isCurrent: { _ in true })
        let task = Task { try await held.load(lease: lease) }
        await gate.wait()
        do { _ = try await other.load(lease: lease); XCTFail("busy lock must fail closed") } catch EstimateDraftRecovery.Failure.unavailable {}
        task.cancel()
        await gate.release()
        do { _ = try await task.value; XCTFail("cancelled read") } catch EstimateDraftRecovery.Failure.unavailable {}
        let result = try await other.load(lease: lease)
        XCTAssertTrue(result.isEmpty)
    }

    func testAmbiguousWriteIsRereadByNewInstance() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let owner = EstimateDraftRecovery.Owner(origin: "https://app.thorbis.com", organizationID: UUID(), actorID: UUID(), estimateID: UUID())
        let lease = EstimateDraftRecovery.Lease(owner: owner, sessionGeneration: UUID(), authorityRevision: UUID(), apiGeneration: UUID(), savedCopyRevision: UUID())
        let operation = UUID()
        let payload = try JSONSerialization.data(withJSONObject: ["contractVersion": 1, "operationId": operation.uuidString, "estimateId": owner.estimateID.uuidString, "expectedDraftVersion": 0, "expectedRevisionNumber": 0])
        let uncertain = try EstimateDraftRecovery(directory: dir, isCurrent: { _ in true }, writeData: { data, file in
            try data.write(to: file, options: [.atomic, .completeFileProtection]); throw CocoaError(.fileWriteUnknown)
        })
        do { try await uncertain.save(lease: lease, operationID: operation, payload: payload); XCTFail("ambiguous write") } catch {}
        do { _ = try await uncertain.load(lease: lease); XCTFail("frozen store") } catch EstimateDraftRecovery.Failure.unavailable {}
        let reopened = try EstimateDraftRecovery(directory: dir, isCurrent: { _ in true })
        let recovered = try await reopened.load(lease: lease)
        XCTAssertEqual(recovered.first?.payload, payload)
        // Recovery is not an acknowledgement; any eventual transport must reconcile first.
    }

}
