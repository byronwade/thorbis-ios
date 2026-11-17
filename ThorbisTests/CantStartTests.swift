import XCTest
@testable import Thorbis

final class CantStartTests: XCTestCase {
    private let jobID = "00000000-0000-4000-8000-000000000001"

    func testEveryReasonBecomesAnOfficeNoticeWithANextStep() {
        for reason in CantStartReason.allCases {
            let report = CantStartReport(reason: reason, note: "")
            XCTAssertEqual(report.kind, .notifyOffice)
            XCTAssertEqual(report.request.kind, .notifyOffice)
            XCTAssertFalse(report.request.nextAction.isEmpty)
            XCTAssertLessThanOrEqual(report.request.nextAction.utf16.count, CantStartReport.maxLength)
            XCTAssertNil(report.request.ownerUserId)
            XCTAssertNil(report.request.requestedFor)
        }
    }

    func testPaperWordsAndOrder() {
        XCTAssertEqual(CantStartReason.allCases.map(\.label), ["No one home", "Wrong part", "Unsafe", "Needs approval"])
    }

    func testReasonIsTheLabelAloneWithoutANote() {
        let report = CantStartReport(reason: .noOneHome, note: "  \n ")
        XCTAssertEqual(report.followUpReason, "Can\u{2019}t start: No one home")
    }

    func testReasonCarriesTheTrimmedNote() {
        let report = CantStartReport(reason: .wrongPart, note: "  Brought a 35/5, unit needs a 45/5.\n")
        XCTAssertEqual(report.followUpReason, "Can\u{2019}t start: Wrong part. Brought a 35/5, unit needs a 45/5.")
    }

    func testOverTheServerLimitIsTooLong() {
        let fits = CantStartReport(reason: .unsafe, note: "")
        XCTAssertFalse(fits.isTooLong)
        let long = CantStartReport(reason: .unsafe, note: String(repeating: "a", count: CantStartReport.maxLength))
        XCTAssertTrue(long.isTooLong)
    }

    func testQueuedPayloadMatchesTheRequest() {
        let report = CantStartReport(reason: .needsApproval, note: "Owner wants to see the quote first.")
        let payload = report.payload(jobID: jobID)
        XCTAssertEqual(payload.jobId, jobID)
        XCTAssertEqual(payload.kind, report.request.kind.rawValue)
        XCTAssertEqual(payload.kind, "notify_office")
        XCTAssertEqual(payload.reason, report.request.reason)
        XCTAssertEqual(payload.nextAction, report.request.nextAction)
    }

    func testRequestEncodesOnlyServerFields() throws {
        let data = try JSONEncoder().encode(CantStartReport(reason: .noOneHome, note: "").request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["kind", "reason", "nextAction"])
        XCTAssertEqual(object["kind"] as? String, "notify_office")
    }

    func testQueuedOutcomeNeverReadsAsSent() {
        XCTAssertTrue(CantStartOutcome.queued.message.contains("Saved on this phone"))
        XCTAssertNotEqual(CantStartOutcome.queued.message, CantStartOutcome.sent.message)
    }
}
