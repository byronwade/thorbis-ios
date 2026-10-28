import XCTest
@testable import Thorbis

final class BookingCallTests: XCTestCase {
    private func decode(_ json: String) throws -> BookingCallRecord? {
        struct Envelope: Decodable { let call: BookingCallRecord? }
        return try JSONDecoder().decode(Envelope.self, from: Data(json.utf8)).call
    }

    // MARK: JS-05 the call that booked it

    func testNoLinkedCallMeansNoSection() throws {
        XCTAssertNil(try decode(#"{"call":null}"#))
    }

    func testARecordedCallIsPlayableWithItsTranscriptInOrder() throws {
        let call = try XCTUnwrap(decode("""
        {"call":{"id":"c1","status":"completed","direction":"inbound","callerNumber":"555-0100","callerName":"Dana Ruiz",
          "jobId":"j1","lineId":"l1","linkedAt":"2026-10-27T15:20:00Z","startedAt":"2026-10-27T15:12:00Z","durationSeconds":192,
          "recording":{"status":"available","durationSeconds":190,"contentPath":"/v1/calls/00000000-0000-4000-8000-000000009601/recording"},
          "summary":{"text":"Leak at the base.","source":"deterministic"},"transcriptStatus":"available",
          "transcript":[{"sequence":2,"speaker":"caller","text":"It's leaking."},{"sequence":1,"speaker":"business","text":"How can we help?"}],
          "disclosure":"This call may be recorded."}}
        """))
        XCTAssertEqual(call.caller, "Dana Ruiz")
        XCTAssertEqual(call.playablePath, "/v1/calls/00000000-0000-4000-8000-000000009601/recording")
        XCTAssertNil(call.recordingNote)
        XCTAssertEqual(call.length, 190)
        XCTAssertEqual(call.transcript.map(\.label), ["Office", "Caller"])
        XCTAssertEqual(call.summary?.text, "Leak at the base.")
        XCTAssertEqual(call.disclosure, "This call may be recorded.")
    }

    func testOnlyTheServersOwnRecordingRouteIsPlayable() throws {
        let call = try XCTUnwrap(decode("""
        {"call":{"id":"c1","status":"completed","startedAt":"2026-10-27T15:12:00Z",
          "recording":{"status":"available","contentPath":"https://provider.example/recording.mp3"},"transcript":[]}}
        """))
        XCTAssertNil(call.playablePath)
        XCTAssertEqual(call.recordingNote, "The recording isn't available.")
    }

    func testNoRecordingIsSaidInWordsNeverAnEmptyPlayer() throws {
        func note(status: String, recording: String) throws -> String? {
            try decode("""
            {"call":{"id":"c1","status":"\(status)","startedAt":"2026-10-27T15:12:00Z","recording":{"status":"\(recording)"}}}
            """)?.recordingNote
        }
        XCTAssertEqual(try note(status: "missed", recording: "none"), "Missed call. Nothing was recorded.")
        XCTAssertEqual(try note(status: "completed", recording: "pending"), "The recording is still processing.")
        XCTAssertEqual(try note(status: "completed", recording: "failed"), "The recording didn't save.")
        XCTAssertEqual(try note(status: "completed", recording: "none"), "This call wasn't recorded.")
    }

    func testAnUnnamedCallerFallsBackToTheirNumber() throws {
        let call = try XCTUnwrap(decode("""
        {"call":{"id":"c1","status":"completed","callerNumber":"555-0100","startedAt":"2026-10-27T15:12:00Z","recording":{"status":"none"}}}
        """))
        XCTAssertEqual(call.caller, "555-0100")
        XCTAssertEqual(BookingCallRecord.clock(192), "3:12")
        XCTAssertEqual(BookingCallRecord.clock(-4), "0:00")
    }
}
