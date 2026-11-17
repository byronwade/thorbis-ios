import XCTest
@testable import Thorbis

@MainActor
final class PipelineRecordsTests: XCTestCase {
    private let orgA = "00000000-0000-4000-8000-000000000003"
    private let orgB = "00000000-0000-4000-8000-000000000004"

    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private var sample: [LeadRecord] {
        [LeadRecord(name: "Gloria Reyes", valueCents: 720_000),
         LeadRecord(name: "Mei Chen", valueCents: 620_000),
         LeadRecord(name: "No estimate"),
         LeadRecord(name: "Tom Becker", valueCents: 240_000, stage: .visitBooked),
         LeadRecord(name: "Ridgeview HOA", valueCents: 980_050, stage: .quoted),
         LeadRecord(name: "Won job", valueCents: 500_000, stage: .won),
         LeadRecord(name: "Lost job", valueCents: 100_000, stage: .lost)]
    }

    func testStageCounts() {
        let counts = PipelineMath.counts(sample)
        XCTAssertEqual(counts[.new], 3)
        XCTAssertEqual(counts[.visitBooked], 1)
        XCTAssertEqual(counts[.quoted], 1)
        XCTAssertEqual(counts[.won], 1)
        XCTAssertEqual(counts[.lost], 1)
        XCTAssertEqual(PipelineMath.count(sample, in: .new), 3)
        XCTAssertEqual(PipelineMath.openCount(sample), 5)
        XCTAssertEqual(PipelineMath.counts([])[.new], 0)
    }

    func testValueTotalsLeaveOutWonLostAndMissingEstimates() {
        XCTAssertEqual(PipelineMath.possibleValue(sample), 2_560_050)
        XCTAssertEqual(PipelineMath.value(sample, in: .new), 1_340_000)
        XCTAssertEqual(PipelineMath.value(sample, in: .won), 500_000)
        XCTAssertEqual(PipelineMath.value(sample, in: .lost), 100_000)
        XCTAssertEqual(PipelineMath.possibleValue([LeadRecord(name: "Odd", valueCents: -5)]), 0)
        XCTAssertEqual(PipelineMath.summary(sample), "5 leads \u{00B7} $25,600.50 possible")
        XCTAssertEqual(PipelineMath.summary([LeadRecord(name: "One")]), "1 lead")
        XCTAssertEqual(PipelineMath.summary([]), "0 leads")
        XCTAssertEqual(PipelineMath.money(3_480_000), "$34,800")
    }

    func testStagesMoveForwardAndEnd() {
        XCTAssertEqual(LeadStage.new.next, .visitBooked)
        XCTAssertEqual(LeadStage.visitBooked.next, .quoted)
        XCTAssertEqual(LeadStage.quoted.next, .won)
        XCTAssertNil(LeadStage.won.next)
        XCTAssertNil(LeadStage.lost.next)
        XCTAssertTrue(LeadStage.quoted.isOpen)
        XCTAssertFalse(LeadStage.won.isOpen)
    }

    func testLeadsRoundTripMoveAndPartitionByWorkspace() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = try PipelineRecords(organizationID: orgA, directory: directory)
        let made = Date(timeIntervalSince1970: 1_800_000_000)
        let lead = LeadRecord(name: "Tom Becker", phone: "(555) 010-0192", need: "Water heater quote",
                              source: "Google", valueCents: 240_000, note: "Home after 3", createdAt: made)
        try records.save(lead)
        XCTAssertEqual(records.lead(lead.id)?.updatedAt, made)
        XCTAssertThrowsError(try records.save(LeadRecord(name: " ")))

        let later = made.addingTimeInterval(3_600)
        try records.move(lead.id, to: .visitBooked, now: later)
        try records.move(lead.id, to: .won, now: later)
        let reopened = try PipelineRecords(organizationID: orgA, directory: directory)
        let saved = try XCTUnwrap(reopened.lead(lead.id))
        XCTAssertEqual(saved.stage, .won)
        XCTAssertEqual(saved.updatedAt, later)
        XCTAssertEqual(saved.createdAt, made)
        XCTAssertEqual(saved.valueCents, 240_000)
        XCTAssertEqual(saved.callURL?.absoluteString, "tel:5550100192")
        XCTAssertEqual(saved.textURL?.absoluteString, "sms:5550100192")
        XCTAssertNil(LeadRecord(name: "No phone").callURL)

        XCTAssertTrue(try PipelineRecords(organizationID: orgB, directory: directory).leads.isEmpty)
        XCTAssertFalse(reopened.fileURL.lastPathComponent.contains(orgA))
        XCTAssertThrowsError(try records.move("missing", to: .lost))
        try reopened.remove(lead.id)
        XCTAssertTrue(try PipelineRecords(organizationID: orgA, directory: directory).leads.isEmpty)
    }

    func testStageListIsNewestFirst() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let older = LeadRecord(name: "Older", createdAt: now.addingTimeInterval(-500))
        let newer = LeadRecord(name: "Newer", createdAt: now)
        XCTAssertEqual(PipelineMath.leads([older, newer], in: .new).map(\.name), ["Newer", "Older"])
        XCTAssertTrue(PipelineMath.leads([older, newer], in: .quoted).isEmpty)
    }

    func testWhenReadsYesterdayAndOlderDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 12)))
        XCTAssertEqual(PipelineMath.when(now.addingTimeInterval(-86_400), now: now, calendar: calendar), "Yesterday")
        XCTAssertFalse(PipelineMath.when(now.addingTimeInterval(-30 * 86_400), now: now, calendar: calendar).isEmpty)
    }
}
