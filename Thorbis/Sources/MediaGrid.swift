import SwiftUI
import UIKit

// The job's Photos screen pieces (Paper 21A): thumbnails two across (more when the column is
// wide), the stage on a dark pill bottom-left, and an upload state that comes straight from
// PendingMediaStore: Waiting, Sending or Failed.

/// What the Photos chips show. "Untagged" is the warning chip at the end of the row.
enum MediaFilter: String, CaseIterable, Hashable {
    case all = "All", before = "Before", after = "After", documents = "Documents", untagged = "Untagged"

    /// The choices offered in the one menu shown at accessibility text sizes.
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

/// How many columns the grid uses for a content width: 2 on a phone (Paper 21A: 175 by 132
/// tiles, 8 apart), more on iPad.
enum MediaGridMetrics {
    static let spacing: CGFloat = 8
    /// Paper 21A: a thumbnail's corner.
    static let tileRadius: CGFloat = 16
    /// Paper's tile is 175 wide and 132 tall.
    static let aspect: CGFloat = 175.0 / 132.0
    /// The pills over a photo keep one tone in light and dark: they sit on the picture, not the page.
    static let scrim = Color.black.opacity(0.72)
    static let afterPill = Color(hex: 0x0E9A3F).opacity(0.92)
    static func columns(width: CGFloat, accessibility: Bool) -> Int {
        if accessibility || width < 600 { return 2 }
        return max(3, Int(width / 190))
    }
}

/// One tile in the grid. The image fills it; the stage sits bottom-left (After on green with a
/// tick), the upload state top-right, and while choosing photos a 24pt circle top-right.
struct MediaTile<Thumb: View>: View {
    let stage: String?
    let state: MediaUploadState
    var selecting = false
    var selected = false
    @ViewBuilder var image: Thumb
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MediaGridMetrics.tileRadius, style: .continuous)
        Color.clear
            .aspectRatio(typeSize.isAccessibilitySize ? 1 : MediaGridMetrics.aspect, contentMode: .fit)
            .overlay { image }
            .clipShape(shape)
            // A filled thumbnail overflows its tile; taps must stay on this tile.
            .contentShape(shape)
            .overlay {
                // Paper: no rim until the photo is chosen, then 2pt of brand.
                shape.strokeBorder(selected ? Theme.brand : Color.clear, lineWidth: 2)
            }
            .overlay(alignment: .bottomLeading) {
                if let stage {
                    HStack(spacing: 4) {
                        if stage == "After" {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                .accessibilityHidden(true)
                        }
                        Text(stage).font(Theme.font(13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(minHeight: 24)
                    .background(stage == "After" ? MediaGridMetrics.afterPill : MediaGridMetrics.scrim, in: Capsule())
                    .padding(8)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let word = state.word {
                    HStack(spacing: 5) {
                        if state == .sending {
                            ProgressView().controlSize(.mini).tint(.white)
                        } else if let tint = state.tint {
                            Circle().fill(tint).frame(width: 7, height: 7)
                        }
                        Text(word).font(Theme.font(13, weight: .semibold)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 9).frame(minHeight: 24)
                    .background(MediaGridMetrics.scrim, in: Capsule())
                    .padding(8)
                } else if selecting {
                    ZStack {
                        Circle().fill(selected ? Theme.brand : Color.black.opacity(0.25))
                        if selected {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        } else {
                            Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .padding(8)
                    .accessibilityHidden(true)
                }
            }
            .contentShape(shape)
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

/// A row for the Documents list (Paper 21A): a 44pt file tile, the title over one supporting
/// line, then the upload state as a word, or the download glyph on a stored file.
struct MediaDocumentRow: View {
    let title: String
    let detail: String
    let state: MediaUploadState
    var symbol = "doc"
    /// A stored file opens when tapped; the glyph says so.
    var showsDownload = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let large = typeSize.isAccessibilitySize
        HStack(alignment: .center, spacing: 12) {
            if !large {
                Image(systemName: symbol).font(.system(size: 17, weight: .regular)).foregroundStyle(Theme.subtle)
                    .frame(width: 44, height: 44)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    .lineLimit(large ? nil : 1)
                Text(detail).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .lineLimit(large ? nil : 2)
                if large, let word = state.word { StatusWord(text: word, tint: state.tint).padding(.top, 4) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !large, let word = state.word {
                StatusWord(text: word, tint: state.tint)
            } else if showsDownload && state == .stored {
                Image(systemName: "arrow.down.to.line").font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Theme.subtle)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A quiet 56pt word pill (field fill) for the selection bar and the quick tag step.
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
                Text(title).font(Theme.font(16, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: height)
            // Paper v2: a secondary action is a pill on the field fill, 16 Semibold.
            .background(selected ? Theme.brandSurface : Theme.fill, in: Capsule())
            .overlay {
                Capsule().strokeBorder(selected ? Theme.brand : Color.clear, lineWidth: 2)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
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

/// Text handed to the share sheet (a job's summary from its ••• menu).
struct SharedText: Identifiable {
    let id = UUID()
    let text: String
    init(_ text: String) { self.text = text }
}

struct TextShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
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
