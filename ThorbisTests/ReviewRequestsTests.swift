import XCTest
@testable import Thorbis

final class ReviewRequestsTests: XCTestCase {
    func testReviewLinkAcceptsOneShortHTTPSLink() {
        XCTAssertEqual(ReviewLink.validated("  https://g.page/r/wadesplumbing/review "),
                       "https://g.page/r/wadesplumbing/review")
    }

    func testReviewLinkRefusesWhatTheServerRefuses() {
        for link in ["http://g.page/r/x", "https://localhost/review", "https://user:pw@example.com/r",
                     "https://example.com/a b", "https://example.com/" + String(repeating: "r", count: 90),
                     "not a link", ""] {
            XCTAssertNil(ReviewLink.validated(link), link)
        }
    }

    func testPendingFactsKeepOnlyTheLastValuePerFact() {
        let defaults = UserDefaults(suiteName: "ReviewRequestsTests.\(UUID().uuidString)")!
        let store = PendingOrganizationFacts(defaults: defaults)
        store.put(.init(key: "review_requests", value: "off"), actorID: "A", organizationID: "O")
        store.put(.init(key: "review_link", value: "https://g.page/r/x"), actorID: "A", organizationID: "O")
        store.put(.init(key: "review_requests", value: "on"), actorID: "A", organizationID: "O")
        XCTAssertEqual(store.changes(actorID: "a", organizationID: "o"), [
            .init(key: "review_link", value: "https://g.page/r/x"),
            .init(key: "review_requests", value: "on"),
        ])
        store.remove(.init(key: "review_link", value: "https://g.page/r/x"), actorID: "A", organizationID: "O")
        XCTAssertEqual(store.changes(actorID: "A", organizationID: "O").map(\.key), ["review_requests"])
    }

    func testRemovingASentValueKeepsANewerOneSavedMeanwhile() {
        let defaults = UserDefaults(suiteName: "ReviewRequestsTests.\(UUID().uuidString)")!
        let store = PendingOrganizationFacts(defaults: defaults)
        let sent = PendingOrganizationFacts.Change(key: "review_link", value: "https://g.page/r/a")
        store.put(sent, actorID: "A", organizationID: "O")
        store.put(.init(key: "review_link", value: "https://g.page/r/b"), actorID: "A", organizationID: "O")
        store.remove(sent, actorID: "A", organizationID: "O")
        XCTAssertEqual(store.changes(actorID: "A", organizationID: "O"),
                       [.init(key: "review_link", value: "https://g.page/r/b")])
    }

    func testPendingFactsNeverCrossActorsOrCompanies() {
        let defaults = UserDefaults(suiteName: "ReviewRequestsTests.\(UUID().uuidString)")!
        let store = PendingOrganizationFacts(defaults: defaults)
        store.put(.init(key: "review_requests", value: "off"), actorID: "A", organizationID: "O")
        XCTAssertTrue(store.changes(actorID: "B", organizationID: "O").isEmpty)
        XCTAssertTrue(store.changes(actorID: "A", organizationID: "P").isEmpty)
        store.clearAll()
        XCTAssertTrue(store.changes(actorID: "A", organizationID: "O").isEmpty)
    }
}
