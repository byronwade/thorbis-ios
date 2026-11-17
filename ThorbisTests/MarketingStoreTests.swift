import XCTest
@testable import Thorbis

@MainActor
final class MarketingStoreTests: XCTestCase {
    private let orgA = "00000000-0000-4000-8000-000000000003"
    private let orgB = "00000000-0000-4000-8000-000000000004"

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }

    private func day(_ text: String) -> Date { LearnDay.date(from: text, calendar: calendar) ?? .distantPast }

    private func entry(_ source: String?, _ added: String? = nil) -> LeadSourceEntry {
        LeadSourceEntry(source: source, createdAt: added.map(day))
    }

    // MARK: Lead source tally

    func testTallyCountsCustomersPerSourceAndFoldsSpelling() {
        let tally = LeadSourceTally.make([
            entry("Google"), entry("google "), entry("  GOOGLE"), entry("Google"),
            entry("Referral"), entry("referral"),
            entry("Yard  sign"),
            entry(nil), entry(""), entry("   "),
        ])
        XCTAssertEqual(tally.recorded, 7)
        XCTAssertEqual(tally.unrecorded, 3)
        XCTAssertEqual(tally.total, 10)
        XCTAssertEqual(tally.sources.map(\.name), ["Google", "Referral", "Yard sign"])
        XCTAssertEqual(tally.sources.map(\.count), [4, 2, 1])
        XCTAssertEqual(tally.sources.map(\.percent), [57, 29, 14])
        XCTAssertEqual(tally.sources.reduce(0) { $0 + $1.share }, 1, accuracy: 0.0001)
        XCTAssertEqual(tally.summary, "Google 57% \u{00B7} Referral 29% \u{00B7} Yard sign 14%")
    }

    func testTallyKeepsTheSpellingMostCustomersUseAndBreaksTiesByName() {
        let tally = LeadSourceTally.make([entry("nextdoor"), entry("Nextdoor"), entry("Nextdoor"), entry("Angi"), entry("Angi"), entry("Angi")])
        XCTAssertEqual(tally.sources.map(\.name), ["Angi", "Nextdoor"])
        // The first spelling seen settles a one-each tie.
        XCTAssertEqual(LeadSourceTally.make([entry("yelp"), entry("Yelp")]).sources.first?.name, "yelp")
    }

    func testTallyWithNoCustomersOrNoSources() {
        XCTAssertEqual(LeadSourceTally.make([]), .empty)
        let none = LeadSourceTally.make([entry(nil), entry("")])
        XCTAssertTrue(none.sources.isEmpty)
        XCTAssertEqual(none.unrecorded, 2)
        XCTAssertEqual(none.summary, "")
    }

    func testTallyRangeCountsOnlyCustomersAddedSinceTheStart() {
        let entries = [
            entry("Google", "2026-11-10"), entry("Referral", "2026-10-01"), entry("Google", "2026-03-02"),
            entry("Mailer", "2025-12-30"), entry(nil, "2026-11-01"), entry("Google"),
        ]
        let now = calendar.date(byAdding: .hour, value: 10, to: day("2026-11-17")) ?? day("2026-11-17")
        func tally(_ period: LeadSourcePeriod) -> LeadSourceTally {
            LeadSourceTally.make(entries, since: period.start(now: now, calendar: calendar))
        }
        XCTAssertEqual(tally(.days30).sources.map(\.name), ["Google"])
        XCTAssertEqual(tally(.days30).unrecorded, 1)
        XCTAssertEqual(tally(.days90).sources.map(\.count), [1, 1])
        XCTAssertEqual(tally(.year).sources.map(\.count), [2, 1])
        XCTAssertEqual(tally(.year).total, 4)
        // All time counts the customer with no added date too.
        XCTAssertEqual(tally(.all).sources.first?.count, 3)
        XCTAssertEqual(tally(.all).total, 6)
        XCTAssertEqual(LeadSourcePeriod.days30.start(now: now, calendar: calendar), day("2026-10-18"))
        XCTAssertEqual(LeadSourcePeriod.year.start(now: now, calendar: calendar), day("2026-01-01"))
        XCTAssertNil(LeadSourcePeriod.all.start(now: now, calendar: calendar))
    }

    func testLongTailFoldsIntoOther() {
        let names = ["A", "A", "A", "B", "B", "C", "D", "E", "F", "G"]
        let tally = LeadSourceTally.make(names.map { entry($0) })
        XCTAssertEqual(tally.sources.count, 7)
        XCTAssertEqual(tally.grouped.map(\.name), ["A", "B", "C", "D", "E", "Other"])
        XCTAssertEqual(tally.grouped.last?.count, 2)
        XCTAssertEqual(tally.grouped.reduce(0) { $0 + $1.count }, 10)
        XCTAssertEqual(LeadSourceTally.make([entry("A"), entry("B")]).grouped.count, 2)
    }

    // MARK: Campaign notes

    func testCostParsesDollarsAndCents() {
        XCTAssertEqual(MarketingCampaigns.cents(from: "250"), 25_000)
        XCTAssertEqual(MarketingCampaigns.cents(from: " $1,250.50 "), 125_050)
        XCTAssertEqual(MarketingCampaigns.cents(from: "0.5"), 50)
        XCTAssertEqual(MarketingCampaigns.cents(from: ".05"), 5)
        XCTAssertEqual(MarketingCampaigns.cents(from: "12."), 1_200)
        XCTAssertNil(MarketingCampaigns.cents(from: ""))
        XCTAssertNil(MarketingCampaigns.cents(from: "."))
        XCTAssertNil(MarketingCampaigns.cents(from: "-20"))
        XCTAssertNil(MarketingCampaigns.cents(from: "1.234"))
        XCTAssertNil(MarketingCampaigns.cents(from: "1.2.3"))
        XCTAssertNil(MarketingCampaigns.cents(from: "about 300"))
        XCTAssertEqual(MarketingCampaigns.text(cents: 125_050), "1250.50")
        XCTAssertEqual(MarketingCampaigns.text(cents: 30_000), "300")
        XCTAssertEqual(MarketingCampaigns.text(cents: nil), "")
    }

    func testTotalsDatesAndOrder() {
        let locale = Locale(identifier: "en_US")
        let fall = MarketingCampaignNote(id: "fall", name: "Fall tune-up", channel: "Text", startsOn: "2026-09-01", endsOn: "2026-09-30",
                                         costCents: 25_000, createdAt: "2026-08-20T00:00:00Z")
        let mailer = MarketingCampaignNote(id: "mailer", name: "Mailer", channel: "Mail", startsOn: "2026-10-05", costCents: 80_050,
                                           createdAt: "2026-08-01T00:00:00Z")
        let idea = MarketingCampaignNote(id: "idea", name: "Yard signs", channel: "Other", createdAt: "2026-11-01T00:00:00Z")
        XCTAssertEqual(MarketingCampaigns.totalCents([fall, mailer, idea]), 105_050)
        XCTAssertEqual(MarketingCampaigns.dates(fall, calendar: calendar, locale: locale), "Sep 1, 2026 to Sep 30, 2026")
        XCTAssertEqual(MarketingCampaigns.dates(mailer, calendar: calendar, locale: locale), "Oct 5, 2026")
        XCTAssertNil(MarketingCampaigns.dates(idea, calendar: calendar, locale: locale))
        XCTAssertEqual(MarketingCampaigns.sorted([idea, fall, mailer]).map(\.id), ["mailer", "fall", "idea"])
    }

    func testCampaignNotesRoundTripPerWorkspace() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let book = try MarketingRecords(organizationID: orgA, directory: directory)
        XCTAssertTrue(book.campaigns.isEmpty)
        var note = MarketingCampaignNote(id: "fall", name: "Fall tune-up", channel: "Text", startsOn: "2026-09-01", costCents: 25_000, note: "Past AC customers")
        try book.save(note)
        note.costCents = 30_000
        try book.save(note)

        let again = try MarketingRecords(organizationID: orgA.uppercased(), directory: directory)
        XCTAssertEqual(again.campaigns.count, 1)
        XCTAssertEqual(again.campaigns.first?.costCents, 30_000)
        XCTAssertEqual(again.campaigns.first?.note, "Past AC customers")
        XCTAssertTrue(try MarketingRecords(organizationID: orgB, directory: directory).campaigns.isEmpty)
        XCTAssertFalse(again.fileURL.lastPathComponent.contains(orgA))
        XCTAssertThrowsError(try MarketingRecords(organizationID: "nope", directory: directory))

        try again.removeCampaign("fall")
        XCTAssertTrue(try MarketingRecords(organizationID: orgA, directory: directory).campaigns.isEmpty)
    }

    func testTrainingAndMarketingBooksNeverShareAFile() throws {
        let actor = "00000000-0000-4000-8000-000000000001"
        XCTAssertNotEqual(try LearnPartition.name(kind: "training", actorID: actor, organizationID: orgA),
                          try LearnPartition.name(kind: "marketing", actorID: nil, organizationID: orgA))
        XCTAssertNotEqual(try LearnPartition.name(kind: "marketing", actorID: nil, organizationID: orgA),
                          try LearnPartition.name(kind: "marketing", actorID: nil, organizationID: orgB))
    }
}
