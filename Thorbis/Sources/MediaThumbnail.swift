import ImageIO
import SwiftUI
import UIKit

/// An image cache entry belongs to one actor, workspace and verified session.
/// `authorizationEpoch` is unique to a thumbnail view so a new presentation must
/// fetch through the job-authorized media download instead of reusing old bytes.
struct MediaThumbnailScope: Hashable {
    let actorID: String
    let organizationID: String
    let generation: UUID
    let authorityRevision: UUID
    var policyVersion: Int = 0
    var jobID: String = ""
    var authorizationEpoch: UUID = UUID()

    fileprivate func key(for id: String) -> NSString {
        [actorID, organizationID, generation.uuidString, authorityRevision.uuidString, String(policyVersion), jobID,
         authorizationEpoch.uuidString, id].map { "\($0.utf8.count):\($0)" }.joined() as NSString
    }
}

/// Downloads through the signed, job-authorized media route and keeps a bounded
/// memory-only thumbnail for the lifetime of this particular view presentation.
@MainActor
final class MediaThumbnailCache {
    static let shared = MediaThumbnailCache()
    private let images = NSCache<NSString, UIImage>()

    init() { images.countLimit = 120 }

    func image(id: String, scope: MediaThumbnailScope) -> UIImage? {
        images.object(forKey: scope.key(for: id))
    }

    func load(id: String, scope: MediaThumbnailScope, isCurrent: () -> Bool,
              operation: () async -> UIImage?) async -> UIImage? {
        guard isCurrent(), !Task.isCancelled else { return nil }
        if let cached = image(id: id, scope: scope) { return cached }
        let image = await operation()
        guard isCurrent(), !Task.isCancelled, let image else { return nil }
        images.setObject(image, forKey: scope.key(for: id))
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
    @EnvironmentObject private var session: SessionController
    @Environment(\.displayScale) private var scale
    @State private var authorizationEpoch = UUID()
    @State private var loadedScope: MediaThumbnailScope?
    @State private var loadedID: String?
    @State private var image: UIImage?
    @State private var failed = false

    private var scope: MediaThumbnailScope? {
        guard session.can("job.view", feature: "jobs"),
              let actor = session.user?.id,
              let organization = session.activeOrganization?.id,
              organization == record.organizationId,
              let policy = session.policyVersion else { return nil }
        return MediaThumbnailScope(actorID: actor, organizationID: organization, generation: session.generation,
                                   authorityRevision: session.authorityRevision, policyVersion: policy, jobID: record.jobId, authorizationEpoch: authorizationEpoch)
    }

    var body: some View {
        let currentScope = scope
        ZStack {
            Theme.fill
            if let image, let currentScope, loadedScope == currentScope, loadedID == record.id {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            } else {
                Image(systemName: failed && loadedScope == currentScope ? "exclamationmark.triangle" : "photo")
                    .font(.system(size: 22, weight: .light)).foregroundStyle(Theme.muted)
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: ThumbnailRequest(mediaID: record.id, scope: currentScope, uploadState: record.uploadState, attempt: attempt)) {
            image = nil
            failed = false
            loadedScope = nil
            loadedID = nil
            guard let currentScope, record.uploadState == "stored", MediaThumbnailCache.isImage(record) else { return }
            #if DEBUG
            if PaperPreview.enabled {
                // Screenshot fixtures: a labelled solid tile, never a network read.
                loadedScope = currentScope
                loadedID = record.id
                image = MediaSample.image(caption: record.caption ?? record.originalFilename, tags: record.tags)
                return
            }
            #endif
            let pixelSize = 240 * scale
            let loaded = await MediaThumbnailCache.shared.load(id: record.id, scope: currentScope, isCurrent: {
                scope == currentScope
            }) {
                guard let file = try? await MediaTransfer(api: api).download(mediaID: record.id, filename: record.originalFilename)
                else { return nil }
                defer { try? FileManager.default.removeItem(at: file) }
                return await Task.detached(priority: .utility) {
                    MediaThumbnailCache.downsample(file, to: pixelSize)
                }.value
            }
            guard !Task.isCancelled, scope == currentScope else { return }
            loadedScope = currentScope
            loadedID = record.id
            withAnimation(.easeOut(duration: 0.15)) { image = loaded }
            failed = loaded == nil
        }
    }
}

private struct ThumbnailRequest: Hashable {
    let mediaID: String
    let scope: MediaThumbnailScope?
    let uploadState: String
    let attempt: Int
}
