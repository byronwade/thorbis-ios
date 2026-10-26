import XCTest
@testable import Thorbis

@MainActor
final class InboxLocalDraftTests: XCTestCase {
    private let actorA = "00000000-0000-4000-8000-000000000001"
    private let actorB = "00000000-0000-4000-8000-000000000002"
    private let orgA = "00000000-0000-4000-8000-000000000003"

    func testDraftAndQueueAreLocalAndClearOnAuthorityChange() throws {
        let inbox = InboxLocalDrafts()
        inbox.bind(actorID: actorA, organizationID: orgA)
        let draft = try inbox.save(channel: .sms, recipient: "2025550100", subject: "", body: "Hi", mode: .draft)
        XCTAssertEqual(draft.status, .draft)
        XCTAssertEqual(inbox.messages.count, 1)
        let queued = try inbox.save(channel: .email, recipient: "person@example.com", subject: "Hello", body: "Hi", mode: .queue)
        XCTAssertEqual(queued.status, .queued)
        XCTAssertEqual(inbox.messages.count, 2)
        inbox.bind(actorID: actorB, organizationID: orgA)
        XCTAssertTrue(inbox.messages.isEmpty)
        inbox.bind(actorID: actorA, organizationID: orgA)
        XCTAssertTrue(inbox.messages.isEmpty)
    }

    func testScheduledTextNeverSendsAndCanBeCanceled() throws {
        let inbox = InboxLocalDrafts()
        inbox.bind(actorID: actorA, organizationID: orgA)
        let message = try inbox.save(channel: .sms, recipient: "2025550100", subject: "", body: "Hi", mode: .queue,
                                     scheduledAt: "2026-11-01T10:00:00Z")
        XCTAssertEqual(message.status, .queued)
        XCTAssertEqual(message.scheduledAt, "2026-11-01T10:00:00Z")
        inbox.cancelScheduled(message.id)
        XCTAssertEqual(inbox.messages.first?.status, .draft)
        XCTAssertNil(inbox.messages.first?.scheduledAt)
        XCTAssertThrowsError(try inbox.save(channel: .sms, recipient: "2025550100", subject: "", body: "Hi", mode: .queue))
    }

    func testParentOwnedBoardSurvivesDestinationReentryUntilSessionInvalidates() throws {
        let appOwnedBoard = InboxLocalDrafts()
        appOwnedBoard.bind(actorID: actorA, organizationID: orgA)
        try appOwnedBoard.save(channel: .email, recipient: "person@example.com", subject: "Visit", body: "Hello", mode: .draft)
        // Popping and reopening a destination calls bind again but does not own the board.
        appOwnedBoard.bind(actorID: actorA, organizationID: orgA)
        XCTAssertEqual(appOwnedBoard.messages.count, 1)
        // SessionController.onInvalidate calls clear before another destination appears.
        appOwnedBoard.clear()
        appOwnedBoard.bind(actorID: actorA, organizationID: orgA)
        XCTAssertTrue(appOwnedBoard.messages.isEmpty)
    }
}
