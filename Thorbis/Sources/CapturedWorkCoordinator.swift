import Foundation
import Combine

struct CapturedWorkScope: Hashable {
    let actorID: String
    let organizationID: String
    let origin: String
    let jobID: String

    @MainActor init?(actorID: String, organizationID: String, origin: String, jobID: String) {
        guard !actorID.isEmpty, !organizationID.isEmpty, !jobID.isEmpty,
              let origin = APIClient.normalizedOrigin(origin) else { return nil }
        self.actorID = actorID
        self.organizationID = organizationID
        self.origin = origin
        self.jobID = jobID
    }
}

struct CapturedNoteHandle: Hashable {
    fileprivate let scope: CapturedWorkScope
    fileprivate let sceneID: UUID
    fileprivate let editorID: UUID
    fileprivate let binding: UUID
}

struct CapturedWorkSessionToken: Hashable { fileprivate let id: UUID }

struct CapturedNoteSnapshot: Equatable {
    enum State: Equatable { case memoryOnly, saveFailed }
    let text: String
    let revision: UUID
    let state: State
}

@MainActor
final class CapturedWorkCoordinator: ObservableObject {
    /// Memory only: callers must independently authorize each scene/job before binding.
    /// This prototype is not connected to session, editor or sign-out flows.
    private struct Key: Hashable {
        let scope: CapturedWorkScope
        let sceneID: UUID
        let editorID: UUID
    }
    private struct Binding {
        let scope: CapturedWorkScope
        let token: UUID
    }
    private struct Owner: Equatable {
        let actorID: String
        let organizationID: String
        let origin: String
        init(_ scope: CapturedWorkScope) {
            actorID = scope.actorID
            organizationID = scope.organizationID
            origin = scope.origin
        }
    }
    private var activeOwner: Owner?
    private var activeSession: CapturedWorkSessionToken?
    private var bindings: [UUID: Binding] = [:]
    private var drafts: [Key: CapturedNoteSnapshot] = [:]

    func beginVerifiedSession(actorID: String, organizationID: String, origin: String) -> CapturedWorkSessionToken? {
        invalidateAllScopes()
        guard let scope = CapturedWorkScope(actorID: actorID, organizationID: organizationID, origin: origin, jobID: "scope-check") else { return nil }
        let token = CapturedWorkSessionToken(id: UUID())
        activeOwner = Owner(scope)
        activeSession = token
        return token
    }

    @discardableResult func bindAuthorizedScope(_ scope: CapturedWorkScope?, sceneID: UUID, session: CapturedWorkSessionToken) -> Bool {
        guard activeSession == session, scope.map({ Owner($0) == activeOwner }) ?? true else { return false }
        objectWillChange.send()
        bindings[sceneID] = scope.map { Binding(scope: $0, token: UUID()) }
        return true
    }

    @discardableResult func editNote(_ handle: CapturedNoteHandle, text: String, expectedRevision: UUID?) -> Bool {
        guard current(handle), text.utf16.count <= 10_000,
              drafts[key(handle)]?.revision == expectedRevision else { return false }
        objectWillChange.send()
        drafts[key(handle)] = CapturedNoteSnapshot(text: text, revision: UUID(), state: .memoryOnly)
        return true
    }

    func invalidateAllScopes() {
        objectWillChange.send()
        bindings.removeAll()
        activeOwner = nil
        activeSession = nil
    }

    func openNote(sceneID: UUID, editorID: UUID) -> CapturedNoteHandle? {
        guard let binding = bindings[sceneID] else { return nil }
        return CapturedNoteHandle(scope: binding.scope, sceneID: sceneID, editorID: editorID, binding: binding.token)
    }

    func note(_ handle: CapturedNoteHandle) -> CapturedNoteSnapshot? {
        guard current(handle) else { return nil }
        return drafts[key(handle)]
    }

    @discardableResult func markSaveFailed(_ handle: CapturedNoteHandle, revision: UUID) -> Bool {
        guard current(handle), let draft = drafts[key(handle)], draft.revision == revision else { return false }
        objectWillChange.send()
        drafts[key(handle)] = CapturedNoteSnapshot(text: draft.text, revision: draft.revision, state: .saveFailed)
        return true
    }

    private func current(_ handle: CapturedNoteHandle) -> Bool {
        guard let binding = bindings[handle.sceneID] else { return false }
        return binding.scope == handle.scope && binding.token == handle.binding
    }

    private func key(_ handle: CapturedNoteHandle) -> Key {
        Key(scope: handle.scope, sceneID: handle.sceneID, editorID: handle.editorID)
    }
}
