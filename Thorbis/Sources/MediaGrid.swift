import SwiftUI
import UIKit

// The job's Photos screen pieces (2026-10-31 media redesign): square thumbnails three across
// (four when the column is wide), a small stage word on each, and an upload state that comes
// straight from PendingMediaStore: Waiting, Sending or Failed.

/// What the Photos selector shows. "Untagged" lives in the filter circle, not the selector.
enum MediaFilter: String, CaseIterable, Hashable {
    case all = "All", before = "Before", after = "After", documents = "Documents", untagged = "Untagged"

    /// The selector's four choices; Untagged reads as All there, with the filter circle lit.
    static let selector: [MediaFilter] = [.all, .before, .after, .documents]
}

/// An item's upload state as one word, for a tile or a document row.
enum MediaUploadState: Equatable {
    case stored
    /// Saved on this phone, not being sent right now (offline counts as waiting, not failed).
    case waiting
    case sending
    case failed(String)
    /// A server record that is registered but not confirmed yet.
    case server(String)

    var word: String? {
        switch self {
        case .stored: nil
        case .waiting: "Waiting"
        case .sending: "Sending"
        case .failed: "Failed"
        case .server(let state): state.statusLabel
        }
    }

    var tint: Color? {
        switch self {
        case .stored: nil
        case .waiting, .server: Theme.warning
        case .sending: Theme.brand
        case .failed: Theme.destructive
        }
    }

    @MainActor static func of(_ media: PendingMedia, in store: PendingMediaStore) -> MediaUploadState {
        if store.uploadingID == media.id { return .sending }
        if store.waitingForConnection.contains(media.id) { return .waiting }
        if let error = store.errors[media.id] { return .failed(error) }
        return .waiting
    }

    static func of(_ record: MediaAssetRecord) -> MediaUploadState {
        record.uploadState == "stored" ? .stored : .server(record.uploadState)
    }
}

/// The stage word a photo is filed under, if any.
func mediaStageWord(_ tags: [String]) -> String? { ["Before", "After"].first(where: tags.contains) }

/// How many columns the grid uses for a content width: 3 on a phone, 4 from about 380pt
/// (Pro Max / Plus), more on iPad, 2 at accessibility text sizes.
enum MediaGridMetrics {
    static let spacing: CGFloat = 6
    static func columns(width: CGFloat, accessibility: Bool) -> Int {
        if accessibility { return 2 }
        if width >= 600 { return max(5, Int(width / 140)) }
        return width >= 380 ? 4 : 3
    }
}

/// One square in the grid. The image fills the square; the stage word sits bottom-left and the
/// upload state top-right, both on a small ground pill so they read over any photo.
struct MediaTile<Thumb: View>: View {
    let stage: String?
    let state: MediaUploadState
    var selecting = false
    var selected = false
    @ViewBuilder var image: Thumb

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { image }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Theme.brand : Theme.border.opacity(0.5), lineWidth: selected ? 3 : 1)
            }
            .overlay(alignment: .bottomLeading) {
                if let stage {
                    Text(stage).font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 7).frame(minHeight: 22)
                        .background(Theme.background.opacity(0.92), in: Capsule())
                        .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let word = state.word {
                    HStack(spacing: 5) {
                        if state == .sending {
                            ProgressView().controlSize(.mini).tint(Theme.foreground)
                        } else if let tint = state.tint {
                            Circle().fill(tint).frame(width: 7, height: 7)
                        }
                        Text(word).font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.foreground)
                    }
                    .padding(.horizontal, 7).frame(minHeight: 22)
                    .background(Theme.background.opacity(0.92), in: Capsule())
                    .padding(5)
                }
            }
            .overlay(alignment: .topLeading) {
                if selecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .medium))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(selected ? Theme.onInk : Theme.foreground, selected ? Theme.brand : Theme.background.opacity(0.85))
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// A saved-on-this-phone photo's thumbnail, read straight from its payload file and downsampled
/// off the main thread. Documents and clips show a glyph.
struct PendingMediaThumbnail: View {
    let media: PendingMedia
    @EnvironmentObject private var pendingMedia: PendingMediaStore
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.fill
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: media.kind == "document" ? "doc" : media.kind == "video" ? "video" : "photo")
                    .font(.system(size: 22, weight: .light)).foregroundStyle(Theme.muted)
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: media.id) {
            guard media.kind == "photo", let url = pendingMedia.payloadURL(media) else { return }
            let pixels = 240 * scale
            let loaded = await Task.detached(priority: .utility) { MediaThumbnailCache.downsample(url, to: pixels) }.value
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) { image = loaded }
        }
    }
}

/// A row for the Documents list: title, one supporting line, status as a word on the right.
struct MediaDocumentRow: View {
    let title: String
    let detail: String
    let state: MediaUploadState
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                  : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            if let word = state.word { StatusWord(text: word, tint: state.tint) }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A quiet 56pt word button (field fill) for the selection bar and the quick tag step.
struct MediaQuietButton: View {
    let title: String
    var symbol: String? = nil
    var selected = false
    var height: CGFloat = 56
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 16, weight: .medium)) }
                Text(title).font(Theme.font(17, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(selected ? Theme.brandSurface : Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(selected ? Theme.brand : .clear, lineWidth: 2)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// UIKit's share sheet with a completion, so the caller can delete the temporary copies it shared.
struct MediaShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Files handed to the share sheet; Identifiable so one `.sheet(item:)` presents them.
struct MediaShareFiles: Identifiable {
    let id = UUID()
    let urls: [URL]
}

#if DEBUG
/// Screenshot fixtures only: a solid tile in the stage's colour, labelled SAMPLE with the caption,
/// so nobody mistakes it for a real photo. Never compiled into Release.
enum MediaSample {
    static func image(caption: String, tags: [String], size: CGSize = CGSize(width: 480, height: 480)) -> UIImage {
        let color: UIColor = tags.contains("Before") ? UIColor(red: 0.78, green: 0.62, blue: 0.46, alpha: 1)
            : tags.contains("After") ? UIColor(red: 0.46, green: 0.64, blue: 0.54, alpha: 1)
            : UIColor(red: 0.58, green: 0.6, blue: 0.66, alpha: 1)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill(); context.fill(CGRect(origin: .zero, size: size))
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            let big: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size.width * 0.09, weight: .semibold),
                                                       .foregroundColor: UIColor.white.withAlphaComponent(0.9), .paragraphStyle: paragraph]
            let small: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size.width * 0.06, weight: .medium),
                                                         .foregroundColor: UIColor.white.withAlphaComponent(0.85), .paragraphStyle: paragraph]
            ("SAMPLE" as NSString).draw(in: CGRect(x: 0, y: size.height * 0.36, width: size.width, height: size.height * 0.14), withAttributes: big)
            (caption as NSString).draw(in: CGRect(x: size.width * 0.06, y: size.height * 0.52, width: size.width * 0.88, height: size.height * 0.2), withAttributes: small)
        }
    }

    static func file(caption: String, tags: [String]) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sample-\(UUID().uuidString).jpg")
        guard let data = image(caption: caption, tags: tags, size: CGSize(width: 1200, height: 900)).jpegData(compressionQuality: 0.8),
              (try? data.write(to: url)) != nil else { return nil }
        return url
    }
}
#endif
