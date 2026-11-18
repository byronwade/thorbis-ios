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
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var path = NavigationPath()
    @State private var discardID: DiscardRequest?
    @State private var work: Task<Void, Never>?
    @State private var workID: UUID?
    @State private var detent: PresentationDetent = .large

    /// The refused change a discard confirmation is about. Only its id is kept.
    private struct DiscardRequest: Identifiable {
        let id: String
    }

    /// Paper 73B pins the two answers under the list. Large type and landscape keep them in the
    /// scrolling content so the list stays in reach.
    private var pinsActions: Bool { !typeSize.isAccessibilitySize && verticalSizeClass != .compact }
    /// A payment recorded on this phone and still waiting to reach the server.
    private var hasQueuedPayment: Bool {
        outbox.entries.contains { entry in
            guard entry.actorId == scope.actorID, entry.organizationId == scope.organizationID else { return false }
            if case .payment = entry.action { return true }
            return false
        }
    }

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
                            // Paper 73A/73B: the 34 Bold heading sits in the content, so the bar
                            // shows no words. The title stays set for VoiceOver and the tests.
                            ThorbisToolbarItem(placement: .principal) {
                                Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                            }
                            // Paper 73A/73B: the back circle alone at the leading edge; "Keep working"
                            // under the list is the other way out.
                            ThorbisToolbarItem(placement: .topBarLeading) {
                                ThorbisBackButton(action: { close() }).accessibilityIdentifier("saved-work-done")
                            }
                        }
                }
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
        // Paper P4 Confirm: the question, what happens, then Cancel beside the red "Discard".
        .thorbisConfirm(item: $discardID,
                        title: { _ in "Discard saved change?" },
                        message: { _ in "Only this phone's refused change is removed. The server stays unchanged; later eligible changes can retry." },
                        actions: { request in
                            [ThorbisConfirmAction("Discard", role: .destructive) {
                                _ = scope.discardCommand(request.id, session: session, api: api, media: media, outbox: outbox)
                            }]
                        })
    }

    private var review: some View {
        let state = snapshot
        let refused = rejectedCount(state)
        let total = state.totalCount
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Paper 73A / 73B: a 34 Bold heading and one 15 muted line that counts. Refused
                // changes lead ("Needs your attention"); otherwise it is the outbox.
                PaperPageTitle(title: refused > 0 ? "Needs your attention" : "Saved on this phone",
                               subtitle: refused > 0 ? "\(refused) \(refused == 1 ? "change" : "changes") could not be saved"
                                   : (total > 0 ? "\(total) \(total == 1 ? "thing" : "things") waiting to send"
                                                : "Review saved changes, photos and scans by job."),
                               columnInset: PaperCardMetrics.margin)
                    .padding(.bottom, 4)
                if !pinsActions {
                    actionButtons.padding(.top, 12)
                }
                Group {
                    if session.isOffline {
                        Label("Offline · work stays saved on this phone", systemImage: "wifi.slash")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .padding(.top, 12)
                    } else if busy {
                        Label("Syncing saved work", systemImage: "arrow.triangle.2.circlepath")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .padding(.top, 12)
                    } else if !editable {
                        Text("You can review saved work. Your current access doesn't allow retrying or discarding changes.")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .padding(.top, 12)
                    }
                    if state.hasListingWarning {
                        Label("The list may be incomplete. Saved work has not been cleared.", systemImage: "exclamationmark.triangle")
                            .font(Theme.font(14)).foregroundStyle(Theme.foreground)
                            .padding(.top, 12)
                    }
                    #if DEBUG
                    if PaperPreview.showSavedWorkControls { SavedWorkPreviewControls().padding(.top, 12) }
                    #endif
                }
                .padding(.horizontal, 4)
                if state.groups.isEmpty {
                    Text(state.isSending ? "Waiting for the current sync to finish." : "No pending items listed for this workspace.")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4).padding(.top, 12)
                        .accessibilityIdentifier("saved-work-empty")
                }
                // One card per job (radius 20, 12 apart), its name on top, the saved items under it.
                ForEach(state.groups) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        groupHeader(group)
                            .padding(.horizontal, PaperCardMetrics.inset).padding(.top, 14).padding(.bottom, 4)
                        ForEach(group.rows) { row in
                            WellDivider()
                            workRow(row)
                                .padding(.horizontal, PaperCardMetrics.inset)
                        }
                        if group.rows.contains(where: \.isMedia) {
                            Text("For previews, tags and file retries, open this job's Photos tab.")
                                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, PaperCardMetrics.inset).padding(.bottom, 12)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelBackground()
                    .padding(.top, 12)
                }
                // Paper's footnote under the list. Left out while a payment recorded on this phone
                // is still waiting here, so the line never contradicts the list above it.
                if total > 0 && !hasQueuedPayment {
                    Text(refused > 0 ? "Money never moves while you are offline." : "Payments are never taken while you are offline.")
                        .font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4).padding(.top, 12)
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 24)
            .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("saved-work-review")
        .accessibilityValue("\(total) items listed")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if pinsActions {
                actionButtons
                    .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 16).padding(.bottom, 8)
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
                    .background(Theme.canvas)
            }
        }
        .background(Theme.canvas).foregroundStyle(Theme.foreground)
    }

    /// Paper 73B's two answers: "Send now" on the brand pill, "Keep working" on the fill pill under
    /// it. Both 50 tall, 8 apart.
    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button { startSync() } label: {
                ZStack {
                    Text("Send now")
                    if busy { HStack { ProgressView().tint(.white); Spacer() } }
                }
                .inkCommit()
            }
            .buttonStyle(PressStyle())
            .disabled(!editable || session.isOffline || busy)
            .accessibilityIdentifier("saved-work-sync")
            Button { close() } label: {
                Text("Keep working").font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                    .frame(maxWidth: .infinity).frame(minHeight: Theme.commitHeight)
                    .background(Theme.fill, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("saved-work-keep-working")
        }
    }

    /// Changes the server refused: what "could not be saved" counts.
    private func rejectedCount(_ state: SavedWorkSnapshot) -> Int {
        var count = 0
        for group in state.groups {
            for row in group.rows {
                if case .rejected = row.state { count += 1 }
            }
        }
        return count
    }

    @ViewBuilder private func groupHeader(_ group: SavedWorkGroup) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) { jobTitle(group); openJob(group) }
        } else {
            HStack(alignment: .top, spacing: 12) { jobTitle(group); Spacer(minLength: 8); openJob(group) }
        }
    }
    private func jobTitle(_ group: SavedWorkGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.title).font(Theme.font(16, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(group.shortReference).font(Theme.monoFont(13)).foregroundStyle(Theme.muted)
        }
    }
    @ViewBuilder
    private func openJob(_ group: SavedWorkGroup) -> some View {
        if group.jobID != OutboxEntry.organizationRecord { openJobLink(group) }
    }
    private func openJobLink(_ group: SavedWorkGroup) -> some View {
        NavigationLink(value: PaperRoute.job(group.jobID)) {
            HStack(spacing: 6) {
                Text("Open job")
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
            }
            .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.brandText)
            .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .accessibilityLabel("Open job, \(group.title), \(group.shortReference)")
        .accessibilityIdentifier("saved-work-open-\(group.jobID)")
    }
    private func workRow(_ row: SavedWorkRow) -> some View {
        let refused: Bool = {
            if case .rejected = row.state { return true }
            return false
        }()
        // Paper 73B: the words lead (no mark) and a waiting item's state trails as one 14 Medium
        // word. An item that needs review keeps its state and reason under the title (Paper 73A).
        let trailing = !row.state.needsReview && !typeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title).font(Theme.font(16, weight: .medium))
                    if row.state.needsReview {
                        Text(row.state.title).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    } else if !trailing {
                        statusWord(row)
                    }
                    if let reason = row.state.reason {
                        Text(reason).font(Theme.font(14)).foregroundStyle(refused ? Theme.destructive : Theme.muted)
                    }
                    Text(row.date.stampLabel()).font(Theme.monoFont(13)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if trailing { statusWord(row) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityValue((row.isMedia ? "Captured " : "Saved ") + row.date.stampLabel())
            if refused {
                Group {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) { recoveryButtons(row) }
                    } else {
                        HStack(spacing: 8) { recoveryButtons(row) }
                    }
                }
                .disabled(!editable || busy)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saved-work-\(row.id)")
    }

    /// A waiting item's state in Paper 73B's words: "Sending" in the brand's text colour while it
    /// goes, "Waiting for signal" in the warning tone with no connection, otherwise its own state.
    private func statusWord(_ row: SavedWorkRow) -> some View {
        let sending = row.state == .uploading
        let noSignal = session.isOffline && (row.state == .waitingToSync || row.state == .waitingToUpload)
        let word = sending ? "Sending" : (noSignal ? "Waiting for signal" : row.state.title)
        return Text(word).font(Theme.font(14, weight: .medium))
            .foregroundStyle(sending ? Theme.brandText : (noSignal ? Theme.warning : Theme.muted))
    }

    /// Paper 73A: the two answers as pills, the quieter one on the field fill.
    @ViewBuilder private func recoveryButtons(_ row: SavedWorkRow) -> some View {
        Button { retryCommand(row.originalID) } label: {
            Text("Retry").font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.brandText)
                .padding(.horizontal, 18).frame(minWidth: 44, minHeight: 44)
                .background(Theme.brandSurface, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Retry \(row.title)")
        .accessibilityIdentifier("saved-work-retry-\(row.originalID)")
        Button(role: .destructive) { if editable { discardID = DiscardRequest(id: row.originalID) } } label: {
            Text("Dismiss").font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.foreground)
                .padding(.horizontal, 18).frame(minWidth: 44, minHeight: 44)
                .background(Theme.fill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
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
