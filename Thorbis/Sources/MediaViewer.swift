import SwiftUI
import UIKit

// Photo viewer and Before/After compare (2026-10-31 media redesign).
// The viewer is a full-screen pager over the photos the grid is showing: swipe between them,
// pinch or double-tap to zoom, with the stage, caption, time and who took it underneath and the
// actions as quiet circles. Compare puts one Before beside one After for the customer.

/// Downloads one stored record's file for viewing, checked against the screen's current scope by
/// the caller. The viewer owns the returned temporary file and deletes it when it closes.
typealias MediaFileLoader = (MediaAssetRecord) async throws -> URL

struct MediaViewerStart: Identifiable, Equatable {
    let id: String
}

/// Full-resolution images for the viewer and compare, read from downloaded files and kept only
/// while the cover is open. Neighbours are fetched ahead so a swipe lands on a loaded photo.
@MainActor
final class MediaImageLoader: ObservableObject {
    @Published private(set) var images: [String: UIImage] = [:]
    @Published private(set) var failures: [String: String] = [:]
    private(set) var files: [String: URL] = [:]
    private var inFlight: Set<String> = []
    private let load: MediaFileLoader

    init(load: @escaping MediaFileLoader) { self.load = load }

    func fetch(_ record: MediaAssetRecord, pixels: CGFloat) async {
        guard images[record.id] == nil, !inFlight.contains(record.id) else { return }
        inFlight.insert(record.id)
        defer { inFlight.remove(record.id) }
        failures[record.id] = nil
        do {
            let url = try await load(record)
            files[record.id] = url
            let image = await Task.detached(priority: .userInitiated) { MediaThumbnailCache.downsample(url, to: pixels) }.value
            if let image { images[record.id] = image } else { failures[record.id] = "This photo couldn’t be opened." }
        } catch is CancellationError {
        } catch {
            failures[record.id] = error.localizedDescription
        }
    }

    func retry(_ record: MediaAssetRecord) { failures[record.id] = nil }

    /// Deletes every downloaded copy. Called when the cover closes or the screen's scope changes.
    func clear() {
        for url in files.values { try? FileManager.default.removeItem(at: url) }
        files = [:]; images = [:]; failures = [:]
    }
}

struct MediaPhotoViewer: View {
    /// The photos the grid is showing, in its order. Only stored photos open here.
    let records: [MediaAssetRecord]
    let start: String
    let canEdit: Bool
    let currentUserID: String?
    let load: MediaFileLoader
    let retag: (MediaAssetRecord, MediaStage) async -> Void
    /// Archives the photo on the server; true when it is gone from the job.
    let archive: (MediaAssetRecord) async -> Bool
    let fileMarkup: (UIImage, [String]) throws -> Void
    let onClose: () -> Void

    @StateObject private var loader: MediaImageLoader
    @Environment(\.displayScale) private var scale
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var current: String
    @State private var confirmArchive: MediaAssetRecord?
    @State private var share: MediaShareFiles?
    @State private var markup: MediaMarkupTarget?
    @State private var working = false

    init(records: [MediaAssetRecord], start: String, canEdit: Bool, currentUserID: String?, load: @escaping MediaFileLoader,
         retag: @escaping (MediaAssetRecord, MediaStage) async -> Void, archive: @escaping (MediaAssetRecord) async -> Bool,
         fileMarkup: @escaping (UIImage, [String]) throws -> Void, onClose: @escaping () -> Void) {
        self.records = records; self.start = start; self.canEdit = canEdit; self.currentUserID = currentUserID
        self.load = load; self.retag = retag; self.archive = archive; self.fileMarkup = fileMarkup; self.onClose = onClose
        _loader = StateObject(wrappedValue: MediaImageLoader(load: load))
        _current = State(initialValue: start)
    }

    private var index: Int? { records.firstIndex { $0.id == current } }
    private var record: MediaAssetRecord? { index.map { records[$0] } }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $current) {
                ForEach(records) { record in
                    page(record).tag(record.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black)
            if let record { info(record) }
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .environment(\.colorScheme, .dark)
        .task(id: current) { await prefetch() }
        .onChange(of: records) { _, list in
            // An archived photo leaves the list: land on its neighbour, or close when none is left.
            if list.isEmpty { onClose() } else if !list.contains(where: { $0.id == current }) { current = list[0].id }
        }
        .onDisappear { loader.clear() }
        .thorbisConfirm(item: $confirmArchive, title: { _ in "Remove this photo from the job?" },
                        message: { _ in "It’s archived, not erased: the office can still restore it." },
                        actions: { record in [ThorbisConfirmAction("Remove photo", role: .destructive) {
                            Task { working = true; _ = await archive(record); working = false }
                        }] })
        .sheet(item: $share) { files in MediaShareSheet(urls: files.urls) { share = nil } }
        .fullScreenCover(item: $markup) { target in
            PhotoMarkupView(image: target.image, onSave: { flattened in
                try fileMarkup(flattened, target.tags)
                markup = nil
            }, onCancel: { markup = nil })
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button("Done", action: onClose)
                .buttonStyle(ThorbisBarButtonStyle())
                .accessibilityIdentifier("media-viewer-done")
            Spacer(minLength: 0)
            if let index {
                Text("\(index + 1) of \(records.count)").font(Theme.monoFont(15, weight: .medium)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Color.clear.frame(width: 64, height: 44)
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 6)
    }

    @ViewBuilder private func page(_ record: MediaAssetRecord) -> some View {
        if let image = loader.images[record.id] {
            ZoomableMediaImage(image: image)
                .accessibilityLabel(record.caption ?? "Photo")
        } else if let failure = loader.failures[record.id] {
            VStack(spacing: 12) {
                Text(failure).font(Theme.font(15)).foregroundStyle(.white).multilineTextAlignment(.center)
                Button("Try again") { loader.retry(record); Task { await prefetch() } }
                    .buttonStyle(ThorbisBarButtonStyle())
            }
            .padding(Theme.gutter)
        } else {
            ProgressView().tint(.white)
        }
    }

    private func info(_ record: MediaAssetRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    StatusWord(text: mediaStageWord(record.tags) ?? "No stage")
                    Spacer(minLength: 0)
                }
                Text(record.caption ?? record.originalFilename)
                    .font(Theme.font(17, weight: .medium))
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                Text(detail(record)).font(Theme.font(14)).foregroundStyle(Theme.muted)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 0) {
                if canEdit {
                    action("Markup", symbol: "pencil.tip.crop.circle") {
                        guard let image = loader.images[record.id] else { return }
                        markup = MediaMarkupTarget(image: image, tags: record.tags.filter { $0 == "Before" || $0 == "After" })
                    }
                    .disabled(loader.images[record.id] == nil)
                    VStack(spacing: 4) {
                        ThorbisMenu(items: [
                            ThorbisMenuItem("Before", isSelected: record.tags.contains("Before")) { Task { await retag(record, .before) } },
                            ThorbisMenuItem("After", isSelected: record.tags.contains("After")) { Task { await retag(record, .after) } },
                            ThorbisMenuItem("No stage", isSelected: mediaStageWord(record.tags) == nil) { Task { await retag(record, .other) } },
                        ], title: "Photo stage", accessibilityLabel: "Change stage, currently \(mediaStageWord(record.tags) ?? "none")") {
                            PaperCircleLabel(symbol: "tag", size: 52)
                        }
                        Text("Stage").font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
                action("Share", symbol: "square.and.arrow.up") {
                    if let url = loader.files[record.id] { share = MediaShareFiles(urls: [url]) }
                }
                .disabled(loader.files[record.id] == nil)
                if canEdit {
                    action("Remove", symbol: "trash") { confirmArchive = record }
                        .accessibilityIdentifier("media-viewer-remove")
                }
            }
            .disabled(working)
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 14).padding(.bottom, 8)
    }

    private func action(_ title: String, symbol: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 4) {
                PaperCircleLabel(symbol: symbol, size: 52)
                Text(title).font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
    }

    private func detail(_ record: MediaAssetRecord) -> String {
        // Capture time only; the upload time is not when the photo was taken.
        let when = record.capturedAt.flatMap { JobFiltering.isoFractional.date(from: $0) ?? JobFiltering.isoPlain.date(from: $0) }
            .map { "Taken \($0.visitLabel())" } ?? "Time not recorded"
        let who = currentUserID == record.uploaderUserId ? "by you" : "by a teammate"
        return "\(when) · \(who)"
    }

    private func prefetch() async {
        guard let index else { return }
        let pixels = 2400 * min(scale, 2) / 2
        for offset in [0, 1, -1] where records.indices.contains(index + offset) {
            await loader.fetch(records[index + offset], pixels: max(pixels, 1600))
        }
    }
}

struct MediaMarkupTarget: Identifiable {
    let id = UUID()
    let image: UIImage
    let tags: [String]
}

/// A photo that pinches and double-taps to zoom and pans once zoomed. Paging stays with the pager
/// until the photo is zoomed in. VoiceOver can zoom with the standard zoom action.
struct ZoomableMediaImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        Image(uiImage: image).resizable().scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(MagnifyGesture()
                .onChanged { value in scale = min(5, max(1, baseScale * value.magnification)) }
                .onEnded { _ in baseScale = scale; if scale <= 1.01 { reset() } })
            .gesture(DragGesture()
                .onChanged { value in
                    offset = CGSize(width: baseOffset.width + value.translation.width, height: baseOffset.height + value.translation.height)
                }
                .onEnded { _ in baseOffset = offset }, including: scale > 1 ? .all : .subviews)
            .onTapGesture(count: 2) {
                withMotion(.easeOut(duration: 0.2)) {
                    if scale > 1 { reset() } else { scale = 2.5; baseScale = 2.5 }
                }
            }
            .accessibilityZoomAction { action in
                withMotion(.easeOut(duration: 0.2)) {
                    scale = action.direction == .zoomIn ? min(5, scale + 1) : max(1, scale - 1)
                    baseScale = scale
                    if scale == 1 { reset() }
                }
            }
            .clipped()
    }

    private func reset() {
        scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero
    }
}

// MARK: - Before / After compare

/// One Before beside one After, for showing the customer. Slider or side by side (so nothing is
/// gesture-only); customer-sized words and targets; no captions or staff details.
struct MediaCompareView: View {
    let befores: [MediaAssetRecord]
    let afters: [MediaAssetRecord]
    let load: MediaFileLoader
    let onClose: () -> Void

    @StateObject private var loader: MediaImageLoader
    @State private var beforeID: String
    @State private var afterID: String
    @State private var mode = "slider"
    @State private var split: CGFloat = 0.5
    @Environment(\.dynamicTypeSize) private var typeSize

    init(befores: [MediaAssetRecord], afters: [MediaAssetRecord], load: @escaping MediaFileLoader, onClose: @escaping () -> Void) {
        self.befores = befores; self.afters = afters; self.load = load; self.onClose = onClose
        _loader = StateObject(wrappedValue: MediaImageLoader(load: load))
        _beforeID = State(initialValue: befores.first?.id ?? "")
        _afterID = State(initialValue: afters.first?.id ?? "")
    }

    private var before: MediaAssetRecord? { befores.first { $0.id == beforeID } }
    private var after: MediaAssetRecord? { afters.first { $0.id == afterID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Before and after").font(Theme.font(24, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button("Done", action: onClose)
                    .buttonStyle(ThorbisBarButtonStyle(customerFacing: true))
                    .accessibilityIdentifier("media-compare-done")
            }
            ThorbisSegmented(options: [("slider", "Slider"), ("side", "Side by side")], selection: $mode)
            GeometryReader { proxy in
                Group {
                    if mode == "slider" { slider(size: proxy.size) } else { sideBySide(size: proxy.size) }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            if befores.count > 1 { chooser("Before", records: befores, selection: $beforeID) }
            if afters.count > 1 { chooser("After", records: afters, selection: $afterID) }
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 12)
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .task(id: "\(beforeID)|\(afterID)") {
            if let before { await loader.fetch(before, pixels: 2000) }
            if let after { await loader.fetch(after, pixels: 2000) }
        }
        .onDisappear { loader.clear() }
    }

    @ViewBuilder private func photo(_ record: MediaAssetRecord?) -> some View {
        ZStack {
            Theme.fill
            if let record, let image = loader.images[record.id] {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let record, let failure = loader.failures[record.id] {
                Text(failure).font(Theme.font(17)).multilineTextAlignment(.center).padding()
            } else {
                ProgressView()
            }
        }
        .clipped()
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Theme.font(17, weight: .medium)).foregroundStyle(Theme.foreground)
            .padding(.horizontal, 12).frame(minHeight: 34)
            .background(Theme.background.opacity(0.92), in: Capsule())
            .padding(10)
    }

    private func slider(size: CGSize) -> some View {
        let x = size.width * split
        return ZStack(alignment: .leading) {
            photo(after).frame(width: size.width, height: size.height)
            photo(before).frame(width: size.width, height: size.height)
                .mask(alignment: .leading) { Rectangle().frame(width: max(0, x)) }
            Rectangle().fill(.white).frame(width: 3).offset(x: x - 1.5).shadow(radius: 2)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 18, weight: .medium)).foregroundStyle(.black)
                .frame(width: 56, height: 56).background(.white, in: Circle()).shadow(radius: 3)
                .offset(x: x - 28)
        }
        .overlay(alignment: .topLeading) { label("Before") }
        .overlay(alignment: .topTrailing) { label("After") }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            split = min(1, max(0, value.location.x / max(size.width, 1)))
        })
        .accessibilityElement()
        .accessibilityLabel("Before and after slider")
        .accessibilityValue("\(Int((split * 100).rounded())) percent before")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: split = min(1, split + 0.1)
            case .decrement: split = max(0, split - 0.1)
            @unknown default: break
            }
        }
    }

    @ViewBuilder private func sideBySide(size: CGSize) -> some View {
        let layout = size.width > size.height ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 6))
        layout {
            photo(before).overlay(alignment: .topLeading) { label("Before") }
            photo(after).overlay(alignment: .topLeading) { label("After") }
        }
    }

    private func chooser(_ title: String, records: [MediaAssetRecord], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Choose \(title.lowercased())").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(records) { record in
                        Button { selection.wrappedValue = record.id } label: {
                            MediaThumbnail(record: record)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(selection.wrappedValue == record.id ? Theme.brand : Theme.border, lineWidth: selection.wrappedValue == record.id ? 3 : 1))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("\(title) photo \((records.firstIndex(of: record) ?? 0) + 1)")
                        .accessibilityAddTraits(selection.wrappedValue == record.id ? .isSelected : [])
                    }
                }
            }
        }
    }
}
