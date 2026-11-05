import SwiftUI

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

    init?(lease: LegacyCustomerHandoffLease, content: AnyView, api: APIClient, session: SessionController,
          onDismiss: @escaping @MainActor (Exit) -> Void) {
        guard session.phase == .ready, let actor = session.user?.id,
              let organization = session.activeOrganization?.id, let origin = api.normalizedOrigin else { return nil }
        self.lease = lease; self.content = content; self.onDismiss = onDismiss
        self.actor = actor; self.organization = organization; self.origin = origin
        sessionGeneration = session.generation; authorityRevision = session.authorityRevision
        requestGeneration = api.requestGeneration; scopeRevision = api.savedCopyScopeRevision
    }

    func retire() { content = nil; onDismiss = nil }

    func isCurrent(api: APIClient, session: SessionController) -> Bool {
        session.phase == .ready && session.user?.id == actor && session.activeOrganization?.id == organization &&
        session.generation == sessionGeneration && session.authorityRevision == authorityRevision &&
        api.requestGeneration == requestGeneration && api.savedCopyScopeRevision == scopeRevision && api.normalizedOrigin == origin
    }
}

@MainActor
final class LegacyCustomerPresenter: ObservableObject {
    @Published private(set) var active: LegacyCustomerHandoff?
    private var retiring: (LegacyCustomerHandoff, LegacyCustomerHandoff.Exit)?

    func present(_ handoff: LegacyCustomerHandoff) -> Bool {
        guard active == nil, retiring == nil else { return false }
        active = handoff
        return true
    }

    func authenticatedExit(for lease: LegacyCustomerHandoffLease, _ exit: LegacyCustomerHandoff.Exit = .done) {
        guard let active, active.lease === lease else { return }
        retiring = (active, exit)
        self.active = nil
    }

    func completedDismissal(api: APIClient, session: SessionController) {
        guard let (handoff, exit) = retiring else { return }
        retiring = nil
        handoff.lease.release()
        if handoff.isCurrent(api: api, session: session) { handoff.onDismiss?(exit) }
    }
}

struct LegacyCustomerProtectedView: View {
    @ObservedObject var handoff: LegacyCustomerHandoff
    @ObservedObject var presenter: LegacyCustomerPresenter
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController

    var body: some View {
        Group {
            if handoff.isCurrent(api: api, session: session), let content = handoff.content {
                content
            } else {
                CustomerModeContainer(onUnlocked: { presenter.authenticatedExit(for: handoff.lease) }, ownerControlTitle: "Hand back") { handBack in
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
