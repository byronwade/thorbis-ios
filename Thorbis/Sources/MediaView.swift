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
    private var visible: [MediaAssetRecord] { records.filter { !$0.archived } }
    private var photos: [MediaAssetRecord] { visible.filter { $0.kind == "photo" } }
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
                HStack(spacing: 8) {
                    if selectedData != nil {
                        Button { Task { await upload() } } label: {
                            HStack(spacing: 7) {
                                if busy { ProgressView().tint(.white) } else { Image(systemName: "arrow.up.circle") }
                                Text("Upload \(selectedMime == "application/pdf" ? "document" : "photo")")
                            }
                            .font(Theme.font(15, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain).disabled(busy)
                    } else {
                        PhotosPicker(selection: $selection, matching: .images) {
                            Label("Add photo", systemImage: "camera")
                                .font(Theme.font(15, weight: .semibold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(height: 46)
                                .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(busy)
                    }
                    PaperSquareButton(symbol: "doc.badge.plus", label: "Add PDF") { importDocument = true }
                        .disabled(busy)
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 10).padding(.bottom, 8)
                .background(Theme.background)
            }
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
                    let type = item.supportedContentTypes.first ?? .jpeg
                    try select(data, mime: type.preferredMIMEType ?? "image/jpeg", filename: "photo." + (type.preferredFilenameExtension ?? "jpg"))
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
            _ = try await MediaTransfer(api: api).upload(jobID: jobID, clientAssetID: clientAssetID, kind: selectedMime == "application/pdf" ? "document" : "photo", mime: selectedMime, originalFilename: selectedFilename, data: selectedData)
            self.selectedData = nil
            selection = nil
            await load()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
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
