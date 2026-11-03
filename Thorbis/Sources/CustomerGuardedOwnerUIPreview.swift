#if DEBUG
import SwiftUI
import UIKit

@MainActor private final class OwnerPreviewStore: CustomerQuarantineStore {
    private var records: [CustomerQuarantineScope: CustomerQuarantineState] = [:]
    func read(_ scope: CustomerQuarantineScope) throws -> CustomerQuarantineState? { records[scope] }
    func write(_ state: CustomerQuarantineState, for scope: CustomerQuarantineScope) throws { records[scope] = state }
}

@MainActor private final class OwnerPreviewModel: ObservableObject {
    let scope: CustomerQuarantineScope
    let authority: CustomerQuarantineAuthority
    let sessionID = UUID()
    let owner: CustomerGuardedReadOwner<String>
    let other: CustomerGuardedReadOwner<String>
    init() {
        let scope = try! CustomerQuarantineScope(actorID: "abcdefab-0000-4000-8000-000000000001", organizationID: "abcdefab-0000-4000-8000-000000000002", origin: "https://app.thorbis.com", customerID: "abcdefab-0000-4000-8000-000000000003")
        self.scope = scope
        authority = CustomerQuarantineAuthority(actorID: scope.actorID, organizationID: scope.organizationID, origin: scope.origin, policyVersion: 1, serverGeneration: "test", capabilities: ["customer.view"], features: ["core_crm": true], deadline: Date().addingTimeInterval(60))
        let quarantine = CustomerQuarantine(store: OwnerPreviewStore())
        owner = CustomerGuardedReadOwner(quarantine: quarantine)
        other = CustomerGuardedReadOwner(quarantine: quarantine)
    }
    func load() async {
        try? await owner.refresh(scope: scope, authority: authority, sessionID: sessionID, isCurrent: { true }) {
            CustomerGuardedValue(value: "Customer secret", evidence: .completeLive)
        }
    }
    func deny() async {
        try? await other.refresh(scope: scope, authority: authority, sessionID: sessionID, isCurrent: { true }) {
            throw CustomerGuardedReadError.denied
        }
    }
}

struct CustomerGuardedOwnerUIPreview: View {
    @StateObject private var model = OwnerPreviewModel()
    var body: some View { OwnerPreviewContent(model: model, owner: model.owner) }
}

private struct OwnerPreviewContent: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: OwnerPreviewModel
    @ObservedObject var owner: CustomerGuardedReadOwner<String>
    var body: some View {
        VStack {
            if let value = owner.visibleValue(scope: model.scope, authority: model.authority, sessionID: model.sessionID) {
                Text(value).accessibilityIdentifier("owner-secret")
            } else {
                Text("Records unavailable").accessibilityIdentifier("owner-retired")
            }
            Button("Deny in another owner") { Task { await model.deny() } }
        }
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { owner.recheckDeadline() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            owner.recheckDeadline()
        }
    }
}
#endif
