import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import VisionKit

struct JobMediaView: View {
    let jobID: String
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var pendingMedia: PendingMediaStore
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var records: [MediaAssetRecord] = []
    @State private var selection: PhotosPickerItem?
    @State private var selectedData: Data?
    @State private var selectedMime = "image/jpeg"
    @State private var selectedFilename = "photo.jpg"
    @State private var clientAssetID = UUID().uuidString
    @State private var selectedCapturedAt = Date()
    @State private var captureContext: PendingMediaStore.CaptureContext?
    @State private var captureGeneration: UUID?
    @State private var captureOrigin: String?
    @State private var loading = true
    /// Bumped by pull-to-refresh so thumbnails that failed to download try again.
    @State private var thumbnailAttempt = 0
    @State private var busy = false
    @State private var error: String?
    @StateObject private var preview = DocumentPreviewController()
    @State private var importDocument = false
    @State private var showCamera = false
    @State private var showScanner = false
    @State private var showLegacyRecovery = false
    /// Paper 21C: the stage a new photo is filed under (server tags "Before" / "After").
    @State private var stage = "Before"
    @State private var filter = "All"
    /// Photos taken but not yet confirmed by the server; kept on disk until they are.
    private var waiting: [PendingMedia] { pendingMedia.items.filter { $0.jobID == jobID } }
    private var visible: [MediaAssetRecord] { records.filter { !$0.archived } }
    private var allPhotos: [MediaAssetRecord] { visible.filter { $0.kind == "photo" } }
    private var photos: [MediaAssetRecord] {
        switch filter {
        case "Before", "After": allPhotos.filter { $0.tags.contains(filter) }
        case "Untagged": allPhotos.filter { !$0.tags.contains("Before") && !$0.tags.contains("After") }
        default: allPhotos
        }
    }
    private var documents: [MediaAssetRecord] { visible.filter { $0.kind != "photo" } }
    private var canAdd: Bool { session.can("job.edit", feature: "jobs") }

    /// Paper 21A: a photo grid, a documents list, and one commit to add more.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error = error ?? preview.error {
                    ErrorBanner(message: error, retry: selectedData == nil ? nil : { enqueueSelection() })
                        .padding(.horizontal, -Theme.gutter)
                }
                if loading || preview.loading { SkeletonRows(count: 2, inset: 0) }
                if let selectedData {
                    HStack(spacing: 12) {
                        Image(systemName: selectedMime == "application/pdf" ? "doc" : "photo")
                            .frame(width: 36, height: 36).background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedFilename).font(Theme.font(14, weight: .medium)).lineLimit(1)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(selectedData.count), countStyle: .file))
                                .font(Theme.monoFont(11)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button("Discard", role: .destructive) { self.selectedData = nil; selection = nil }
                            .font(Theme.font(13, weight: .medium)).frame(minHeight: 44).disabled(busy)
                    }
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
                }
                if !allPhotos.isEmpty {
                    if dynamicTypeSize.isAccessibilitySize {
                        Menu {
                            ForEach(["All", "Before", "After", "Untagged"], id: \.self) { option in
                                Button("\(option) · \(photoFilterCount(option))") { filter = option }
                            }
                        } label: {
                            Label("Filter photos · \(filter)", systemImage: "line.3.horizontal.decrease.circle")
                                .font(.body.weight(.medium))
                                .frame(minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("photo-filter-menu")
                    } else {
                        HStack(spacing: 6) {
                            ForEach(["All", "Before", "After", "Untagged"], id: \.self) { option in
                                let count = photoFilterCount(option)
                                Button { filter = option } label: {
                                    Text("\(option) · \(count)").font(Theme.font(13, weight: .medium))
                                        .foregroundStyle(filter == option ? Theme.background : Theme.muted)
                                        .padding(.horizontal, 11).frame(height: 28)
                                        .background(filter == option ? Theme.foreground : Theme.fill, in: Capsule())
                                        .frame(minHeight: 44).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(filter == option ? .isSelected : [])
                            }
                        }
                    }
                }
                if let warning = pendingMedia.storageWarning { ErrorBanner(message: warning) }
                if pendingMedia.legacyCount > 0 {
                    ErrorBanner(message: "Older photos remain on this phone. Check this job before choosing which photos to recover.")
                    Button("Recover older photos") { showLegacyRecovery = true }
                        .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.brandText)
                        .frame(minHeight: 44).disabled(!canAdd || busy)
                }
                if !waiting.isEmpty {
                    PaperGroupHeader(title: "Waiting to upload", count: waiting.count) {
                        Button("Retry") { Task { await retryWaiting() } }
                            .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.brandText)
                            .frame(minHeight: 44).disabled(busy || !canAdd)
                    }
                    ForEach(waiting) { photo in
                        HStack(spacing: 12) {
                            Image(systemName: pendingMedia.errors[photo.id] != nil ? "exclamationmark.triangle" : photo.kind == "document" ? "doc" : "clock.arrow.circlepath").foregroundStyle(Theme.warning)
                                .frame(width: 32, height: 32).background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(photo.title).font(Theme.font(15, weight: .medium))
                                Text(pendingMedia.errors[photo.id].map { "Needs attention · \($0)" } ?? (pendingMedia.uploadingID == photo.id ? "Uploading…" : pendingMedia.unverifiedIDs.contains(photo.id) ? "Saved copy not yet verified" : "Saved on this phone · \(photo.capturedAt.formatted(date: .omitted, time: .shortened))"))
                                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                        }
                        .frame(minHeight: 48)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("pending-media-\(photo.id)")
                        .accessibilityValue(Text("Captured \(photo.capturedAt.formatted(date: .abbreviated, time: .shortened))"))
                    }
                }
                if canAdd && dynamicTypeSize.isAccessibilitySize {
                    photoCaptureControls.padding(.top, 10)
                }
                // One empty state for the whole tab instead of two empty sections.
                if photos.isEmpty && documents.isEmpty && waiting.isEmpty && pendingMedia.legacyCount == 0 && pendingMedia.storageWarning == nil && !loading {
                    PaperEmptyState(symbol: "camera", title: "No photos yet",
                                    message: canAdd ? "Take a before photo when you arrive. Photos and PDFs up to 8 MB." : "Photos and documents added to this job show here.")
                }
                if !photos.isEmpty { PaperGroupHeader(title: "Photos", count: photos.count) }
                if !photos.isEmpty {
                    ForEach(JobPhotoDateGroups.group(photos, calendar: calendar), id: \.day) { group in
                        Text(group.day.map(photoDayLabel) ?? "Date unavailable")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                                  ? [GridItem(.flexible())]
                                  : [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(group.photos) { record in
                                ZStack(alignment: .bottomTrailing) {
                                    Button { open(record) } label: {
                                        VStack(alignment: .leading, spacing: 0) {
                                            MediaThumbnail(record: record, attempt: thumbnailAttempt)
                                                .frame(maxWidth: .infinity).frame(height: 120)
                                                .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.cardRadius, topTrailingRadius: Theme.cardRadius))
                                                .overlay(alignment: .topLeading) {
                                                    if let tag = ["Before", "After"].first(where: record.tags.contains) {
                                                        Text(tag).font(Theme.font(11, weight: .semibold))
                                                            .foregroundStyle(Theme.foreground)
                                                            .padding(.horizontal, 8).frame(height: 24)
                                                            .background(Theme.background.opacity(0.9), in: Capsule())
                                                            .padding(8)
                                                    }
                                                }
                                            Text(record.caption ?? record.originalFilename).font(Theme.font(13, weight: .medium))
                                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                                .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                                                .padding(.horizontal, 10).padding(.vertical, 8)
                                                .padding(.trailing, dynamicTypeSize.isAccessibilitySize && canAdd && record.uploadState == "stored" ? 46 : 0)
                                            if record.uploadState != "stored" {
                                                Text(record.uploadState.statusLabel).font(Theme.font(11)).foregroundStyle(Theme.warning)
                                                    .padding(.horizontal, 10).padding(.bottom, 8)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(busy || preview.loading || record.uploadState != "stored")
                                    .accessibilityLabel("Photo, \(record.caption ?? record.originalFilename)")
                                    if canAdd, record.uploadState == "stored" {
                                        ThorbisMenu(items: [
                                            ThorbisMenuItem("Before") { Task { await retag(record, .before) } },
                                            ThorbisMenuItem("After") { Task { await retag(record, .after) } },
                                            ThorbisMenuItem("Other") { Task { await retag(record, .other) } },
                                        ], title: "Tag photo", accessibilityLabel: stageName(record)) {
                                            Image(systemName: "tag")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(Theme.foreground)
                                                .frame(width: 44, height: 44)
                                                .background(Theme.background.opacity(0.92), in: Circle())
                                        }
                                        .disabled(busy)
                                        .padding(4)
                                    }
                                }
                            }
                        }
                    }
                }
                if !documents.isEmpty { PaperGroupHeader(title: "Documents", count: documents.count).padding(.top, 6) }
                ForEach(documents) { record in
                    Button { open(record) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc").font(.system(size: 15)).foregroundStyle(Theme.muted)
                                .frame(width: 32, height: 32).background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.originalFilename).font(Theme.font(15, weight: .medium)).lineLimit(1)
                                Text(record.uploadState == "stored" ? "PDF" : record.uploadState.statusLabel)
                                    .font(Theme.monoFont(11)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "arrow.down.circle").foregroundStyle(Theme.muted)
                        }
                        .frame(minHeight: 48).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || preview.loading || record.uploadState != "stored")
                }
                if canAdd && !(photos.isEmpty && documents.isEmpty) {
                    Text("Photos and PDFs up to 8 MB.").font(Theme.font(12)).foregroundStyle(Theme.muted).padding(.top, 4)
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            if canAdd && !dynamicTypeSize.isAccessibilitySize {
                photoCaptureControls
                    .padding(.horizontal, Theme.gutter).padding(.top, 10).padding(.bottom, 8)
                    .background(Theme.background)
            }
        }
        .sheet(isPresented: $showLegacyRecovery) {
            LegacyMediaRecoveryView(jobID: jobID, workspaceName: session.activeOrganization?.name ?? "Current workspace")
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner { pdf in
                showScanner = false
                guard let pdf else { return }
                do {
                    let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "")
                    try select(pdf, mime: "application/pdf", filename: "scan-\(stamp).pdf")
                    enqueueSelection()
                } catch { self.error = error.localizedDescription }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { image in
                showCamera = false
                guard let image else { return }
                uploadImage(image)
            }
            .ignoresSafeArea()
        }
        .task {
            if captureContext == nil {
                captureContext = pendingMedia.captureContext
                captureGeneration = api.requestGeneration
                captureOrigin = api.normalizedOrigin
            }
            pendingMedia.reload()
            await load()
            if !waiting.isEmpty { await retryWaiting() }
        }
        .refreshable { thumbnailAttempt += 1; await load() }
        .onChange(of: selection) { _, item in
            Task {
                guard let item else { return }
                busy = true
                defer { busy = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                    selection = nil
                    if let image = UIImage(data: data) {
                        busy = false
                        uploadImage(image)
                    } else {
                        let type = item.supportedContentTypes.first ?? .jpeg
                        try select(data, mime: type.preferredMIMEType ?? "image/jpeg", filename: "photo." + (type.preferredFilenameExtension ?? "jpg"))
                        enqueueSelection()
                    }
                } catch { self.error = error.localizedDescription }
            }
        }
        .fileImporter(isPresented: $importDocument, allowedContentTypes: [.pdf]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 8 * 1024 * 1024 else { throw MediaSelectionError.tooLarge }
                try select(Data(contentsOf: url), mime: "application/pdf", filename: url.lastPathComponent)
                enqueueSelection()
            } catch { self.error = error.localizedDescription }
        }
        .sheet(isPresented: Binding(get: { preview.url != nil }, set: { if !$0 { preview.clear() } })) {
            if let file = preview.url { NativeDocumentPreview(url: file) }
        }
        .onDisappear { selectedData = nil; preview.clear() }
    }
    private func select(_ data: Data, mime: String, filename: String) throws {
        guard !data.isEmpty, data.count <= 8 * 1024 * 1024 else { throw MediaSelectionError.tooLarge }
        guard ["image/jpeg", "image/png", "image/heic", "image/webp", "application/pdf"].contains(mime) else { throw MediaSelectionError.unsupported }
        selectedData = data
        selectedMime = mime
        selectedFilename = filename
        clientAssetID = UUID().uuidString
        selectedCapturedAt = Date()
        error = nil
    }
    private func photoFilterCount(_ option: String) -> Int {
        switch option {
        case "Before", "After": allPhotos.filter { $0.tags.contains(option) }.count
        case "Untagged": allPhotos.filter { !$0.tags.contains("Before") && !$0.tags.contains("After") }.count
        default: allPhotos.count
        }
    }

    private var photoCaptureControls: some View {
        VStack(spacing: 8) {
            ThorbisSegmented(options: [("Before", "Before"), ("After", "After"), ("Other", "Other")],
                             selection: $stage)
                .disabled(busy)
            HStack(spacing: 8) {
                Button { showCamera = true } label: {
                    HStack(spacing: 7) {
                        if busy { ProgressView().tint(Theme.onInk) } else { Image(systemName: "camera") }
                        Text(busy ? "Uploading…" : "Take \(stage == "Other" ? "a" : stage.lowercased()) photo")
                    }
                    .inkCommit()
                }
                .buttonStyle(PressStyle())
                .disabled(busy || !UIImagePickerController.isSourceTypeAvailable(.camera))
                PhotosPicker(selection: $selection, matching: .images) {
                    Image(systemName: "photo.on.rectangle").font(.system(size: 17)).foregroundStyle(Theme.foreground)
                        .frame(width: 46, height: 46)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
                }
                .disabled(busy)
                .accessibilityLabel("Choose from library")
                ThorbisMenu(items: (VNDocumentCameraViewController.isSupported
                    ? [ThorbisMenuItem("Scan a document", icon: "doc.viewfinder") { showScanner = true }]
                    : []) + [ThorbisMenuItem("Choose a PDF", icon: "doc") { importDocument = true }],
                            title: "Add a document", accessibilityLabel: "Add a document") {
                    Image(systemName: "doc.badge.plus").font(.system(size: 17)).foregroundStyle(Theme.foreground)
                        .frame(width: 46, height: 46)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
                }
                .disabled(busy)
            }
        }
    }

    private func photoDayLabel(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: day)
    }

    private func stageName(_ record: MediaAssetRecord) -> String {
        if record.tags.contains("Before") { return "Change photo stage, currently Before" }
        if record.tags.contains("After") { return "Change photo stage, currently After" }
        return "Change photo stage, currently Other"
    }

    private func retag(_ record: MediaAssetRecord, _ stage: MediaStage) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let updated = try await api.tagFieldMedia(record.id, tags: MediaStageTags.applying(stage, to: record.tags), caption: record.caption)
            if let index = records.firstIndex(where: { $0.id == updated.id }) { records[index] = updated }
            error = nil
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do { records = try await api.fieldMedia(jobID); error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func enqueueSelection() {
        guard let selectedData else { return }
        guard canAdd, captureGeneration == api.requestGeneration, captureOrigin == api.normalizedOrigin,
              let captureContext else {
            error = "Your workspace changed. Return to the original job before adding media."
            return
        }
        let media = PendingMedia(id: clientAssetID, jobID: jobID, filename: selectedFilename,
            tags: selectedMime == "application/pdf" ? [] : stageTags, capturedAt: selectedCapturedAt,
            kind: selectedMime == "application/pdf" ? "document" : "photo", mime: selectedMime)
        do {
            try pendingMedia.save(media, data: selectedData, context: captureContext)
            self.selectedData = nil
            selection = nil
            error = nil
            // The callback releases original camera/library images before awaiting networking.
            Task { await retryWaiting() }
        } catch { self.error = error.localizedDescription }
    }
    private var stageTags: [String] { stage == "Other" ? [] : [stage] }

    /// Save original bounded JPEG bytes before the first network request.
    private func uploadImage(_ image: UIImage) {
        guard canAdd else { return }
        guard let data = Self.jpeg(image) else {
            error = MediaSelectionError.tooLarge.localizedDescription
            return
        }
        let capturedAt = Date()
        let stamp = capturedAt.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "")
        do {
            try select(data, mime: "image/jpeg", filename: "\(stage.lowercased())-\(stamp).jpg")
            enqueueSelection()
        } catch { self.error = error.localizedDescription }
    }

    private func retryWaiting() async {
        busy = true
        defer { busy = false }
        await pendingMedia.drain(api: api, jobID: jobID, canUpload: { session.can("job.edit", feature: "jobs") })
        await load()
    }

    static func jpeg(_ image: UIImage) -> Data? {
        let longEdge = max(image.size.width, image.size.height)
        let scale = min(1, 2560 / max(longEdge, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        for quality in [0.82, 0.7, 0.55] {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= 8 * 1024 * 1024 { return data }
        }
        return nil
    }

    private func open(_ record: MediaAssetRecord) {
        preview.open { try await MediaTransfer(api: api).download(mediaID: record.id, filename: record.originalFilename) }
    }
}

private enum MediaSelectionError: LocalizedError {
    case tooLarge, unsupported
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "Choose a nonempty file no larger than 8 MB."
        case .unsupported: return "Choose a JPEG, PNG, HEIC, WebP photo or a PDF."
        }
    }
}

struct NativeDocumentPreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}

/// System camera (HIG-019): returns the captured photo or nil when cancelled.
struct CameraCapture: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}

/// VisionKit's document camera: edge detection, perspective correction, multi-page.
/// Pages come back as one PDF so they file under the job's Documents.
struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (Data?) -> Void
        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
            let data = UIGraphicsPDFRenderer(bounds: pageRect).pdfData { context in
                for index in 0..<scan.pageCount {
                    context.beginPage()
                    let image = scan.imageOfPage(at: index)
                    let scale = min(pageRect.width / image.size.width, pageRect.height / image.size.height)
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    image.draw(in: CGRect(x: (pageRect.width - size.width) / 2, y: (pageRect.height - size.height) / 2,
                                          width: size.width, height: size.height))
                }
            }
            onFinish(data.count <= 8 * 1024 * 1024 ? data : nil)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish(nil) }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onFinish(nil) }
    }
}

/// Presentation-only grouping; unavailable capture dates never fall back to upload time.
enum JobPhotoDateGroups {
    struct Group {
        let day: Date?
        let photos: [MediaAssetRecord]
    }

    static func group(_ photos: [MediaAssetRecord], calendar: Calendar) -> [Group] {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        var byDay: [Date: [MediaAssetRecord]] = [:]
        var unavailable: [MediaAssetRecord] = []
        for photo in photos {
            guard let raw = photo.capturedAt,
                  let date = fractional.date(from: raw) ?? standard.date(from: raw) else {
                unavailable.append(photo)
                continue
            }
            byDay[calendar.startOfDay(for: date), default: []].append(photo)
        }
        var groups = byDay.keys.sorted(by: >).map { Group(day: $0, photos: byDay[$0]!) }
        if !unavailable.isEmpty { groups.append(Group(day: nil, photos: unavailable)) }
        return groups
    }
}
