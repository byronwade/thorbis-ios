import XCTest
@testable import Thorbis

final class VerifiedJobNotesCacheTests: XCTestCase {
    func testCompleteCopyIsBoundToActorAndAuthority() {
        let actor = UUID().uuidString.lowercased()
        let org = UUID().uuidString.lowercased()
        let job = UUID().uuidString.lowercased()
        let note = JobNoteRecord(id: UUID().uuidString.lowercased(), organizationId: org, jobId: job,
                                 authorUserId: actor, body: "Synthetic cache note", createdAt: "2026-11-12T00:00:00Z")
        let scope = JobDetailCache.VerifiedNotesScope(actorID: actor, organizationID: org, jobID: job,
            origin: "https://app.thorbis.com", policyVersion: 1, authorityGeneration: "synthetic", authorityRevision: UUID())
        JobDetailCache.saveVerifiedNotes([note], scope: scope)
        XCTAssertEqual(JobDetailCache.verifiedNotes(scope: scope), [note])
        let anotherActor = JobDetailCache.VerifiedNotesScope(actorID: UUID().uuidString.lowercased(), organizationID: org,
            jobID: job, origin: scope.origin, policyVersion: scope.policyVersion, authorityGeneration: scope.authorityGeneration, authorityRevision: scope.authorityRevision)
        XCTAssertNil(JobDetailCache.verifiedNotes(scope: anotherActor))
        let revoked = JobDetailCache.VerifiedNotesScope(actorID: actor, organizationID: org, jobID: job,
            origin: scope.origin, policyVersion: 2, authorityGeneration: scope.authorityGeneration, authorityRevision: scope.authorityRevision)
        XCTAssertNil(JobDetailCache.verifiedNotes(scope: revoked))
        let moved = JobDetailCache.VerifiedNotesScope(actorID: actor, organizationID: org, jobID: job,
            origin: scope.origin, policyVersion: scope.policyVersion, authorityGeneration: "new-authority", authorityRevision: scope.authorityRevision)
        XCTAssertNil(JobDetailCache.verifiedNotes(scope: moved))
        let refreshed = JobDetailCache.VerifiedNotesScope(actorID: actor, organizationID: org, jobID: job,
            origin: scope.origin, policyVersion: scope.policyVersion, authorityGeneration: scope.authorityGeneration,
            authorityRevision: UUID())
        XCTAssertNil(JobDetailCache.verifiedNotes(scope: refreshed), "A new authority revision must reauthorize this specific job")
    }
}
