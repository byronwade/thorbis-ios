import XCTest
@testable import Thorbis

final class PushNotificationsTests: XCTestCase {
    func testRegistrationBodyMatchesTheDevicesContract() throws {
        let body = DeviceRegistration(installationId: "6f1c2a3e-0000-4000-8000-000000000001", token: "ab01ff",
                                      environment: "production", appVersion: "1.0")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: String]
        XCTAssertEqual(json, ["installationId": "6f1c2a3e-0000-4000-8000-000000000001", "token": "ab01ff",
                              "environment": "production", "appVersion": "1.0"])
    }

    func testTapOnAJobNotificationOpensThatJob() {
        let payload: [AnyHashable: Any] = ["aps": ["alert": ["title": "New job"]],
                                           "thorbis": ["kind": "job.assigned", "organizationId": "org", "jobId": "job-1"]]
        XCTAssertEqual(PushNotifications.jobID(from: payload), "job-1")
        XCTAssertNil(PushNotifications.jobID(from: ["thorbis": ["kind": "payment.received", "invoiceId": "inv"]]))
        XCTAssertNil(PushNotifications.jobID(from: [:]))
    }

    @MainActor func testInstallationIDIsStable() {
        XCTAssertEqual(PushNotifications.installationID, PushNotifications.installationID)
        XCTAssertEqual(PushNotifications.environment, "development")
    }
}
