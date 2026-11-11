import SwiftUI
import UIKit

@MainActor
func customerHandoffAuthenticate() async -> Bool {
    #if DEBUG
    if let authenticate = PaperPreview.ownerAuthentication { return await authenticate("Unlock to leave customer mode") }
    #endif
    return await StaffUnlock.unlock()
}

/// A legacy single-document presentation stays above session/navigation replacement until
/// authenticated hand-back. The body is hidden immediately if its original authority changes.
@MainActor
final class LegacyCustomerHandoff: ObservableObject, Identifiable {
    enum Exit { case done, collect }
    let id = UUID()
    let lease: LegacyCustomerHandoffLease
    @Published private(set) var content: AnyView?
    private(set) var onDismiss: (@MainActor (Exit) -> Void)?
    private let actor: String
    private let organization: String
    private let sessionGeneration: UUID
    private let authorityRevision: UUID
    private let requestGeneration: UUID
    private let scopeRevision: UUID
    private let origin: String
    private let capability: String
    private let feature: String
    private let sourceAttached: @MainActor () -> Bool

    init?(lease: LegacyCustomerHandoffLease, content: AnyView, api: APIClient, session: SessionController,
          capability: String = "estimate.view", feature: String = "estimates",
          sourceAttached: @escaping @MainActor () -> Bool = { true },
          onDismiss: @escaping @MainActor (Exit) -> Void) {
        guard session.can(capability, feature: feature), let actor = session.user?.id,
              let organization = session.activeOrganization?.id, let origin = api.normalizedOrigin else { return nil }
        self.lease = lease; self.content = content; self.onDismiss = onDismiss
        self.actor = actor; self.organization = organization; self.origin = origin
        self.capability = capability; self.feature = feature
        self.sourceAttached = sourceAttached
        sessionGeneration = session.generation; authorityRevision = session.authorityRevision
        requestGeneration = api.requestGeneration; scopeRevision = api.savedCopyScopeRevision
    }

    func retire() { content = nil; onDismiss = nil }

    func isCurrent(api: APIClient, session: SessionController) -> Bool {
        session.can(capability, feature: feature) && session.user?.id == actor && session.activeOrganization?.id == organization &&
        session.generation == sessionGeneration && session.authorityRevision == authorityRevision &&
        api.requestGeneration == requestGeneration && api.savedCopyScopeRevision == scopeRevision && api.normalizedOrigin == origin
    }
    func sourceIsAttached() -> Bool { sourceAttached() }
}

/// Captures the window that actually owns a document detail, including sheet-hosted details.
@MainActor
final class CustomerWindowAnchor: ObservableObject {
    weak var view: UIView?
    var window: UIWindow? { view?.window }
    var visible = false
    func isAttached(to source: UIWindow) -> Bool { visible && view?.window === source }
}

struct CustomerWindowAnchorView: UIViewRepresentable {
    let anchor: CustomerWindowAnchor
    func makeUIView(context: Context) -> AnchorView { AnchorView(anchor: anchor) }
    func updateUIView(_ view: AnchorView, context: Context) { view.anchor = anchor; view.capture() }
    final class AnchorView: UIView {
        weak var anchor: CustomerWindowAnchor?
        init(anchor: CustomerWindowAnchor) { self.anchor = anchor; super.init(frame: .zero); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { nil }
        override func didMoveToWindow() { super.didMoveToWindow(); capture() }
        func capture() { anchor?.view = self }
    }
}

@MainActor
final class LegacyCustomerPresenter: ObservableObject {
    @Published private(set) var active: LegacyCustomerHandoff?
    private var overlay: UIWindow?
    private weak var previousKeyWindow: UIWindow?
    private var observers: [NSObjectProtocol] = []
    private var privacyShield: UIView?
    private var pendingExit: (UUID, LegacyCustomerHandoff.Exit)?
    private weak var api: APIClient?
    private weak var session: SessionController?
    #if DEBUG
    private var testRetiring: (LegacyCustomerHandoff, LegacyCustomerHandoff.Exit)?
    // State-machine tests do not own a UIWindowScene; mounted tests exercise the actual host.
    func present(_ handoff: LegacyCustomerHandoff) -> Bool {
        guard active == nil, testRetiring == nil else { return false }
        active = handoff
        return true
    }
    func completedDismissal(api: APIClient, session: SessionController) {
        guard let (handoff, exit) = testRetiring else { return }
        testRetiring = nil; handoff.lease.release()
        if handoff.isCurrent(api: api, session: session) { handoff.onDismiss?(exit) }
    }
    #endif

    #if DEBUG
    private func traceScene(_ event: String) {
        guard PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-legacy-handoff-test") else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-scene-events.log")
        let line = "\(event) state=\(overlay?.windowScene?.activationState.rawValue ?? -1) shield=\(privacyShield != nil) active=\(active != nil)\n"
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let file = try? FileHandle(forWritingTo: url) { try? file.seekToEnd(); try? file.write(contentsOf: Data(line.utf8)); try? file.close() }
    }
    #endif

    func present(_ handoff: LegacyCustomerHandoff, sourceWindow: UIWindow?, api: APIClient, session: SessionController) -> Bool {
        guard active == nil, overlay == nil, let sourceWindow, let scene = sourceWindow.windowScene,
              scene.activationState == .foregroundActive, handoff.isCurrent(api: api, session: session) else { return false }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        let view = LegacyCustomerProtectedView(handoff: handoff, presenter: self)
            .environmentObject(api).environmentObject(session)
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = sourceWindow.traitCollection.userInterfaceStyle
        host.view.accessibilityViewIsModal = true
        window.rootViewController = host
        previousKeyWindow = scene.windows.first(where: { $0.isKeyWindow }) ?? sourceWindow
        self.api = api; self.session = session
        active = handoff; overlay = window
        let handoffID = handoff.id
        observers.append(NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification, object: scene, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sceneDisconnected(handoffID: handoffID) }
        })
        // Cover the customer window itself before the app-switcher snapshot. Keep the staff
        // window behind it; never hide the protected window during an inactive transition.
        observers.append(NotificationCenter.default.addObserver(forName: UIScene.willDeactivateNotification, object: scene, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setPrivacyShield(true, handoffID: handoffID) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: scene, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sceneBecameActive(handoffID: handoffID) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sceneBecameActive(handoffID: handoffID) }
        })
        window.makeKeyAndVisible()
        #if DEBUG
        traceScene("present")
        #endif
        return true
    }

    func authenticatedExit(for lease: LegacyCustomerHandoffLease, _ exit: LegacyCustomerHandoff.Exit = .done) {
        guard let handoff = active, handoff.lease === lease else { return }
        #if DEBUG
        traceScene("exit-request")
        if overlay == nil { testRetiring = (handoff, exit); active = nil; return }
        #endif
        guard let window = overlay else { return }
        guard window.windowScene?.activationState == .foregroundActive, privacyShield == nil else {
            pendingExit = (handoff.id, exit)
            return
        }
        finishExit(handoff: handoff, window: window, exit: exit)
    }

    private func finishExit(handoff: LegacyCustomerHandoff, window: UIWindow, exit: LegacyCustomerHandoff.Exit) {
        pendingExit = nil
        // Hide first: the staff callback may present a payment sheet only after the customer window is gone.
        window.isHidden = true
        window.rootViewController = nil
        overlay = nil; active = nil
        removeObserver()
        let scene = window.windowScene
        let target: UIWindow? = scene.flatMap { scene in
            (previousKeyWindow?.windowScene === scene && previousKeyWindow?.isHidden == false ? previousKeyWindow : nil)
                ?? scene.windows.first(where: { $0 !== window && !$0.isHidden && $0.windowLevel == .normal })
        }
        target?.makeKey()
        handoff.lease.release()
        if target != nil, handoff.sourceIsAttached(), let api, let session, handoff.isCurrent(api: api, session: session) { handoff.onDismiss?(exit) }
    }

    private func sceneDisconnected(handoffID: UUID) {
        guard let handoff = active, handoff.id == handoffID else { return }
        handoff.retire()
        overlay?.isHidden = true; overlay?.rootViewController = nil
        overlay = nil; active = nil; pendingExit = nil
        removeObserver(); handoff.lease.release()
    }

    private func sceneBecameActive(handoffID: UUID) {
        #if DEBUG
        traceScene("active-notification")
        #endif
        guard let handoff = active, handoff.id == handoffID, let window = overlay,
              window.windowScene?.activationState == .foregroundActive else { return }
        if let pendingExit, pendingExit.0 == handoffID {
            finishExit(handoff: handoff, window: window, exit: pendingExit.1)
        } else {
            setPrivacyShield(false, handoffID: handoffID)
        }
    }

    private func setPrivacyShield(_ visible: Bool, handoffID: UUID) {
        #if DEBUG
        traceScene(visible ? "shield-on" : "shield-off")
        #endif
        guard active?.id == handoffID, let hostView = overlay?.rootViewController?.view else { return }
        if visible {
            guard privacyShield == nil else { return }
            let shield = UIView(frame: hostView.bounds)
            shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            shield.backgroundColor = .systemBackground
            shield.isAccessibilityElement = true
            shield.accessibilityLabel = "Customer view is hidden while the app is inactive."
            shield.accessibilityViewIsModal = true
            hostView.addSubview(shield)
            privacyShield = shield
        } else {
            privacyShield?.removeFromSuperview(); privacyShield = nil
        }
    }

    private func removeObserver() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        privacyShield?.removeFromSuperview(); privacyShield = nil
    }
}

struct LegacyCustomerProtectedView: View {
    @ObservedObject var handoff: LegacyCustomerHandoff
    @ObservedObject var presenter: LegacyCustomerPresenter
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController

    private func authenticateOwner() async -> Bool {
        #if DEBUG
        if let authenticate = PaperPreview.ownerAuthentication { return await authenticate("Unlock to leave customer mode") }
        #endif
        return await StaffUnlock.unlock()
    }

    var body: some View {
        Group {
            if handoff.isCurrent(api: api, session: session), let content = handoff.content {
                content
            } else {
                CustomerModeContainer(onUnlocked: { presenter.authenticatedExit(for: handoff.lease) }, ownerControlTitle: "Hand back", authenticateOwner: authenticateOwner) { handBack in
                    VStack(spacing: 20) {
                        Image(systemName: "lock.shield").font(.system(size: 44)).accessibilityHidden(true)
                        Text("Please hand the device back to your technician.")
                            .font(Theme.customerFont(CustomerModeStyle.body)).multilineTextAlignment(.center)
                        CustomerCommitButton(title: "Hand back", icon: "hand.wave") { handBack() }
                    }.padding(24)
                }
            }
        }
        .onChange(of: handoff.isCurrent(api: api, session: session)) { _, valid in
            if !valid { handoff.retire() }
        }
        .onAppear { if !handoff.isCurrent(api: api, session: session) { handoff.retire() } }
    }
}

/// A scene-scoped host for job documents and the supervised gallery. The owner keeps its
/// arbiter lease until this window has been hidden, or until the scene disconnects.
@MainActor
final class CustomerProtectedSceneWindow: ObservableObject {
    #if DEBUG
    private let debugSuppressContent: Bool
    init(debugSuppressContent: Bool = false) { self.debugSuppressContent = debugSuppressContent }
    #else
    init() {}
    #endif
    @Published private(set) var sceneActive = false
    private var window: UIWindow?
    private weak var previous: UIWindow?
    private var ownerID: UUID?
    private var observers: [NSObjectProtocol] = []
    private var shield: UIView?
    private var pendingExit: (UUID, @MainActor (Bool) -> Void)?
    private var disconnected: (@MainActor () -> Void)?

    func present(id: UUID, source: UIWindow?, content: AnyView, onDisconnect: @escaping @MainActor () -> Void) -> Bool {
        guard window == nil, ownerID == nil, let source, let scene = source.windowScene,
              scene.activationState == .foregroundActive else { return false }
        let next = UIWindow(windowScene: scene)
        next.windowLevel = .normal + 1
        #if DEBUG
        let hostedContent = debugSuppressContent ? AnyView(EmptyView()) : content
        #else
        let hostedContent = content
        #endif
        let host = UIHostingController(rootView: hostedContent)
        host.overrideUserInterfaceStyle = source.traitCollection.userInterfaceStyle
        host.view.accessibilityViewIsModal = true
        next.rootViewController = host
        previous = scene.windows.first(where: { $0.isKeyWindow }) ?? source
        ownerID = id; window = next; disconnected = onDisconnect; sceneActive = true
        observers.append(NotificationCenter.default.addObserver(forName: UIScene.willDeactivateNotification, object: scene, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cover(id: id) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: scene, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.activate(id: id) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.activate(id: id) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification, object: scene, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.disconnect(id: id) }
        })
        next.makeKeyAndVisible()
        return true
    }

    func dismiss(id: UUID, completion: @escaping @MainActor (Bool) -> Void) {
        guard ownerID == id, let window else { return }
        guard window.windowScene?.activationState == .foregroundActive, shield == nil else {
            pendingExit = (id, completion); return
        }
        let restored = remove(id: id); completion(restored)
    }

    private func cover(id: UUID) {
        guard ownerID == id, shield == nil, let host = window?.rootViewController?.view else { return }
        sceneActive = false
        let view = UIView(frame: host.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = .systemBackground
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Customer view is hidden while the app is inactive."
        view.accessibilityViewIsModal = true
        host.addSubview(view); shield = view
    }

    private func activate(id: UUID) {
        guard ownerID == id, window?.windowScene?.activationState == .foregroundActive else { return }
        sceneActive = true
        if let pendingExit, pendingExit.0 == id {
            let restored = remove(id: id); pendingExit.1(restored)
        } else { shield?.removeFromSuperview(); shield = nil }
    }

    private func disconnect(id: UUID) {
        guard ownerID == id else { return }
        let action = disconnected
        _ = remove(id: id, restore: false)
        action?()
    }

    @discardableResult private func remove(id: UUID, restore: Bool = true) -> Bool {
        guard ownerID == id, let old = window else { return false }
        let scene = old.windowScene
        let target: UIWindow? = scene.flatMap { scene in
            (previous?.windowScene === scene && previous?.isHidden == false ? previous : nil)
                ?? scene.windows.first(where: { $0 !== old && !$0.isHidden && $0.windowLevel == .normal })
        }
        old.isHidden = true; old.rootViewController = nil
        window = nil; ownerID = nil; pendingExit = nil; disconnected = nil; sceneActive = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
        shield?.removeFromSuperview(); shield = nil
        if restore { target?.makeKey() }
        return restore && target != nil
    }
}
