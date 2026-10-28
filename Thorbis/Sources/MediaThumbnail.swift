import ImageIO
import SwiftUI
import UIKit

/// The photo itself in the Photos grid, so a tech can tell before from after at a glance.
/// Downloads through MediaTransfer (signed, no redirects), downsamples with ImageIO so a
/// 12 MP photo costs a few hundred KB, and keeps decoded thumbnails in memory per media id.
@MainActor
final class MediaThumbnailCache {
    static let shared = MediaThumbnailCache()
    private let images = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init() { images.countLimit = 120 }

    func image(for id: String) -> UIImage? { images.object(forKey: id as NSString) }

    func load(_ record: MediaAssetRecord, api: APIClient, pixelSize: CGFloat) async -> UIImage? {
        if let cached = image(for: record.id) { return cached }
        if let running = inFlight[record.id] { return await running.value }
        let task = Task<UIImage?, Never> {
            guard let file = try? await MediaTransfer(api: api).download(mediaID: record.id, filename: record.originalFilename)
            else { return nil }
            defer { try? FileManager.default.removeItem(at: file) }
            return await Task.detached(priority: .utility) { Self.downsample(file, to: pixelSize) }.value
        }
        inFlight[record.id] = task
        let image = await task.value
        inFlight[record.id] = nil
        if let image { images.setObject(image, forKey: record.id as NSString) }
        return image
    }

    nonisolated static func downsample(_ url: URL, to pixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    static func isImage(_ record: MediaAssetRecord) -> Bool {
        ["jpg", "jpeg", "png", "webp", "heic"].contains((record.originalFilename as NSString).pathExtension.lowercased())
    }
}

struct MediaThumbnail: View {
    let record: MediaAssetRecord
    var attempt = 0
    @EnvironmentObject private var api: APIClient
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Theme.fill
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            } else {
                Image(systemName: failed ? "exclamationmark.triangle" : "photo")
                    .font(.system(size: 22, weight: .light)).foregroundStyle(Theme.muted)
            }
        }
        .clipped()
        .accessibilityHidden(true)
        // Keyed on upload state (a photo first seen mid-upload loads once stored) and on the
        // refresh attempt (pull-to-refresh retries a failed download; cached ones return at once).
        .task(id: "\(record.id)|\(record.uploadState)|\(attempt)") {
            guard record.uploadState == "stored", MediaThumbnailCache.isImage(record) else { return }
            if let cached = MediaThumbnailCache.shared.image(for: record.id) { image = cached; return }
            let loaded = await MediaThumbnailCache.shared.load(record, api: api, pixelSize: 240 * scale)
            withAnimation(.easeOut(duration: 0.15)) { image = loaded }
            failed = loaded == nil && !Task.isCancelled
        }
    }
}
