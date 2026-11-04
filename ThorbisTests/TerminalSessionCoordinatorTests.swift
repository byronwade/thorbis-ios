import XCTest
@testable import Thorbis

@MainActor private final class FakeTerminalSession: TerminalSessionDriver {
    typealias Intent = Int
    typealias Result = Int
    var isConnected = false
    var events: [String] = []
    var fetch: (@MainActor () async throws -> String)?
    var afterCollect: (() -> Void)?
    var afterConnect: (() -> Void)?
    var beforeRetrieve: (@MainActor () async -> Void)?
    var disconnectError = false
    var intentID = "payment-a"
    var collectedIntentID: String?
    var confirmationError = false
    var afterConfirm: (() -> Void)?
    var collectionError = false
    var bootstrapOccupied = false
    func bootstrap(_ fetch: @escaping @MainActor () async throws -> String) throws {
        if bootstrapOccupied { throw TerminalOwnershipError.occupied }
    }
    func disconnect() async throws {
        events.append("disconnect")
        if disconnectError { throw CancellationError() }
        isConnected = false
    }
    func clearCredentials() throws { events.append("clear") }
    func configureTokenProvider(_ fetch: @escaping @MainActor () async throws -> String) throws {
        events.append("configure")
        self.fetch = fetch
    }
    func connect(locationID: String) async throws {
        events.append("connect")
        _ = try await fetch?()
        isConnected = true
        afterConnect?()
    }
    func retrieveIntent() async throws -> TerminalRetrievedIntent<Int> { events.append("retrieve"); await beforeRetrieve?(); return .init(value: 1, paymentIntentID: intentID) }
    func collect(_ intent: Int) async throws -> TerminalRetrievedIntent<Int> { events.append("collect"); if collectionError { throw CancellationError() }; afterCollect?(); return .init(value: intent, paymentIntentID: collectedIntentID ?? intentID) }
    func confirm(_ intent: Int) async throws -> Int { events.append("confirm"); if confirmationError { throw CancellationError() }; afterConfirm?(); return intent }
}

@MainActor final class TerminalSessionCoordinatorTests: XCTestCase {
    func testDefiniteOwnerRefusalDoesNotParkTheNextAttempt() async throws {
        defer { TerminalSessionCoordinator.resetForTests() }
        let coordinator = TerminalSessionCoordinator(), driver = FakeTerminalSession()
        let a = binding("a")
        driver.bootstrapOccupied = true
        do {
            _ = try await coordinator.collect(binding: a, driver: driver, isCurrent: { true }, fetch: { self.token(a) })
            XCTFail("Expected occupied owner")
        } catch is TerminalOwnershipError {}
        driver.bootstrapOccupied = false
        _ = try await coordinator.collect(binding: a, driver: driver, isCurrent: { true }, fetch: { self.token(a) })
        XCTAssertTrue(driver.events.contains("confirm"))
    }
    private func binding(_ id: String, location: String = "location") -> TerminalAttemptBinding {
        .init(invoiceID: "invoice-\(id)", attemptID: "attempt-\(id)", paymentIntentID: "payment-\(id)", locationID: location,
              origin: "https://app.thorbis.com", scope: "workspace-\(id)", generation: UUID())
    }
    private func token(_ binding: TerminalAttemptBinding) -> TerminalBoundToken {
        .init(secret: "synthetic", attemptID: binding.attemptID, locationID: binding.locationID)
    }

    func testSwitchingAttemptDisconnectsAndClearsEvenWhenLocationMatches() async throws {
        let coordinator = TerminalSessionCoordinator(), driver = FakeTerminalSession()
        let a = binding("a"), b = binding("b")
        _ = try await coordinator.collect(binding: a, driver: driver, isCurrent: { true }, fetch: { self.token(a) })
        driver.events.removeAll()
        driver.intentID = "payment-b"
        _ = try await coordinator.collect(binding: b, driver: driver, isCurrent: { true }, fetch: { self.token(b) })
        XCTAssertEqual(driver.events, ["disconnect", "clear", "configure", "connect", "retrieve", "collect", "confirm"])
    }

    func testWrongAttemptTokenCannotReachRetrieveOrConfirm() async throws {
        defer { TerminalSessionCoordinator.resetForTests() }
        let coordinator = TerminalSessionCoordinator(), driver = FakeTerminalSession()
        let a = binding("a"), b = binding("b")
        do {
            _ = try await coordinator.collect(binding: a, driver: driver, isCurrent: { true }, fetch: { self.token(b) })
            XCTFail("Expected token mismatch")
        } catch { XCTAssertEqual(error as? TerminalBindingError, .invalidToken) }
        XCTAssertFalse(driver.events.contains("retrieve"))
        XCTAssertFalse(driver.events.contains("confirm"))
    }

    func testRetiredSessionAfterCollectionCannotConfirm() async throws {
        defer { TerminalSessionCoordinator.resetForTests() }
        let coordinator = TerminalSessionCoordinator(), driver = FakeTerminalSession()
        let a = binding("a")
        var current = true
        driver.afterCollect = { current = false }
        do {
            _ = try await coordinator.collect(binding: a, driver: driver, isCurrent: { current }, fetch: { self.token(a) })
            XCTFail("Expected retirement")
        } catch { XCTAssertEqual(error as? TerminalBindingError, .confirmationUncertain) }
        XCTAssertFalse(driver.events.contains("confirm"))
    }

    func testDisconnectFailureDoesNotSwitchTokenProvider() async throws {
        defer { TerminalSessionCoordinator.resetForTests() }
        let coordinator = TerminalSessionCoordinator(), driver = FakeTerminalSession()
        driver.isConnected = true
        driver.disconnectError = true
        let a = binding("a")
        do {
            _ = try await coordinator.collect(binding: a, driver: driver, isCurrent: { true }, fetch: { self.token(a) })
            XCTFail("Expected disconnect failure")
        } catch { XCTAssertEqual(error as? TerminalBindingError, .confirmationUncertain) }
        XCTAssertEqual(driver.events, ["disconnect"])
    }

    func testConcurrentOtherAttemptCannotReplaceProviderWhileFirstIsCollecting() async throws {
        let coordinator = TerminalSessionCoordinator(), another = TerminalSessionCoordinator(), first = FakeTerminalSession(), second = FakeTerminalSession()
        let a = binding("a"), b = binding("b")
        let entered = expectation(description: "first retrieval")
        var continuation: CheckedContinuation<Void, Never>?
        first.beforeRetrieve = {
            await withCheckedContinuation { next in continuation = next; entered.fulfill() }
        }
        let pending = Task { try await coordinator.collect(binding: a, driver: first, isCurrent: { true }, fetch: { self.token(a) }) }
        await fulfillment(of: [entered], timeout: 5)
        do {
            _ = try await another.collect(binding: b, driver: second, isCurrent: { true }, fetch: { self.token(b) })
            XCTFail("Expected concurrent attempt refusal")
        } catch { XCTAssertEqual(error as? TerminalBindingError, .busy) }
        XCTAssertTrue(second.events.isEmpty)
        continuation?.resume()
        _ = try await pending.value
    }

    func testWrongLocationTokenCannotReachRetrieveOrConfirm() async throws {
        defer { TerminalSessionCoordinator.resetForTests() }
        let coordinator = TerminalSessionCoordinator(), driver = FakeTerminalSession()
        let a = binding("a"), wrong = binding("a", location: "other-location")
        do {
            _ = try await coordinator.collect(binding: a, driver: driver, isCurrent: { true }, fetch: { self.token(wrong) })
            XCTFail("Expected location mismatch")
        } catch { XCTAssertEqual(error as? TerminalBindingError, .invalidToken) }
        XCTAssertFalse(driver.events.contains("retrieve"))
        XCTAssertFalse(driver.events.contains("confirm"))
    }

    func testRetiredTokenProviderCannotIssueAfterCollectionEnds() async throws {
        let coordinator = TerminalSessionCoordinator(), driver = FakeTerminalSession()
        let a = binding("a")
        var calls = 0
        _ = try await coordinator.collect(binding: a, driver: driver, isCurrent: { true }, fetch: { calls += 1; return self.token(a) })
        XCTAssertEqual(calls, 1)
        do {
            _ = try await driver.fetch?()
            XCTFail("A retired provider must not fetch another credential")
        } catch { XCTAssertEqual(error as? TerminalBindingError, .retired) }
        XCTAssertEqual(calls, 1)
    }

    func testWrongStripeIntentCannotBeCollected() async throws {
        let coordinator = TerminalSessionCoordinator(), driver = FakeTerminalSession()
        let a = binding("a")
        driver.intentID = "payment-from-another-attempt"
        do {
            _ = try await coordinator.collect(binding: a, driver: driver, isCurrent: { true }, fetch: { self.token(a) })
            XCTFail("Expected intent mismatch")
        } catch { XCTAssertEqual(error as? TerminalBindingError, .invalidIntent) }
        XCTAssertFalse(driver.events.contains("collect"))
        XCTAssertFalse(driver.events.contains("confirm"))
    }

    func testUncertainConfirmationBlocksEveryCoordinator() async throws {
        defer { TerminalSessionCoordinator.resetForTests() }
        let first = TerminalSessionCoordinator(), second = TerminalSessionCoordinator()
        let driver = FakeTerminalSession(), other = FakeTerminalSession(), a = binding("a"), b = binding("b")
        driver.confirmationError = true
        do {
            _ = try await first.collect(binding: a, driver: driver, isCurrent: { true }, fetch: { self.token(a) })
            XCTFail("Expected uncertain confirmation")
        } catch { XCTAssertEqual(error as? TerminalBindingError, .confirmationUncertain) }
        do {
            _ = try await second.collect(binding: b, driver: other, isCurrent: { true }, fetch: { self.token(b) })
            XCTFail("Unreconciled confirmation must block another attempt")
        } catch { XCTAssertEqual(error as? TerminalBindingError, .confirmationUncertain) }
        XCTAssertTrue(other.events.isEmpty)
    }

    func testCancelledSDKCollectionBlocksOtherCoordinatorsUntilReconciled() async throws {
        defer { TerminalSessionCoordinator.resetForTests() }
        let first = TerminalSessionCoordinator(), second = TerminalSessionCoordinator()
        let driver = FakeTerminalSession(), other = FakeTerminalSession(), a = binding("a"), b = binding("b")
        driver.collectionError = true
        other.intentID = "payment-b"
        do { _ = try await first.collect(binding: a, driver: driver, isCurrent: { true }, fetch: { self.token(a) }) }
        catch { }
        do {
            _ = try await second.collect(binding: b, driver: other, isCurrent: { true }, fetch: { self.token(b) })
            XCTFail("An unfinished SDK callback must not permit a second collection")
        } catch { XCTAssertEqual(error as? TerminalBindingError, .confirmationUncertain) }
        XCTAssertTrue(other.events.isEmpty)
    }

    func testCollectedIntentMismatchCannotBeConfirmed() async throws {
        defer { TerminalSessionCoordinator.resetForTests() }
        let coordinator = TerminalSessionCoordinator(), driver = FakeTerminalSession(), a = binding("a")
        driver.collectedIntentID = "payment-from-another-attempt"
        do {
            _ = try await coordinator.collect(binding: a, driver: driver, isCurrent: { true }, fetch: { self.token(a) })
            XCTFail("Expected collected intent mismatch")
        } catch { XCTAssertEqual(error as? TerminalBindingError, .confirmationUncertain) }
        XCTAssertFalse(driver.events.contains("confirm"))
    }

    func testRetirementDuringConfirmationLeavesAttemptUncertain() async throws {
        defer { TerminalSessionCoordinator.resetForTests() }
        let coordinator = TerminalSessionCoordinator(), driver = FakeTerminalSession(), a = binding("a")
        var current = true
        driver.afterConfirm = { current = false }
        do {
            _ = try await coordinator.collect(binding: a, driver: driver, isCurrent: { current }, fetch: { self.token(a) })
            XCTFail("Expected uncertain confirmation")
        } catch { XCTAssertEqual(error as? TerminalBindingError, .confirmationUncertain) }
        let second = FakeTerminalSession()
        do {
            _ = try await TerminalSessionCoordinator().collect(binding: a, driver: second, isCurrent: { true }, fetch: { self.token(a) })
            XCTFail("Expected held attempt")
        } catch { XCTAssertEqual(error as? TerminalBindingError, .confirmationUncertain) }
        XCTAssertTrue(second.events.isEmpty)
    }

    func testBlankServerIntentIdentityIsRejectedBeforeReaderWork() async throws {
        let coordinator = TerminalSessionCoordinator(), driver = FakeTerminalSession()
        let a = TerminalAttemptBinding(invoiceID: "invoice", attemptID: "attempt", paymentIntentID: " ", locationID: "location", origin: "https://app.thorbis.com", scope: "workspace", generation: UUID())
        do {
            _ = try await coordinator.collect(binding: a, driver: driver, isCurrent: { true }, fetch: { self.token(a) })
            XCTFail("Expected invalid identity")
        } catch { XCTAssertEqual(error as? TerminalBindingError, .invalidIntent) }
        XCTAssertTrue(driver.events.isEmpty)
    }

    func testRetirementAfterSDKConnectBlocksAnotherAttempt() async throws {
        defer { TerminalSessionCoordinator.resetForTests() }
        let first = TerminalSessionCoordinator(), second = TerminalSessionCoordinator()
        let driver = FakeTerminalSession(), other = FakeTerminalSession(), a = binding("a"), b = binding("b")
        var current = true
        driver.afterConnect = { current = false }
        do { _ = try await first.collect(binding: a, driver: driver, isCurrent: { current }, fetch: { self.token(a) }) }
        catch { }
        other.intentID = "payment-b"
        do {
            _ = try await second.collect(binding: b, driver: other, isCurrent: { true }, fetch: { self.token(b) })
            XCTFail("A retired SDK operation must remain held")
        } catch { XCTAssertEqual(error as? TerminalBindingError, .confirmationUncertain) }
        XCTAssertTrue(other.events.isEmpty)
    }
}
