import SwiftUI

// Text buttons open the Inbox like the web's threadForPhone (apps/web features/inbox/store.ts):
// the conversation with that number (found by its digits, brought back from Archive or Bin) or a
// new empty one, kept on this device. Nothing is sent from it. Call and Email keep `tel:` and
// `mailto:`, as on the web.

/// Opens a text conversation over whatever is on screen. Installed once at the app's root, so a
/// Text button on any pushed page (job, customer, contacts) reaches it.
@MainActor
final class InboxTextPresenter: ObservableObject {
    static let shared = InboxTextPresenter()

    struct Opening: Identifiable, Equatable {
        let id: String
        let actorID: String?
        let organizationID: String?
    }

    @Published var opening: Opening?
    @Published var storageUnavailable = false
    /// Who is signed in, set by the root; nil while no workspace is open.
    fileprivate var identity: (actorID: String, organizationID: String)?

    func bind(actorID: String, organizationID: String) {
        identity = (actorID, organizationID)
    }

    /// False when there is no workspace to keep the conversation in; the caller falls back.
    func open(phone: String, name: String?) -> Bool {
        guard let identity, CommsCallGrouping.key(phone) != nil else { return false }
        let store = CommsLocalStore.shared(actorID: identity.actorID, organizationID: identity.organizationID)
        guard let threadID = store.threadForPhone(phone, contactName: name) else {
            // An active workspace must not silently switch to the system Messages app
            // just because its local inbox is unavailable.
            storageUnavailable = true
            return true
        }
        opening = Opening(id: threadID,
                          actorID: identity.actorID, organizationID: identity.organizationID)
        return true
    }
}

/// What a Text button calls: the Inbox conversation, or the phone's Messages when no workspace
/// is open (as before).
struct InboxTextAction {
    /// `sms` is the button's own `sms:` link; its number opens the conversation.
    @MainActor func callAsFunction(_ sms: URL, name: String?, openURL: OpenURLAction) {
        if let phone = Self.phone(sms), InboxTextPresenter.shared.open(phone: phone, name: name) { return }
        openURL(sms)
    }

    static func phone(_ sms: URL) -> String? {
        let raw = sms.absoluteString
        guard raw.lowercased().hasPrefix("sms:") else { return nil }
        let rest = String(raw.dropFirst(4))
        let number = rest.removingPercentEncoding ?? rest
        return CommsCallGrouping.key(number) == nil ? nil : number
    }
}

extension EnvironmentValues {
    @Entry var inboxText = InboxTextAction()
}

private struct InboxTextPresenterModifier: ViewModifier {
    @EnvironmentObject private var session: SessionController
    @ObservedObject private var presenter = InboxTextPresenter.shared

    func body(content: Content) -> some View {
        content
            .onAppear { bind() }
            .onChange(of: session.user?.id) { _, _ in bind() }
            .onChange(of: session.activeOrganization?.id) { _, _ in bind() }
            .onDisappear { presenter.identity = nil; presenter.opening = nil; presenter.storageUnavailable = false }
            .alert("Couldn't open text", isPresented: $presenter.storageUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your inbox on this device isn't available. Copy unsaved work before restarting the app, then check saved messages.")
            }
            .sheet(item: $presenter.opening) { opening in
                NavigationStack {
                    CommsLocalThreadView(threadID: opening.id,
                                         store: CommsLocalStore.shared(actorID: opening.actorID, organizationID: opening.organizationID))
                        .toolbar {
                            ThorbisToolbarItem(placement: .topBarLeading) {
                                PaperCircleButton(symbol: "xmark", label: "Close", fill: Theme.card, bordered: true) {
                                    presenter.opening = nil
                                }
                                .accessibilityIdentifier("inbox-text-close")
                            }
                        }
                }
                .thorbisSheetPresentation([.large])
            }
    }

    private func bind() {
        if let actor = session.user?.id, let org = session.activeOrganization?.id {
            presenter.bind(actorID: actor, organizationID: org)
        } else {
            presenter.identity = nil
        }
    }
}

extension View {
    func inboxTextPresenter() -> some View { modifier(InboxTextPresenterModifier()) }
}

/// A preaddressed email opens in the same scoped, device-local inbox composer.
@MainActor
final class InboxEmailPresenter: ObservableObject {
    static let shared = InboxEmailPresenter()
    #if DEBUG
    private static let previewRecoveryNamespace: String = {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--paper-preview-email-recovery-namespace"), args.indices.contains(index + 1),
           UUID(uuidString: args[index + 1]) != nil { return args[index + 1] }
        return UUID().uuidString
    }()
    #endif
    struct Opening: Identifiable {
        let id = UUID()
        let actorID: String
        let organizationID: String
        let sessionGeneration: UUID
        let recoveryScope: CommsEmailRecoveryScope
        let mail: MailDraft
    }
    @Published var opening: Opening?
    private var identity: (actorID: String, organizationID: String, origin: String, generation: UUID)?
    private var current: (@MainActor () -> Bool)?

    func bind(actorID: String, organizationID: String, origin: String, generation: UUID, current: @escaping @MainActor () -> Bool) {
        if let opening, opening.actorID != actorID || opening.organizationID != organizationID || opening.sessionGeneration != generation || identity?.origin != origin {
            self.opening = nil
        }
        identity = (actorID, organizationID, origin, generation); self.current = current
    }
    func unbind() { identity = nil; current = nil; opening = nil }
    func open(_ mail: MailDraft, context: String) {
        guard let identity, current?() == true else { unbind(); return }
        // Do not replace an unsaved composer through another entry point.
        #if DEBUG
        let namespace: String? = PaperPreview.enabled ? Self.previewRecoveryNamespace : nil
        #else
        let namespace: String? = nil
        #endif
        guard opening == nil,
              let scope = CommsEmailRecoveryScope(actorID: identity.actorID, organizationID: identity.organizationID,
                                                  origin: identity.origin, context: context, namespace: namespace) else { return }
        opening = Opening(actorID: identity.actorID, organizationID: identity.organizationID,
                          sessionGeneration: identity.generation, recoveryScope: scope, mail: mail)
    }
    func isCurrent(_ opening: Opening) -> Bool {
        self.opening?.id == opening.id && current?() == true && identity?.actorID == opening.actorID &&
            identity?.organizationID == opening.organizationID && identity?.generation == opening.sessionGeneration
    }
    func close(_ id: UUID) {
        if opening?.id == id { opening = nil }
    }

}

struct InboxEmailAction {
    @MainActor func callAsFunction(_ mail: MailDraft, context: String) {
        InboxEmailPresenter.shared.open(mail, context: context)
    }
    @MainActor func callAsFunction(_ url: URL, context: String) {
        guard let mail = MailDraft(mailtoURL: url) else { return }
        callAsFunction(mail, context: context)
    }
}

extension EnvironmentValues {
    @Entry var inboxEmail = InboxEmailAction()
}

private struct InboxEmailPresenterModifier: ViewModifier {
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var api: APIClient
    @ObservedObject private var presenter = InboxEmailPresenter.shared

    func body(content: Content) -> some View {
        content
            .onAppear { bind() }
            .onChange(of: session.generation) { _, _ in bind() }
            .onChange(of: session.user?.id) { _, _ in bind() }
            .onChange(of: session.activeOrganization?.id) { _, _ in bind() }
            .onChange(of: api.requestGeneration) { _, _ in bind() }
            .onDisappear { presenter.unbind() }
            .sheet(item: $presenter.opening) { opening in
                if presenter.isCurrent(opening) {
                    CommsMailSheet(draft: CommsMailDraft(mail: opening.mail),
                                   store: CommsLocalStore.shared(actorID: opening.actorID, organizationID: opening.organizationID),
                                   recoveryScope: opening.recoveryScope, recoveryCurrent: { presenter.isCurrent(opening) },
                                   onSaved: { _ in presenter.close(opening.id) }, onClose: { presenter.close(opening.id) })
                }
            }
    }

    private func bind() {
        guard let actor = session.user?.id, let org = session.activeOrganization?.id,
              let origin = api.normalizedOrigin else { presenter.unbind(); return }
        let generation = session.generation
        let apiGeneration = api.requestGeneration
        presenter.bind(actorID: actor, organizationID: org, origin: origin, generation: generation, current: { [weak session, weak api] in
            guard let session, let api else { return false }
            return session.user?.id == actor && session.activeOrganization?.id == org && session.generation == generation &&
                api.requestGeneration == apiGeneration && api.normalizedOrigin == origin
        })
    }
}

extension View {
    func inboxEmailPresenter() -> some View { modifier(InboxEmailPresenterModifier()) }
}
