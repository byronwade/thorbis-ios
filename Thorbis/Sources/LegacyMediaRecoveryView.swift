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
            // Paper v2 tokens: grouped cards (radius 20) 16 from the edge, 20 apart, a 13 Semibold
            // label 8 above its card, rows of a 16 Medium title over a 14 muted line.
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error { ErrorBanner(message: error) { await load() } }
                    if busy {
                        ThorbisLoadingLine(message: "Checking this job…")
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, PaperCardMetrics.margin)
                    }
                    if let destination {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(destination.job.title).font(Theme.font(16, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(workspaceName).font(Theme.font(14)).foregroundStyle(Theme.muted)
                            Text("The original account is unknown. Recover only photos that belong in this job. Other older files remain on this phone.")
                                .font(Theme.font(14)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 6)
                        }
                        .padding(PaperCardMetrics.inset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panelBackground()
                        .padding(.horizontal, PaperCardMetrics.margin)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Older photos for this job").font(Theme.font(13, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.horizontal, 4)
                            VStack(spacing: 0) {
                                ForEach(Array(destination.candidates.enumerated()), id: \.element.id) { index, candidate in
                                    if index > 0 { WellDivider() }
                                    Button {
                                        selected = candidate
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "photo").font(.system(size: 17, weight: .medium))
                                                .foregroundStyle(Theme.muted).frame(width: 24)
                                                .accessibilityHidden(true)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(candidate.media.filename).font(Theme.font(16, weight: .medium))
                                                    .foregroundStyle(Theme.foreground)
                                                Text(recovered.contains(candidate.id) ? "Recovered to this job" : candidate.media.capturedAt.stampLabel())
                                                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                                            }
                                            Spacer(minLength: 8)
                                            if recovered.contains(candidate.id) {
                                                Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
                                                    .foregroundStyle(Theme.statusDone)
                                            }
                                        }
                                        .multilineTextAlignment(.leading)
                                        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 10)
                                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PressStyle())
                                    .disabled(busy || recovered.contains(candidate.id))
                                    .accessibilityIdentifier("legacy-recover-\(candidate.id)")
                                }
                                if destination.candidates.isEmpty {
                                    Text("No identifiable older photos for this job. Other files remain on this phone.")
                                        .font(Theme.font(14)).foregroundStyle(Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(PaperCardMetrics.inset)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .panelBackground()
                        }
                        .padding(.horizontal, PaperCardMetrics.margin)

                        if !recovered.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Recovered to this job").font(Theme.font(16, weight: .medium))
                                Text("Return to Photos to retry upload.").font(Theme.font(14)).foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, Theme.gutter)
                        }
                    }
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.canvas).foregroundStyle(Theme.foreground)
            .navigationTitle("Recover older photos").navigationBarTitleDisplayMode(.inline)
            .toolbar { ThorbisToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.disabled(busy) } }
            .task { await load() }
            .thorbisConfirm(item: $selected,
                            title: { _ in "Recover this photo?" },
                            message: destination.map { destination in { _ in
                                "Add this older photo to \(destination.job.title) in \(workspaceName). Its original account is unknown. The photo will be saved to this job for upload using your current account."
                            } },
                            actions: { candidate in
                [ThorbisConfirmAction("Recover to this job") { Task { await recover(candidate) } }]
            })
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
