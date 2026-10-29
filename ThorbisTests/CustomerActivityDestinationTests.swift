import XCTest
@testable import Thorbis

final class CustomerActivityDestinationTests: XCTestCase {
    private let id = "11111111-1111-4111-8111-111111111111"

    private func entry(kind: String) -> CustomerHistoryEntry {
        CustomerHistoryEntry(occurredAt: "2026-10-29T12:00:00Z", kind: kind, subjectId: id, summary: "Example")
    }

    func testRecordKindsOpenTheirDetail() {
        XCTAssertEqual(entry(kind: "estimate").destination, .estimate(id))
        XCTAssertEqual(entry(kind: "invoice").destination, .invoice(id))
        XCTAssertEqual(entry(kind: "job").destination, .job(id))
    }

    func testKindsWithoutADetailStayNonInteractive() {
        // No standalone detail screen yet — these rows must not become dead-end taps.
        // Tracked in docs/gaps/activity-feed-destinations.md.
        for kind in ["payment", "contact", "location", "note", "call", "message", "unknown"] {
            XCTAssertNil(entry(kind: kind).destination, "\(kind) should have no destination")
        }
    }
}
