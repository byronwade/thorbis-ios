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
    fileprivate let editorBinding: UUID
}

struct CapturedWorkSessionToken: Hashable { fileprivate let id: UUID }

struct CapturedNoteSnapshot: Equatable {
    enum State: Equatable { case memoryOnly, saveFailed }
    let text: String
    let revision: UUID
    let state: State
}

enum CapturedNoteEditResult: Equatable {
    case updated, unavailable, staleRevision, tooLong, capacityExceeded
}

struct CapturedNoteRecovery: Identifiable {
    let id: UUID
    let snapshot: CapturedNoteSnapshot
    fileprivate let scope: CapturedWorkScope
    fileprivate let sceneID: UUID
    fileprivate let binding: UUID
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
    private var draftIDs: [Key: UUID] = [:]
    private var openEditors: [Key: UUID] = [:]
    private let maxDrafts: Int
    private let maxTotalUTF16: Int
    private var totalUTF16 = 0
    private var mutating = false
    private var pendingInvalidation = false

    init(maxDrafts: Int = 128, maxTotalUTF16: Int = 1_000_000) {
        precondition(maxDrafts > 0 && maxDrafts <= 128 && maxTotalUTF16 > 0 && maxTotalUTF16 <= 1_000_000)
        self.maxDrafts = maxDrafts
        self.maxTotalUTF16 = maxTotalUTF16
    }

    @discardableResult func closeNote(_ handle: CapturedNoteHandle) -> Bool {
        guard current(handle) else { return false }
        return mutate { openEditors[key(handle)] = nil; return true } ?? false
    }

    func recoverableNotes(sceneID: UUID) -> [CapturedNoteRecovery] {
        guard !pendingInvalidation, activeSession != nil, let binding = bindings[sceneID],
              Owner(binding.scope) == activeOwner else { return [] }
        return drafts.compactMap { key, snapshot in
            guard key.scope == binding.scope, openEditors[key] == nil, let id = draftIDs[key] else { return nil }
            return CapturedNoteRecovery(id: id, snapshot: snapshot, scope: binding.scope, sceneID: sceneID, binding: binding.token)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    @discardableResult func recoverNote(_ candidate: CapturedNoteRecovery, into handle: CapturedNoteHandle, expectedRevision: UUID) -> Bool {
        guard current(handle), candidate.sceneID == handle.sceneID, candidate.scope == handle.scope,
              candidate.binding == handle.binding, candidate.snapshot.revision == expectedRevision,
              let source = candidateKey(candidate), openEditors[source] == nil,
              let draft = drafts[source], draft.revision == expectedRevision, drafts[key(handle)] == nil else { return false }
        return mutate {
            drafts[source] = nil
            draftIDs[source] = nil
            drafts[key(handle)] = draft
            draftIDs[key(handle)] = candidate.id
            return true
        } ?? false
    }

    @discardableResult func discardNote(_ candidate: CapturedNoteRecovery, expectedRevision: UUID) -> Bool {
        guard !pendingInvalidation, activeSession != nil, let binding = bindings[candidate.sceneID],
              Owner(binding.scope) == activeOwner, binding.scope == candidate.scope,
              binding.token == candidate.binding, candidate.snapshot.revision == expectedRevision,
              let source = candidateKey(candidate), openEditors[source] == nil,
              let draft = drafts[source], draft.revision == expectedRevision else { return false }
        return mutate {
            totalUTF16 -= draft.text.utf16.count
            drafts[source] = nil
            draftIDs[source] = nil
            return true
        } ?? false
    }

    private func candidateKey(_ candidate: CapturedNoteRecovery) -> Key? {
        draftIDs.first { $0.value == candidate.id && $0.key.scope == candidate.scope }?.key
    }

    func beginVerifiedSession(actorID: String, organizationID: String, origin: String) -> CapturedWorkSessionToken? {
        guard !mutating else { pendingInvalidation = true; return nil }
        guard let scope = CapturedWorkScope(actorID: actorID, organizationID: organizationID, origin: origin, jobID: "scope-check") else {
            invalidateAllScopes()
            return nil
        }
        let token = CapturedWorkSessionToken(id: UUID())
        return mutate {
            resetAuthority()
            activeOwner = Owner(scope)
            activeSession = token
            return token
        }
    }

    @discardableResult func bindAuthorizedScope(_ scope: CapturedWorkScope?, sceneID: UUID, session: CapturedWorkSessionToken) -> Bool {
        guard !pendingInvalidation, activeSession == session, scope.map({ Owner($0) == activeOwner }) ?? true,
              scope == nil || bindings[sceneID] != nil || bindings.count < 64 else { return false }
        return mutate {
            openEditors = openEditors.filter { $0.key.sceneID != sceneID }
            bindings[sceneID] = scope.map { Binding(scope: $0, token: UUID()) }
            return true
        } ?? false
    }

    func editNote(_ handle: CapturedNoteHandle, text: String, expectedRevision: UUID?) -> CapturedNoteEditResult {
        let key = key(handle)
        let length = text.utf16.count
        let oldLength = drafts[key]?.text.utf16.count ?? 0
        guard current(handle) else { return .unavailable }
        guard drafts[key]?.revision == expectedRevision else { return .staleRevision }
        guard length <= 10_000 else { return .tooLong }
        guard (drafts[key] != nil || drafts.count < maxDrafts),
              length <= maxTotalUTF16 - totalUTF16 + oldLength else { return .capacityExceeded }
        return mutate {
            totalUTF16 += length - oldLength
            if drafts[key] == nil { draftIDs[key] = UUID() }
            drafts[key] = CapturedNoteSnapshot(text: text, revision: UUID(), state: .memoryOnly)
            return .updated
        } ?? .unavailable
    }

    func invalidateAllScopes() {
        if mutating { pendingInvalidation = true; return }
        _ = mutate { resetAuthority() }
    }

    func openNote(sceneID: UUID, editorID: UUID) -> CapturedNoteHandle? {
        guard !mutating, !pendingInvalidation, activeSession != nil, let binding = bindings[sceneID],
              Owner(binding.scope) == activeOwner else { return nil }
        let key = Key(scope: binding.scope, sceneID: sceneID, editorID: editorID)
        if let existing = openEditors[key] {
            return CapturedNoteHandle(scope: binding.scope, sceneID: sceneID, editorID: editorID,
                                      binding: binding.token, editorBinding: existing)
        }
        guard openEditors.count < maxDrafts + 16 else { return nil }
        let editorBinding = UUID()
        return mutate {
            openEditors[key] = editorBinding
            return CapturedNoteHandle(scope: binding.scope, sceneID: sceneID, editorID: editorID, binding: binding.token, editorBinding: editorBinding)
        }
    }

    func note(_ handle: CapturedNoteHandle) -> CapturedNoteSnapshot? {
        guard current(handle) else { return nil }
        return drafts[key(handle)]
    }

    @discardableResult func markSaveFailed(_ handle: CapturedNoteHandle, revision: UUID) -> Bool {
        guard current(handle), let draft = drafts[key(handle)], draft.revision == revision else { return false }
        return mutate {
            drafts[key(handle)] = CapturedNoteSnapshot(text: draft.text, revision: UUID(), state: .saveFailed)
            return true
        } ?? false
    }

    private func current(_ handle: CapturedNoteHandle) -> Bool {
        guard !pendingInvalidation, activeSession != nil, let binding = bindings[handle.sceneID],
              Owner(binding.scope) == activeOwner else { return false }
        return binding.scope == handle.scope && binding.token == handle.binding && openEditors[key(handle)] == handle.editorBinding
    }

    private func key(_ handle: CapturedNoteHandle) -> Key {
        Key(scope: handle.scope, sceneID: handle.sceneID, editorID: handle.editorID)
    }

    private func resetAuthority() {
        bindings.removeAll()
        openEditors.removeAll()
        activeOwner = nil
        activeSession = nil
    }

    /// Combine delivers synchronously. Reject reentrant mutations, and let an
    /// authority invalidation win before the outer mutation can publish data.
    private func mutate<T>(_ operation: () -> T) -> T? {
        guard !mutating else { return nil }
        mutating = true
        objectWillChange.send()
        if pendingInvalidation {
            resetAuthority()
            pendingInvalidation = false
            mutating = false
            return nil
        }
        let result = operation()
        mutating = false
        return result
    }
}
