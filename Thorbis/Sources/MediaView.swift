import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import VisionKit
import AVFoundation

private struct JobMediaReadScope: Hashable {
    let actor: String
    let organization: String
    let job: String
    let sessionGeneration: UUID
    let authorityRevision: UUID
    let policy: Int
    let requestGeneration: UUID
    let origin: String
}

private struct JobMediaPageValidationError: LocalizedError {
    var errorDescription: String? { "Media could not be verified. Refresh this job and try again." }
}

enum JobMediaPageIntegrity {
    static func validate(_ page: JobMediaPage, jobID: String, organizationID: String, seen: Set<String>, existing: [MediaAssetRecord] = []) throws {
        let prior = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard Set(page.items.map(\.id)).count == page.items.count,
              page.items.allSatisfy({ $0.jobId == jobID && $0.organizationId == organizationID && !$0.archived && (prior[$0.id] == nil || prior[$0.id] == $0) }),
              page.nextCursor.map({ !$0.isEmpty && !seen.contains($0) }) ?? true else {
            throw JobMediaPageValidationError()
        }
    }
}

/// A capture the job screen's toolkit asked for (Photo, Scan, Measure). The media screen opens it
/// once, as soon as its capture context is ready, then clears the request.
enum JobMediaLaunch: Equatable {
    /// The camera, filing the photo under this stage ("Before", "After") when given.
    case camera(stage: String?)
    case scan
    case measure
}

struct JobMediaView: View {
    let jobID: String
    /// One-shot capture request from the job screen; nil leaves the screen as it opens today.
    var launch: Binding<JobMediaLaunch?> = .constant(nil)
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionController
    @EnvironmentObject var pendingMedia: PendingMediaStore
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var records: [MediaAssetRecord] = []
    @State private var sourceScope: JobMediaReadScope?
    @State private var nextCursor: String?
    @State private var seenCursors = Set<String>()
    @State private var pageRequest = UUID()
    @State private var loadingMore = false
    @State private var pageError: String?
    @State private var pageErrorScope: JobMediaReadScope?
    @State private var retryPage = false
    @State private var previewScope: JobMediaReadScope?
    @State private var previewRecord: MediaAssetRecord?
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
    /// A server change in flight (tag, archive, a file being prepared). Never blocks the camera.
    @State private var busy = false
    /// Uploads running in the background. Capture, tagging and launch never wait on this.
    @State private var draining = false
    @State private var error: String?
    @StateObject private var preview = DocumentPreviewController()
    @State private var importDocument = false
    @State private var showLibrary = false
    /// Camera access is off in Settings; the notice above the capture buttons says so.
    @State private var cameraDenied = false
    @State private var showScanner = false
    @State private var showLegacyRecovery = false
    /// Markup opened from the "just taken" suggestion.
    @State private var captureMarkup: PhotoMarkupTarget?
    /// The bounded JPEG last saved from the camera or library, offered for markup.
    @State private var justCaptured: PhotoMarkupTarget?
    @State private var showMeasure = false
    /// A short clip (60 s at most) recorded with the system camera, filed under Documents.
    @State private var showVideo = false
    @State private var videoNotice: String?
    /// The stage the quick tag step preselects ("Before", "After", "Other"). Paper 21C.
    @State private var stage = "Before"
    @State private var filter: MediaFilter = .all
    @State private var capture: MediaCaptureRequest?
    @State private var viewer: MediaViewerStart?
    @State private var showCompare = false
    @State private var selecting = false
    @State private var picked = Set<String>()
    @State private var confirmBulkArchive = false
    @State private var shareFiles: MediaShareFiles?
    @State private var contentWidth: CGFloat = 353
    #if DEBUG
    @State private var previewStateApplied = false
    #endif

    /// Photos taken but not yet confirmed by the server; kept on disk until they are.
    private var currentPendingContext: PendingMediaStore.CaptureContext? {
        guard let scope = readScope else { return nil }
        return pendingMedia.captureContext(matching: PendingMediaScope(actorID: scope.actor, organizationID: scope.organization, origin: scope.origin))
    }
    private var waiting: [PendingMedia] {
        guard currentPendingContext != nil else { return [] }
        return pendingMedia.items.filter { $0.jobID == jobID }
    }
    private var canShowSelection: Bool {
        guard let captureContext, let currentPendingContext else { return false }
        return captureContext == currentPendingContext && captureGeneration == api.requestGeneration && captureOrigin == api.normalizedOrigin
    }
    private var readScope: JobMediaReadScope? {
        guard session.can("job.view", feature: "jobs"), let actor = session.user?.id,
              let organization = session.activeOrganization?.id, let policy = session.policyVersion,
              let origin = api.normalizedOrigin else { return nil }
        return JobMediaReadScope(actor: actor, organization: organization, job: jobID,
                                 sessionGeneration: session.generation, authorityRevision: session.authorityRevision,
                                 policy: policy, requestGeneration: api.requestGeneration, origin: origin)
    }
    private var visible: [MediaAssetRecord] {
        guard let scope = readScope, scope == sourceScope else { return [] }
        return records.filter { !$0.archived }
    }
    private var hasMore: Bool { readScope != nil && readScope == sourceScope && nextCursor != nil }
    private var previewIsCurrent: Bool {
        guard let scope = readScope, previewScope == scope, sourceScope == scope, let record = previewRecord else { return false }
        return records.contains(record)
    }
    private var allPhotos: [MediaAssetRecord] { visible.filter { $0.kind == "photo" } }
    private var photos: [MediaAssetRecord] { allPhotos.filter { matches($0.tags) } }
    private var documents: [MediaAssetRecord] { visible.filter { $0.kind != "photo" } }
    private var waitingPhotos: [PendingMedia] { waiting.filter { $0.kind == "photo" && matches($0.tags) } }
    private var waitingDocuments: [PendingMedia] { waiting.filter { $0.kind != "photo" } }
    private var storedPhotos: [MediaAssetRecord] { photos.filter { $0.uploadState == "stored" } }
    private var befores: [MediaAssetRecord] { allPhotos.filter { $0.uploadState == "stored" && $0.tags.contains("Before") } }
    private var afters: [MediaAssetRecord] { allPhotos.filter { $0.uploadState == "stored" && $0.tags.contains("After") } }
    private var showsPhotos: Bool { filter != .documents }
    private var showsDocuments: Bool { filter == .all || filter == .documents }
    private var canAdd: Bool { session.can("job.edit", feature: "jobs") }
    private var pickedRecords: [MediaAssetRecord] { storedPhotos.filter { picked.contains($0.id) } }

    private func matches(_ tags: [String]) -> Bool {
        switch filter {
        case .before: tags.contains("Before")
        case .after: tags.contains("After")
        case .untagged: !tags.contains("Before") && !tags.contains("After")
        case .all, .documents: true
        }
    }

    /// Camera, scanner, measure and video availability. The simulator has none; a DEBUG screenshot
    /// flag shows the full bar so it can be reviewed.
    private var tools: (camera: Bool, scan: Bool, measure: Bool, video: Bool) {
        #if DEBUG
        if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-media-all-tools") { return (true, true, true, true) }
        #endif
        return (UIImagePickerController.isSourceTypeAvailable(.camera), VNDocumentCameraViewController.isSupported,
                SiteMeasure.isSupported, VideoCapture.isAvailable)
    }

    /// Photos screen (2026-10-31 redesign): one selector, a square-thumbnail grid with each photo's
    /// stage and upload state, documents as rows, and one ink "Take photo" with quiet circles beside.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                notices
                selectorRow
                if loading || (previewIsCurrent && preview.loading) { SkeletonRows(count: 2, inset: 0) }
                selectedFileRow
                waitingSummary
                if canAdd && dynamicTypeSize.isAccessibilitySize && !selecting {
                    captureControls.padding(.top, 4)
                }
                justCapturedRow
                emptyStates
                if showsPhotos { photoSections }
                if showsDocuments { documentSection }
                loadMoreRow
                if canAdd && !(allPhotos.isEmpty && documents.isEmpty) {
                    Text(videoNotice ?? "Photos, PDFs and video clips up to 8 MB.").font(Theme.font(12)).foregroundStyle(Theme.muted).padding(.top, 4)
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 24)
            .onGeometryChange(for: CGFloat.self) { $0.size.width - Theme.gutter * 2 } action: { contentWidth = $0 }
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            if selecting {
                selectionBar
            } else if canAdd && !dynamicTypeSize.isAccessibilitySize {
                captureControls
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
        .fullScreenCover(isPresented: $showVideo) {
            VideoCapture { url in
                showVideo = false
                guard let url else { return }
                Task { await addVideo(url) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $capture) { request in
            MediaCaptureFlow(request: request, file: { data, tags, caption in
                try filePhoto(data, tags: tags, caption: caption)
            }, fileMarkup: { image, tags in
                try enqueueDerived(image, tags: tags, caption: "Marked up", prefix: "markup")
            }, onStage: { stage = $0 }, onClose: { capture = nil })
        }
        .fullScreenCover(item: $viewer) { start in
            MediaPhotoViewer(records: storedPhotos, start: start.id, canEdit: canAdd, currentUserID: session.user?.id,
                             load: { try await download($0) },
                             retag: { await retag($0, $1) },
                             archive: { await archive([$0]) },
                             fileMarkup: { image, tags in try enqueueDerived(image, tags: tags, caption: "Marked up", prefix: "markup") },
                             onClose: { viewer = nil })
        }
        .fullScreenCover(isPresented: $showCompare) {
            MediaCompareView(befores: befores, afters: afters, load: { try await download($0) }) { showCompare = false }
        }
        .task(id: readScope) {
            if captureContext == nil {
                captureContext = pendingMedia.captureContext
                captureGeneration = api.requestGeneration
                captureOrigin = api.normalizedOrigin
            }
            pendingMedia.reload()
            consumeLaunch()
            await load()
            if readScope != nil && !waiting.isEmpty { await retryWaiting() }
            #if DEBUG
            applyPreviewState()
            #endif
        }
        .onChange(of: launch.wrappedValue) { _, _ in consumeLaunch() }
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
                        // A library photo goes through the same quick tag step as a new one.
                        guard let jpeg = Self.jpeg(image) else { throw MediaSelectionError.tooLarge }
                        capture = MediaCaptureRequest(mode: .library, stage: stage, held: jpeg)
                    } else {
                        let type = item.supportedContentTypes.first ?? .jpeg
                        try select(data, mime: type.preferredMIMEType ?? "image/jpeg", filename: "photo." + (type.preferredFilenameExtension ?? "jpg"))
                        enqueueSelection()
                    }
                } catch { self.error = error.localizedDescription }
            }
        }
        .photosPicker(isPresented: $showLibrary, selection: $selection, matching: .images)
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
        // Documents and clips keep the system preview.
        .sheet(isPresented: Binding(get: { previewIsCurrent && preview.url != nil }, set: { if !$0 { preview.clear(); previewScope = nil; previewRecord = nil } })) {
            if previewIsCurrent, let file = preview.url {
                NativeDocumentPreview(url: file).accessibilityIdentifier("job-media-preview")
            }
        }
        .fullScreenCover(item: $captureMarkup) { target in
            markupCover(target, cancel: { captureMarkup = nil }) { captureMarkup = nil; justCaptured = nil }
        }
        .fullScreenCover(isPresented: $showMeasure) {
            SiteMeasureView(onSave: { image, caption in
                // A measurement is filed with no stage; tag it from the grid if it belongs to one.
                try enqueueDerived(image, tags: [], caption: caption, prefix: "measure")
                showMeasure = false
            }, onClose: { showMeasure = false })
        }
        .thorbisConfirm(pickedRecords.count == 1 ? "Remove this photo from the job?" : "Remove \(pickedRecords.count) photos from the job?",
                        message: "They’re archived, not erased: the office can still restore them.",
                        isPresented: $confirmBulkArchive,
                        actions: [ThorbisConfirmAction(pickedRecords.count == 1 ? "Remove photo" : "Remove photos", role: .destructive) {
                            let chosen = pickedRecords
                            Task { if await archive(chosen) { endSelecting() } }
                        }])
        .sheet(item: $shareFiles) { files in
            MediaShareSheet(urls: files.urls) {
                for url in files.urls { try? FileManager.default.removeItem(at: url) }
                shareFiles = nil
            }
        }
        .onChange(of: readScope) { _, _ in
            preview.clear(); previewScope = nil; previewRecord = nil; busy = false; justCaptured = nil; captureMarkup = nil
            viewer = nil; showCompare = false; endSelecting()
        }
        .onChange(of: records) { _, _ in if !previewIsCurrent { preview.clear(); previewScope = nil; previewRecord = nil } }
        .onDisappear { selectedData = nil; justCaptured = nil; preview.clear() }
    }

    // MARK: Sections

    @ViewBuilder private var notices: some View {
        if let error = error ?? (previewIsCurrent ? preview.error : nil) {
            ErrorBanner(message: error, retry: selectedData == nil ? nil : { enqueueSelection() })
                .padding(.horizontal, -Theme.gutter)
        }
        if let pageError, let scope = readScope, pageErrorScope == scope {
            ErrorBanner(message: pageError) {
                if retryPage && hasMore { await loadMore() } else { await load() }
            }
        }
        if readScope == nil {
            Label("Photos and documents are unavailable with your current access.", systemImage: "lock")
                .font(Theme.font(14)).foregroundStyle(Theme.muted)
        }
        if currentPendingContext != nil, let warning = pendingMedia.storageWarning { ErrorBanner(message: warning) }
        if currentPendingContext != nil && pendingMedia.legacyCount > 0 {
            ErrorBanner(message: "Older photos remain on this phone. Check this job before choosing which photos to recover.")
            Button("Recover older photos") { showLegacyRecovery = true }
                .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.brandText)
                .frame(minHeight: 44).disabled(!canAdd || busy)
        }
    }

    /// The screen's one selector, with Untagged and Select in the filter circle beside it.
    @ViewBuilder private var selectorRow: some View {
        if readScope != nil && !(allPhotos.isEmpty && documents.isEmpty && waiting.isEmpty && !hasMore) {
            HStack(spacing: 8) {
                if dynamicTypeSize.isAccessibilitySize {
                    ThorbisMenu(items: (MediaFilter.selector + [.untagged]).map { option in
                        ThorbisMenuItem(option.rawValue, isSelected: filter == option) { filter = option; endSelecting() }
                    }, title: "Show") {
                        Label("Show · \(filter.rawValue)", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.body.weight(.medium)).foregroundStyle(Theme.foreground)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("photo-filter-menu")
                } else {
                    ThorbisSegmented(options: MediaFilter.selector.map { ($0, $0.rawValue) },
                                     selection: Binding(get: { filter == .untagged ? .all : filter },
                                                        set: { filter = $0; if $0 == .documents { endSelecting() } }))
                        .accessibilityIdentifier("job-media-selector")
                    ThorbisMenu(items: filterMenuItems, title: "Photos", accessibilityLabel: "More photo options") {
                        PaperCircleLabel(symbol: "line.3.horizontal.decrease", size: 44,
                                         fill: filter == .untagged ? Theme.brandSurface : Theme.fill)
                    }
                    .accessibilityValue(filter == .untagged ? "Showing untagged photos" : "")
                    .accessibilityIdentifier("photo-filter-menu")
                }
            }
        }
    }

    private var filterMenuItems: [ThorbisMenuItem] {
        var items = [
            ThorbisMenuItem("All photos", icon: "square.grid.3x3", isSelected: filter == .all) { filter = .all },
            ThorbisMenuItem("Untagged photos", icon: "tag.slash", subtitle: "\(allPhotos.filter { mediaStageWord($0.tags) == nil }.count) loaded",
                            isSelected: filter == .untagged) { filter = .untagged },
        ]
        if canAdd && !storedPhotos.isEmpty {
            items.append(ThorbisMenuItem("Select photos", icon: "checkmark.circle") { startSelecting() })
        }
        if !befores.isEmpty && !afters.isEmpty {
            items.append(ThorbisMenuItem("Compare before and after", icon: "rectangle.split.2x1") { showCompare = true })
        }
        return items
    }

    @ViewBuilder private var selectedFileRow: some View {
        if let selectedData, canShowSelection {
            JobPanel {
                MediaDocumentRow(title: selectedFilename,
                                 detail: ByteCountFormatter.string(fromByteCount: Int64(selectedData.count), countStyle: .file) + " · not saved yet",
                                 state: .stored)
                    .overlay(alignment: .trailing) {
                        Button("Discard", role: .destructive) { self.selectedData = nil; selection = nil }
                            .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.destructive)
                            .frame(minWidth: 44, minHeight: 44).padding(.trailing, 12).disabled(busy)
                    }
            }
        }
    }

    /// One calm line for everything saved on this phone and not on the server yet.
    @ViewBuilder private var waitingSummary: some View {
        if !waiting.isEmpty {
            let failed = waiting.filter { if case .failed = MediaUploadState.of($0, in: pendingMedia) { true } else { false } }.count
            let offline = session.isOffline || waiting.contains { pendingMedia.waitingForConnection.contains($0.id) }
            JobPanel {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(waiting.count) saved on this phone").font(Theme.font(16, weight: .medium)).monospacedDigit()
                        Text(pendingMedia.uploadingID != nil ? "Sending now…"
                             : failed > 0 ? "\(failed) couldn’t send. Tap one to see why."
                             : offline ? "They send by themselves when you’re back online."
                             : "Waiting to send.")
                            .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 8)
                    if pendingMedia.uploadingID == nil && !session.isOffline {
                        Button("Send now") { Task { await retryWaiting() } }
                            .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(Theme.fill, in: Capsule())
                            .buttonStyle(PressStyle())
                            .disabled(draining || !canAdd)
                            .accessibilityIdentifier("job-media-send-now")
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder private var justCapturedRow: some View {
        if let justCaptured, canAdd, !selecting {
            JobPanel {
                HStack(spacing: 8) {
                    Button { captureMarkup = justCaptured } label: {
                        Label("Mark up the photo you just took", systemImage: "pencil.tip.crop.circle")
                            .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("markup-just-captured")
                    Button { self.justCaptured = nil } label: {
                        Image(systemName: "xmark").foregroundStyle(Theme.muted).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss markup suggestion")
                }
                .padding(.leading, 16).padding(.trailing, 6)
            }
        }
    }

    @ViewBuilder private var emptyStates: some View {
        // One empty state for the whole tab instead of two empty sections.
        if allPhotos.isEmpty && documents.isEmpty && waiting.isEmpty && (currentPendingContext == nil || (pendingMedia.legacyCount == 0 && pendingMedia.storageWarning == nil)) && !loading && !hasMore && pageError == nil && readScope == sourceScope && readScope != nil {
            PaperEmptyState(symbol: "camera", title: "No photos yet",
                            message: canAdd ? "Take a before photo when you arrive. Photos, PDFs and clips up to 8 MB." : nil)
        } else if !loading && showsPhotos && (!allPhotos.isEmpty || hasMore || !waiting.isEmpty) && photos.isEmpty && waitingPhotos.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Text(hasMore ? "No matches in loaded photos. More may be available." : "No matching photos").foregroundStyle(Theme.muted)
                    Spacer(minLength: 0)
                    Button("Show all photos") { filter = .all }.frame(minHeight: 44)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(hasMore ? "No matches in loaded photos. More may be available." : "No matching photos").foregroundStyle(Theme.muted)
                    Button("Show all photos") { filter = .all }.frame(minHeight: 44)
                }
            }
            .font(.subheadline)
            .tint(Theme.brandText)
            .frame(minHeight: 44)
            if hasMore {
                Button(loadingMore ? "Loading…" : "Load more") { Task { await loadMore() } }
                    .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.brandText)
                    .frame(minHeight: 44).disabled(loadingMore || loading)
                    .accessibilityIdentifier("job-media-load-more-matches")
            }
        }
    }

    private var gridColumns: [GridItem] {
        let count = MediaGridMetrics.columns(width: contentWidth, accessibility: dynamicTypeSize.isAccessibilitySize)
        return Array(repeating: GridItem(.flexible(), spacing: MediaGridMetrics.spacing), count: count)
    }

    @ViewBuilder private var photoSections: some View {
        if !waitingPhotos.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                JobPanelLabel(title: "On this phone", count: "\(waitingPhotos.count)")
                LazyVGrid(columns: gridColumns, spacing: MediaGridMetrics.spacing) {
                    ForEach(waitingPhotos) { media in pendingTile(media) }
                }
            }
        }
        if !photos.isEmpty {
            let groups = JobPhotoDateGroups.group(photos, calendar: calendar)
            ForEach(Array(groups.enumerated()), id: \.element.day) { index, group in
                VStack(alignment: .leading, spacing: 6) {
                    photoGroupLabel(group, first: index == 0)
                    LazyVGrid(columns: gridColumns, spacing: MediaGridMetrics.spacing) {
                        ForEach(group.photos) { record in recordTile(record) }
                    }
                }
            }
        }
    }

    private func photoGroupLabel(_ group: JobPhotoDateGroups.Group, first: Bool) -> some View {
        let day = group.day.map(photoDayLabel) ?? "Date unavailable"
        let title = "\(day) · \(group.photos.count)"
        return HStack(spacing: 8) {
            Text(title).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted).monospacedDigit()
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if first && canAdd && !storedPhotos.isEmpty {
                Button(selecting ? "Done" : "Select") { if selecting { endSelecting() } else { startSelecting() } }
                    .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(selecting ? Theme.brandSurface : Theme.fill, in: Capsule())
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("job-media-select")
            }
            if first && !selecting && !befores.isEmpty && !afters.isEmpty {
                Button { showCompare = true } label: {
                    Label("Compare", systemImage: "rectangle.split.2x1")
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(Theme.fill, in: Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("job-media-compare")
            }
        }
        .frame(minHeight: 44)
    }

    private func recordTile(_ record: MediaAssetRecord) -> some View {
        let stored = record.uploadState == "stored"
        let isPicked = picked.contains(record.id)
        return Button {
            if selecting {
                guard stored else { return }
                if isPicked { picked.remove(record.id) } else { picked.insert(record.id) }
            } else {
                open(record)
            }
        } label: {
            MediaTile(stage: mediaStageWord(record.tags), state: .of(record), selecting: selecting && stored, selected: isPicked) {
                MediaThumbnail(record: record, attempt: thumbnailAttempt)
            }
        }
        .buttonStyle(PressStyle())
        .disabled(!stored || (!selecting && preview.loading))
        .accessibilityLabel("Photo, \(record.caption ?? record.originalFilename)")
        .accessibilityValue([mediaStageWord(record.tags), MediaUploadState.of(record).word, selecting ? (isPicked ? "Selected" : "Not selected") : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier("job-media-photo-\(record.id)")
    }

    @ViewBuilder private func pendingTile(_ media: PendingMedia) -> some View {
        let state = MediaUploadState.of(media, in: pendingMedia)
        let tile = MediaTile(stage: mediaStageWord(media.tags), state: state) { PendingMediaThumbnail(media: media) }
        Group {
            if case .failed(let reason) = state {
                ThorbisMenu(items: [
                    ThorbisMenuItem("Try sending again", icon: "arrow.clockwise", subtitle: reason) { Task { await retryWaiting() } },
                ], title: "Couldn’t send this photo", accessibilityLabel: "\(media.title), failed to send") { tile }
                    .disabled(draining || !canAdd)
            } else {
                tile
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pending-media-\(media.id)")
        .accessibilityValue(Text("\(state.word ?? "") · captured \(media.capturedAt.formatted(date: .abbreviated, time: .shortened))"))
    }

    @ViewBuilder private var documentSection: some View {
        if !documents.isEmpty || !waitingDocuments.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                JobPanelLabel(title: hasMore ? "Documents loaded" : "Documents", count: "\(documents.count + waitingDocuments.count)")
                JobPanel {
                    ForEach(waitingDocuments) { media in
                        let state = MediaUploadState.of(media, in: pendingMedia)
                        Group {
                            if case .failed(let reason) = state {
                                ThorbisMenu(items: [ThorbisMenuItem("Try sending again", icon: "arrow.clockwise", subtitle: reason) { Task { await retryWaiting() } }],
                                            title: "Couldn’t send this file") {
                                    MediaDocumentRow(title: media.title, detail: pendingDetail(media), state: state)
                                }
                            } else {
                                MediaDocumentRow(title: media.title, detail: pendingDetail(media), state: state)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("pending-media-\(media.id)")
                        .accessibilityValue(Text("Captured \(media.capturedAt.formatted(date: .abbreviated, time: .shortened))"))
                    }
                    ForEach(documents) { record in
                        Button { open(record) } label: {
                            MediaDocumentRow(title: record.originalFilename, detail: documentDetail(record), state: .of(record))
                        }
                        .buttonStyle(RowPressStyle())
                        .disabled(busy || preview.loading || record.uploadState != "stored")
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var loadMoreRow: some View {
        if hasMore {
            VStack(alignment: .leading, spacing: 4) {
                Text("More photos and documents may be available. Counts and filters apply to loaded items.")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
                Button(loadingMore ? "Loading…" : "Load more") { Task { await loadMore() } }
                    .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.brandText)
                    .frame(minHeight: 44).disabled(loadingMore || loading)
                    .accessibilityIdentifier("job-media-load-more")
            }
        }
    }

    private func documentDetail(_ record: MediaAssetRecord) -> String {
        let kind = record.kind == "video" ? "Video clip" : "PDF"
        let size = ByteCountFormatter.string(fromByteCount: Int64(record.sizeBytes), countStyle: .file)
        let day = record.capturedAt.flatMap { JobFiltering.isoFractional.date(from: $0) ?? JobFiltering.isoPlain.date(from: $0) }
        return [kind, size, day.map(photoDayLabel)].compactMap { $0 }.joined(separator: " · ")
    }

    private func pendingDetail(_ media: PendingMedia) -> String {
        let kind = media.kind == "video" ? "Video clip" : "PDF"
        if pendingMedia.unverifiedIDs.contains(media.id), pendingMedia.errors[media.id] == nil { return "\(kind) · saved copy not yet verified" }
        return "\(kind) · saved on this phone \(media.capturedAt.tradeTime)"
    }

    // MARK: Bars

    /// One ink "Take photo", with Burst, Scan, Measure, Video and Import as quiet circles above it.
    private var captureControls: some View {
        let tools = tools
        return VStack(spacing: 10) {
            if cameraDenied {
                PermissionNotice(permission: .camera, purpose: "add photos to jobs", outer: 0)
            }
            HStack(spacing: 0) {
                if tools.camera {
                    toolCircle("Burst", symbol: "square.stack.3d.down.right", identifier: "job-media-burst",
                               hint: "Keeps the camera open for many shots. Tag them later.") { openCamera(.burst) }
                }
                toolCircle("Scan", symbol: "doc.viewfinder", identifier: "job-media-scan",
                           hint: tools.scan ? "Scan a paper document into a PDF." : "Choose a PDF to add.") {
                    if tools.scan { showScanner = true } else { importDocument = true }
                }
                if tools.measure {
                    toolCircle("Measure", symbol: "ruler", identifier: "job-media-measure",
                               hint: "Measure a distance with the camera and add it to this job as a photo.") { showMeasure = true }
                }
                if tools.video {
                    toolCircle("Video", symbol: "video", identifier: "job-media-video", hint: "Record a clip of up to 60 seconds.") { showVideo = true }
                }
                VStack(spacing: 3) {
                    ThorbisMenu(items: [
                        ThorbisMenuItem("Choose a photo", icon: "photo.on.rectangle") { showLibrary = true },
                        ThorbisMenuItem("Choose a PDF", icon: "doc") { importDocument = true },
                    ] + (tools.scan ? [ThorbisMenuItem("Scan a document", icon: "doc.viewfinder") { showScanner = true }] : []),
                                title: "Add from this phone", accessibilityLabel: "Import a photo or PDF") {
                        PaperCircleLabel(symbol: "square.and.arrow.down", size: 48)
                    }
                    .accessibilityIdentifier("job-media-import")
                    Text("Import").font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
            }
            Button { openCamera(.single) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera")
                    Text("Take photo")
                }
                .inkCommit(height: 56)
            }
            .buttonStyle(PressStyle())
            .disabled(!tools.camera)
            .accessibilityIdentifier("job-media-take-photo")
        }
    }

    private func toolCircle(_ title: String, symbol: String, identifier: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                PaperCircleLabel(symbol: symbol, size: 48)
                Text(title).font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }

    /// Bulk actions on picked photos: stage them, share them, or remove them.
    private var selectionBar: some View {
        let count = pickedRecords.count
        return VStack(spacing: 10) {
            HStack {
                Text(count == 0 ? "Tap photos to choose them" : "\(count) chosen")
                    .font(Theme.font(15, weight: .medium)).monospacedDigit()
                Spacer()
                Button(count == storedPhotos.count ? "Clear" : "Choose all") {
                    picked = count == storedPhotos.count ? [] : Set(storedPhotos.map(\.id))
                }
                .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground).frame(minHeight: 44)
                .accessibilityIdentifier("job-media-choose-all")
            }
            HStack(spacing: 8) {
                MediaQuietButton(title: "Before") { Task { await retagPicked(.before) } }
                MediaQuietButton(title: "After") { Task { await retagPicked(.after) } }
                MenuOrCircle(symbol: "tag.slash", label: "No stage") { Task { await retagPicked(.other) } }
                MenuOrCircle(symbol: "square.and.arrow.up", label: "Share") { Task { await sharePicked() } }
                MenuOrCircle(symbol: "trash", label: "Remove") { confirmBulkArchive = true }
                    .accessibilityIdentifier("job-media-remove-picked")
            }
            .disabled(count == 0 || busy)
            if busy { ProgressView().frame(height: 20) }
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 10).padding(.bottom, 8)
        .background(Theme.background)
    }

    // MARK: Actions

    /// The camera, or, when it is turned off for Thorbis, the notice that says so with Open Settings.
    private func openCamera(_ mode: MediaCaptureMode) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        cameraDenied = [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video))
        if !cameraDenied { capture = MediaCaptureRequest(mode: mode, stage: stage) }
    }

    /// Opens what the job screen's toolkit asked for, with the same checks as the buttons below.
    private func consumeLaunch() {
        guard let request = launch.wrappedValue, captureContext != nil else { return }
        launch.wrappedValue = nil
        guard canAdd, readScope != nil else { return }
        switch request {
        case .camera(let requested):
            if let requested, ["Before", "After", "Other"].contains(requested) { stage = requested }
            openCamera(.single)
        case .scan:
            if VNDocumentCameraViewController.isSupported { showScanner = true } else { importDocument = true }
        case .measure:
            if SiteMeasure.isSupported { showMeasure = true }
        }
    }

    private func startSelecting() {
        filter = filter == .documents ? .all : filter
        picked = []
        justCaptured = nil
        withMotion(.easeOut(duration: 0.2)) { selecting = true }
    }

    private func endSelecting() {
        picked = []
        withMotion(.easeOut(duration: 0.2)) { selecting = false }
    }

    private func select(_ data: Data, mime: String, filename: String) throws {
        guard !data.isEmpty, data.count <= 8 * 1024 * 1024 else { throw MediaSelectionError.tooLarge }
        guard ["image/jpeg", "image/png", "image/heic", "image/webp", "application/pdf", "video/mp4"].contains(mime) else { throw MediaSelectionError.unsupported }
        selectedData = data
        selectedMime = mime
        selectedFilename = filename
        clientAssetID = UUID().uuidString
        selectedCapturedAt = Date()
        error = nil
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

    private func retag(_ record: MediaAssetRecord, _ stage: MediaStage) async {
        guard let scope = readScope, sourceScope == scope else { return }
        do {
            let updated = try await api.tagFieldMedia(record.id, tags: MediaStageTags.applying(stage, to: record.tags), caption: record.caption)
            guard readScope == scope, sourceScope == scope, updated.id == record.id, records.contains(where: { $0.id == record.id }),
                  updated.jobId == jobID, updated.organizationId == scope.organization else { return }
            if let index = records.firstIndex(where: { $0.id == updated.id }) { records[index] = updated }
            error = nil
        } catch is CancellationError {
        } catch {
            guard readScope == scope, sourceScope == scope else { return }
            self.error = error.localizedDescription
        }
    }

    private func retagPicked(_ stage: MediaStage) async {
        let chosen = pickedRecords
        guard !chosen.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        for record in chosen {
            guard readScope != nil else { return }
            await retag(record, stage)
            if error != nil { return }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        endSelecting()
    }

    /// Archives each record on the server, removing it from the grid once the server confirms.
    /// Returns true when every one was archived.
    private func archive(_ chosen: [MediaAssetRecord]) async -> Bool {
        guard let scope = readScope, sourceScope == scope, canAdd else { return false }
        busy = true
        defer { if readScope == scope { busy = false } }
        for record in chosen {
            do {
                let updated = try await api.archiveFieldMedia(record.id)
                guard readScope == scope, sourceScope == scope, updated.id == record.id, updated.archived,
                      updated.jobId == jobID, updated.organizationId == scope.organization else {
                    if readScope == scope { error = "The server didn’t confirm that this photo was removed. Refresh and check." }
                    return false
                }
                records.removeAll { $0.id == record.id }
                picked.remove(record.id)
            } catch is CancellationError {
                return false
            } catch {
                if readScope == scope { self.error = error.localizedDescription }
                return false
            }
        }
        error = nil
        return true
    }

    /// Downloads the picked photos and opens the share sheet; the copies are deleted afterwards.
    private func sharePicked() async {
        let chosen = pickedRecords
        guard !chosen.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        var urls: [URL] = []
        do {
            for record in chosen { urls.append(try await download(record)) }
            shareFiles = MediaShareFiles(urls: urls)
        } catch {
            for url in urls { try? FileManager.default.removeItem(at: url) }
            if !(error is CancellationError) { self.error = error.localizedDescription }
        }
    }

    /// The full file for a stored record, bound to the scope the screen is showing.
    private func download(_ record: MediaAssetRecord) async throws -> URL {
        guard let scope = readScope, sourceScope == scope, records.contains(where: { $0.id == record.id }), record.uploadState == "stored" else {
            throw CancellationError()
        }
        #if DEBUG
        if PaperPreview.enabled, let sample = MediaSample.file(caption: record.caption ?? record.originalFilename, tags: record.tags) { return sample }
        #endif
        let file = try await MediaTransfer(api: api).download(mediaID: record.id, filename: record.originalFilename)
        guard !Task.isCancelled, readScope == scope, sourceScope == scope else {
            try? FileManager.default.removeItem(at: file)
            throw CancellationError()
        }
        return file
    }

    private func load() async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        pageRequest = request
        guard let scope = readScope else {
            records = []; sourceScope = nil; nextCursor = nil; seenCursors = []; pageError = nil; pageErrorScope = nil; loading = false; loadingMore = false
            return
        }
        if sourceScope != scope { records = []; sourceScope = nil; nextCursor = nil; seenCursors = [] }
        loading = true
        loadingMore = false
        defer { if pageRequest == request { loading = false } }
        do {
            let page = try await api.fieldMediaPage(jobID)
            guard !Task.isCancelled, pageRequest == request, readScope == scope else { return }
            try JobMediaPageIntegrity.validate(page, jobID: scope.job, organizationID: scope.organization, seen: [])
            records = page.items; sourceScope = scope; nextCursor = page.nextCursor
            seenCursors = Set(page.nextCursor.map { [$0] } ?? [])
            pageError = nil; pageErrorScope = nil
        } catch is CancellationError {
        } catch {
            guard pageRequest == request, readScope == scope else { return }
            pageError = error.localizedDescription; pageErrorScope = scope; retryPage = false
        }
    }

    private func loadMore() async {
        guard !loading, !loadingMore, let scope = readScope, sourceScope == scope, let cursor = nextCursor else { return }
        let request = UUID(); pageRequest = request; loadingMore = true
        defer { if pageRequest == request { loadingMore = false } }
        do {
            let page = try await api.fieldMediaPage(jobID, cursor: cursor)
            #if DEBUG
            if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-media-revoke-late-page") {
                PaperPreviewProtocol.revokeJobMediaView()
                await session.revalidate()
            }
            #endif
            guard !Task.isCancelled, pageRequest == request, readScope == scope, sourceScope == scope, nextCursor == cursor else { return }
            try JobMediaPageIntegrity.validate(page, jobID: scope.job, organizationID: scope.organization, seen: seenCursors, existing: records)
            var ids = Set(records.map(\.id))
            records.append(contentsOf: page.items.filter { ids.insert($0.id).inserted })
            nextCursor = page.nextCursor
            if let cursor = page.nextCursor { seenCursors.insert(cursor) }
            pageError = nil; pageErrorScope = nil
        } catch is CancellationError {
        } catch {
            guard pageRequest == request, readScope == scope else { return }
            pageError = error.localizedDescription; pageErrorScope = scope; retryPage = !(error is JobMediaPageValidationError)
        }
    }

    private func enqueueSelection() {
        guard let selectedData else { return }
        guard canAdd, captureGeneration == api.requestGeneration, captureOrigin == api.normalizedOrigin,
              let captureContext else {
            error = "Your workspace changed. Return to the original job before adding media."
            return
        }
        let kind = selectedMime == "application/pdf" ? "document" : selectedMime.hasPrefix("video/") ? "video" : "photo"
        let media = PendingMedia(id: clientAssetID, jobID: jobID, filename: selectedFilename,
            tags: kind == "photo" ? MediaStageChoice.tags(stage) : [], capturedAt: selectedCapturedAt,
            kind: kind, mime: selectedMime, caption: kind == "video" ? "Video clip" : nil)
        do {
            try pendingMedia.save(media, data: selectedData, context: captureContext)
            self.selectedData = nil
            selection = nil
            error = nil
            // The callback releases original camera/library images before awaiting networking.
            Task { await retryWaiting() }
        } catch { self.error = error.localizedDescription }
    }

    /// Saves one photo from the capture flow to the on-phone queue under its chosen stage and
    /// caption, then starts sending in the background. Original bytes are on disk first.
    private func filePhoto(_ data: Data, tags: [String], caption: String?) throws {
        guard canAdd, captureGeneration == api.requestGeneration, captureOrigin == api.normalizedOrigin,
              let captureContext else { throw MediaSelectionError.workspaceChanged }
        guard !data.isEmpty, data.count <= 8 * 1024 * 1024 else { throw MediaSelectionError.tooLarge }
        let capturedAt = Date()
        let stamp = capturedAt.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "")
        let name = (mediaStageWord(tags) ?? "photo").lowercased()
        let media = PendingMedia(id: UUID().uuidString, jobID: jobID, filename: "\(name)-\(stamp).jpg", tags: tags,
                                 capturedAt: capturedAt, kind: "photo", mime: "image/jpeg", caption: caption)
        try pendingMedia.save(media, data: data, context: captureContext)
        error = nil
        justCaptured = PhotoMarkupTarget(data: data, tags: tags)
        Task { await retryWaiting() }
    }

    /// Re-encodes a recorded clip to MP4 under the 8 MB single-upload limit, then queues it like a
    /// photo. A clip too long for the limit keeps its first part, and the screen says so.
    private func addVideo(_ source: URL) async {
        guard canAdd else { return }
        busy = true
        defer { busy = false; try? FileManager.default.removeItem(at: source) }
        do {
            let clip = try await VideoCapture.exportMP4(source)
            defer { try? FileManager.default.removeItem(at: clip.url) }
            let data = try Data(contentsOf: clip.url)
            let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "")
            try select(data, mime: "video/mp4", filename: "clip-\(stamp).mp4")
            enqueueSelection()
            videoNotice = clip.trimmedTo.map { "Video clips are limited to 8 MB, so the first \(Int($0)) seconds were kept." }
        } catch { self.error = error.localizedDescription }
    }

    private func markupCover(_ target: PhotoMarkupTarget, cancel: @escaping () -> Void, saved close: @escaping () -> Void) -> some View {
        Group {
            if let image = UIImage(data: target.data) {
                PhotoMarkupView(image: image, onSave: { flattened in
                    try enqueueDerived(flattened, tags: target.tags, caption: "Marked up", prefix: "markup")
                    close()
                }, onCancel: cancel)
            } else {
                PaperEmptyState(symbol: "photo", title: "Photo unavailable", message: "This photo could not be opened for markup.")
                    .onTapGesture(perform: cancel)
            }
        }
    }

    /// Files a new image (markup or measurement) through the same on-phone queue as a captured
    /// photo, with a fresh ID. The source photo is never changed.
    private func enqueueDerived(_ image: UIImage, tags: [String], caption: String, prefix: String) throws {
        guard canAdd, captureGeneration == api.requestGeneration, captureOrigin == api.normalizedOrigin,
              let captureContext else { throw MediaSelectionError.workspaceChanged }
        guard let data = Self.jpeg(image) else { throw MediaSelectionError.tooLarge }
        let capturedAt = Date()
        let stamp = capturedAt.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "")
        let media = PendingMedia(id: UUID().uuidString, jobID: jobID, filename: "\(prefix)-\(stamp).jpg", tags: tags,
                                 capturedAt: capturedAt, kind: "photo", mime: "image/jpeg", caption: caption)
        try pendingMedia.save(media, data: data, context: captureContext)
        error = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { await retryWaiting() }
    }

    /// Sends everything saved for this job, in the background. Runs again while new photos arrive
    /// mid-send, stops at a failure or lost connection, and reloads the grid once at the end.
    private func retryWaiting() async {
        guard !Task.isCancelled, !draining, let scope = readScope, currentPendingContext != nil else { return }
        draining = true
        defer { if readScope == scope { draining = false } }
        var sent = false
        var attempted = Set<String>()
        while !Task.isCancelled, readScope == scope, currentPendingContext != nil {
            let batch = waiting.filter { !attempted.contains($0.id) }
            guard !batch.isEmpty else { break }
            attempted.formUnion(batch.map(\.id))
            let before = Set(waiting.map(\.id))
            await pendingMedia.drain(api: api, jobID: jobID, canUpload: { session.can("job.edit", feature: "jobs") })
            let after = Set(waiting.map(\.id))
            if !before.subtracting(after).isEmpty { sent = true }
            // A failure or lost connection leaves items behind; try again on the next save or reconnect.
            if batch.contains(where: { after.contains($0.id) }) { break }
        }
        guard sent, !Task.isCancelled, readScope == scope, currentPendingContext != nil else { return }
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

    /// Photos open in the viewer; documents and clips open in the system preview.
    private func open(_ record: MediaAssetRecord) {
        guard let scope = readScope, sourceScope == scope, records.contains(record), record.uploadState == "stored" else { return }
        if record.kind == "photo" {
            viewer = MediaViewerStart(id: record.id)
            #if DEBUG
            if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-media-revoke-preview") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(7))
                    PaperPreviewProtocol.revokeJobMediaView()
                    await session.revalidate()
                }
            }
            #endif
            return
        }
        previewScope = scope
        previewRecord = record
        preview.open {
            guard readScope == scope, sourceScope == scope, records.contains(record) else { throw CancellationError() }
            let file: URL
            #if DEBUG
            if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-media-revoke-preview") {
                file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
                let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
                try data.write(to: file)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(7))
                    PaperPreviewProtocol.revokeJobMediaView()
                    await session.revalidate()
                }
            } else {
                file = try await MediaTransfer(api: api).download(mediaID: record.id, filename: record.originalFilename)
            }
            #else
            file = try await MediaTransfer(api: api).download(mediaID: record.id, filename: record.originalFilename)
            #endif
            guard !Task.isCancelled, readScope == scope, sourceScope == scope, records.contains(record) else {
                try? FileManager.default.removeItem(at: file)
                throw CancellationError()
            }
            return file
        }
    }

    #if DEBUG
    /// Screenshot fixtures: `--paper-preview-media-state viewer|compare|tag|select|markup|measure|burst`
    /// opens that part of the flow once the sample grid has loaded.
    private func applyPreviewState() {
        let args = ProcessInfo.processInfo.arguments
        guard PaperPreview.enabled, !previewStateApplied, let index = args.firstIndex(of: "--paper-preview-media-state"),
              args.indices.contains(index + 1) else { return }
        previewStateApplied = true
        let sample = MediaSample.image(caption: "Water heater, as found", tags: ["Before"], size: CGSize(width: 1200, height: 1600))
        switch args[index + 1] {
        case "viewer": if let first = storedPhotos.first { viewer = MediaViewerStart(id: first.id) }
        case "compare": showCompare = true
        case "tag": capture = MediaCaptureRequest(mode: .single, stage: "Before", held: sample.jpegData(compressionQuality: 0.8))
        case "select":
            startSelecting()
            picked = Set(storedPhotos.prefix(3).map(\.id))
        case "markup": captureMarkup = sample.jpegData(compressionQuality: 0.8).map { PhotoMarkupTarget(data: $0, tags: ["Before"]) }
        case "measure": showMeasure = true
        case "untagged": filter = .untagged
        case "documents": filter = .documents
        default: break
        }
    }
    #endif
}

/// Picks one of the selection bar's quiet circles (a 56pt field circle with a spoken name).
private struct MenuOrCircle: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { PaperCircleLabel(symbol: symbol, size: 56) }
            .buttonStyle(PressStyle())
            .accessibilityLabel(label)
    }
}

struct PhotoMarkupTarget: Identifiable {
    let id = UUID()
    let data: Data
    let tags: [String]
}

private enum MediaSelectionError: LocalizedError {
    case tooLarge, unsupported, workspaceChanged
    var errorDescription: String? {
        switch self {
        case .workspaceChanged: return "Your workspace changed. Return to the original job before adding media."
        case .tooLarge: return "Choose a nonempty file no larger than 8 MB."
        case .unsupported: return "Choose a JPEG, PNG, HEIC, WebP photo, a PDF or a video clip."
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

/// System camera in video mode: up to 60 seconds, returns the recorded file or nil when cancelled.
/// The file is the camera's temporary copy; the caller deletes it once it has been re-encoded.
struct VideoCapture: UIViewControllerRepresentable {
    let onFinish: (URL?) -> Void

    /// Media uploads are a single PUT of at most 8 MB until multipart confirmation is wired.
    static let byteLimit: Int64 = 8 * 1024 * 1024 - 64 * 1024
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
            && (UIImagePickerController.availableMediaTypes(for: .camera) ?? []).contains(UTType.movie.identifier)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        picker.videoMaximumDuration = 60
        picker.videoQuality = .typeMedium
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (URL?) -> Void
        init(onFinish: @escaping (URL?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.mediaURL] as? URL)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }

    struct Clip {
        let url: URL
        /// Seconds kept when the 8 MB limit cut the end off; nil when the whole clip fit.
        let trimmedTo: Double?
    }

    enum ExportError: LocalizedError {
        case failed
        var errorDescription: String? { "This video couldn’t be prepared for upload. Try a shorter clip." }
    }

    static func exportMP4(_ source: URL) async throws -> Clip {
        let asset = AVURLAsset(url: source)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else { throw ExportError.failed }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID().uuidString).mp4")
        export.fileLengthLimit = byteLimit
        export.shouldOptimizeForNetworkUse = true
        try await export.export(to: output, as: .mp4)
        let original = try await asset.load(.duration).seconds
        let kept = try await AVURLAsset(url: output).load(.duration).seconds
        let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, size <= 8 * 1024 * 1024 else {
            try? FileManager.default.removeItem(at: output)
            throw ExportError.failed
        }
        return Clip(url: output, trimmedTo: kept + 0.5 < original ? kept : nil)
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
        let fractional = JobFiltering.isoFractional
        let standard = JobFiltering.isoPlain
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
