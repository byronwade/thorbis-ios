import Foundation
import XCTest
@testable import Thorbis

final class JobPhotoDateGroupingTests: XCTestCase {
    private func photo(_ id: String, _ capturedAt: String?) -> MediaAssetRecord {
        MediaAssetRecord(id: id, organizationId: "org", jobId: "job", uploaderUserId: "user",
                         kind: "photo", mime: "image/jpeg", sizeBytes: 1, originalFilename: "photo.jpg",
                         contentHash: "hash", storageKey: id, capturedAt: capturedAt, uploadState: "stored",
                         tags: [], caption: nil, archived: false, sourceAssetId: nil,
                         createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-01T00:00:00Z")
    }

    func testGroupsLocalDaysNewestFirstAndKeepsServerOrderWithinDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -7 * 3600)!
        let input = [photo("first", "2026-10-27T08:00:00Z"),
                     photo("second", "2026-10-27T09:00:00.123Z"),
                     photo("older", "2026-10-27T02:00:00Z")]
        let groups = JobPhotoDateGroups.group(input, calendar: calendar)
        XCTAssertEqual(groups.map { $0.photos.map(\.id) }, [["first", "second"], ["older"]])
        XCTAssertEqual(groups.map { calendar.component(.day, from: $0.day!) }, [27, 26])
    }

    func testOffsetsAndDaylightSavingTransitionUseTheLocalCaptureDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let groups = JobPhotoDateGroups.group([
            photo("first-hour", "2026-11-01T01:30:00-07:00"),
            photo("second-hour", "2026-11-01T01:30:00.123-08:00"),
            photo("previous-day", "2026-11-01T06:30:00Z")
        ], calendar: calendar)
        XCTAssertEqual(groups.map { $0.photos.map(\.id) }, [["first-hour", "second-hour"], ["previous-day"]])
        XCTAssertEqual(groups.map { calendar.component(.day, from: $0.day!) }, [1, 31])
    }

    func testMissingAndMalformedCaptureDatesStayVisibleWithoutInventedDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let groups = JobPhotoDateGroups.group([photo("missing", nil), photo("bad", "invalid"),
                                               photo("known", "2026-10-27T12:00:00Z")], calendar: calendar)
        XCTAssertEqual(groups.map { $0.photos.map(\.id) }, [["known"], ["missing", "bad"]])
        XCTAssertNotNil(groups[0].day)
        XCTAssertNil(groups[1].day)
    }
}
