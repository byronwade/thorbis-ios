import UIKit
import XCTest
@testable import Thorbis

@MainActor
final class WhatsNewTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "whats-new-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func note(_ id: String, highlights: Int = 1, fixes: Int = 0) -> ReleaseNote {
        ReleaseNote(id: id, date: "2026-10-28",
                    highlights: (0..<highlights).map { .init(symbol: "sparkles", title: "Change \($0)", detail: "Detail.") },
                    fixes: fixes)
    }

    // MA-21: every shipped note follows the writing rules.
    func testShippedNotesFollowTheWritingRules() {
        let notes = ReleaseNotes.all
        XCTAssertFalse(notes.isEmpty)
        XCTAssertEqual(Set(notes.map(\.id)).count, notes.count, "Release note ids must be unique")
        var previous: Date?
        for note in notes {
            let day = try? XCTUnwrap(note.day, "\(note.id): date must be yyyy-MM-dd")
            if let previous, let day { XCTAssertLessThanOrEqual(day, previous, "\(note.id): newest entries go first") }
            previous = day
            XCTAssertTrue((1...ReleaseNote.maxHighlights).contains(note.highlights.count), "\(note.id): one to five highlights")
            XCTAssertGreaterThanOrEqual(note.fixes, 0)
            for item in note.highlights {
                XCTAssertFalse(item.title.isEmpty)
                XCTAssertLessThanOrEqual(item.title.count, ReleaseNote.maxTitle, "Too long: \(item.title)")
                XCTAssertFalse(item.detail.isEmpty)
                XCTAssertLessThanOrEqual(item.detail.count, ReleaseNote.maxDetail, "Too long: \(item.detail)")
                XCTAssertNotNil(UIImage(systemName: item.symbol), "Unknown SF Symbol \(item.symbol)")
                XCTAssertNil(item.title.range(of: #"(BYR|THOR)-\d+|#\d+"#, options: .regularExpression), "No ticket ids: \(item.title)")
                XCTAssertNil(item.detail.range(of: #"(BYR|THOR)-\d+|#\d+"#, options: .regularExpression), "No ticket ids: \(item.detail)")
            }
        }
    }

    // MA-19: a fresh install (signed in through the sign-in screen) never sees the sheet.
    func testFreshInstallMarksEverythingSeen() {
        let store = defaults()
        let whatsNew = WhatsNew(defaults: store, notes: [note("b"), note("a")])
        whatsNew.signedInThisLaunch = true
        whatsNew.presentIfNeeded(build: "66")
        XCTAssertNil(whatsNew.showing)
        XCTAssertEqual(store.array(forKey: WhatsNew.seenKey) as? [String], ["a", "b"])
    }

    // MA-19: updating from a build before What's new shows the newest notes only.
    func testUpdateFromBeforeWhatsNewShowsTheNewestEntry() {
        let whatsNew = WhatsNew(defaults: defaults(), notes: [note("b"), note("a")])
        whatsNew.presentIfNeeded(build: "66")
        XCTAssertEqual(whatsNew.showing?.notes.map(\.id), ["b"])
    }

    // MA-19, MA-22: skipped builds fold together, and once dismissed they never come back.
    func testUnseenNotesFoldAndDismissingIsReading() {
        let store = defaults()
        store.set(["a"], forKey: WhatsNew.seenKey)
        let whatsNew = WhatsNew(defaults: store, notes: [note("c"), note("b"), note("a")])
        whatsNew.presentIfNeeded(build: "66")
        XCTAssertEqual(whatsNew.showing?.notes.map(\.id), ["c", "b"])
        // A swipe down clears the binding before onDismiss runs.
        whatsNew.showing = nil
        whatsNew.dismissed()
        XCTAssertEqual(Set(store.array(forKey: WhatsNew.seenKey) as? [String] ?? []), ["a", "b", "c"])

        let next = WhatsNew(defaults: store, notes: [note("c"), note("b"), note("a")])
        next.presentIfNeeded(build: "66")
        XCTAssertNil(next.showing)
    }

    // MA-19: a launch from a link or notification waits; the notes stay unseen for next time.
    func testLaunchFromALinkWaitsForTheNextLaunch() {
        let store = defaults()
        store.set(["a"], forKey: WhatsNew.seenKey)
        let whatsNew = WhatsNew(defaults: store, notes: [note("b"), note("a")])
        whatsNew.skipThisLaunch = true
        whatsNew.presentIfNeeded(build: "66")
        XCTAssertNil(whatsNew.showing)
        XCTAssertEqual(WhatsNew(defaults: store, notes: [note("b"), note("a")]).pending(signedInThisLaunch: false).map(\.id), ["b"])
    }

    func testSignInAfterAnUpdateStillShowsUnseenNotes() {
        let store = defaults()
        store.set(["a"], forKey: WhatsNew.seenKey)
        let whatsNew = WhatsNew(defaults: store, notes: [note("b"), note("a")])
        whatsNew.signedInThisLaunch = true
        whatsNew.presentIfNeeded(build: "66")
        XCTAssertEqual(whatsNew.showing?.notes.map(\.id), ["b"])
    }

    // MA-20: five highlights at most; the rest and the fixes are counted.
    func testSheetShowsFiveHighlightsAndCountsTheRest() {
        let content = WhatsNewSheetContent(notes: [note("b", highlights: 4, fixes: 2), note("a", highlights: 3, fixes: 1)], build: "66")
        XCTAssertEqual(content.highlights.count, 5)
        XCTAssertEqual(content.moreLine, "Also: 5 more changes")
        XCTAssertEqual(WhatsNewSheetContent(notes: [note("a", fixes: 3)], build: "66").moreLine, "Also: 3 smaller fixes")
        XCTAssertEqual(WhatsNewSheetContent(notes: [note("a", fixes: 1)], build: "66").moreLine, "Also: 1 smaller fix")
        XCTAssertNil(WhatsNewSheetContent(notes: [note("a")], build: "66").moreLine)
    }

    func testBuildLineNamesTheBuildAndDay() {
        let content = WhatsNewSheetContent(notes: [note("a")], build: "66")
        XCTAssertEqual(content.buildLine, "Build 66 · \(note("a").dayLabel)")
        XCTAssertTrue(note("a").dayLabel.contains("28"))
    }
}
