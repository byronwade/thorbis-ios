import XCTest
@testable import Thorbis

@MainActor
final class DocumentPreviewTests: XCTestCase {
    func testDismissedDownloadDeletesLateFile() async throws {
        let controller = DocumentPreviewController()
        var continuation: CheckedContinuation<URL, Error>?
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        controller.open { try await withCheckedThrowingContinuation { continuation = $0 } }
        while continuation == nil { await Task.yield() }
        controller.clear()
        try Data("private".utf8).write(to: file)
        continuation?.resume(returning: file)
        for _ in 0..<100 where FileManager.default.fileExists(atPath: file.path) { await Task.yield() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNil(controller.url)
    }

    func testClearingVisiblePreviewDeletesFile() async throws {
        let controller = DocumentPreviewController()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("private".utf8).write(to: file)
        controller.open { file }
        for _ in 0..<100 where controller.url == nil { await Task.yield() }
        XCTAssertEqual(controller.url, file)
        controller.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
