import SwiftUI

/// Explicit adoption of one older local photo into a freshly verified destination.
/// Original account ownership is unknown; no image is previewed or uploaded here.
struct LegacyMediaRecoveryView: View {
    let jobID: String
    let workspaceName: String
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var media: PendingMediaStore
    @Environment(\.dismiss) private var dismiss
    @State private var destination: PendingMediaStore.LegacyDestination?
    @State private var selected: PendingMediaStore.LegacyCandidate?
    @State private var busy = false
    @State private var error: String?
    @State private var recovered: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                if let error { ErrorBanner(message: error) { await load() } }
                if busy { ProgressView("Checking this job…") }
                if let destination {
                    Section {
                        Text(destination.job.title).font(Theme.font(18, weight: .medium))
                        Text(workspaceName).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        Text("The original account is unknown. Recover only photos that belong in this job. Other older files remain on this phone.")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                    Section("Older photos for this job") {
                        ForEach(destination.candidates) { candidate in
                            Button {
                                selected = candidate
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "photo").foregroundStyle(Theme.muted)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(candidate.media.filename).font(Theme.font(15, weight: .medium))
                                        Text(recovered.contains(candidate.id) ? "Recovered to this job" : candidate.media.capturedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(Theme.font(12)).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    if recovered.contains(candidate.id) { Image(systemName: "checkmark") }
                                }.frame(minHeight: 48)
                            }
                            .disabled(busy || recovered.contains(candidate.id))
                            .accessibilityIdentifier("legacy-recover-\(candidate.id)")
                        }
                        if destination.candidates.isEmpty {
                            Text("No identifiable older photos for this job. Other files remain on this phone.")
                                .font(Theme.font(14)).foregroundStyle(Theme.muted)
                        }
                    }
                    if !recovered.isEmpty {
                        Text("Recovered to this job")
                        Text("Return to Photos to retry upload.").font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Theme.background).foregroundStyle(Theme.foreground)
            .navigationTitle("Recover older photos").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.disabled(busy) } }
            .task { await load() }
            .confirmationDialog("Recover this photo?", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), titleVisibility: .visible) {
                if let candidate = selected {
                    Button("Recover to this job") { Task { await recover(candidate) } }
                }
                Button("Cancel", role: .cancel) { selected = nil }
            } message: {
                if let destination {
                    Text("Add this older photo to \(destination.job.title) in \(workspaceName). Its original account is unknown. The photo will be saved to this job for upload using your current account.")
                }
            }
        }
    }
    private func load() async {
        busy = true; defer { busy = false }
        do {
            destination = try await media.prepareLegacyRecovery(api: api, jobID: jobID, canUpload: { session.can("job.edit", feature: "jobs") })
            error = nil
        } catch { self.error = error.localizedDescription; destination = nil }
    }
    private func recover(_ candidate: PendingMediaStore.LegacyCandidate) async {
        guard let destination else { return }
        selected = nil; busy = true; defer { busy = false }
        do {
            try await media.recoverLegacy(candidate, destination: destination, api: api, canUpload: { session.can("job.edit", feature: "jobs") })
            recovered.insert(candidate.id); error = nil
        } catch { self.error = error.localizedDescription }
    }
}
