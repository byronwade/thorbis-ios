import Foundation
import ImageIO

/// ImageIO work stays off the UI actor; only the bounded decoded image returns to the gallery.
struct CustomerPhotoThumbnail: @unchecked Sendable {
    let image: CGImage

    static func load(_ file: URL) async throws -> CustomerPhotoThumbnail {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048]
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw CustomerPhotoSelection.Invalid.records
            }
            try Task.checkCancellation()
            return CustomerPhotoThumbnail(image: image)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
