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
    /// Who is signed in, set by the root; nil while no workspace is open.
    fileprivate var identity: (actorID: String, organizationID: String)?

    /// False when there is no workspace to keep the conversation in; the caller falls back.
    func open(phone: String, name: String?) -> Bool {
        guard let identity, CommsCallGrouping.key(phone) != nil else { return false }
        let store = CommsLocalStore.shared(actorID: identity.actorID, organizationID: identity.organizationID)
        guard let threadID = store.threadForPhone(phone, contactName: name) else { return false }
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
            .onDisappear { presenter.identity = nil; presenter.opening = nil }
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
            presenter.identity = (actor, org)
        } else {
            presenter.identity = nil
        }
    }
}

extension View {
    func inboxTextPresenter() -> some View { modifier(InboxTextPresenterModifier()) }
}
