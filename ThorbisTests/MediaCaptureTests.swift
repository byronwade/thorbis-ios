import XCTest
import UIKit
@testable import Thorbis

final class MediaCaptureTests: XCTestCase {
    func testCapturedPhotosAreDownscaledJPEGUnderTheSinglePutLimit() throws {
        let size = CGSize(width: 6000, height: 4000)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            for x in stride(from: 0, to: 6000, by: 40) {
                UIColor(hue: CGFloat(x) / 6000, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                context.fill(CGRect(x: x, y: 0, width: 40, height: 4000))
            }
        }
        let data = try XCTUnwrap(JobMediaView.jpeg(image))
        XCTAssertLessThanOrEqual(data.count, 8 * 1024 * 1024)
        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(max(decoded.size.width, decoded.size.height), 2560, accuracy: 1)
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8], "JPEG start-of-image marker")
    }

    func testRegistrationCarriesStageTagsAndOmitsEmptyTags() throws {
        let tagged = FieldMediaRegistrationRequest(clientAssetId: UUID().uuidString, kind: "photo", mime: "image/jpeg",
                                                   sizeBytes: 10, originalFilename: "before.jpg", contentHash: "abc", tags: ["Before"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(tagged)) as? [String: Any])
        XCTAssertEqual(json["tags"] as? [String], ["Before"])

        let untagged = FieldMediaRegistrationRequest(clientAssetId: UUID().uuidString, kind: "photo", mime: "image/jpeg",
                                                     sizeBytes: 10, originalFilename: "photo.jpg", contentHash: "abc")
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(untagged)) as? [String: Any])
        XCTAssertNil(plain["tags"])
    }
}
