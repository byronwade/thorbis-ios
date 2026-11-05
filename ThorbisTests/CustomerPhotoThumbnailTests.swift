import XCTest
@testable import Thorbis

final class CustomerPhotoThumbnailTests: XCTestCase {
    func testAlreadyCancelledThumbnailTaskDoesNotPublishImage() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGOwb9kCRAwQCgAnPgXdEEuqSQAAAABJRU5ErkJggg=="))
        try png.write(to: file)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CustomerPhotoThumbnail.load(file)
        }
        do { _ = try await task.value; XCTFail("Cancelled decode must not publish") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testThumbnailDecodesAnImageAndRejectsNonImageData() async throws {
        let valid = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let invalid = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: valid); try? FileManager.default.removeItem(at: invalid) }
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGOwb9kCRAwQCgAnPgXdEEuqSQAAAABJRU5ErkJggg=="))
        try png.write(to: valid); try Data("not an image".utf8).write(to: invalid)
        let thumbnail = try await CustomerPhotoThumbnail.load(valid)
        XCTAssertEqual(thumbnail.image.width, 2)
        XCTAssertEqual(thumbnail.image.height, 2)
        do { _ = try await CustomerPhotoThumbnail.load(invalid); XCTFail("Invalid image data must fail") } catch {}
    }
}
