import XCTest
@testable import Thorbis

@MainActor
final class CustomerNotesStoreTests: XCTestCase {
    private let orgA = "00000000-0000-4000-8000-000000000003"
    private let orgB = "00000000-0000-4000-8000-000000000004"
    private let ramon = "00000000-0000-4000-8000-000000000001"

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text) ?? .distantPast }

    func testAddKeepsWhoAndWhenAndSurvivesReopening() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CustomerNotesStore(organizationID: orgA, directory: directory)
        XCTAssertTrue(store.notes(for: "cus-1").isEmpty)
        let note = try store.add(customerID: "cus-1", body: "  Prefers texts  ", authorID: ramon, authorName: " Ramon Mendez ",
                                 now: date("2026-11-17T17:00:00Z"))
        XCTAssertEqual(note.body, "Prefers texts")
        XCTAssertEqual(note.authorName, "Ramon Mendez")
        XCTAssertEqual(note.authorID, ramon)
        XCTAssertEqual(note.createdAt, "2026-11-17T17:00:00Z")
        XCTAssertNil(note.editedAt)

        let reopened = try CustomerNotesStore(organizationID: orgA, directory: directory)
        XCTAssertEqual(reopened.notes(for: "cus-1"), [note])
        XCTAssertEqual(reopened.notes(for: "CUS-1"), [note])
        XCTAssertTrue(reopened.notes(for: "cus-2").isEmpty)
    }

    func testNotesAreNewestFirstPerCustomer() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CustomerNotesStore(organizationID: orgA, directory: directory)
        try store.add(customerID: "cus-1", body: "Dog in back yard", authorID: ramon, authorName: "Ramon", now: date("2026-11-10T10:00:00Z"))
        try store.add(customerID: "cus-2", body: "Other customer", authorID: ramon, authorName: "Ramon", now: date("2026-11-12T10:00:00Z"))
        try store.add(customerID: "cus-1", body: "Prefers texts\nNot before 9", authorID: ramon, authorName: "Ramon", now: date("2026-11-15T10:00:00Z"))
        XCTAssertEqual(store.notes(for: "cus-1").map(\.body), ["Prefers texts\nNot before 9", "Dog in back yard"])
        XCTAssertEqual(CustomerNoteRules.summary(store.notes(for: "cus-1")), "Prefers texts · Dog in back yard")
        XCTAssertNil(CustomerNoteRules.summary([]))
    }

    func testEditChangesTheWordsAndMarksItEdited() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CustomerNotesStore(organizationID: orgA, directory: directory)
        let note = try store.add(customerID: "cus-1", body: "Gate code 4482", authorID: ramon, authorName: "Ramon",
                                 now: date("2026-11-10T10:00:00Z"))
        let same = try store.edit(note.id, body: " Gate code 4482 ", now: date("2026-11-11T10:00:00Z"))
        XCTAssertNil(same.editedAt, "saving the same words is not an edit")
        let edited = try store.edit(note.id, body: "Gate code 4490", now: date("2026-11-12T10:00:00Z"))
        XCTAssertEqual(edited.body, "Gate code 4490")
        XCTAssertEqual(edited.editedAt, "2026-11-12T10:00:00Z")
        XCTAssertEqual(edited.createdAt, note.createdAt)
        XCTAssertEqual(edited.authorName, "Ramon")
        XCTAssertEqual(try CustomerNotesStore(organizationID: orgA, directory: directory).notes(for: "cus-1"), [edited])
        XCTAssertThrowsError(try store.edit("missing", body: "x"))
    }

    func testEmptyAndOverlongNotesAreRefused() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CustomerNotesStore(organizationID: orgA, directory: directory)
        XCTAssertThrowsError(try store.add(customerID: "cus-1", body: " \n ", authorID: ramon, authorName: "Ramon"))
        XCTAssertThrowsError(try store.add(customerID: "cus-1", body: String(repeating: "a", count: CustomerNoteRules.limit + 1),
                                           authorID: ramon, authorName: "Ramon"))
        let note = try store.add(customerID: "cus-1", body: String(repeating: "a", count: CustomerNoteRules.limit),
                                 authorID: ramon, authorName: "Ramon")
        XCTAssertThrowsError(try store.edit(note.id, body: ""))
        XCTAssertEqual(store.notes(for: "cus-1").count, 1)
    }

    func testDeleteRemovesOnlyThatNote() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CustomerNotesStore(organizationID: orgA, directory: directory)
        let first = try store.add(customerID: "cus-1", body: "One", authorID: ramon, authorName: "Ramon", now: date("2026-11-10T10:00:00Z"))
        let second = try store.add(customerID: "cus-1", body: "Two", authorID: ramon, authorName: "Ramon", now: date("2026-11-11T10:00:00Z"))
        try store.remove(first.id)
        XCTAssertEqual(store.notes(for: "cus-1"), [second])
        XCTAssertEqual(try CustomerNotesStore(organizationID: orgA, directory: directory).notes(for: "cus-1"), [second])
    }

    func testWorkspacesDoNotShareNotes() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = try CustomerNotesStore(organizationID: orgA, directory: directory)
        let b = try CustomerNotesStore(organizationID: orgB, directory: directory)
        try a.add(customerID: "cus-1", body: "Only in A", authorID: ramon, authorName: "Ramon")
        XCTAssertNotEqual(a.fileURL, b.fileURL)
        XCTAssertTrue(try CustomerNotesStore(organizationID: orgB, directory: directory).notes(for: "cus-1").isEmpty)
        XCTAssertFalse(a.fileURL.lastPathComponent.contains(orgA), "the workspace id is not readable on disk")
        XCTAssertThrowsError(try CustomerNotesStore(organizationID: "not-a-workspace", directory: directory))
    }

    func testBylineSaysWhoWhenAndEdited() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        let locale = Locale(identifier: "en_US")
        var note = CustomerPhoneNote(customerID: "cus-1", body: "x", authorID: ramon, authorName: "Ramon Mendez",
                                     createdAt: "2026-11-17T17:00:00Z")
        XCTAssertEqual(CustomerNoteRules.byline(note, calendar: calendar, locale: locale), "Ramon Mendez · Nov 17, 2026")
        note.editedAt = "2026-11-18T17:00:00Z"
        XCTAssertEqual(CustomerNoteRules.byline(note, calendar: calendar, locale: locale), "Ramon Mendez · Nov 17, 2026 · edited")
    }
}
