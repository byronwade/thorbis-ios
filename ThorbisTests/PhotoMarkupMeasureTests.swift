import XCTest
import PencilKit
@testable import Thorbis

final class PhotoMarkupMeasureTests: XCTestCase {
    func testUSLocaleUsesFeetAndInchesWithCarry() {
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(MeasureDistanceFormatter.format(meters: 0.2, locale: us), "8 in")
        XCTAssertEqual(MeasureDistanceFormatter.format(meters: 1.3, locale: us), "4 ft 3 in")
        // 3 ft 11.7 in rounds up to a whole foot, never "3 ft 12 in".
        XCTAssertEqual(MeasureDistanceFormatter.format(meters: 47.7 * 0.0254, locale: us), "4 ft 0 in")
        XCTAssertEqual(MeasureDistanceFormatter.caption(meters: 1.3, locale: us), "Measured 4 ft 3 in")
    }

    func testMetricLocalesUseLocaleNumberFormatting() {
        XCTAssertEqual(MeasureDistanceFormatter.format(meters: 1.25, locale: Locale(identifier: "fr_FR")), "1,25 m")
        XCTAssertEqual(MeasureDistanceFormatter.format(meters: 2.5, locale: Locale(identifier: "de_DE")), "2,50 m")
        XCTAssertEqual(MeasureDistanceFormatter.format(meters: 0.456, locale: Locale(identifier: "en_GB")), "46 cm")
    }

    func testFlatteningReturnsNewImageAndKeepsOriginal() {
        let size = CGSize(width: 200, height: 100)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
        }
        let originalBytes = original.pngData()
        let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: [
            PKStrokePoint(location: CGPoint(x: 10, y: 25), timeOffset: 0, size: CGSize(width: 8, height: 8), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: 90, y: 25), timeOffset: 0.1, size: CGSize(width: 8, height: 8), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
        ], creationDate: Date()))
        // Drawn on a half-size canvas; flattening scales ink up to the photo's pixels.
        let flattened = PhotoMarkupFlattener.flatten(original, drawing: PKDrawing(strokes: [stroke]), canvasSize: CGSize(width: 100, height: 50))

        XCTAssertFalse(flattened === original)
        XCTAssertEqual(flattened.size, size)
        XCTAssertEqual(original.pngData(), originalBytes, "The original photo must not change")
        XCTAssertNotEqual(flattened.pngData(), originalBytes, "The markup must be in the new image")
    }

    func testFittedRectKeepsAspectRatio() {
        let rect = PhotoMarkupFlattener.fittedRect(for: CGSize(width: 4000, height: 3000), in: CGSize(width: 400, height: 800))
        XCTAssertEqual(rect.width, 400, accuracy: 0.01)
        XCTAssertEqual(rect.height, 300, accuracy: 0.01)
        XCTAssertEqual(rect.minY, 250, accuracy: 0.01)
    }

    func testPendingMediaWithoutCaptionStillDecodesAndCaptionNamesTheRow() throws {
        let legacy = #"{"id":"6F1C1D44-0B0B-4C55-9D8E-1E1A5E4D9A01","jobID":"job","filename":"a.jpg","tags":["Before"],"capturedAt":0,"kind":"photo","mime":"image/jpeg"}"#
        let decoded = try JSONDecoder().decode(PendingMedia.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.caption)
        XCTAssertEqual(decoded.title, "Before photo")
        let marked = PendingMedia(id: decoded.id, jobID: "job", filename: "markup.jpg", tags: ["Before"],
                                  capturedAt: Date(), kind: "photo", mime: "image/jpeg", caption: "Marked up")
        XCTAssertEqual(marked.title, "Marked up")
    }
}
