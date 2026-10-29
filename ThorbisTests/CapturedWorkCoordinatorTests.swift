import XCTest
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
        XCTAssertTrue(store.editNote(handle, text: "Original field note", expectedRevision: nil))
        store.invalidateAllScopes()
        XCTAssertNil(store.note(handle))
        XCTAssertFalse(store.editNote(handle, text: "Late callback", expectedRevision: nil))
        let otherSession = try session(store, actor: "actor-b")
        XCTAssertTrue(store.bindAuthorizedScope(try scope(actor: "actor-b"), sceneID: scene, session: otherSession))
        XCTAssertNil(store.note(handle))
        let other = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertNil(store.note(other))
        let resumedSession = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(original, sceneID: scene, session: resumedSession))
        let resumed = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertEqual(store.note(resumed)?.text, "Original field note")
        XCTAssertFalse(store.editNote(handle, text: "Old session", expectedRevision: nil))
    }

    func testSameJobEditorsKeepIndependentDraftsAndRevisions() throws {
        let store = CapturedWorkCoordinator()
        let firstScene = UUID(), secondScene = UUID()
        let token = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: firstScene, session: token))
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: secondScene, session: token))
        let first = try XCTUnwrap(store.openNote(sceneID: firstScene, editorID: UUID()))
        let second = try XCTUnwrap(store.openNote(sceneID: secondScene, editorID: UUID()))
        XCTAssertTrue(store.editNote(first, text: "First scene", expectedRevision: nil))
        XCTAssertTrue(store.editNote(second, text: "Second scene", expectedRevision: nil))
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
        XCTAssertTrue(store.editNote(handle, text: "First", expectedRevision: nil))
        let oldRevision = try XCTUnwrap(store.note(handle)?.revision)
        XCTAssertTrue(store.editNote(handle, text: "Newer", expectedRevision: oldRevision))
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
        XCTAssertTrue(store.editNote(first, text: "First job", expectedRevision: nil))
        XCTAssertTrue(store.editNote(second, text: "Second job", expectedRevision: nil))
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
        XCTAssertTrue(store.editNote(old, text: "Original owner", expectedRevision: nil))
        let otherSession = try session(store, workspace: "workspace-b")
        XCTAssertTrue(store.bindAuthorizedScope(try scope(workspace: "workspace-b"), sceneID: secondScene, session: otherSession))
        XCTAssertNil(store.note(old))
        XCTAssertFalse(store.editNote(old, text: "Wrong workspace", expectedRevision: nil))
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
        XCTAssertTrue(store.editNote(oldHandle, text: "Original", expectedRevision: nil))
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
        XCTAssertTrue(store.editNote(handle, text: "First", expectedRevision: nil))
        let first = try XCTUnwrap(store.note(handle))
        XCTAssertTrue(store.editNote(handle, text: "Newer", expectedRevision: first.revision))
        XCTAssertFalse(store.editNote(handle, text: "Delayed older edit", expectedRevision: first.revision))
        XCTAssertEqual(store.note(handle)?.text, "Newer")
    }

    func testOriginSwitchCannotReadOrOverwriteOriginalDraft() throws {
        let store = CapturedWorkCoordinator(), scene = UUID(), editor = UUID()
        let original = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: scene, session: original))
        let old = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertTrue(store.editNote(old, text: "Original", expectedRevision: nil))
        let local = try session(store, origin: "http://localhost:3000")
        XCTAssertTrue(store.bindAuthorizedScope(try scope(origin: "http://localhost:3000"), sceneID: scene, session: local))
        XCTAssertNil(store.note(old))
        let other = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertNil(store.note(other))
        XCTAssertFalse(store.editNote(old, text: "Wrong origin", expectedRevision: nil))
    }

    func testOversizeNoteDoesNotReplaceExistingDraft() throws {
        let store = CapturedWorkCoordinator(), scene = UUID()
        let token = try session(store)
        XCTAssertTrue(store.bindAuthorizedScope(try scope(), sceneID: scene, session: token))
        let handle = try XCTUnwrap(store.openNote(sceneID: scene, editorID: UUID()))
        XCTAssertTrue(store.editNote(handle, text: "Keep", expectedRevision: nil))
        let saved = try XCTUnwrap(store.note(handle))
        XCTAssertFalse(store.editNote(handle, text: String(repeating: "a", count: 10_001), expectedRevision: saved.revision))
        XCTAssertEqual(store.note(handle), saved)
    }

    func testReauthorizingSameScopeRetiresOldHandleButKeepsDraft() throws {
        let store = CapturedWorkCoordinator(), scene = UUID(), editor = UUID()
        let token = try session(store), currentScope = try scope()
        XCTAssertTrue(store.bindAuthorizedScope(currentScope, sceneID: scene, session: token))
        let old = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertTrue(store.editNote(old, text: "Keep", expectedRevision: nil))
        XCTAssertTrue(store.bindAuthorizedScope(currentScope, sceneID: scene, session: token))
        XCTAssertNil(store.note(old))
        let new = try XCTUnwrap(store.openNote(sceneID: scene, editorID: editor))
        XCTAssertEqual(store.note(new)?.text, "Keep")
    }
}
