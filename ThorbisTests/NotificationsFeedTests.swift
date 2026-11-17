import XCTest
@testable import Thorbis

final class NotificationsFeedTests: XCTestCase {
    private func notice(_ id: String, read: Bool, at: String? = "2026-11-17T17:00:00Z", job: String = "job-1") -> StaffNotice {
        StaffNotice(id: id, jobId: job, title: "Dispatch assigned you a job", meta: "JOB-2231", at: at, read: read)
    }

    func testAPageReadTwiceShowsEachNoticeOnceWithTheNewerReadState() {
        let first = [notice("a", read: false), notice("b", read: false)]
        let second = [notice("b", read: true), notice("c", read: true)]
        let merged = NotificationsFeed.merged(first, adding: second)
        XCTAssertEqual(merged.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(merged.map(\.read), [false, true, true])
        XCTAssertTrue(NotificationsFeed.merged([], adding: []).isEmpty)
    }

    func testNewestFirstWithUndatedLast() {
        let list = [notice("old", read: true, at: "2026-11-10T10:00:00Z"), notice("undated", read: true, at: nil),
                    notice("new", read: false, at: "2026-11-17T10:00:00Z"), notice("same-1", read: true, at: "2026-11-12T10:00:00Z"),
                    notice("same-2", read: true, at: "2026-11-12T10:00:00Z")]
        XCTAssertEqual(NotificationsFeed.ordered(list).map(\.id), ["new", "same-1", "same-2", "old", "undated"])
    }

    func testUnreadNarrowsTheList() {
        let list = [notice("a", read: false, at: "2026-11-17T10:00:00Z"), notice("b", read: true, at: "2026-11-16T10:00:00Z"),
                    notice("c", read: false, at: "2026-11-15T10:00:00Z")]
        XCTAssertEqual(NotificationsFeed.visible(list, filter: .all).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(NotificationsFeed.visible(list, filter: .unread).map(\.id), ["a", "c"])
        XCTAssertEqual(NotificationsFeed.unreadCount(list), 2)
    }

    func testGroupsPutNewOverEarlierOnlyWhenBothExist() {
        let mixed = [notice("a", read: false, at: "2026-11-17T10:00:00Z"), notice("b", read: true, at: "2026-11-16T10:00:00Z"),
                     notice("c", read: false, at: "2026-11-15T10:00:00Z")]
        let groups = NotificationsFeed.groups(mixed, filter: .all)
        XCTAssertEqual(groups.map(\.title), ["New", "Earlier"])
        XCTAssertEqual(groups.map { $0.notices.map(\.id) }, [["a", "c"], ["b"]])

        // Paper 77's one card, without a label, when everything is unread, read, or narrowed to unread.
        let allUnread = NotificationsFeed.groups([notice("a", read: false), notice("b", read: false)], filter: .all)
        XCTAssertEqual(allUnread.map(\.title), [""])
        XCTAssertEqual(allUnread.first?.notices.count, 2)
        XCTAssertEqual(NotificationsFeed.groups([notice("a", read: true)], filter: .all).map(\.title), [""])
        XCTAssertEqual(NotificationsFeed.groups(mixed, filter: .unread).map { $0.notices.map(\.id) }, [["a", "c"]])
        XCTAssertTrue(NotificationsFeed.groups([notice("a", read: true)], filter: .unread).isEmpty)
        XCTAssertTrue(NotificationsFeed.groups([], filter: .all).isEmpty)
    }

    func testSubtitleCountsOnlyWhenEveryPageIsHere() {
        let list = [notice("a", read: false), notice("b", read: false), notice("c", read: true), notice("d", read: false)]
        XCTAssertEqual(NotificationsFeed.subtitle(notices: list, complete: true, unreadState: .present, loading: false), "3 unread")
        XCTAssertEqual(NotificationsFeed.subtitle(notices: list, complete: false, unreadState: .present, loading: false), "3 unread so far")
        XCTAssertEqual(NotificationsFeed.subtitle(notices: [notice("c", read: true)], complete: false, unreadState: .present, loading: false),
                       "Unread notices waiting")
        XCTAssertEqual(NotificationsFeed.subtitle(notices: [notice("c", read: true)], complete: true, unreadState: .none, loading: false),
                       "All caught up")
        XCTAssertEqual(NotificationsFeed.subtitle(notices: [], complete: false, unreadState: .unknown, loading: true),
                       "Checking for new notices\u{2026}")
        XCTAssertEqual(NotificationsFeed.subtitle(notices: [], complete: false, unreadState: .unknown, loading: false), "Job updates")
    }
}
