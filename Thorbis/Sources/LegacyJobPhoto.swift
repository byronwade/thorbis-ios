import Foundation

/// A reconciled media asset retains its job-photo fallback because its .bin
/// filename is not suitable for extension-based preview.
enum JobPhotoSource: Identifiable, Hashable {
    case modern(MediaAssetRecord, legacyFallback: JobPhotoRecord?)
    case legacy(JobPhotoRecord)

    var id: String {
        switch self {
        case .modern(let asset, _): "media:\(asset.id)"
        case .legacy(let photo): "legacy:\(photo.id)"
        }
    }
}

enum JobPhotoMerge {
    static func combine(modern: [MediaAssetRecord], legacy: [JobPhotoRecord], organizationID: String, jobID: String) -> [JobPhotoSource] {
        compile(modern: modern, legacy: legacy, organizationID: organizationID, jobID: jobID).items
    }

    static func hasConflictingMetadata(modern: [MediaAssetRecord], legacy: [JobPhotoRecord], organizationID: String, jobID: String) -> Bool {
        compile(modern: modern, legacy: legacy, organizationID: organizationID, jobID: jobID).conflict
    }

    private static func compile(modern: [MediaAssetRecord], legacy: [JobPhotoRecord], organizationID: String, jobID: String) -> (items: [JobPhotoSource], conflict: Bool) {
        let scopedMedia = modern.filter { $0.organizationId == organizationID && $0.jobId == jobID && $0.kind == "photo" }
        let media = scopedMedia.filter { !$0.archived }
        let archived = scopedMedia.filter(\.archived)
        let archivedKeys = Set(archived.map(\.storageKey).filter { !$0.isEmpty })
        let uncertainTombstone = archived.contains { $0.storageKey.isEmpty }
        let scopedLegacy = legacy.filter { $0.organizationId == organizationID && $0.jobId == jobID }
        // Without a key an archived record cannot be safely matched against legacy photos.
        let photos = uncertainTombstone ? [] : scopedLegacy.filter { !archivedKeys.contains($0.storageKey) }
        let mediaByKey = Dictionary(grouping: media.filter { !$0.storageKey.isEmpty }, by: \.storageKey)
        let photosByKey = Dictionary(grouping: photos.filter { !$0.storageKey.isEmpty }, by: \.storageKey)
        var items: [JobPhotoSource] = []
        var handled = Set<String>()
        var conflict = (uncertainTombstone && !scopedLegacy.isEmpty)
            || media.contains { $0.storageKey.isEmpty || $0.uploadState != "stored" }
            || photos.contains { $0.storageKey.isEmpty }
        for asset in media {
            guard !asset.storageKey.isEmpty else { items.append(.modern(asset, legacyFallback: nil)); continue }
            guard handled.insert(asset.storageKey).inserted else { continue }
            let matches = mediaByKey[asset.storageKey] ?? []
            let legacyMatches = photosByKey[asset.storageKey] ?? []
            let chosen = matches.first(where: { $0.uploadState == "stored" }) ?? asset
            if matches.count > 1 || legacyMatches.count > 1 { conflict = true }
            if !legacyMatches.isEmpty && chosen.uploadState != "stored" {
                conflict = true
                items.append(.legacy(legacyMatches[0]))
                continue
            }
            var fallback: JobPhotoRecord?
            if let photo = legacyMatches.first {
                if matches.count == 1 && legacyMatches.count == 1 && chosen.mime == photo.contentType && chosen.sizeBytes == photo.byteSize {
                    fallback = photo
                } else {
                    conflict = true
                }
            }
            items.append(.modern(chosen, legacyFallback: fallback))
        }
        for photo in photos {
            if photo.storageKey.isEmpty { items.append(.legacy(photo)); continue }
            guard handled.insert(photo.storageKey).inserted else { continue }
            if (photosByKey[photo.storageKey]?.count ?? 0) > 1 { conflict = true }
            items.append(.legacy(photo))
        }
        return (items, conflict)
    }
}

import ImageIO
import UIKit

enum LegacyPhotoDecode {
    nonisolated static func thumbnail(_ data: Data, pixelSize: CGFloat) -> UIImage? {
        guard !data.isEmpty, data.count <= 15 * 1024 * 1024,
              pixelSize > 0, pixelSize.isFinite,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(pixelSize, 1024)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
