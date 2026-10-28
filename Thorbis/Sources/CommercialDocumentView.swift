import SwiftUI

struct CommercialDocumentView: View {
    let path: String
    @EnvironmentObject var api: APIClient
    @StateObject private var preview = DocumentPreviewController()
    var body: some View {
        Group {
            if let file = preview.url { NativeDocumentPreview(url: file) }
            else if let error = preview.error {
                ContentUnavailableView { Label("Document unavailable", systemImage: "doc.badge.ellipsis") } description: { Text(error) } actions: { Button("Retry") { load() }.disabled(preview.loading) }
            } else { ProgressView("Preparing document…") }
        }
        .navigationTitle("Document")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
        .onDisappear { preview.clear() }
    }
    private func load() {
        preview.open {
            let data = try await api.documentData(path)
            try Task.checkCancellation()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        }
    }
}
