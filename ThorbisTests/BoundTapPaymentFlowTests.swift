import XCTest
@testable import Thorbis

@MainActor final class BoundTapPaymentFlowTests: XCTestCase {
    override func tearDown() { super.tearDown() }

    func testDisabledOrUnsupportedNeverCreatesAttempt() async throws {
        defer { BoundTapPaymentFlow.resetForTests() }
        var created = 0
        for enabled in [false, true] {
            do {
                _ = try await BoundTapPaymentFlow.run(enabled: enabled, supported: false, isCurrent: { true }, create: { created += 1; return 1 }, collect: { $0 })
                XCTFail("Expected unavailable")
            } catch { XCTAssertEqual(error as? BoundTapFlowError, .unavailable) }
        }
        XCTAssertEqual(created, 0)
    }

    func testRetiredScopeAfterAttemptIsParked() async throws {
        defer { BoundTapPaymentFlow.resetForTests() }
        var current = true
        do {
            _ = try await BoundTapPaymentFlow.run(enabled: true, supported: true, isCurrent: { current }, create: { current = false; return 1 }, collect: { $0 })
            XCTFail("Expected uncertainty")
        } catch { XCTAssertEqual(error as? BoundTapFlowError, .uncertain) }
        do {
            _ = try await BoundTapPaymentFlow.run(enabled: true, supported: true, isCurrent: { true }, create: { 2 }, collect: { $0 })
            XCTFail("Must not start another attempt")
        } catch { XCTAssertEqual(error as? BoundTapFlowError, .uncertain) }
    }

    func testCreationFailureIsUncertainAndBlocksRetry() async throws {
        defer { BoundTapPaymentFlow.resetForTests() }
        do {
            let _: Int = try await BoundTapPaymentFlow.run(enabled: true, supported: true, isCurrent: { true }, create: { () async throws -> Int in throw CancellationError() }, collect: { $0 })
            XCTFail("Expected uncertainty")
        } catch { XCTAssertEqual(error as? BoundTapFlowError, .uncertain) }
        do {
            _ = try await BoundTapPaymentFlow.run(enabled: true, supported: true, isCurrent: { true }, create: { 2 }, collect: { $0 })
            XCTFail("Must not retry")
        } catch { XCTAssertEqual(error as? BoundTapFlowError, .uncertain) }
    }

    func testOtherControllerCannotCreateAnAttemptDuringFirstCreation() async throws {
        defer { BoundTapPaymentFlow.resetForTests() }
        let entered = expectation(description: "first request entered")
        var release: CheckedContinuation<Void, Never>?
        let first = Task { @MainActor in
            try await BoundTapPaymentFlow.run(enabled: true, supported: true, isCurrent: { true }, create: {
                entered.fulfill()
                await withCheckedContinuation { release = $0 }
                return 1
            }, collect: { $0 })
        }
        await fulfillment(of: [entered], timeout: 1)
        var otherCreated = false
        do {
            _ = try await BoundTapPaymentFlow.run(enabled: true, supported: true, isCurrent: { true }, create: { otherCreated = true; return 2 }, collect: { $0 })
            XCTFail("Expected process lease")
        } catch { XCTAssertEqual(error as? BoundTapFlowError, .busy) }
        XCTAssertFalse(otherCreated)
        release?.resume()
        let result = try await first.value
        XCTAssertEqual(result, 1)
    }

    func testRecoveryPreflightFailureAllowsRetryWithoutCreatingAnAttempt() async throws {
        defer { BoundTapPaymentFlow.resetForTests() }
        do {
            let _: Int = try await BoundTapPaymentFlow.run(enabled: true, supported: true, isCurrent: { true }, create: { throw BoundTapPreflightError.recoveryUnavailable }, collect: { $0 })
            XCTFail("Expected recovery preflight failure")
        } catch { XCTAssertEqual(error as? BoundTapFlowError, .recoveryUnavailable) }
        let result = try await BoundTapPaymentFlow.run(enabled: true, supported: true, isCurrent: { true }, create: { 1 }, collect: { $0 })
        XCTAssertEqual(result, 1)
    }
}

final class BoundTapAuthorityTests: XCTestCase {
    func testSameCacheScopeCannotHideActorOrAuthorityChange() {
        let generation = UUID(), revision = UUID(), api = UUID()
        let base = BoundTapAuthority(actorID: "actor-a", organizationID: "org", sessionGeneration: generation, authorityRevision: revision, apiGeneration: api, origin: "https://example.test", permitted: true)
        let revoked = BoundTapAuthority(actorID: "actor-a", organizationID: "org", sessionGeneration: generation, authorityRevision: UUID(), apiGeneration: api, origin: "https://example.test", permitted: false)
        let switched = BoundTapAuthority(actorID: "actor-b", organizationID: "org", sessionGeneration: generation, authorityRevision: revision, apiGeneration: api, origin: "https://example.test", permitted: true)
        XCTAssertNotEqual(base, revoked)
        XCTAssertNotEqual(base, switched)
    }
}
