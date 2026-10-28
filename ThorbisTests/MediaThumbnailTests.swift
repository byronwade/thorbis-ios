import XCTest
import UIKit
@testable import Thorbis

final class MediaThumbnailTests: XCTestCase {
    func testDownsampleKeepsAspectAndCapsTheLongEdge() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try XCTUnwrap(image.jpegData(compressionQuality: 0.8)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let thumbnail = try XCTUnwrap(MediaThumbnailCache.downsample(url, to: 480))
        XCTAssertEqual(max(thumbnail.size.width, thumbnail.size.height), 480, accuracy: 1)
        XCTAssertEqual(thumbnail.size.width / thumbnail.size.height, 4.0 / 3.0, accuracy: 0.01)
    }

    func testDownsampleRejectsAFileThatIsNotAnImage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try Data("not an image".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(MediaThumbnailCache.downsample(url, to: 480))
    }
}
