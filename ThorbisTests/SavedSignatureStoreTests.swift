import XCTest
@testable import Thorbis

@MainActor
final class SavedSignatureStoreTests: XCTestCase {
    private let ramon = "00000000-0000-4000-8000-000000000001"
    private let sam = "00000000-0000-4000-8000-000000000002"

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private let ink: [[CGPoint]] = [[CGPoint(x: 10, y: 40), CGPoint(x: 60, y: 10), CGPoint(x: 110, y: 40)], [CGPoint(x: 5, y: 5)]]

    func testSaveKeepsInkNameAndDayAndSurvivesReopening() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertFalse(SavedSignatureStore.isOnFile(actorID: ramon, directory: directory))
        let store = try SavedSignatureStore(actorID: ramon, directory: directory)
        XCTAssertNil(store.signature)
        let saved = try store.save(strokes: ink, padSize: CGSize(width: 320, height: 200), signerName: " Ramon Mendez ",
                                   now: ISO8601DateFormatter().date(from: "2026-06-03T16:00:00Z") ?? Date())
        XCTAssertEqual(saved.strokes.count, 1, "a tap without ink is not kept")
        XCTAssertEqual(saved.signerName, "Ramon Mendez")
        XCTAssertEqual(saved.savedAt, "2026-06-03T16:00:00Z")
        XCTAssertTrue(SavedSignatureStore.isOnFile(actorID: ramon, directory: directory))
        XCTAssertEqual(try SavedSignatureStore(actorID: ramon, directory: directory).signature, saved)
    }

    func testEmptyDrawingIsRefused() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SavedSignatureStore(actorID: ramon, directory: directory)
        XCTAssertThrowsError(try store.save(strokes: [[CGPoint(x: 1, y: 1)]], padSize: CGSize(width: 320, height: 200), signerName: "Ramon"))
        XCTAssertNil(store.signature)
        XCTAssertFalse(SavedSignatureStore.isOnFile(actorID: ramon, directory: directory))
    }

    func testClearDeletesTheFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SavedSignatureStore(actorID: ramon, directory: directory)
        try store.save(strokes: ink, padSize: CGSize(width: 320, height: 200), signerName: "Ramon")
        try store.clear()
        XCTAssertNil(store.signature)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertNil(try SavedSignatureStore(actorID: ramon, directory: directory).signature)
        XCTAssertNoThrow(try store.clear())
    }

    func testEachPersonHasTheirOwn() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try SavedSignatureStore(actorID: ramon, directory: directory)
            .save(strokes: ink, padSize: CGSize(width: 320, height: 200), signerName: "Ramon")
        let other = try SavedSignatureStore(actorID: sam, directory: directory)
        XCTAssertNil(other.signature)
        XCTAssertFalse(SavedSignatureStore.isOnFile(actorID: sam, directory: directory))
        XCTAssertFalse(other.fileURL.lastPathComponent.contains(sam))
        XCTAssertThrowsError(try SavedSignatureStore(actorID: "someone", directory: directory))
        XCTAssertFalse(SavedSignatureStore.isOnFile(actorID: nil, directory: directory))
    }

    func testFitCentresTheInkAndKeepsItsShape() {
        let fitted = SavedSignatureInk.fit(ink, in: CGSize(width: 300, height: 100), padding: 10, maxScale: 10)
        XCTAssertEqual(fitted.count, 1)
        let points = fitted.flatMap { $0 }
        let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 0
        // 100 x 30 of ink in a 280 x 80 box scales by 80 / 30.
        XCTAssertEqual(maxY - minY, 80, accuracy: 0.001)
        XCTAssertEqual((maxX - minX) / (maxY - minY), 100.0 / 30.0, accuracy: 0.001)
        XCTAssertEqual(minY, 10, accuracy: 0.001)
        XCTAssertEqual(minX, 300 - maxX, accuracy: 0.001)
        XCTAssertTrue(SavedSignatureInk.fit([], in: CGSize(width: 300, height: 100)).isEmpty)
        XCTAssertTrue(SavedSignatureInk.fit(ink, in: CGSize(width: 10, height: 10)).isEmpty)
        // Small ink is not blown up past the cap.
        let capped = SavedSignatureInk.fit(ink, in: CGSize(width: 3000, height: 1000), padding: 10, maxScale: 1.5).flatMap { $0 }
        XCTAssertEqual((capped.map(\.x).max() ?? 0) - (capped.map(\.x).min() ?? 0), 150, accuracy: 0.001)
    }

    func testSavedLabel() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        let locale = Locale(identifier: "en_US")
        let now = ISO8601DateFormatter().date(from: "2026-11-17T20:00:00Z") ?? Date()
        XCTAssertEqual(SavedSignatureInk.savedLabel("2026-06-03T16:00:00Z", now: now, calendar: calendar, locale: locale), "Saved Jun 3")
        XCTAssertEqual(SavedSignatureInk.savedLabel("2025-06-03T16:00:00Z", now: now, calendar: calendar, locale: locale), "Saved Jun 3, 2025")
        XCTAssertEqual(SavedSignatureInk.savedLabel("", now: now, calendar: calendar, locale: locale), "Saved")
    }
}
