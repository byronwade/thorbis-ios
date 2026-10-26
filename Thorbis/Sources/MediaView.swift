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
    var body: some View {
        List {
            if let error = error ?? preview.error { ErrorBanner(message: error) }
            if loading || busy || preview.loading { ProgressView() }
            if session.can("job.edit", feature: "jobs") {
                Section("Add media") {
                    PhotosPicker(selection: $selection, matching: .images) { Label("Choose photo", systemImage: "photo") }.disabled(busy)
                    Button("Choose PDF", systemImage: "doc") { importDocument = true }.disabled(busy)
                    Text("Photos and PDFs up to 8 MB.").font(.caption).foregroundStyle(.secondary)
                    if selectedData != nil {
                        Text(selectedFilename)
                        Button("Upload") { Task { await upload() } }.disabled(busy)
                        Button("Discard selection", role: .destructive) { selectedData = nil; selection = nil }.disabled(busy)
                    }
                }
            }
            Section("Files") {
                ForEach(records.filter { !$0.archived }) { record in
                    Button { open(record) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(record.originalFilename, systemImage: record.kind == "photo" ? "photo" : "doc")
                            Text(record.uploadState.statusLabel).font(.caption).foregroundStyle(.secondary)
                            if let caption = record.caption { Text(caption).font(.subheadline) }
                        }
                    }.disabled(busy || preview.loading || record.uploadState != "stored")
                }
                if records.isEmpty && !loading { Text("No media yet").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Media")
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
