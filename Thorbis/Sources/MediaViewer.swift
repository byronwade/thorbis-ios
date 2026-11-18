import SwiftUI
import UIKit

// Photo viewer and Before/After compare (2026-10-31 media redesign).
// The viewer (Paper 21S) is a full-screen pager on black over the photos the grid is showing:
// swipe between them, pinch or double-tap to zoom. A close circle, "2 of 6" and the stage menu
// sit above; the stage pill rides the photo; the caption, who and when, page dots and three
// tiles (Markup, Share, Delete) sit below. Compare puts one Before beside one After for the customer.

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
    /// Saves a new caption on the server; true when it was kept.
    let recaption: (MediaAssetRecord, String) async -> Bool
    let fileMarkup: (UIImage, [String]) throws -> Void
    let onClose: () -> Void

    @StateObject private var loader: MediaImageLoader
    @Environment(\.displayScale) private var scale
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var current: String
    @State private var confirmArchive: MediaAssetRecord?
    @State private var share: MediaShareFiles?
    @State private var markup: MediaMarkupTarget?
    @State private var captioning: MediaAssetRecord?
    @State private var working = false

    init(records: [MediaAssetRecord], start: String, canEdit: Bool, currentUserID: String?, load: @escaping MediaFileLoader,
         retag: @escaping (MediaAssetRecord, MediaStage) async -> Void, archive: @escaping (MediaAssetRecord) async -> Bool,
         recaption: @escaping (MediaAssetRecord, String) async -> Bool,
         fileMarkup: @escaping (UIImage, [String]) throws -> Void, onClose: @escaping () -> Void) {
        self.records = records; self.start = start; self.canEdit = canEdit; self.currentUserID = currentUserID
        self.load = load; self.retag = retag; self.archive = archive; self.recaption = recaption
        self.fileMarkup = fileMarkup; self.onClose = onClose
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
        .background(Color.black.ignoresSafeArea())
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
        .sheet(item: $captioning) { editing in SheetSurface {
            MediaCaptionSheet(caption: editing.caption ?? "", save: { text in await recaption(editing, text) }, onClose: { captioning = nil })
        } }
        .fullScreenCover(item: $markup) { target in
            PhotoMarkupView(image: target.image, stage: mediaStageWord(target.tags), onSave: { flattened in
                try fileMarkup(flattened, target.tags)
                markup = nil
            }, onCancel: { markup = nil })
        }
    }

    /// Paper 21S: the close circle, "2 of 6" over the day it was taken, and the stage menu.
    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) { MediaViewerCircle(symbol: "xmark") }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Done")
                .accessibilityIdentifier("media-viewer-done")
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                if let index {
                    // Paper 21S: 17 Semibold, proportional digits.
                    Text("\(index + 1) of \(records.count)")
                        .font(Theme.font(17, weight: .semibold)).foregroundStyle(.white)
                }
                if let record {
                    // Paper 21S: "JOB-2214 · Today"; the job alone when the capture time wasn't recorded.
                    let number = "JOB-\(record.jobId.suffix(4).uppercased())"
                    Text(dayWord(record).map { "\(number) \u{00B7} \($0)" } ?? number)
                        .font(Theme.font(13)).foregroundStyle(.white.opacity(0.65))
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if canEdit, let record {
                ThorbisMenu(items: [
                    ThorbisMenuItem("Before", isSelected: record.tags.contains("Before")) { Task { await retag(record, .before) } },
                    ThorbisMenuItem("After", isSelected: record.tags.contains("After")) { Task { await retag(record, .after) } },
                    ThorbisMenuItem("No stage", isSelected: mediaStageWord(record.tags) == nil) { Task { await retag(record, .other) } },
                ], title: "Photo stage", accessibilityLabel: "Change stage, currently \(mediaStageWord(record.tags) ?? "none")") {
                    MediaViewerCircle(symbol: "ellipsis")
                }
                .disabled(working)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 6)
    }

    /// "Today", or "Jul 20" for an earlier day; nil when the capture time was not recorded.
    private func dayWord(_ record: MediaAssetRecord) -> String? {
        guard let taken = record.capturedAt.flatMap({ JobFiltering.isoFractional.date(from: $0) ?? JobFiltering.isoPlain.date(from: $0) }) else { return nil }
        if Calendar.current.isDateInToday(taken) { return "Today" }
        return taken.formatted(.dateTime.month(.abbreviated).day())
    }

    @ViewBuilder private func page(_ record: MediaAssetRecord) -> some View {
        if let image = loader.images[record.id] {
            ZoomableMediaImage(image: image)
                .accessibilityLabel(record.caption ?? "Photo")
                .overlay(alignment: .topLeading) {
                    // Paper 21S: the stage on a dark pill at the photo's top-left.
                    if let stage = mediaStageWord(record.tags) {
                        Text(stage).font(Theme.font(14, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 12).frame(minHeight: 30)
                            .background(Color.black.opacity(0.7), in: Capsule())
                            .padding(16)
                            .accessibilityHidden(true)
                    }
                }
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
            VStack(alignment: .leading, spacing: 0) {
                Text(record.caption ?? record.originalFilename)
                    .font(Theme.font(17, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .accessibilityAddTraits(.isHeader)
                Text(detail(record)).font(Theme.font(14)).foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                if canEdit {
                    // Paper prints "Add caption" at the end of the line; here it keeps a 44pt target.
                    Button(record.caption == nil ? "Add caption" : "Edit caption") { captioning = record }
                        .font(Theme.font(14, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("media-viewer-caption")
                }
            }
            .padding(.horizontal, 4)
            if let index, records.count > 1, records.count <= 12 {
                HStack(spacing: 6) {
                    ForEach(0..<records.count, id: \.self) { position in
                        Capsule().fill(Color.white.opacity(position == index ? 1 : 0.35))
                            .frame(width: position == index ? 18 : 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            }
            HStack(spacing: 8) {
                if canEdit {
                    tile("Markup", symbol: "pencil") {
                        guard let image = loader.images[record.id] else { return }
                        markup = MediaMarkupTarget(image: image, tags: record.tags.filter { $0 == "Before" || $0 == "After" })
                    }
                    .disabled(loader.images[record.id] == nil)
                }
                tile("Share", symbol: "square.and.arrow.up") {
                    if let url = loader.files[record.id] { share = MediaShareFiles(urls: [url]) }
                }
                .disabled(loader.files[record.id] == nil)
                if canEdit {
                    tile("Delete", symbol: "trash", danger: true) { confirmArchive = record }
                        .accessibilityIdentifier("media-viewer-remove")
                }
            }
            .disabled(working)
        }
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 8)
    }

    /// Paper 21S: an action tile on white 10%, radius 18: the glyph over a 14 Medium word.
    private func tile(_ title: String, symbol: String, danger: Bool = false, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 19, weight: .medium)).frame(height: 22)
                    .accessibilityHidden(true)
                Text(title).font(Theme.font(14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(danger ? Theme.destructive : Color.white)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
    }

    private func detail(_ record: MediaAssetRecord) -> String {
        // Capture time only; the upload time is not when the photo was taken.
        let when = record.capturedAt.flatMap { JobFiltering.isoFractional.date(from: $0) ?? JobFiltering.isoPlain.date(from: $0) }
            .map { $0.visitLabel() } ?? "Time not recorded"
        // Paper: who, then when ("Ramon M. · Today 9:24 AM"). The record names no one, only whose it is.
        let who = currentUserID == record.uploaderUserId ? "You" : "A teammate"
        return "\(who) · \(when)"
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

/// The viewer's 44pt circle on black: a white glyph on white 14% (Paper 21S).
private struct MediaViewerCircle: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Color.white.opacity(0.14), in: Circle())
            .contentShape(Circle())
    }
}

/// "Add caption" from the viewer: a few words about the photo, saved on the photo's record.
private struct MediaCaptionSheet: View {
    let save: (String) async -> Bool
    let onClose: () -> Void
    private let editing: Bool
    @State private var text: String
    @State private var busy = false
    @State private var problem: String?
    @FocusState private var focused: Bool

    init(caption: String, save: @escaping (String) async -> Bool, onClose: @escaping () -> Void) {
        self.save = save
        self.onClose = onClose
        self.editing = !caption.isEmpty
        _text = State(initialValue: caption)
    }

    var body: some View {
        ThorbisModalSheet(title: editing ? "Edit caption" : "Add caption", closeLabel: "Cancel",
                          onClose: busy ? nil : onClose, detents: [.medium], commitTitle: "Save caption", busy: busy,
                          commitIdentifier: "media-caption-save", commit: { commit() }) {
            ThorbisSheetField(label: "Caption", error: problem) {
                TextField("Caption", text: $text, prompt: .placeholder("What this photo shows"), axis: .vertical)
                    .font(Theme.font(16)).lineLimit(1...4)
                    .fieldWell()
                    .focused($focused)
                    .onChange(of: text) { _, _ in problem = nil }
                    .accessibilityLabel("Caption")
                    .accessibilityIdentifier("media-caption-field")
            }
        }
        .interactiveDismissDisabled(busy)
        .onAppear { focused = true }
    }

    private func commit() {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280))
        guard !trimmed.isEmpty else {
            problem = "Type a few words about the photo."
            return
        }
        busy = true
        Task {
            let kept = await save(trimmed)
            busy = false
            if kept { onClose() } else { problem = "The caption wasn\u{2019}t saved. Check your connection and try again." }
        }
    }
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
    @State private var split: CGFloat = 0.5
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    /// The side-by-side picture handed to the share sheet (Paper 21P "Share with customer").
    @State private var shared: MediaShareFiles?
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Paper 21P is the slider alone. A handle can't be dragged with VoiceOver, so there the two
    /// photos sit side by side instead.
    private var mode: String { voiceOver ? "side" : "slider" }

    init(befores: [MediaAssetRecord], afters: [MediaAssetRecord], load: @escaping MediaFileLoader, onClose: @escaping () -> Void) {
        self.befores = befores; self.afters = afters; self.load = load; self.onClose = onClose
        _loader = StateObject(wrappedValue: MediaImageLoader(load: load))
        _beforeID = State(initialValue: befores.first?.id ?? "")
        _afterID = State(initialValue: afters.first?.id ?? "")
    }

    private var before: MediaAssetRecord? { befores.first { $0.id == beforeID } }
    private var after: MediaAssetRecord? { afters.first { $0.id == afterID } }

    var body: some View {
        // Paper 21P: a 44pt card circle to leave, the 34 Bold title, the photos on a radius-20
        // frame, then the pickers and a quiet hint.
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onClose) { CreamCircleLabel(symbol: "chevron.left") }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Done")
                .accessibilityIdentifier("media-compare-done")
                .padding(.leading, -4)
            Text("Before and after").font(Theme.font(34, weight: .bold)).tracking(-0.85)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 4).padding(.top, 2)
            GeometryReader { proxy in
                Group {
                    if mode == "slider" { slider(size: proxy.size) } else { sideBySide(size: proxy.size) }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            if befores.count > 1 { chooser("Before", records: befores, selection: $beforeID) }
            if afters.count > 1 { chooser("After", records: afters, selection: $afterID) }
            Text(mode == "slider" ? "Drag the handle to compare" : "Before on the left, after on the right")
                .font(Theme.font(14)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)
            // Paper 21P: the commit shares the pair. It is one picture, before on the left.
            // Paper: a quiet card pill, 50 tall, 16 Semibold.
            Button { shareComparison() } label: {
                Text("Share with customer").font(Theme.font(16, weight: .semibold))
                    .foregroundStyle(canShare ? Theme.foreground : Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.card, in: Capsule())
            }
            .buttonStyle(PressStyle())
            .disabled(!canShare)
            .accessibilityIdentifier("media-compare-share")
        }
        .padding(.horizontal, PaperCardMetrics.margin).padding(.vertical, 12)
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .sheet(item: $shared) { files in
            MediaShareSheet(urls: files.urls) {
                for url in files.urls { try? FileManager.default.removeItem(at: url) }
                shared = nil
            }
        }
        .task(id: "\(beforeID)|\(afterID)") {
            if let before { await loader.fetch(before, pixels: 2000) }
            if let after { await loader.fetch(after, pixels: 2000) }
        }
        .onDisappear { loader.clear() }
    }

    /// Both photos have loaded, so there is a pair to share.
    private var canShare: Bool {
        guard let before, let after else { return false }
        return loader.images[before.id] != nil && loader.images[after.id] != nil
    }

    /// Draws the pair side by side at the same height (before on the left) and opens the share sheet.
    private func shareComparison() {
        guard let before, let after,
              let left = loader.images[before.id], let right = loader.images[after.id],
              left.size.height > 0, right.size.height > 0 else { return }
        let height: CGFloat = 1200
        let gap: CGFloat = 8
        let leftWidth = (left.size.width / left.size.height * height).rounded()
        let rightWidth = (right.size.width / right.size.height * height).rounded()
        let size = CGSize(width: leftWidth + gap + rightWidth, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let picture = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            left.draw(in: CGRect(x: 0, y: 0, width: leftWidth, height: height))
            right.draw(in: CGRect(x: leftWidth + gap, y: 0, width: rightWidth, height: height))
        }
        guard let data = picture.jpegData(compressionQuality: 0.85) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("before-and-after-\(UUID().uuidString.prefix(8)).jpg")
        do {
            try data.write(to: url, options: .atomic)
            shared = MediaShareFiles(urls: [url])
        } catch {
            shared = nil
        }
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
        // Paper 21P: a 28pt pill on the canvas tone, 13 Semibold.
        Text(text).font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.foreground)
            .padding(.horizontal, 12).frame(minHeight: 28)
            .background(Theme.background, in: Capsule())
            .padding(12)
    }

    private func slider(size: CGSize) -> some View {
        let x = size.width * split
        return ZStack(alignment: .leading) {
            photo(after).frame(width: size.width, height: size.height)
            photo(before).frame(width: size.width, height: size.height)
                .mask(alignment: .leading) { Rectangle().frame(width: max(0, x)) }
            // Paper 21P: a 2pt rule and a 40pt handle in the foreground tone; 56pt to grab.
            Rectangle().fill(Theme.foreground).frame(width: 2).offset(x: x - 1)
            Image(systemName: "chevron.left.chevron.right")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.background)
                .frame(width: 40, height: 40).background(Theme.foreground, in: Circle())
                .frame(width: 56, height: 56).contentShape(Circle())
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
            Text("Choose \(title.lowercased())").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(records) { record in
                        Button { selection.wrappedValue = record.id } label: {
                            // Paper 21P: 72pt tiles, radius 14, the chosen one ringed in brand.
                            MediaThumbnail(record: record)
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(selection.wrappedValue == record.id ? Theme.brand : Color.clear, lineWidth: 2))
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
