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

@MainActor
final class MediaThumbnailIsolationTests: XCTestCase {
    private func picture(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    func testSameMediaIDDoesNotReuseAnotherActorOrWorkspaceImage() async {
        let cache = MediaThumbnailCache()
        let generation = UUID()
        let epoch = UUID()
        let authority = UUID()
        let first = MediaThumbnailScope(actorID: "actor-a", organizationID: "org-a", generation: generation, authorityRevision: authority, authorizationEpoch: epoch)
        let otherActor = MediaThumbnailScope(actorID: "actor-b", organizationID: "org-a", generation: generation, authorityRevision: authority, authorizationEpoch: epoch)
        let otherOrganization = MediaThumbnailScope(actorID: "actor-a", organizationID: "org-b", generation: generation, authorityRevision: authority, authorizationEpoch: epoch)
        let red = picture(.red)
        let blue = picture(.blue)
        let green = picture(.green)
        let loadedFirst = await cache.load(id: "same-media", scope: first, isCurrent: { true }) { red }
        let loadedActor = await cache.load(id: "same-media", scope: otherActor, isCurrent: { true }) { blue }
        let loadedOrganization = await cache.load(id: "same-media", scope: otherOrganization, isCurrent: { true }) { green }
        XCTAssertTrue(loadedFirst === red)
        XCTAssertTrue(loadedActor === blue)
        XCTAssertTrue(loadedOrganization === green)
    }

    func testSameSessionRegrantRequiresFreshImageAuthorization() async {
        let cache = MediaThumbnailCache()
        let generation = UUID(), epoch = UUID()
        let old = MediaThumbnailScope(actorID: "actor", organizationID: "org", generation: generation,
                                      authorityRevision: UUID(), authorizationEpoch: epoch)
        let regranted = MediaThumbnailScope(actorID: "actor", organizationID: "org", generation: generation,
                                            authorityRevision: UUID(), authorizationEpoch: epoch)
        let oldImage = picture(.red), newImage = picture(.blue)
        _ = await cache.load(id: "media", scope: old, isCurrent: { true }) { oldImage }
        let shown = await cache.load(id: "media", scope: regranted, isCurrent: { true }) { newImage }
        XCTAssertTrue(shown === newImage, "An earlier grant must not serve a new grant from cache")
    }

    func testRetiredSessionCannotPublishOrCacheAnInFlightImage() async {
        let cache = MediaThumbnailCache()
        let old = MediaThumbnailScope(actorID: "actor", organizationID: "org", generation: UUID(), authorityRevision: UUID())
        let replacement = MediaThumbnailScope(actorID: "actor", organizationID: "org", generation: UUID(), authorityRevision: UUID())
        let image = picture(.red)
        var active = true
        let stale = await cache.load(id: "media", scope: old, isCurrent: { active }) {
            active = false
            return image
        }
        XCTAssertNil(stale)
        XCTAssertNil(cache.image(id: "media", scope: old))
        let replacementImage = picture(.blue)
        let current = await cache.load(id: "media", scope: replacement, isCurrent: { true }) { replacementImage }
        XCTAssertTrue(current === replacementImage)
    }
}
