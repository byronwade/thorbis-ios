import SwiftUI
import ImageIO

/// A temporary selection, kept only in memory and scoped to the current staff authority.
@MainActor
final class CustomerPhotoHandoff: ObservableObject, Identifiable {
    let id = UUID()
    let selection: CustomerPhotoSelection
    private let api: APIClient
    private let session: SessionController
    private let actor: String
    private let sessionGeneration: UUID
    private let authorityRevision: UUID
    private let requestGeneration: UUID
    private let scopeRevision: UUID
    private let origin: String
    @Published var index = 0
    @Published var image: UIImage?
    @Published var message: String?
    @Published var loading = false
    @Published var foreground = true
    private var loadID = UUID()

    init?(selection: CustomerPhotoSelection, api: APIClient, session: SessionController) {
        guard let actor = session.user?.id, let origin = api.normalizedOrigin,
              session.activeOrganization?.id == selection.organizationID,
              session.can("job.view", feature: "jobs") else { return nil }
        self.selection = selection; self.api = api; self.session = session
        self.actor = actor; self.origin = origin
        sessionGeneration = session.generation; authorityRevision = session.authorityRevision
        requestGeneration = api.requestGeneration; scopeRevision = api.savedCopyScopeRevision
    }

    var isCurrent: Bool {
        foreground && session.user?.id == actor && session.activeOrganization?.id == selection.organizationID &&
        session.generation == sessionGeneration && session.authorityRevision == authorityRevision &&
        session.can("job.view", feature: "jobs") && api.requestGeneration == requestGeneration &&
        api.savedCopyScopeRevision == scopeRevision && api.normalizedOrigin == origin
    }

    func prepare() async throws {
        _ = try await CustomerPhotoPreparation.prepare(selection: selection, isCurrent: { self.isCurrent },
            loadJob: { let job = try await self.api.fieldJob(self.selection.jobID, requireFresh: true); return (job.id, job.organizationId) },
            loadAsset: { try await self.api.customerPhotoMetadata($0) })
    }

    private func download(_ assetID: String) async throws -> URL {
        #if DEBUG
        if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-photo-handoff") {
            guard let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGOwb9kCRAwQCgAnPgXdEEuqSQAAAABJRU5ErkJggg==") else { throw CustomerPhotoSelection.Invalid.records }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        }
        #endif
        return try await MediaTransfer(api: api).download(mediaID: assetID, filename: "photo.jpg", requireFresh: true)
    }

    func clear() { loadID = UUID(); image = nil; loading = false }

    func move(to newIndex: Int) {
        guard selection.selectedIDs.indices.contains(newIndex), newIndex != index else { return }
        clear()
        message = nil
        index = newIndex
    }

    func load() async {
        clear()
        guard isCurrent, selection.selectedIDs.indices.contains(index) else { message = "These photos are no longer available. Please hand the device back to your technician."; return }
        let current = UUID(); loadID = current; loading = true; message = nil
        do {
            let assetID = selection.selectedIDs[index]
            let record = try await api.customerPhotoMetadata(assetID)
            guard isCurrent, current == loadID, !Task.isCancelled else { throw CancellationError() }
            _ = try CustomerPhotoSelection(jobID: selection.jobID, organizationID: selection.organizationID, selectedIDs: [assetID]).validateFresh([record])
            let file = try await download(assetID)
            defer { try? FileManager.default.removeItem(at: file) }
            guard isCurrent, current == loadID, !Task.isCancelled else { throw CancellationError() }
            // The download endpoint may issue a URL for an archived object. Recheck the exact
            // record after the transfer before placing any bytes on the customer screen.
            let latest = try await api.customerPhotoMetadata(assetID)
            guard isCurrent, current == loadID, !Task.isCancelled else { throw CancellationError() }
            _ = try CustomerPhotoSelection(jobID: selection.jobID, organizationID: selection.organizationID, selectedIDs: [assetID]).validateFresh([latest])
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048]
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw CustomerPhotoSelection.Invalid.records
            }
            guard isCurrent, current == loadID, !Task.isCancelled else { throw CancellationError() }
            image = UIImage(cgImage: thumbnail); loading = false
        } catch {
            guard current == loadID else { return }
            image = nil; loading = false
            message = isCurrent ? "Couldn’t load this photo. Try again or hand the device back to your technician." : "These photos are no longer available. Please hand the device back to your technician."
        }
    }
}

struct CustomerPhotoHandoffView: View {
    @ObservedObject var owner: CustomerPhotoHandoff
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var api: APIClient
    @Environment(\.scenePhase) private var scenePhase
    let onUnlocked: () -> Void

    private func authenticateOwner() async -> Bool {
        #if DEBUG
        if let authenticate = PaperPreview.ownerAuthentication { return await authenticate("Unlock to leave customer mode") }
        #endif
        return await StaffUnlock.unlock()
    }

    var body: some View {
        CustomerModeContainer(onUnlocked: { owner.clear(); onUnlocked() }, ownerControlTitle: "Hand back", authenticateOwner: authenticateOwner) { handBack in
            VStack(spacing: 20) {
                Text("Photos from this job").font(Theme.customerFont(24, weight: .medium)).accessibilityAddTraits(.isHeader)
                Text("\(owner.index + 1) of \(owner.selection.selectedIDs.count)")
                    .font(Theme.customerFont(17)).foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
                if owner.loading { ProgressView() }
                else if let image = owner.image, owner.isCurrent, scenePhase == .active {
                    Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Photo \(owner.index + 1) of \(owner.selection.selectedIDs.count)").accessibilityIdentifier("customer-photo-image")
                        .gesture(DragGesture(minimumDistance: 35).onEnded { gesture in
                            guard abs(gesture.translation.width) > abs(gesture.translation.height) else { return }
                            if gesture.translation.width < -50, owner.index + 1 < owner.selection.selectedIDs.count { owner.move(to: owner.index + 1) }
                            if gesture.translation.width > 50, owner.index > 0 { owner.move(to: owner.index - 1) }
                        })
                } else if let message = owner.message {
                    Text(message).font(Theme.customerFont(17)).multilineTextAlignment(.center)
                    if owner.isCurrent {
                        Button("Try again") { Task { await owner.load() } }
                            .font(Theme.customerFont(CustomerModeStyle.body))
                            .frame(minWidth: CustomerModeStyle.target, minHeight: CustomerModeStyle.target).contentShape(Rectangle())
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    Button("Previous") { owner.move(to: owner.index - 1) }
                        .frame(minWidth: CustomerModeStyle.target, minHeight: CustomerModeStyle.target).contentShape(Rectangle())
                        .disabled(owner.index == 0)
                    Spacer()
                    Button("Next") { owner.move(to: owner.index + 1) }
                        .frame(minWidth: CustomerModeStyle.target, minHeight: CustomerModeStyle.target).contentShape(Rectangle())
                        .disabled(owner.index + 1 >= owner.selection.selectedIDs.count)
                }.font(Theme.customerFont(CustomerModeStyle.body))
                Button("Done") { owner.clear(); handBack() }
                    .font(Theme.customerFont(CustomerModeStyle.body, weight: .medium))
                    .frame(minWidth: CustomerModeStyle.target, minHeight: CustomerModeStyle.target).contentShape(Rectangle())
            }
            .padding(24)
            .task(id: owner.index) {
                guard scenePhase == .active else {
                    owner.foreground = false
                    owner.message = "Please hand the device back to your technician."
                    return
                }
                await owner.load()
            }
            .onDisappear { owner.clear() }
            .onChange(of: scenePhase) { _, phase in
                owner.foreground = phase == .active
                if phase != .active { owner.clear(); owner.message = "Please hand the device back to your technician." }
            }
            .onChange(of: owner.isCurrent) { _, valid in
                if !valid { owner.clear(); owner.message = "These photos are no longer available. Please hand the device back to your technician." }
            }
            .onChange(of: session.authorityRevision) { _, _ in if !owner.isCurrent { owner.clear(); owner.message = "These photos are no longer available. Please hand the device back to your technician." } }
            .onChange(of: api.savedCopyScopeRevision) { _, _ in if !owner.isCurrent { owner.clear(); owner.message = "These photos are no longer available. Please hand the device back to your technician." } }
            .onChange(of: session.generation) { _, _ in if !owner.isCurrent { owner.clear(); owner.message = "These photos are no longer available. Please hand the device back to your technician." } }
            .onChange(of: api.requestGeneration) { _, _ in if !owner.isCurrent { owner.clear(); owner.message = "These photos are no longer available. Please hand the device back to your technician." } }
        }
    }
}
