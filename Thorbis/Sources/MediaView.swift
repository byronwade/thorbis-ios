import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

struct JobMediaView: View {
    let jobID: String
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @State private var records: [MediaAssetRecord] = []
    @State private var selection: PhotosPickerItem?
    @State private var selectedData: Data?
    @State private var selectedMime = "image/jpeg"
    @State private var selectedFilename = "photo.jpg"
    @State private var clientAssetID = UUID().uuidString
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?
    @StateObject private var preview = DocumentPreviewController()
    @State private var importDocument = false
    @State private var showCamera = false
    /// Paper 21C: the stage a new photo is filed under (server tags "Before" / "After").
    @State private var stage = "Before"
    @State private var filter = "All"
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
                if let error = error ?? preview.error { ErrorBanner(message: error).padding(.horizontal, -Theme.gutter) }
                if loading || preview.loading { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20) }
                if let selectedData {
                    HStack(spacing: 12) {
                        Image(systemName: selectedMime == "application/pdf" ? "doc" : "photo")
                            .frame(width: 36, height: 36).background(Theme.fill, in: RoundedRectangle(cornerRadius: 8))
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
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                }
                if !allPhotos.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(["All", "Before", "After", "Untagged"], id: \.self) { option in
                            let count = option == "All" ? allPhotos.count : option == "Untagged"
                                ? allPhotos.filter { !$0.tags.contains("Before") && !$0.tags.contains("After") }.count
                                : allPhotos.filter { $0.tags.contains(option) }.count
                            Button { filter = option } label: {
                                Text("\(option) · \(count)").font(Theme.font(12, weight: filter == option ? .semibold : .medium))
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
                PaperGroupHeader(title: "Photos", count: photos.count)
                if photos.isEmpty && !loading {
                    Text("No photos on this job yet.").font(Theme.font(13)).foregroundStyle(Theme.muted)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(photos) { record in
                            Button { open(record) } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    Image(systemName: "photo").font(.system(size: 22, weight: .light)).foregroundStyle(Theme.muted)
                                        .frame(maxWidth: .infinity, minHeight: 96)
                                        .overlay(alignment: .topLeading) {
                                            if let tag = ["Before", "After"].first(where: record.tags.contains) {
                                                Text(tag).font(Theme.font(11, weight: .semibold))
                                                    .foregroundStyle(tag == "After" ? Theme.success : Theme.foreground)
                                                    .padding(.horizontal, 7).frame(height: 20)
                                                    .background(tag == "After" ? Theme.successSurface : Theme.fill, in: RoundedRectangle(cornerRadius: 6))
                                                    .padding(8)
                                            }
                                        }
                                    Text(record.caption ?? record.originalFilename).font(Theme.font(12, weight: .medium)).lineLimit(1)
                                        .padding(.horizontal, 10).padding(.bottom, 8)
                                    if record.uploadState != "stored" {
                                        Text(record.uploadState.statusLabel).font(Theme.font(11)).foregroundStyle(Theme.warning)
                                            .padding(.horizontal, 10).padding(.bottom, 8)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                            }
                            .buttonStyle(.plain)
                            .disabled(busy || preview.loading || record.uploadState != "stored")
                            .accessibilityLabel("Photo, \(record.caption ?? record.originalFilename)")
                        }
                    }
                }
                PaperGroupHeader(title: "Documents", count: documents.count).padding(.top, 6)
                if documents.isEmpty && !loading {
                    Text("No documents on this job yet.").font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
                ForEach(documents) { record in
                    Button { open(record) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc").font(.system(size: 15)).foregroundStyle(Theme.muted)
                                .frame(width: 32, height: 32).background(Theme.fill, in: RoundedRectangle(cornerRadius: 8))
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
                if canAdd {
                    Text("Photos and PDFs up to 8 MB.").font(Theme.font(12)).foregroundStyle(Theme.muted).padding(.top, 4)
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            if canAdd {
                VStack(spacing: 8) {
                    Picker("Photo stage", selection: $stage) {
                        Text("Before").tag("Before")
                        Text("After").tag("After")
                        Text("Other").tag("Other")
                    }
                    .pickerStyle(.segmented)
                    .disabled(busy)
                    HStack(spacing: 8) {
                        Button { showCamera = true } label: {
                            HStack(spacing: 7) {
                                if busy { ProgressView().tint(.white) } else { Image(systemName: "camera") }
                                Text(busy ? "Uploading…" : "Take \(stage == "Other" ? "a" : stage.lowercased()) photo")
                            }
                            .font(Theme.font(15, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(busy || !UIImagePickerController.isSourceTypeAvailable(.camera))
                        PhotosPicker(selection: $selection, matching: .images) {
                            Image(systemName: "photo.on.rectangle").font(.system(size: 17)).foregroundStyle(Theme.foreground)
                                .frame(width: 46, height: 46)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                        }
                        .disabled(busy)
                        .accessibilityLabel("Choose from library")
                        PaperSquareButton(symbol: "doc.badge.plus", label: "Add PDF") { importDocument = true }
                            .disabled(busy)
                    }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 10).padding(.bottom, 8)
                .background(Theme.background)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { image in
                showCamera = false
                guard let image else { return }
                Task { await uploadImage(image) }
            }
            .ignoresSafeArea()
        }
        .task { await load() }
        .refreshable { await load() }
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
                        await uploadImage(image)
                    } else {
                        let type = item.supportedContentTypes.first ?? .jpeg
                        try select(data, mime: type.preferredMIMEType ?? "image/jpeg", filename: "photo." + (type.preferredFilenameExtension ?? "jpg"))
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
        error = nil
    }
    private func load() async {
        loading = true
        defer { loading = false }
        do { records = try await api.fieldMedia(jobID); error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func upload() async {
        guard let selectedData else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await MediaTransfer(api: api).upload(jobID: jobID, clientAssetID: clientAssetID, kind: selectedMime == "application/pdf" ? "document" : "photo", mime: selectedMime, originalFilename: selectedFilename, data: selectedData, tags: selectedMime == "application/pdf" ? [] : stageTags)
            self.selectedData = nil
            selection = nil
            await load()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private var stageTags: [String] { stage == "Other" ? [] : [stage] }

    /// Photos upload as soon as they are taken: JPEG, long edge at most 2560 pt, under the 8 MB single-PUT limit.
    private func uploadImage(_ image: UIImage) async {
        guard let data = Self.jpeg(image) else {
            error = MediaSelectionError.tooLarge.localizedDescription
            return
        }
        busy = true
        defer { busy = false }
        do {
            let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "")
            _ = try await MediaTransfer(api: api).upload(jobID: jobID, clientAssetID: UUID().uuidString, kind: "photo", mime: "image/jpeg",
                                                         originalFilename: "\(stage.lowercased())-\(stamp).jpg", data: data, tags: stageTags)
            error = nil
            await load()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
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
