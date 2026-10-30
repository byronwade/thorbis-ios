import XCTest
@testable import Thorbis

@MainActor
final class JobNoteReadTests: XCTestCase {
    private let scope = ActivitySnapshotScope(actorID: "actor-a", organizationID: "org-a", recordID: "job-a", generation: UUID(), authorityRevision: UUID(), capability: "job.view", feature: "jobs")
    private func note(job: String = "job-a", organization: String = "org-a") -> JobNoteRecord {
        JobNoteRecord(id: "note-a", organizationId: organization, jobId: job, authorUserId: "actor-a", body: "Private note", createdAt: "2026-10-30T10:00:00Z")
    }

    func testDelayedNotesAreDiscardedWhenAuthorityChanges() async throws {
        let (stream, release) = AsyncStream<Void>.makeStream()
        var current = true
        let pending = Task { @MainActor in
            try await JobNotesReader.read(scope: scope, fetch: {
                for await _ in stream { break }
                return [self.note()]
            }, isCurrent: { current })
        }
        await Task.yield()
        current = false
        release.yield(())
        release.finish()
        let result = try await pending.value
        XCTAssertNil(result, "A late response must not be published under changed authority")
    }

    func testRejectsNotesFromDifferentJobOrWorkspace() async throws {
        for bad in [note(job: "other-job"), note(organization: "other-org")] {
            do {
                _ = try await JobNotesReader.read(scope: scope, fetch: { [bad] }, isCurrent: { true })
                XCTFail("Mismatched note identity must not be accepted")
            } catch { }
        }
    }
}
