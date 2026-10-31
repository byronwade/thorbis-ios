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
    @State private var busy = false
    @State private var error: String?
    @StateObject private var preview = DocumentPreviewController()
    @State private var importDocument = false
    @State private var showCamera = false
    @State private var showScanner = false
    @State private var showLegacyRecovery = false
    /// Markup opened from a photo's preview (drawn over that sheet) or right after capture.
    @State private var previewMarkup: PhotoMarkupTarget?
    @State private var captureMarkup: PhotoMarkupTarget?
    /// The bounded JPEG just saved from the camera or library, offered for markup.
    @State private var justCaptured: PhotoMarkupTarget?
    @State private var showMeasure = false
    /// A short clip (60 s at most) recorded with the system camera, filed under Documents.
    @State private var showVideo = false
    @State private var videoNotice: String?
    /// Paper 21C: the stage a new photo is filed under (server tags "Before" / "After").
    @State private var stage = "Before"
    @State private var filter = "All"
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
                if loading || (previewIsCurrent && preview.loading) { SkeletonRows(count: 2, inset: 0) }
                if let selectedData, canShowSelection {
                    HStack(spacing: 12) {
                        Image(systemName: selectedMime == "application/pdf" ? "doc" : "photo")
                            .frame(width: 36, height: 36).background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
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
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
                }
                if !allPhotos.isEmpty || hasMore {
                    // Activity's All/Notes/Status/Photos chips are the screen's one chip row; the
                    // photo stage filter under them is a quieter row of words, not a second chip row.
                    if dynamicTypeSize.isAccessibilitySize {
                        ThorbisMenu(items: ["All", "Before", "After", "Untagged"].map { option in
                            ThorbisMenuItem(filterLabel(option), isSelected: filter == option) { filter = option }
                        }, title: "Show photos") {
                            Label("Filter photos · \(filter)", systemImage: "line.3.horizontal.decrease.circle")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.foreground)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("photo-filter-menu")
                    } else {
                        HStack(spacing: 16) {
                            ForEach(["All", "Before", "After", "Untagged"], id: \.self) { option in
                                Button { filter = option } label: {
                                    Text(filterLabel(option))
                                        .font(Theme.font(13, weight: filter == option ? .semibold : .regular))
                                        .foregroundStyle(filter == option ? Theme.foreground : Theme.muted)
                                        .frame(minHeight: 44).contentShape(Rectangle())
                                }
                                .buttonStyle(PressStyle())
                                .accessibilityAddTraits(filter == option ? .isSelected : [])
                            }
                        }
                    }
                    if hasMore {
                        Text("Counts show loaded photos")
                            .font(Theme.font(12)).foregroundStyle(Theme.muted)
                    }
                }
                if !loading && (!allPhotos.isEmpty || hasMore) && photos.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            Text(hasMore ? "No matches in loaded photos. More may be available." : "No matching photos").foregroundStyle(Theme.muted)
                            Spacer(minLength: 0)
                            Button("Show all photos") { filter = "All" }.frame(minHeight: 44)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(hasMore ? "No matches in loaded photos. More may be available." : "No matching photos").foregroundStyle(Theme.muted)
                            Button("Show all photos") { filter = "All" }.frame(minHeight: 44)
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
                if currentPendingContext != nil, let warning = pendingMedia.storageWarning { ErrorBanner(message: warning) }
                if currentPendingContext != nil && pendingMedia.legacyCount > 0 {
                    ErrorBanner(message: "Older photos remain on this phone. Check this job before choosing which photos to recover.")
                    Button("Recover older photos") { showLegacyRecovery = true }
                        .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.brandText)
                        .frame(minHeight: 44).disabled(!canAdd || busy)
                }
                if canAdd && dynamicTypeSize.isAccessibilitySize {
                    photoCaptureControls.padding(.top, 10)
                }
                if let justCaptured, canAdd {
                    HStack(spacing: 12) {
                        Button { captureMarkup = justCaptured } label: {
                            Label("Mark up the photo you just took", systemImage: "pencil.tip.crop.circle")
                                .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.brandText)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("markup-just-captured")
                        Button { self.justCaptured = nil } label: {
                            Image(systemName: "xmark").foregroundStyle(Theme.muted).frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss markup suggestion")
                    }
                    .padding(.horizontal, 12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
                }
                if !waiting.isEmpty {
                    PaperGroupHeader(title: "Waiting to upload", count: waiting.count) {
                        Button("Retry") { Task { await retryWaiting() } }
                            .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.brandText)
                            .frame(minHeight: 44).disabled(busy || !canAdd)
                    }
                    ForEach(waiting) { photo in
                        HStack(spacing: 12) {
                            Image(systemName: pendingMedia.errors[photo.id] != nil ? "exclamationmark.triangle" : photo.kind == "document" ? "doc" : photo.kind == "video" ? "video" : "clock.arrow.circlepath").foregroundStyle(Theme.warning)
                                .frame(width: 32, height: 32).background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(photo.title).font(Theme.font(15, weight: .medium))
                                Text(pendingMedia.errors[photo.id].map { "Needs attention · \($0)" } ?? (pendingMedia.uploadingID == photo.id ? "Uploading…" : pendingMedia.unverifiedIDs.contains(photo.id) ? "Saved copy not yet verified" : "Saved on this phone · \(photo.capturedAt.formatted(date: .omitted, time: .shortened))"))
                                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                        }
                        .frame(minHeight: 48)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("pending-media-\(photo.id)")
                        .accessibilityValue(Text("Captured \(photo.capturedAt.formatted(date: .abbreviated, time: .shortened))"))
                    }
                }
                // One empty state for the whole tab instead of two empty sections.
                if allPhotos.isEmpty && documents.isEmpty && waiting.isEmpty && (currentPendingContext == nil || (pendingMedia.legacyCount == 0 && pendingMedia.storageWarning == nil)) && !loading && !hasMore && pageError == nil && readScope == sourceScope && readScope != nil {
                    PaperEmptyState(symbol: "camera", title: "No photos yet",
                                    message: canAdd ? "Take a before photo when you arrive. Photos, PDFs and video clips up to 8 MB." : "Photos and documents added to this job show here.")
                }
                if !photos.isEmpty { PaperGroupHeader(title: hasMore ? "Photos loaded" : "Photos", count: photos.count) }
                if !photos.isEmpty {
                    ForEach(JobPhotoDateGroups.group(photos, calendar: calendar), id: \.day) { group in
                        Text(group.day.map(photoDayLabel) ?? "Date unavailable")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                                  ? [GridItem(.flexible())]
                                  : [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(group.photos) { record in
                                ZStack(alignment: .bottomTrailing) {
                                    Button { open(record) } label: {
                                        VStack(alignment: .leading, spacing: 0) {
                                            MediaThumbnail(record: record, attempt: thumbnailAttempt)
                                                .frame(maxWidth: .infinity).frame(height: 120)
                                                .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.cardRadius, topTrailingRadius: Theme.cardRadius))
                                                .overlay(alignment: .topLeading) {
                                                    if let tag = ["Before", "After"].first(where: record.tags.contains) {
                                                        Text(tag).font(Theme.font(11, weight: .semibold))
                                                            .foregroundStyle(Theme.foreground)
                                                            .padding(.horizontal, 8).frame(height: 24)
                                                            .background(Theme.background.opacity(0.9), in: Capsule())
                                                            .padding(8)
                                                    }
                                                }
                                            Text(record.caption ?? record.originalFilename).font(Theme.font(13, weight: .medium))
                                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                                .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                                                .padding(.horizontal, 10).padding(.vertical, 8)
                                                .padding(.trailing, dynamicTypeSize.isAccessibilitySize && canAdd && record.uploadState == "stored" ? 46 : 0)
                                            if record.uploadState != "stored" {
                                                Text(record.uploadState.statusLabel).font(Theme.font(11)).foregroundStyle(Theme.warning)
                                                    .padding(.horizontal, 10).padding(.bottom, 8)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(busy || preview.loading || record.uploadState != "stored")
                                    .accessibilityLabel("Photo, \(record.caption ?? record.originalFilename)")
                                    if canAdd, record.uploadState == "stored" {
                                        ThorbisMenu(items: [
                                            ThorbisMenuItem("Before") { Task { await retag(record, .before) } },
                                            ThorbisMenuItem("After") { Task { await retag(record, .after) } },
                                            ThorbisMenuItem("Other") { Task { await retag(record, .other) } },
                                        ], title: "Tag photo", accessibilityLabel: stageName(record)) {
                                            Image(systemName: "tag")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(Theme.foreground)
                                                .frame(width: 44, height: 44)
                                                .background(Theme.background.opacity(0.92), in: Circle())
                                        }
                                        .disabled(busy)
                                        .padding(4)
                                    }
                                }
                            }
                        }
                    }
                }
                if !documents.isEmpty { PaperGroupHeader(title: hasMore ? "Documents loaded" : "Documents", count: documents.count).padding(.top, 6) }
                ForEach(documents) { record in
                    Button { open(record) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: record.kind == "video" ? "video" : "doc").font(.system(size: 15)).foregroundStyle(Theme.muted)
                                .frame(width: 32, height: 32).background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.originalFilename).font(Theme.font(15, weight: .medium)).lineLimit(1)
                                Text(record.uploadState == "stored" ? (record.kind == "video" ? "Video" : "PDF") : record.uploadState.statusLabel)
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
                if hasMore {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("More photos and documents may be available. Filters apply to loaded items.")
                            .font(Theme.font(12)).foregroundStyle(Theme.muted)
                        Button(loadingMore ? "Loading…" : "Load more") { Task { await loadMore() } }
                            .font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.brandText)
                            .frame(minHeight: 44).disabled(loadingMore || loading)
                            .accessibilityIdentifier("job-media-load-more")
                    }
                }
                if canAdd && !(photos.isEmpty && documents.isEmpty) {
                    Text(videoNotice ?? "Photos, PDFs and video clips up to 8 MB.").font(Theme.font(12)).foregroundStyle(Theme.muted).padding(.top, 4)
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            if canAdd && !dynamicTypeSize.isAccessibilitySize {
                photoCaptureControls
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
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { image in
                showCamera = false
                guard let image else { return }
                uploadImage(image)
            }
            .ignoresSafeArea()
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
                        busy = false
                        uploadImage(image)
                    } else {
                        let type = item.supportedContentTypes.first ?? .jpeg
                        try select(data, mime: type.preferredMIMEType ?? "image/jpeg", filename: "photo." + (type.preferredFilenameExtension ?? "jpg"))
                        enqueueSelection()
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
                enqueueSelection()
            } catch { self.error = error.localizedDescription }
        }
        .sheet(isPresented: Binding(get: { previewIsCurrent && preview.url != nil }, set: { if !$0 { preview.clear(); previewScope = nil; previewRecord = nil } })) {
            if previewIsCurrent, let file = preview.url {
                NativeDocumentPreview(url: file).accessibilityIdentifier("job-media-preview")
                    .safeAreaInset(edge: .bottom) {
                        if canAdd, let record = previewRecord, record.kind == "photo" {
                            Button { openPreviewMarkup(file: file, record: record) } label: {
                                Label("Mark up a copy", systemImage: "pencil.tip.crop.circle").inkCommit()
                            }
                            .buttonStyle(PressStyle())
                            .padding(.horizontal, Theme.gutter).padding(.vertical, 8)
                            .background(Theme.background)
                            .accessibilityIdentifier("job-media-markup")
                        }
                    }
                    .fullScreenCover(item: $previewMarkup) { target in
                        markupCover(target, cancel: { previewMarkup = nil }) {
                            previewMarkup = nil
                            preview.clear(); previewScope = nil; previewRecord = nil
                        }
                    }
            }
        }
        .fullScreenCover(item: $captureMarkup) { target in
            markupCover(target, cancel: { captureMarkup = nil }) { captureMarkup = nil; justCaptured = nil }
        }
        .fullScreenCover(isPresented: $showMeasure) {
            SiteMeasureView(onSave: { image, caption in
                try enqueueDerived(image, tags: stageTags, caption: caption, prefix: "measure")
                showMeasure = false
            }, onClose: { showMeasure = false })
        }
        .onChange(of: readScope) { _, _ in preview.clear(); previewScope = nil; previewRecord = nil; busy = false; justCaptured = nil; previewMarkup = nil; captureMarkup = nil }
        .onChange(of: records) { _, _ in if !previewIsCurrent { preview.clear(); previewScope = nil; previewRecord = nil } }
        .onDisappear { selectedData = nil; justCaptured = nil; preview.clear() }
    }
    /// Opens what the job screen's toolkit asked for, with the same checks as the buttons below.
    private func consumeLaunch() {
        guard let request = launch.wrappedValue, captureContext != nil else { return }
        launch.wrappedValue = nil
        guard canAdd, readScope != nil, !busy else { return }
        switch request {
        case .camera(let requested):
            if let requested, ["Before", "After", "Other"].contains(requested) { stage = requested }
            if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
        case .scan:
            if VNDocumentCameraViewController.isSupported { showScanner = true } else { importDocument = true }
        case .measure:
            if SiteMeasure.isSupported { showMeasure = true }
        }
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
    private func photoFilterCount(_ option: String) -> Int {
        switch option {
        case "Before", "After": allPhotos.filter { $0.tags.contains(option) }.count
        case "Untagged": allPhotos.filter { !$0.tags.contains("Before") && !$0.tags.contains("After") }.count
        default: allPhotos.count
        }
    }

    private func filterLabel(_ option: String) -> String {
        let count = photoFilterCount(option)
        return "\(option) · \(count)"
    }

    private var photoCaptureControls: some View {
        VStack(spacing: 8) {
            ThorbisSegmented(options: [("Before", "Before"), ("After", "After"), ("Other", "Other")],
                             selection: $stage)
                .disabled(busy)
            HStack(spacing: 8) {
                Button { showCamera = true } label: {
                    HStack(spacing: 7) {
                        if busy { ProgressView().tint(Theme.onInk) } else { Image(systemName: "camera") }
                        Text(busy ? "Uploading…" : "Take \(stage == "Other" ? "a" : stage.lowercased()) photo")
                    }
                    .inkCommit()
                }
                .buttonStyle(PressStyle())
                .disabled(busy || !UIImagePickerController.isSourceTypeAvailable(.camera))
                PhotosPicker(selection: $selection, matching: .images) {
                    Image(systemName: "photo.on.rectangle").font(.system(size: 17)).foregroundStyle(Theme.foreground)
                        .frame(width: 46, height: 46)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
                }
                .disabled(busy)
                .accessibilityLabel("Choose from library")
                if SiteMeasure.isSupported {
                    Button { showMeasure = true } label: {
                        Image(systemName: "ruler").font(.system(size: 17)).foregroundStyle(Theme.foreground)
                            .frame(width: 46, height: 46)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .accessibilityLabel("Measure")
                    .accessibilityHint("Measure a distance with the camera and add it to this job as a photo.")
                    .accessibilityIdentifier("job-media-measure")
                }
                ThorbisMenu(items: (VNDocumentCameraViewController.isSupported
                    ? [ThorbisMenuItem("Scan a document", icon: "doc.viewfinder") { showScanner = true }]
                    : []) + [ThorbisMenuItem("Choose a PDF", icon: "doc") { importDocument = true }]
                    + (VideoCapture.isAvailable ? [ThorbisMenuItem("Record a video clip", icon: "video") { showVideo = true }] : []),
                            title: "Add a document or clip", accessibilityLabel: "Add a document or video clip") {
                    Image(systemName: "doc.badge.plus").font(.system(size: 17)).foregroundStyle(Theme.foreground)
                        .frame(width: 46, height: 46)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border))
                }
                .disabled(busy)
            }
        }
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

    private func stageName(_ record: MediaAssetRecord) -> String {
        if record.tags.contains("Before") { return "Change photo stage, currently Before" }
        if record.tags.contains("After") { return "Change photo stage, currently After" }
        return "Change photo stage, currently Other"
    }

    private func retag(_ record: MediaAssetRecord, _ stage: MediaStage) async {
        guard !busy, let scope = readScope, sourceScope == scope else { return }
        busy = true
        defer { if readScope == scope { busy = false } }
        do {
            let updated = try await api.tagFieldMedia(record.id, tags: MediaStageTags.applying(stage, to: record.tags), caption: record.caption)
            guard readScope == scope, sourceScope == scope, updated.id == record.id, records.contains(record),
                  updated.jobId == jobID, updated.organizationId == scope.organization else { return }
            if let index = records.firstIndex(where: { $0.id == updated.id }) { records[index] = updated }
            error = nil
        } catch is CancellationError {
        } catch {
            guard readScope == scope, sourceScope == scope else { return }
            self.error = error.localizedDescription
        }
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
            tags: kind == "photo" ? stageTags : [], capturedAt: selectedCapturedAt,
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
    private var stageTags: [String] { stage == "Other" ? [] : [stage] }

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

    /// Save original bounded JPEG bytes before the first network request.
    private func uploadImage(_ image: UIImage) {
        guard canAdd else { return }
        guard let data = Self.jpeg(image) else {
            error = MediaSelectionError.tooLarge.localizedDescription
            return
        }
        let capturedAt = Date()
        let stamp = capturedAt.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "")
        do {
            try select(data, mime: "image/jpeg", filename: "\(stage.lowercased())-\(stamp).jpg")
            let tags = stageTags
            enqueueSelection()
            if selectedData == nil, error == nil {
                justCaptured = PhotoMarkupTarget(data: data, tags: tags)
            }
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

    /// Reads the previewed photo's bytes now; the preview file is deleted when the sheet closes.
    private func openPreviewMarkup(file: URL, record: MediaAssetRecord) {
        guard let data = try? Data(contentsOf: file), UIImage(data: data) != nil else {
            error = "This photo could not be opened for markup."
            return
        }
        previewMarkup = PhotoMarkupTarget(data: data, tags: record.tags.filter { $0 == "Before" || $0 == "After" })
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

    private func retryWaiting() async {
        guard !Task.isCancelled, let scope = readScope, currentPendingContext != nil else { return }
        busy = true
        defer { if readScope == scope { busy = false } }
        await pendingMedia.drain(api: api, jobID: jobID, canUpload: { session.can("job.edit", feature: "jobs") })
        guard !Task.isCancelled, readScope == scope, currentPendingContext != nil else { return }
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

    private func open(_ record: MediaAssetRecord) {
        guard let scope = readScope, sourceScope == scope, records.contains(record), record.uploadState == "stored" else { return }
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
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
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
