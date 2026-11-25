import XCTest
@testable import Thorbis

/// Send now on a job's photo screen. A session check that lands mid-send must not leave the
/// button greyed out, and two send loops must never run at once.
final class MediaSendTurnTests: XCTestCase {
    func testASendStartsWhenNoneIsRunning() throws {
        var turn = MediaSendTurn()
        XCTAssertFalse(turn.isSending)
        let run = try XCTUnwrap(turn.begin())
        XCTAssertTrue(turn.isSending)
        turn.end(run)
        XCTAssertFalse(turn.isSending)
    }

    func testTwoSendsNeverRunAtOnce() throws {
        var turn = MediaSendTurn()
        let first = try XCTUnwrap(turn.begin())
        XCTAssertNil(turn.begin())
        XCTAssertNil(turn.begin())
        XCTAssertEqual(turn.holder, first)
    }

    // The session check changed the screen's scope while the first loop was still uploading.
    func testASessionCheckMidSendFreesSendNowOnceTheOldLoopReturns() throws {
        var turn = MediaSendTurn()
        let old = try XCTUnwrap(turn.begin())
        // The screen asks to send again for the new scope while the old upload is in flight.
        XCTAssertNil(turn.begin())
        XCTAssertTrue(turn.isSending)
        turn.end(old)
        XCTAssertFalse(turn.isSending)
        let next = try XCTUnwrap(turn.begin())
        XCTAssertNotEqual(next, old)
    }

    func testAnOldLoopEndingDoesNotFreeANewerLoop() throws {
        var turn = MediaSendTurn()
        let old = try XCTUnwrap(turn.begin())
        turn.end(old)
        let newer = try XCTUnwrap(turn.begin())
        turn.end(old)
        XCTAssertTrue(turn.isSending)
        XCTAssertNil(turn.begin())
        turn.end(newer)
        XCTAssertFalse(turn.isSending)
    }
}
