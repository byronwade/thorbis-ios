import Foundation

/// Owns preview files for exactly one visible screen. Retired downloads clean up
/// their result even when the underlying loader does not cooperate with cancellation.
@MainActor
final class DocumentPreviewController: ObservableObject {
    @Published private(set) var url: URL?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var operation: Task<Void, Never>?
    private var generation = UUID()

    func open(_ loader: @escaping @MainActor () async throws -> URL) {
        clear()
        let current = generation
        loading = true
        operation = Task { [weak self] in
            do {
                let file = try await loader()
                guard let self, !Task.isCancelled, self.generation == current else {
                    try? FileManager.default.removeItem(at: file)
                    return
                }
                self.url = file
                self.loading = false
            } catch {
                guard let self, self.generation == current else { return }
                self.loading = false
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }

    func clear() {
        generation = UUID()
        operation?.cancel()
        operation = nil
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil
        loading = false
        error = nil
    }
}
