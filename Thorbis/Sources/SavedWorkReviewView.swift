import SwiftUI

private struct SavedWorkReviewReturnKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}
extension EnvironmentValues {
    var savedWorkReviewReturnToRoot: (@MainActor () -> Void)? {
        get { self[SavedWorkReviewReturnKey.self] }
        set { self[SavedWorkReviewReturnKey.self] = newValue }
    }
}

/// One staff review of the existing command and media queues, grouped by job.
struct SavedWorkReviewView: View {
    let scope: SavedWorkScope
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var outbox: FieldOutbox
    @EnvironmentObject private var media: PendingMediaStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var path = NavigationPath()
    @State private var discardID: String?
    @State private var work: Task<Void, Never>?
    @State private var workID: UUID?
    @State private var detent: PresentationDetent = .large

    private var current: Bool { scope.isCurrent(session: session, api: api, media: media, outbox: outbox) }
    private var editable: Bool { scope.canEdit(session: session, api: api, media: media, outbox: outbox) }
    private var busy: Bool { work != nil || outbox.syncing || media.uploadingID != nil }
    private var snapshot: SavedWorkSnapshot {
        .make(scope: scope, entries: outbox.entries, media: media.items, mediaErrors: media.errors,
              unverifiedMediaIDs: media.unverifiedIDs, uploadingMediaID: media.uploadingID,
              commandsSyncing: outbox.syncing, jobs: store.jobs, listingWarning: media.storageWarning)
    }

    var body: some View {
        Group {
            if current {
                NavigationStack(path: $path) {
                    review
                        .navigationTitle("Saved on this phone")
                        .navigationBarTitleDisplayMode(.inline)
                        .paperDestinations()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { close() }.accessibilityIdentifier("saved-work-done")
                            }
                        }
                }
                .environment(\.paperTypedJobsOwner, nil)
                .environment(\.savedWorkReviewReturnToRoot, {
                    guard current else { close(); return }
                    path = NavigationPath()
                })
            } else {
                Color.clear.task { close() }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: current) { _, valid in if !valid { discardID = nil; close() } }
        .onChange(of: editable) { _, allowed in
            if !allowed { discardID = nil; cancelWork() }
        }
        .onDisappear { cancelWork() }
        .alert("Discard saved change?", isPresented: Binding(get: { discardID != nil }, set: { if !$0 { discardID = nil } }), presenting: discardID) { id in
            Button("Discard saved change", role: .destructive) {
                _ = scope.discardCommand(id, session: session, api: api, media: media, outbox: outbox)
                discardID = nil
            }
            Button("Cancel", role: .cancel) { discardID = nil }
        } message: { _ in
            Text("Only this phone's refused change is removed. The server stays unchanged; later eligible changes can retry.")
        }
    }

    private var review: some View {
        let state = snapshot
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Review saved changes, photos and scans by job.")
                        .font(Theme.font(17)).foregroundStyle(Theme.muted)
                    Button { startSync() } label: {
                        ZStack {
                            Text("Sync now").font(Theme.font(17, weight: .medium))
                            if busy { HStack { ProgressView().tint(Theme.background); Spacer() }.padding(.horizontal, 12) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.foreground)
                    .foregroundStyle(Theme.background)
                    .disabled(!editable || session.isOffline || busy)
                    .accessibilityIdentifier("saved-work-sync")
                    if session.isOffline {
                        Label("Offline · work stays saved on this phone", systemImage: "wifi.slash")
                            .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    } else if busy {
                        Label("Syncing saved work", systemImage: "arrow.triangle.2.circlepath")
                            .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    } else if !editable {
                        Text("You can review saved work. Your current access doesn't allow retrying or discarding changes.")
                            .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    }
                    if state.hasListingWarning {
                        Label("The list may be incomplete. Saved work has not been cleared.", systemImage: "exclamationmark.triangle")
                            .font(Theme.font(15)).foregroundStyle(Theme.foreground)
                    }
                    #if DEBUG
                    if PaperPreview.showSavedWorkControls { SavedWorkPreviewControls() }
                    #endif
                }
                if state.groups.isEmpty {
                    Text(state.isSending ? "Waiting for the current sync to finish." : "No pending items listed for this workspace.")
                        .font(Theme.font(17)).foregroundStyle(Theme.muted)
                        .accessibilityIdentifier("saved-work-empty")
                }
                ForEach(state.groups) { group in
                    Section {
                        ForEach(group.rows) { row in
                            workRow(row)
                            if row.id != group.rows.last?.id { Divider().padding(.leading, 36) }
                        }
                        if group.rows.contains(where: \.isMedia) {
                            Text("For previews, tags and file retries, open this job's Photos tab.")
                                .font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.leading, 36)
                        }
                    } header: { groupHeader(group).padding(.top, 16) }
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.vertical, 20)
            .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(Theme.background).foregroundStyle(Theme.foreground)
        .accessibilityIdentifier("saved-work-review")
        .accessibilityValue("\(state.totalCount) items listed")
    }

    @ViewBuilder private func groupHeader(_ group: SavedWorkGroup) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) { jobTitle(group); openJob(group) }
        } else {
            HStack(alignment: .top, spacing: 12) { jobTitle(group); Spacer(minLength: 8); openJob(group) }
        }
    }
    private func jobTitle(_ group: SavedWorkGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.title).font(Theme.font(17, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(group.shortReference).font(Theme.monoFont(13)).foregroundStyle(Theme.muted)
        }
    }
    private func openJob(_ group: SavedWorkGroup) -> some View {
        PaperCompatibleLink(value: PaperRoute.job(group.jobID)) {
            HStack(spacing: 8) { Text("Open job"); Image(systemName: "chevron.right") }
                .font(Theme.font(15, weight: .medium)).frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .accessibilityLabel("Open job, \(group.title), \(group.shortReference)")
        .accessibilityIdentifier("saved-work-open-\(group.jobID)")
    }
    private func workRow(_ row: SavedWorkRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.symbol).font(.system(size: 18)).foregroundStyle(row.state.needsReview ? Theme.warning : Theme.muted)
                .frame(width: 24, height: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.title).font(Theme.font(17, weight: .medium))
                    Text(row.state.title).font(Theme.font(15)).foregroundStyle(Theme.muted)
                    if let reason = row.state.reason { Text(reason).font(Theme.font(15)).foregroundStyle(Theme.muted) }
                    Text(row.date.formatted(date: .abbreviated, time: .shortened)).font(Theme.monoFont(13)).foregroundStyle(Theme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityValue((row.isMedia ? "Captured " : "Saved ") + row.date.formatted(date: .abbreviated, time: .shortened))
                if case .rejected = row.state {
                    Group {
                        if typeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 0) { recoveryButtons(row) }
                        } else {
                            HStack(spacing: 20) { recoveryButtons(row) }
                        }
                    }
                    .font(Theme.font(15, weight: .medium))
                    .disabled(!editable || busy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saved-work-\(row.id)")
    }

    @ViewBuilder private func recoveryButtons(_ row: SavedWorkRow) -> some View {
        Button { retryCommand(row.originalID) } label: {
            Text("Retry").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("Retry \(row.title)")
        .accessibilityIdentifier("saved-work-retry-\(row.originalID)")
        Button(role: .destructive) { if editable { discardID = row.originalID } } label: {
            Text("Dismiss").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("Dismiss \(row.title)")
        .accessibilityIdentifier("saved-work-dismiss-\(row.originalID)")
    }

    private func retryCommand(_ id: String) {
        guard scope.retryCommand(id, session: session, api: api, media: media, outbox: outbox) else { return }
        if !session.isOffline { startSync() }
    }
    private func startSync() {
        guard current, editable, !session.isOffline, !busy else { return }
        let id = UUID(); workID = id
        work = Task { @MainActor in
            await session.revalidate()
            guard current, editable, !session.isOffline, !Task.isCancelled else { finishWork(id); return }
            await outbox.drain(api: api, useCommandEndpoint: session.isFeatureOn("offline_sync"), canSend: {
                scope.canEdit(session: session, api: api, media: media, outbox: outbox) && !session.isOffline
            })
            guard current, editable, !session.isOffline, !Task.isCancelled else { finishWork(id); return }
            await media.drain(api: api, canUpload: { scope.canEdit(session: session, api: api, media: media, outbox: outbox) && !session.isOffline })
            finishWork(id)
        }
    }
    private func finishWork(_ id: UUID) { if workID == id { workID = nil; work = nil } }
    private func cancelWork() { work?.cancel(); work = nil; workID = nil }
    private func close() { cancelWork(); discardID = nil; dismiss() }
}
