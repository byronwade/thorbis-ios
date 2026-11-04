import XCTest
@testable import Thorbis

final class CustomerPhotoSelectionTests: XCTestCase {
    private let job = "job-a"
    private let org = "org-a"
    private func photo(_ id: String, job: String = "job-a", kind: String = "photo", state: String = "stored", archived: Bool = false) -> CustomerPhotoMetadata {
        CustomerPhotoMetadata(id: id, jobId: job, kind: kind, uploadState: state, archived: archived)
    }

    func testExplicitSelectionIsOrderedAndRequiresEveryFreshRecord() throws {
        let selected = try CustomerPhotoSelection(jobID: job, organizationID: org, selectedIDs: ["b", "a"])
        XCTAssertEqual(try selected.validateFresh([photo("a"), photo("b")]).map(\.id), ["b", "a"])
        XCTAssertThrowsError(try selected.validateFresh([photo("a")]))
        XCTAssertThrowsError(try selected.validateFresh([photo("a"), photo("b"), photo("c")]))
    }

    func testInvalidSelectionNeverSilentlyDropsRecords() throws {
        XCTAssertThrowsError(try CustomerPhotoSelection(jobID: job, organizationID: org, selectedIDs: []))
        XCTAssertThrowsError(try CustomerPhotoSelection(jobID: job, organizationID: org, selectedIDs: ["a", "a"]))
        XCTAssertThrowsError(try CustomerPhotoSelection(jobID: job, organizationID: org, selectedIDs: (0..<51).map(String.init)))
        let selected = try CustomerPhotoSelection(jobID: job, organizationID: org, selectedIDs: ["a"])
        for asset in [photo("a", job: "other"), photo("a", kind: "document"), photo("a", state: "pending"), photo("a", archived: true)] {
            XCTAssertThrowsError(try selected.validateFresh([asset]))
        }
        XCTAssertThrowsError(try selected.validateFresh([photo("a"), photo("a")]))
    }

    func testSelectionMustComeFromCurrentValidatedJobAndOrganization() throws {
        let selected = try CustomerPhotoSelection(jobID: job, organizationID: org, selectedIDs: ["a", "b"])
        XCTAssertNoThrow(try selected.validatePageMembership(ids: ["a", "b", "c"], jobID: job, organizationID: org))
        XCTAssertThrowsError(try selected.validatePageMembership(ids: ["a"], jobID: job, organizationID: org))
        XCTAssertThrowsError(try selected.validatePageMembership(ids: ["a", "b"], jobID: "other", organizationID: org))
        XCTAssertThrowsError(try selected.validatePageMembership(ids: ["a", "b"], jobID: job, organizationID: "other"))
    }
}
