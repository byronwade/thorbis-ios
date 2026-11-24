import XCTest
@testable import Thorbis

@MainActor
final class TrainingStoreTests: XCTestCase {
    private let actorA = "00000000-0000-4000-8000-000000000001"
    private let actorB = "00000000-0000-4000-8000-000000000002"
    private let orgA = "00000000-0000-4000-8000-000000000003"
    private let orgB = "00000000-0000-4000-8000-000000000004"

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }

    private func day(_ text: String, hour: Int = 9) -> Date {
        let start = LearnDay.date(from: text, calendar: calendar) ?? .distantPast
        return calendar.date(byAdding: .hour, value: hour, to: start) ?? start
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    // MARK: Expiry maths

    func testDaysLeftCountsWholeCalendarDays() {
        let today = day("2026-11-17", hour: 23)
        XCTAssertEqual(CredentialExpiry.daysLeft(expiresOn: "2026-11-17", today: today, calendar: calendar), 0)
        XCTAssertEqual(CredentialExpiry.daysLeft(expiresOn: "2026-11-18", today: today, calendar: calendar), 1)
        XCTAssertEqual(CredentialExpiry.daysLeft(expiresOn: "2026-12-01", today: today, calendar: calendar), 14)
        XCTAssertEqual(CredentialExpiry.daysLeft(expiresOn: "2026-11-14", today: today, calendar: calendar), -3)
        XCTAssertEqual(CredentialExpiry.daysLeft(expiresOn: "2027-11-17", today: today, calendar: calendar), 365)
        XCTAssertNil(CredentialExpiry.daysLeft(expiresOn: nil, today: today, calendar: calendar))
        XCTAssertNil(CredentialExpiry.daysLeft(expiresOn: "soon", today: today, calendar: calendar))
        XCTAssertNil(CredentialExpiry.daysLeft(expiresOn: "2026-02-31", today: today, calendar: calendar))
    }

    func testDaysLeftHoldsAcrossADaylightSavingChange() {
        // Clocks go back on 1 November 2026 in Los Angeles: that day is 25 hours long.
        let today = day("2026-10-31", hour: 12)
        XCTAssertEqual(CredentialExpiry.daysLeft(expiresOn: "2026-11-02", today: today, calendar: calendar), 2)
        // Clocks go forward on 14 March 2027: that day is 23 hours long.
        XCTAssertEqual(CredentialExpiry.daysLeft(expiresOn: "2027-03-15", today: day("2027-03-13", hour: 20), calendar: calendar), 2)
    }

    func testExpiryStatesAndTheWarningWindow() {
        let today = day("2026-11-17")
        func state(_ text: String?) -> CredentialExpiry { CredentialExpiry(expiresOn: text, today: today, calendar: calendar) }
        XCTAssertEqual(state(nil), .none)
        XCTAssertEqual(state("2026-11-16"), .expired(days: 1))
        XCTAssertEqual(state("2026-11-17"), .today)
        XCTAssertEqual(state("2026-11-18"), .soon(days: 1))
        XCTAssertEqual(state("2026-12-17"), .soon(days: 30))
        XCTAssertEqual(state("2026-12-18"), .valid(days: 31))
        XCTAssertTrue(state("2026-11-16").needsAttention)
        XCTAssertTrue(state("2026-11-17").needsAttention)
        XCTAssertTrue(state("2026-12-17").needsAttention)
        XCTAssertFalse(state("2026-12-18").needsAttention)
        XCTAssertFalse(state(nil).needsAttention)
    }

    func testExpiryLabels() {
        let today = day("2026-11-17")
        let locale = Locale(identifier: "en_US")
        func label(_ text: String?) -> String {
            CredentialExpiry.label(expiresOn: text, today: today, calendar: calendar, locale: locale)
        }
        XCTAssertEqual(label(nil), "No expiry date")
        XCTAssertEqual(label("2026-11-14"), "Expired 3 days ago")
        XCTAssertEqual(label("2026-11-16"), "Expired yesterday")
        XCTAssertEqual(label("2026-11-17"), "Expires today")
        XCTAssertEqual(label("2026-11-18"), "Expires tomorrow")
        XCTAssertEqual(label("2026-12-01"), "Expires in 14 days")
        XCTAssertEqual(label("2027-03-01"), "To Mar 1, 2027")
    }

    func testCredentialsSortSoonestFirstThenUndatedByName() {
        let today = day("2026-11-17")
        let cards = [
            TrainingCredential(id: "a", name: "Zeta", expiresOn: nil),
            TrainingCredential(id: "b", name: "Contractor", expiresOn: "2027-06-01"),
            TrainingCredential(id: "c", name: "EPA 608", expiresOn: "2026-11-01"),
            TrainingCredential(id: "d", name: "Alpha", expiresOn: nil),
            TrainingCredential(id: "e", name: "Backflow", expiresOn: "2026-12-01"),
        ]
        XCTAssertEqual(CredentialExpiry.sorted(cards, today: today, calendar: calendar).map(\.id), ["c", "e", "b", "d", "a"])
    }

    func testDaysRoundTripAndRejectWhatIsNotADay() {
        let date = day("2028-02-29", hour: 15)
        XCTAssertEqual(LearnDay.string(from: date, calendar: calendar), "2028-02-29")
        XCTAssertNotNil(LearnDay.date(from: "2028-02-29", calendar: calendar))
        XCTAssertNil(LearnDay.date(from: "2027-02-29", calendar: calendar))
        XCTAssertNil(LearnDay.date(from: "2027-2-9", calendar: calendar))
        XCTAssertNil(LearnDay.date(from: "", calendar: calendar))
    }

    func testCourseLinksAreWebAddressesOnly() {
        XCTAssertEqual(TrainingLink.url(" https://www.epa.gov/section608 ")?.host, "www.epa.gov")
        XCTAssertEqual(TrainingLink.host("https://www.epa.gov/section608"), "epa.gov")
        XCTAssertNil(TrainingLink.url("epa.gov"))
        XCTAssertNil(TrainingLink.url("tel:8005550199"))
        XCTAssertNil(TrainingLink.url("https://localhost"))
        XCTAssertNil(TrainingLink.url("https://epa.gov/a b"))
        XCTAssertNil(TrainingLink.url(nil))
    }

    // MARK: Store

    func testRecordsRoundTripAndPartitionByPersonAndWorkspace() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try TrainingRecords(actorID: actorA, organizationID: orgA, directory: directory)
        XCTAssertTrue(first.credentials.isEmpty)
        XCTAssertTrue(first.courses.isEmpty)
        try first.save(TrainingCredential(id: "card", name: "EPA 608", number: "1048211", issuer: "EPA", expiresOn: "2027-03-01"))
        try first.save(TrainingCourse(id: "course", title: "Backflow renewal", link: "https://example.com/backflow", progress: "Module 2 of 4"))

        let again = try TrainingRecords(actorID: actorA.uppercased(), organizationID: orgA, directory: directory)
        XCTAssertEqual(again.credentials.first?.number, "1048211")
        XCTAssertEqual(again.credentials.first?.expiresOn, "2027-03-01")
        XCTAssertEqual(again.courses.first?.progress, "Module 2 of 4")
        XCTAssertEqual(again.courses.first?.done, false)
        XCTAssertTrue(try TrainingRecords(actorID: actorB, organizationID: orgA, directory: directory).credentials.isEmpty)
        XCTAssertTrue(try TrainingRecords(actorID: actorA, organizationID: orgB, directory: directory).courses.isEmpty)
        XCTAssertFalse(again.fileURL.lastPathComponent.contains(actorA))
        XCTAssertFalse(again.fileURL.lastPathComponent.contains(orgA))
        XCTAssertThrowsError(try TrainingRecords(actorID: "not-an-id", organizationID: orgA, directory: directory))
    }

    func testEditingKeepsOneRecordAndRemovingDeletesIt() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let book = try TrainingRecords(actorID: actorA, organizationID: orgA, directory: directory)
        var course = TrainingCourse(id: "course", title: "Ladder safety")
        try book.save(course)
        course.done = true
        course.progress = "Passed"
        try book.save(course)
        XCTAssertEqual(book.courses.count, 1)
        XCTAssertEqual(book.courses.first?.done, true)
        try book.removeCourse("course")
        XCTAssertTrue(try TrainingRecords(actorID: actorA, organizationID: orgA, directory: directory).courses.isEmpty)
    }

    func testCardPhotoIsWrittenReplacedAndRemovedWithItsLicense() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let book = try TrainingRecords(actorID: actorA, organizationID: orgA, directory: directory)
        let card = TrainingCredential(id: "card", name: "Contractor license")
        let saved = try book.save(card, photo: .replace(Data([1, 2, 3])))
        let firstURL = try XCTUnwrap(book.photoURL(saved.photoFile))
        XCTAssertEqual(try Data(contentsOf: firstURL), Data([1, 2, 3]))

        // An edit that leaves the photo alone keeps the file, whatever the draft says.
        var edited = card
        edited.number = "CSLB 1048211"
        let kept = try book.save(edited, photo: .keep)
        XCTAssertEqual(kept.photoFile, saved.photoFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))

        let replaced = try book.save(edited, photo: .replace(Data([9])))
        let secondURL = try XCTUnwrap(book.photoURL(replaced.photoFile))
        XCTAssertNotEqual(secondURL, firstURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertEqual(try Data(contentsOf: secondURL), Data([9]))

        let reopened = try TrainingRecords(actorID: actorA, organizationID: orgA, directory: directory)
        XCTAssertEqual(reopened.credentials.first?.photoFile, replaced.photoFile)
        XCTAssertEqual(reopened.credentials.first?.number, "CSLB 1048211")

        try reopened.removeCredential("card")
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertTrue(reopened.credentials.isEmpty)
    }

    func testRemovingAPhotoAndErasingThePartition() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let book = try TrainingRecords(actorID: actorA, organizationID: orgA, directory: directory)
        let saved = try book.save(TrainingCredential(id: "card", name: "EPA 608"), photo: .replace(Data([7])))
        let url = try XCTUnwrap(book.photoURL(saved.photoFile))
        let cleared = try book.save(saved, photo: .remove)
        XCTAssertNil(cleared.photoFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(book.photoURL("../escape.jpg"))
        XCTAssertNil(book.photoURL(nil))

        try book.save(TrainingCredential(id: "other", name: "Backflow"), photo: .replace(Data([8])))
        try book.erasePartition()
        XCTAssertTrue(book.credentials.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: book.fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: book.photosURL.path))
    }
}
