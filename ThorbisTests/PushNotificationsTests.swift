import XCTest
@testable import Thorbis

final class PushNotificationsTests: XCTestCase {
    func testRegistrationBodyMatchesTheDevicesContract() throws {
        let body = DeviceRegistration(installationId: "6f1c2a3e-0000-4000-8000-000000000001", token: "ab01ff",
                                      environment: "production", appVersion: "1.0", timeZone: "America/New_York",
                                      morningDigest: false)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertEqual(json["installationId"] as? String, "6f1c2a3e-0000-4000-8000-000000000001")
        XCTAssertEqual(json["token"] as? String, "ab01ff")
        XCTAssertEqual(json["environment"] as? String, "production")
        XCTAssertEqual(json["appVersion"] as? String, "1.0")
        XCTAssertEqual(json["timeZone"] as? String, "America/New_York")
        XCTAssertEqual(json["morningDigest"] as? Bool, false)
        XCTAssertEqual(json.count, 6)
    }

    func testTapOnAJobNotificationOpensThatJob() {
        let payload: [AnyHashable: Any] = ["aps": ["alert": ["title": "New job"]],
                                           "thorbis": ["kind": "job.assigned", "organizationId": "org", "jobId": "job-1"]]
        XCTAssertEqual(PushNotifications.jobID(from: payload), "job-1")
        XCTAssertNil(PushNotifications.jobID(from: ["thorbis": ["kind": "payment.received", "invoiceId": "inv"]]))
        XCTAssertNil(PushNotifications.jobID(from: [:]))
    }

    func testTheMorningDigestOpensToday() {
        // TG-11: the digest names no record; tapping it opens Today.
        XCTAssertTrue(PushNotifications.isMorningDigest(["thorbis": ["kind": "morning.digest", "organizationId": "org"]]))
        XCTAssertFalse(PushNotifications.isMorningDigest(["thorbis": ["kind": "job.assigned", "jobId": "job-1"]]))
        XCTAssertFalse(PushNotifications.isMorningDigest([:]))
    }

    @MainActor func testInstallationIDIsStable() {
        XCTAssertEqual(PushNotifications.installationID, PushNotifications.installationID)
        XCTAssertEqual(PushNotifications.environment, "development")
    }
}
