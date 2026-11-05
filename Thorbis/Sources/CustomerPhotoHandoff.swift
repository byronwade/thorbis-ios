import SwiftUI
import UIKit
import Combine

/// Owned above the app's session/navigation branches, so losing a job screen cannot
/// reveal staff UI while a device is in customer hands.
@MainActor
final class CustomerPhotoPresenter: ObservableObject {
    private let arbiter: CustomerHandoffArbiter
    private let sceneWindow: CustomerProtectedSceneWindow?
    private var sceneOwnerID: UUID?
    init(arbiter: CustomerHandoffArbiter = CustomerHandoffArbiter(), sceneWindow: CustomerProtectedSceneWindow? = nil) {
        self.arbiter = arbiter; self.sceneWindow = sceneWindow
    }
    @Published private(set) var active: CustomerPhotoHandoff?
    var availableRevision: UUID? { arbiter.owner == nil ? arbiter.revision : nil }
    func present(_ owner: CustomerPhotoHandoff, expectedRevision: UUID, sourceWindow: UIWindow? = nil,
                 api: APIClient? = nil, session: SessionController? = nil) -> Bool {
        guard active == nil, owner.isCurrent, arbiter.revision == expectedRevision,
              arbiter.claim(.photos) else { return false }
        active = owner
        if let sceneWindow {
            guard let api, let session else { finishExit(); return false }
            let id = UUID(); sceneOwnerID = id
            let content = AnyView(CustomerPhotoHandoffView(owner: owner, sceneWindow: sceneWindow) { [weak self, weak owner] in
                guard let owner, self?.active === owner else { return }
                self?.authenticatedExit()
            }
                .environmentObject(api).environmentObject(session))
            guard sceneWindow.present(id: id, source: sourceWindow, content: content, onDisconnect: { [weak self, weak owner] in
                guard let owner, self?.active === owner else { return }
                self?.finishExit()
            }) else {
                finishExit(); return false
            }
        }
        return true
    }
    func authenticatedExit() {
        if let sceneWindow, let sceneOwnerID {
            sceneWindow.dismiss(id: sceneOwnerID) { [weak self] _ in self?.finishExit() }
        } else { finishExit() }
    }
    private func finishExit() { active?.stop(); active = nil; sceneOwnerID = nil; arbiter.release(.photos) }

}

/// A temporary selection, kept only in memory and scoped to the current staff authority.
@MainActor
final class CustomerPhotoHandoff: ObservableObject, Identifiable {
    let id = UUID()
    let selection: CustomerPhotoSelection
    private let api: APIClient
    private let session: SessionController
    private let actor: String
    private let sessionGeneration: UUID
    private var authorityRevision: UUID
    private let authorityFence: CustomerPhotoAuthorityFence
    private var subscriptions = Set<AnyCancellable>()
    private var needsFreshAuthority = false
    private var recoveryID = UUID()
    private var recoveryTask: Task<Void, Never>?
    @Published private(set) var recovering = false
    @Published private(set) var canRetryRecovery = false
    private let requestGeneration: UUID
    private let scopeRevision: UUID
    private let origin: String
    @Published var index = 0
    @Published var image: UIImage?
    @Published var message: String?
    @Published var loading = false
    @Published var foreground = true
    private var loadID = UUID()
    private var loadTask: Task<Void, Never>?

    init?(selection: CustomerPhotoSelection, api: APIClient, session: SessionController) {
        guard let actor = session.user?.id, let origin = api.normalizedOrigin,
              session.activeOrganization?.id == selection.organizationID,
              session.can("job.view", feature: "jobs") else { return nil }
        self.selection = selection; self.api = api; self.session = session
        self.actor = actor; self.origin = origin
        authorityFence = CustomerPhotoAuthorityFence(capabilities: session.capabilities, features: session.features,
            policyVersion: session.policyVersion, authorityGeneration: session.authorityGeneration)
        sessionGeneration = session.generation; authorityRevision = session.authorityRevision
        requestGeneration = api.requestGeneration; scopeRevision = api.savedCopyScopeRevision
        session.$capabilities.dropFirst().sink { [weak self] value in
            MainActor.assumeIsolated {
                self?.authorityFence.observeCapabilities(value)
                self?.retireIfMaterialChanged()
            }
        }.store(in: &subscriptions)
        session.$features.dropFirst().sink { [weak self] value in
            MainActor.assumeIsolated {
                self?.authorityFence.observeFeatures(value)
                self?.retireIfMaterialChanged()
            }
        }.store(in: &subscriptions)
        session.$policyVersion.dropFirst().sink { [weak self, weak session] value in
            MainActor.assumeIsolated {
                guard let self, let session else { return }
                self.authorityFence.observePolicy(version: value, generation: session.authorityGeneration)
                self.retireIfMaterialChanged()
            }
        }.store(in: &subscriptions)
        session.$authorityGeneration.dropFirst().sink { [weak self, weak session] value in
            MainActor.assumeIsolated {
                guard let self, let session else { return }
                self.authorityFence.observePolicy(version: session.policyVersion, generation: value)
                self.retireIfMaterialChanged()
            }
        }.store(in: &subscriptions)
    }

    var isCurrent: Bool {
        foreground && !needsFreshAuthority && authorityFence.isValid && session.user?.id == actor && session.activeOrganization?.id == selection.organizationID &&
        session.generation == sessionGeneration && session.authorityRevision == authorityRevision &&
        session.can("job.view", feature: "jobs") && api.requestGeneration == requestGeneration &&
        api.savedCopyScopeRevision == scopeRevision && api.normalizedOrigin == origin
    }

    var materialAuthorityIntact: Bool { authorityFence.isValid }

    #if DEBUG
    private(set) var debugRecoveryError = ""
    @Published private(set) var debugPauses = 0
    @Published private(set) var debugRecoveries = 0
    @Published private(set) var debugImages = 0
    var debugValidity: String {
        "pauses=\(debugPauses) recoveries=\(debugRecoveries) images=\(debugImages) foreground=\(foreground) actor=\(session.user?.id == actor) org=\(session.activeOrganization?.id == selection.organizationID) generation=\(session.generation == sessionGeneration) authority=\(session.authorityRevision == authorityRevision) canView=\(session.can("job.view", feature: "jobs")) requests=\(api.requestGeneration == requestGeneration) scope=\(api.savedCopyScopeRevision == scopeRevision) origin=\(api.normalizedOrigin == origin)"
    }
    #endif

    private func retireIfMaterialChanged() {
        guard !authorityFence.isValid else { return }
        recoveryTask?.cancel(); recoveryTask = nil; recoveryID = UUID(); recovering = false; canRetryRecovery = false
        clear(); message = "These photos are no longer available. Please hand the device back to your technician."
    }

    func stop() {
        recoveryTask?.cancel(); recoveryTask = nil; recoveryID = UUID(); recovering = false; canRetryRecovery = false
        clear()
    }

    private func materialIsCurrent(revision: UUID) -> Bool {
        authorityFence.observePolicy(version: session.policyVersion, generation: session.authorityGeneration)
        return authorityFence.isValid && foreground && session.phase == .ready && session.user?.id == actor &&
            session.activeOrganization?.id == selection.organizationID && session.generation == sessionGeneration &&
            session.authorityRevision == revision && session.can("job.view", feature: "jobs") &&
            api.requestGeneration == requestGeneration && api.savedCopyScopeRevision == scopeRevision && api.normalizedOrigin == origin
    }

    func pauseForBackground() {
        foreground = false; needsFreshAuthority = true
        recoveryTask?.cancel(); recoveryTask = nil; recoveryID = UUID(); recovering = false; canRetryRecovery = false
        clear(); message = "Photos are hidden while the app is inactive."
        #if DEBUG
        debugPauses += 1
        #endif
    }

    /// Re-read the exact job and complete selection before accepting a new authority revision.
    func refreshForCurrentAuthority() {
        let revision = session.authorityRevision
        guard needsFreshAuthority || revision != authorityRevision else { return }
        clear(); recoveryTask?.cancel(); let id = UUID(); recoveryID = id
        guard materialIsCurrent(revision: revision) else {
            recovering = false; canRetryRecovery = false
            message = "These photos are no longer available. Please hand the device back to your technician."
            return
        }
        guard revision != authorityRevision else {
            recovering = false; canRetryRecovery = true
            message = "Reconnect to reload these photos, or hand the device back to your technician."
            return
        }
        recovering = true; canRetryRecovery = false; message = nil
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await CustomerPhotoPreparation.prepare(selection: self.selection,
                    isCurrent: { self.recoveryID == id && self.materialIsCurrent(revision: revision) },
                    loadJob: { let job = try await self.api.fieldJob(self.selection.jobID, requireFresh: true); return (job.id, job.organizationId) },
                    loadAsset: { try await self.api.customerPhotoMetadata($0) })
                guard !Task.isCancelled, self.recoveryID == id, self.materialIsCurrent(revision: revision) else { return }
                self.authorityRevision = revision; self.needsFreshAuthority = false
                self.recovering = false; self.canRetryRecovery = false; self.message = nil
                #if DEBUG
                self.debugRecoveries += 1
                #endif
                self.beginLoad()
            } catch {
                guard self.recoveryID == id, !Task.isCancelled else { return }
                #if DEBUG
                self.debugRecoveryError = "\(String(reflecting: error)) transient=\(error.isTransientServerFailure)"
                #endif
                self.recovering = false
                self.canRetryRecovery = self.materialIsCurrent(revision: revision) && (error.isConnectivityFailure || error.isTransientServerFailure)
                self.message = self.canRetryRecovery ? "Couldn’t reload these photos. Try again or hand the device back to your technician." :
                    "These photos are no longer available. Please hand the device back to your technician."
            }
        }
    }

    func retryRecovery() {
        guard foreground, canRetryRecovery else { return }
        if session.authorityRevision != authorityRevision { refreshForCurrentAuthority(); return }
        canRetryRecovery = false; recovering = true
        let id = recoveryID
        Task { [weak self] in
            guard let self else { return }
            await self.session.revalidate()
            guard self.foreground, self.recoveryID == id, !Task.isCancelled else { return }
            self.refreshForCurrentAuthority()
        }
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

    func clear() {
        loadTask?.cancel()
        loadTask = nil
        loadID = UUID()
        image = nil
        loading = false
    }

    func beginLoad() {
        clear()
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.load()
        }
    }

    func move(to newIndex: Int) {
        guard selection.selectedIDs.indices.contains(newIndex), newIndex != index else { return }
        clear()
        message = nil
        index = newIndex
    }

    private func load() async {
        guard !Task.isCancelled else { return }
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
            let thumbnail = try await CustomerPhotoThumbnail.load(file)
            guard isCurrent, current == loadID, !Task.isCancelled else { throw CancellationError() }
            image = UIImage(cgImage: thumbnail.image); loading = false
            #if DEBUG
            debugImages += 1
            #endif
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
    @ObservedObject var sceneWindow: CustomerProtectedSceneWindow
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
                if owner.loading || owner.recovering { ProgressView() }
                else if let image = owner.image, owner.isCurrent, sceneWindow.sceneActive {
                    Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Photo \(owner.index + 1) of \(owner.selection.selectedIDs.count)").accessibilityIdentifier("customer-photo-image")
                        .gesture(DragGesture(minimumDistance: 35).onEnded { gesture in
                            guard abs(gesture.translation.width) > abs(gesture.translation.height) else { return }
                            if gesture.translation.width < -50, owner.index + 1 < owner.selection.selectedIDs.count { owner.move(to: owner.index + 1) }
                            if gesture.translation.width > 50, owner.index > 0 { owner.move(to: owner.index - 1) }
                        })
                } else if let message = owner.message {
                    Text(message).font(Theme.customerFont(17)).multilineTextAlignment(.center)
                    if owner.isCurrent || owner.canRetryRecovery {
                        Button("Try again") {
                            if owner.canRetryRecovery { owner.retryRecovery() } else { owner.beginLoad() }
                        }
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
                guard sceneWindow.sceneActive else {
                    owner.foreground = false
                    owner.message = "Please hand the device back to your technician."
                    return
                }
                owner.beginLoad()
            }
            .onDisappear { owner.stop() }
            .onChange(of: sceneWindow.sceneActive) { _, active in
                if active { owner.foreground = true; owner.refreshForCurrentAuthority() }
                else { owner.pauseForBackground() }
            }
            .onChange(of: owner.isCurrent) { _, valid in
                if !valid, !owner.recovering, !owner.canRetryRecovery {
                    owner.clear(); owner.message = "These photos are no longer available. Please hand the device back to your technician."
                }
            }
            .onChange(of: session.authorityRevision) { _, _ in owner.refreshForCurrentAuthority() }
            .onChange(of: api.savedCopyScopeRevision) { _, _ in if !owner.isCurrent { owner.clear(); owner.message = "These photos are no longer available. Please hand the device back to your technician." } }
            .onChange(of: session.generation) { _, _ in if !owner.isCurrent { owner.clear(); owner.message = "These photos are no longer available. Please hand the device back to your technician." } }
            .onChange(of: api.requestGeneration) { _, _ in if !owner.isCurrent { owner.clear(); owner.message = "These photos are no longer available. Please hand the device back to your technician." } }
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-photo-scene-diagnostic") {
                Text("sceneActive=\(sceneWindow.sceneActive) \(owner.debugValidity)")
                    .font(.system(size: 8)).accessibilityIdentifier("preview-photo-scene-diagnostic")
                    .background(Color.white).foregroundStyle(Color.black)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-photo-handoff-revoke") {
                Button("Preview revoke") {
                    Task { PaperPreviewProtocol.revokeJobMediaView(); await session.revalidate() }
                }
                .frame(minWidth: 80, minHeight: 44).background(Theme.canvas)
                .accessibilityIdentifier("preview-customer-photo-revoke")
            }
        }
        #endif
    }
}
