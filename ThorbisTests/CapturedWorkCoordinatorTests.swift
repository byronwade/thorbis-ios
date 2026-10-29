import XCTest
import Combine
@testable import Thorbis

@MainActor
final class CapturedWorkCoordinatorTests: XCTestCase {
    private func scope(actor: String = "actor-a", workspace: String = "workspace-a", origin: String = "https://app.thorbis.com", job: String = "job-a") throws -> CapturedWorkScope {
        try XCTUnwrap(CapturedWorkScope(actorID: actor, organizationID: workspace, origin: origin, jobID: job))
    }
    private func session(_ store: CapturedWorkCoordinator, actor: String = "actor-a", workspace: String = "workspace-a", origin: String = "https://app.thorbis.com") throws -> CapturedWorkSessionToken {
        try XCTUnwrap(store.beginVerifiedSession(actorID: actor, organizationID: workspace, origin: origin))
    }

    func testSessionChangeHidesDraftAndRejectsOldHandleWithoutErasingOriginal() throws {
        let store = CapturedWorkCoordinator()
        let original = try scope()
        let scene = UUID(), editor = UUID()
        let initialSession = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(original, sceneID: scene, session: initialSession))
        let handle = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertEqual(store.editNote(handle, text: "Original field note", expectedRevision: nil), .updated)
        store.invalidateAllScopes()
        XCTAssertNil(store.note(handle))
        XCTAssertEqual(store.editNote(handle, text: "Late callback", expectedRevision: nil), .unavailable)
        let otherSession = try session(store, actor: "actor-b")
        XCTAssertTrue(store.bindAuthorizedScope(try scope(actor: "actor-b"), sceneID: scene, session: otherSession))
        XCTAssertNil(store.note(handle))
        let other = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertNil(store.note(other))
        let resumedSession = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(original, sceneID: scene, session: resumedSession))
        let resumed = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertEqual(store.note(resumed)?.text, "Original field note")
        XCTAssertEqual(store.editNote(handle, text: "Old session", expectedRevision: nil), .unavailable)
    }

    func testSameJobEditorsKeepIndependentDraftsAndRevisions() throws {
        let store = CapturedWorkCoordinator()
        let firstScene = UUID(), secondScene = UUID()
        let token = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: firstScene, session: token))
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: secondScene, session: token))
        let first = try XCTUnwrap(store.openNote(sceneID: firstScene, editorID: UUID()))
        let second = try XCTUnwrap(store.openNote(sceneID: secondScene, editorID: UUID()))
        XCTAssertEqual(store.editNote(first, text: "First scene", expectedRevision: nil), .updated)
        XCTAssertEqual(store.editNote(second, text: "Second scene", expectedRevision: nil), .updated)
        XCTAssertEqual(store.note(first)?.text, "First scene")
        XCTAssertEqual(store.note(second)?.text, "Second scene")
        XCTAssertNotEqual(store.note(first)?.revision, store.note(second)?.revision)
    }

    func testLateStorageFailureCannotOverwriteNewerEdit() throws {
        let store = CapturedWorkCoordinator()
        let scene = UUID()
        let token = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: scene, session: token))
        let handle = try XCTUnwrap(store.openNote(sceneID: scene, editorID: UUID()))
        XCTAssertEqual(store.editNote(handle, text: "First", expectedRevision: nil), .updated)
        let oldRevision = try XCTUnwrap(store.note(handle)?.revision)
        XCTAssertEqual(store.editNote(handle, text: "Newer", expectedRevision: oldRevision), .updated)
        XCTAssertFalse(store.markSaveFailed(handle, revision: oldRevision))
        let current = try XCTUnwrap(store.note(handle))
        XCTAssertEqual(current.text, "Newer")
        XCTAssertEqual(current.state, .memoryOnly)
        XCTAssertTrue(store.markSaveFailed(handle, revision: current.revision))
        XCTAssertEqual(store.note(handle)?.state, .saveFailed)
        XCTAssertEqual(store.note(handle)?.text, "Newer")
    }

    func testUntrustedOriginsAndEmptyIdentityCannotCreateScope() {
        XCTAssertNil(CapturedWorkScope(actorID: "", organizationID: "org", origin: "https://app.thorbis.com", jobID: "job"))
        XCTAssertNil(CapturedWorkScope(actorID: "actor", organizationID: "org", origin: "https://evil.invalid", jobID: "job"))
    }

    func testMultipleScenesCanEditDifferentJobsWithoutCrossingScopes() throws {
        let store = CapturedWorkCoordinator()
        let firstScene = UUID(), secondScene = UUID()
        let token = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(try scope(job: "job-a"), sceneID: firstScene, session: token))
        XCTAssertTrue(store.bindAuthorizedScope(try scope(job: "job-b"), sceneID: secondScene, session: token))
        let first = try XCTUnwrap(store.openNote(sceneID: firstScene, editorID: UUID()))
        let second = try XCTUnwrap(store.openNote(sceneID: secondScene, editorID: UUID()))
        XCTAssertEqual(store.editNote(first, text: "First job", expectedRevision: nil), .updated)
        XCTAssertEqual(store.editNote(second, text: "Second job", expectedRevision: nil), .updated)
        XCTAssertEqual(store.note(first)?.text, "First job")
        XCTAssertEqual(store.note(second)?.text, "Second job")
        store.invalidateAllScopes()
        XCTAssertNil(store.note(first))
        XCTAssertNil(store.note(second))
    }

    func testChangingOwnerRevokesAllScenesBeforeAnotherOwnerCanOpenDrafts() throws {
        let store = CapturedWorkCoordinator()
        let firstScene = UUID(), secondScene = UUID(), editor = UUID()
        let originalSession = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: firstScene, session: originalSession))
        XCTAssertTrue(store.bindAuthorizedScope(try scope(job: "job-b"), sceneID: secondScene, session: originalSession))
        let old = try XCTUnwrap(store.openNote(sceneID: firstScene, editorID: editor))
        XCTAssertEqual(store.editNote(old, text: "Original owner", expectedRevision: nil), .updated)
        let otherSession = try session(store, workspace: "workspace-b")
        XCTAssertTrue(store.bindAuthorizedScope(try scope(workspace: "workspace-b"), sceneID: secondScene, session: otherSession))
        XCTAssertNil(store.note(old))
        XCTAssertEqual(store.editNote(old, text: "Wrong workspace", expectedRevision: nil), .unavailable)
        XCTAssertNil(store.openNote(sceneID: firstScene, editorID: editor))
        let restoredSession = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: firstScene, session: restoredSession))
        let restored = try XCTUnwrap(store.openNote(sceneID: firstScene, editorID: editor))
        XCTAssertEqual(store.note(restored)?.text, "Original owner")
        XCTAssertNil(store.openNote(sceneID: secondScene, editorID: editor))
    }

    func testLatePriorSessionCannotRebindOrExposeDraft() throws {
        let store = CapturedWorkCoordinator()
        let scene = UUID(), editor = UUID(), first = try scope()
        let oldSession = try XCTUnwrap(store.beginVerifiedSession(actorID: "actor-a", organizationID: "workspace-a", origin: "https://app.thorbis.com"))
        XCTAssertTrue(store.bindAuthorizedScope(first, sceneID: scene, session: oldSession))
        let oldHandle = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertEqual(store.editNote(oldHandle, text: "Original", expectedRevision: nil), .updated)
        let newSession = try XCTUnwrap(store.beginVerifiedSession(actorID: "actor-b", organizationID: "workspace-a", origin: "https://app.thorbis.com"))
        XCTAssertTrue(store.bindAuthorizedScope(try scope(actor: "actor-b"), sceneID: scene, session: newSession))
        XCTAssertFalse(store.bindAuthorizedScope(first, sceneID: scene, session: oldSession))
        XCTAssertNil(store.note(oldHandle))
        let activeHandle = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertNil(store.note(activeHandle))
    }

    func testLateEditCannotReplaceNewerRevision() throws {
        let store = CapturedWorkCoordinator(), scene = UUID()
        let token = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: scene, session: token))
        let handle = try XCTUnwrap(store.openNote(sceneID: scene, editorID: UUID()))
        XCTAssertEqual(store.editNote(handle, text: "First", expectedRevision: nil), .updated)
        let first = try XCTUnwrap(store.note(handle))
        XCTAssertEqual(store.editNote(handle, text: "Newer", expectedRevision: first.revision), .updated)
        XCTAssertEqual(store.editNote(handle, text: "Delayed older edit", expectedRevision: first.revision), .staleRevision)
        XCTAssertEqual(store.note(handle)?.text, "Newer")
    }

    func testOriginSwitchCannotReadOrOverwriteOriginalDraft() throws {
        let store = CapturedWorkCoordinator(), scene = UUID(), editor = UUID()
        let original = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: scene, session: original))
        let old = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertEqual(store.editNote(old, text: "Original", expectedRevision: nil), .updated)
        let local = try session(store, origin: "http://localhost:3000")
        XCTAssertTrue(store.bindAuthorizedScope(try scope(origin: "http://localhost:3000"), sceneID: scene, session: local))
        XCTAssertNil(store.note(old))
        let other = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertNil(store.note(other))
        XCTAssertEqual(store.editNote(old, text: "Wrong origin", expectedRevision: nil), .unavailable)
    }

    func testOversizeNoteDoesNotReplaceExistingDraft() throws {
        let store = CapturedWorkCoordinator(), scene = UUID()
        let token = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: scene, session: token))
        let handle = try XCTUnwrap(store.openNote(sceneID: scene, editorID: UUID()))
        XCTAssertEqual(store.editNote(handle, text: "Keep", expectedRevision: nil), .updated)
        let saved = try XCTUnwrap(store.note(handle))
        XCTAssertEqual(store.editNote(handle, text: String(repeating: "a", count: 10_001), expectedRevision: saved.revision), .tooLong)
        XCTAssertEqual(store.note(handle), saved)
    }

    func testReauthorizingSameScopeRetiresOldHandleButKeepsDraft() throws {
        let store = CapturedWorkCoordinator(), scene = UUID(), editor = UUID()
        let token = try session(store), currentScope = try scope()
        XCTAssertTrue(store.bindAuthorizedScope(currentScope, sceneID: scene, session: token))
        let old = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertEqual(store.editNote(old, text: "Keep", expectedRevision: nil), .updated)
        XCTAssertTrue(store.bindAuthorizedScope(currentScope, sceneID: scene, session: token))
        XCTAssertNil(store.note(old))
        let new = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertEqual(store.note(new)?.text, "Keep")
    }

    func testClosedDraftCanBeDiscoveredAndMovedToANewSceneForSameJob() throws {
        let store = CapturedWorkCoordinator(), oldScene = UUID(), newScene = UUID()
        let token = try session(store), job = try scope()
        XCTAssertTrue(store.bindAuthorizedScope(job, sceneID: oldScene, session: token))
        let old = try XCTUnwrap(store.openNote(sceneID: oldScene, editorID: UUID()))
        XCTAssertEqual(store.editNote(old, text: "Keep this note", expectedRevision: nil), .updated)
        XCTAssertTrue(store.closeNote(old))
        store.invalidateAllScopes()
        let resumedSession = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(job, sceneID: newScene, session: resumedSession))
        let candidate = try XCTUnwrap(store.recoverableNotes(sceneID: newScene).first)
        XCTAssertEqual(candidate.snapshot.text, "Keep this note")
        let target = try XCTUnwrap(store.openNote(sceneID: newScene, editorID: UUID()))
        XCTAssertTrue(store.recoverNote(candidate, into: target, expectedRevision: candidate.snapshot.revision))
        XCTAssertEqual(store.note(target)?.text, "Keep this note")
        XCTAssertTrue(store.recoverableNotes(sceneID: newScene).isEmpty)
        XCTAssertNil(store.note(old))
    }

    func testRecoveryRequiresOriginalOwnerJobAndCurrentBinding() throws {
        let store = CapturedWorkCoordinator(), originalScene = UUID(), otherScene = UUID()
        let token = try session(store), job = try scope()
        XCTAssertTrue(store.bindAuthorizedScope(job, sceneID: originalScene, session: token))
        let old = try XCTUnwrap(store.openNote(sceneID: originalScene, editorID: UUID()))
        XCTAssertEqual(store.editNote(old, text: "Private", expectedRevision: nil), .updated)
        XCTAssertTrue(store.closeNote(old))
        XCTAssertTrue(store.bindAuthorizedScope(try scope(job: "job-b"), sceneID: otherScene, session: token))
        XCTAssertTrue(store.recoverableNotes(sceneID: otherScene).isEmpty)
        XCTAssertTrue(store.bindAuthorizedScope(job, sceneID: otherScene, session: token))
        let candidate = try XCTUnwrap(store.recoverableNotes(sceneID: otherScene).first)
        store.invalidateAllScopes()
        XCTAssertFalse(store.discardNote(candidate, expectedRevision: candidate.snapshot.revision))
        let foreign = try session(store, actor: "actor-b")
        XCTAssertTrue(store.bindAuthorizedScope(try scope(actor: "actor-b"), sceneID: otherScene, session: foreign))
        XCTAssertTrue(store.recoverableNotes(sceneID: otherScene).isEmpty)
        XCTAssertFalse(store.discardNote(candidate, expectedRevision: candidate.snapshot.revision))
    }

    func testExplicitDiscardRequiresUnchangedRevision() throws {
        let store = CapturedWorkCoordinator(), scene = UUID(), reviewScene = UUID(), editor = UUID()
        let token = try session(store), job = try scope()
        XCTAssertTrue(store.bindAuthorizedScope(job, sceneID: scene, session: token))
        let first = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertEqual(store.editNote(first, text: "First", expectedRevision: nil), .updated)
        XCTAssertTrue(store.closeNote(first))
        XCTAssertTrue(store.bindAuthorizedScope(job, sceneID: reviewScene, session: token))
        let candidate = try XCTUnwrap(store.recoverableNotes(sceneID: reviewScene).first)
        let resumed = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertEqual(store.editNote(resumed, text: "Newer", expectedRevision: candidate.snapshot.revision), .updated)
        XCTAssertTrue(store.closeNote(resumed))
        XCTAssertFalse(store.discardNote(candidate, expectedRevision: candidate.snapshot.revision))
        let current = try XCTUnwrap(store.recoverableNotes(sceneID: reviewScene).first)
        XCTAssertEqual(current.snapshot.text, "Newer")
        XCTAssertTrue(store.discardNote(current, expectedRevision: current.snapshot.revision))
        XCTAssertTrue(store.recoverableNotes(sceneID: reviewScene).isEmpty)
    }

    func testCapacityRejectsNewDraftWithoutEvictingExistingWork() throws {
        let store = CapturedWorkCoordinator(maxDrafts: 2, maxTotalUTF16: 8), scene = UUID()
        let token = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: scene, session: token))
        let first = try XCTUnwrap(store.openNote(sceneID: scene, editorID: UUID()))
        let second = try XCTUnwrap(store.openNote(sceneID: scene, editorID: UUID()))
        let third = try XCTUnwrap(store.openNote(sceneID: scene, editorID: UUID()))
        XCTAssertEqual(store.editNote(first, text: "one", expectedRevision: nil), .updated)
        XCTAssertEqual(store.editNote(second, text: "two", expectedRevision: nil), .updated)
        XCTAssertEqual(store.editNote(third, text: "new", expectedRevision: nil), .capacityExceeded)
        XCTAssertEqual(store.note(first)?.text, "one")
        XCTAssertEqual(store.note(second)?.text, "two")
        XCTAssertNil(store.note(third))
        let revision = try XCTUnwrap(store.note(first)?.revision)
        XCTAssertEqual(store.editNote(first, text: "toolong", expectedRevision: revision), .capacityExceeded)
        XCTAssertEqual(store.note(first)?.text, "one")
        XCTAssertTrue(store.closeNote(second))
        let discarded = try XCTUnwrap(store.recoverableNotes(sceneID: scene).first)
        XCTAssertTrue(store.discardNote(discarded, expectedRevision: discarded.snapshot.revision))
        XCTAssertEqual(store.editNote(third, text: "new", expectedRevision: nil), .updated)
        XCTAssertEqual(store.note(first)?.text, "one")
        XCTAssertEqual(store.note(third)?.text, "new")
    }

    func testCapacityNeverEvictsAnotherOwnersInaccessibleDraft() throws {
        let store = CapturedWorkCoordinator(maxDrafts: 1, maxTotalUTF16: 100), scene = UUID(), editor = UUID()
        let originalSession = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: scene, session: originalSession))
        let original = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertEqual(store.editNote(original, text: "Original", expectedRevision: nil), .updated)
        let otherSession = try session(store, actor: "actor-b")
        XCTAssertTrue(store.bindAuthorizedScope(try scope(actor: "actor-b"), sceneID: scene, session: otherSession))
        let other = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertEqual(store.editNote(other, text: "Other", expectedRevision: nil), .capacityExceeded)
        XCTAssertNil(store.note(other))
        let resumedSession = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: scene, session: resumedSession))
        let resumed = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertEqual(store.note(resumed)?.text, "Original")
    }

    func testRecoveryDoesNotTakeAnActiveDraftOrOverwriteTarget() throws {
        let store = CapturedWorkCoordinator(), scene = UUID(), otherScene = UUID()
        let token = try session(store), job = try scope()
        XCTAssertTrue(store.bindAuthorizedScope(job, sceneID: scene, session: token))
        XCTAssertTrue(store.bindAuthorizedScope(job, sceneID: otherScene, session: token))
        let original = try XCTUnwrap(store.openNote(sceneID: scene, editorID: UUID()))
        let target = try XCTUnwrap(store.openNote(sceneID: otherScene, editorID: UUID()))
        XCTAssertEqual(store.editNote(original, text: "Original", expectedRevision: nil), .updated)
        XCTAssertEqual(store.editNote(target, text: "Target", expectedRevision: nil), .updated)
        XCTAssertTrue(store.recoverableNotes(sceneID: otherScene).isEmpty)
        XCTAssertTrue(store.closeNote(original))
        let candidate = try XCTUnwrap(store.recoverableNotes(sceneID: otherScene).first)
        XCTAssertFalse(store.recoverNote(candidate, into: target, expectedRevision: candidate.snapshot.revision))
        XCTAssertEqual(store.note(target)?.text, "Target")
        XCTAssertEqual(store.recoverableNotes(sceneID: otherScene).first?.snapshot.text, "Original")
    }

    func testAuthorityInvalidationDuringPublicationCannotCommitOldOwnerEdit() throws {
        let store = CapturedWorkCoordinator(), scene = UUID(), editor = UUID()
        let token = try session(store), original = try scope()
        XCTAssertTrue(store.bindAuthorizedScope(original, sceneID: scene, session: token))
        let handle = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertEqual(store.editNote(handle, text: "Before", expectedRevision: nil), .updated)
        let revision = try XCTUnwrap(store.note(handle)?.revision)
        var fired = false
        let subscription = store.objectWillChange.sink { _ in
            guard !fired else { return }; fired = true; store.invalidateAllScopes()
        }
        XCTAssertNotEqual(store.editNote(handle, text: "After", expectedRevision: revision), .updated)
        XCTAssertNil(store.note(handle))
        subscription.cancel()
        let resumed = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(original, sceneID: scene, session: resumed))
        let newHandle = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertEqual(store.note(newHandle)?.text, "Before")
    }

    func testOwnerChangeDuringBindingCannotInstallRetiredScope() throws {
        let store = CapturedWorkCoordinator(), scene = UUID()
        let original = try session(store)
        var fired = false
        let subscription = store.objectWillChange.sink { _ in
            guard !fired else { return }; fired = true
            _ = store.beginVerifiedSession(actorID: "actor-b", organizationID: "workspace-a", origin: "https://app.thorbis.com")
        }
        XCTAssertFalse(store.bindAuthorizedScope(try scope(), sceneID: scene, session: original))
        XCTAssertNil(store.openNote(sceneID: scene, editorID: UUID()))
        subscription.cancel()
        let other = try session(store, actor: "actor-b")
        XCTAssertTrue(store.bindAuthorizedScope(try scope(actor: "actor-b"), sceneID: scene, session: other))
    }

    func testNestedEditDuringPublicationCannotOverwriteOrDoubleCount() throws {
        let store = CapturedWorkCoordinator(maxDrafts: 2, maxTotalUTF16: 8), scene = UUID()
        let token = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: scene, session: token))
        let handle = try XCTUnwrap(store.openNote(sceneID: scene, editorID: UUID()))
        XCTAssertEqual(store.editNote(handle, text: "one", expectedRevision: nil), .updated)
        let revision = try XCTUnwrap(store.note(handle)?.revision)
        var nested: CapturedNoteEditResult?, fired = false
        let subscription = store.objectWillChange.sink { _ in
            guard !fired else { return }; fired = true
            nested = store.editNote(handle, text: "nested", expectedRevision: revision)
        }
        XCTAssertEqual(store.editNote(handle, text: "two", expectedRevision: revision), .updated)
        XCTAssertNotEqual(nested, .updated)
        XCTAssertEqual(store.note(handle)?.text, "two")
        subscription.cancel()
        let other = try XCTUnwrap(store.openNote(sceneID: scene, editorID: UUID()))
        XCTAssertEqual(store.editNote(other, text: "three", expectedRevision: nil), .updated)
    }

    func testNestedDiscardDoesNotCorruptCapacity() throws {
        let store = CapturedWorkCoordinator(maxDrafts: 1, maxTotalUTF16: 3), scene = UUID()
        let token = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: scene, session: token))
        let handle = try XCTUnwrap(store.openNote(sceneID: scene, editorID: UUID()))
        XCTAssertEqual(store.editNote(handle, text: "one", expectedRevision: nil), .updated)
        XCTAssertTrue(store.closeNote(handle))
        let candidate = try XCTUnwrap(store.recoverableNotes(sceneID: scene).first)
        var nested = false, fired = false
        let subscription = store.objectWillChange.sink { _ in
            guard !fired else { return }; fired = true
            nested = store.discardNote(candidate, expectedRevision: candidate.snapshot.revision)
        }
        XCTAssertTrue(store.discardNote(candidate, expectedRevision: candidate.snapshot.revision))
        XCTAssertFalse(nested)
        subscription.cancel()
        let next = try XCTUnwrap(store.openNote(sceneID: scene, editorID: UUID()))
        XCTAssertEqual(store.editNote(next, text: "new", expectedRevision: nil), .updated)
        let extra = try XCTUnwrap(store.openNote(sceneID: scene, editorID: UUID()))
        XCTAssertEqual(store.editNote(extra, text: "x", expectedRevision: nil), .capacityExceeded)
    }

    func testNestedReopenDoesNotGetSilentlyRetiredByClose() throws {
        let store = CapturedWorkCoordinator(), scene = UUID(), editor = UUID()
        let token = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: scene, session: token))
        let handle = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        var attempted: CapturedNoteHandle?, fired = false
        let subscription = store.objectWillChange.sink { _ in
            guard !fired else { return }; fired = true
            attempted = store.openNote(sceneID: scene, editorID: editor)
        }
        XCTAssertTrue(store.closeNote(handle))
        XCTAssertNil(attempted)
        subscription.cancel()
        let reopened = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertEqual(store.editNote(reopened, text: "New", expectedRevision: nil), .updated)
    }

    func testOpeningSameLiveEditorDoesNotRetireItsExistingHandle() throws {
        let store = CapturedWorkCoordinator(), scene = UUID(), editor = UUID()
        let token = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: scene, session: token))
        let first = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        let again = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertEqual(first, again)
        XCTAssertEqual(store.editNote(first, text: "Keep", expectedRevision: nil), .updated)
    }
}
