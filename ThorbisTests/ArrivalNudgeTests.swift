import XCTest
import CoreLocation
@testable import Thorbis

final class ArrivalNudgeTests: XCTestCase {
    private let place = FieldCoordinates(latitude: 37.7749, longitude: -122.4194)

    func testDistanceMatchesKnownGround() {
        XCTAssertEqual(ArrivalNudge.distanceMeters(latitude: place.latitude, longitude: place.longitude, to: place), 0, accuracy: 0.001)
        // One thousandth of a degree of latitude is about 111 m anywhere on Earth.
        XCTAssertEqual(ArrivalNudge.distanceMeters(latitude: place.latitude + 0.001, longitude: place.longitude, to: place), 111.2, accuracy: 0.5)
        // San Francisco to Oakland city halls, about 13.4 km.
        XCTAssertEqual(ArrivalNudge.distanceMeters(latitude: 37.8044, longitude: -122.2712, to: place), 13_400, accuracy: 200)
    }

    func testNearMeansInsideAbout125MetersWithAUsableFix() {
        XCTAssertTrue(ArrivalNudge.isNear(distanceMeters: 0, accuracyMeters: 5))
        XCTAssertTrue(ArrivalNudge.isNear(distanceMeters: 125, accuracyMeters: 30))
        XCTAssertFalse(ArrivalNudge.isNear(distanceMeters: 126, accuracyMeters: 5))
        XCTAssertFalse(ArrivalNudge.isNear(distanceMeters: 20, accuracyMeters: 101), "A vague fix can't say you're here")
        XCTAssertFalse(ArrivalNudge.isNear(distanceMeters: 20, accuracyMeters: -1), "An invalid fix is ignored")
    }

    func testItWatchesOnlyOnTheWayInTheForegroundWithAPlaceAndLocationAllowed() {
        func watches(status: String = "en_route", active: Bool = true, canArrive: Bool = true, pending: Bool = false,
                     place: FieldCoordinates? = FieldCoordinates(latitude: 37.7749, longitude: -122.4194),
                     allowed: Bool = true, dismissed: Bool = false) -> Bool {
            ArrivalNudge.watches(status: status, appActive: active, canArrive: canArrive, hasPendingStatus: pending,
                                 place: place, locationAllowed: allowed, dismissed: dismissed)
        }
        XCTAssertTrue(watches())
        for status in ["scheduled", "dispatched", "arrived", "in_progress", "paused", "completed", "canceled"] {
            XCTAssertFalse(watches(status: status), status)
        }
        XCTAssertFalse(watches(active: false), "Never in the background")
        XCTAssertFalse(watches(canArrive: false))
        XCTAssertFalse(watches(pending: true), "A step is already waiting to send")
        XCTAssertFalse(watches(place: nil), "No coordinates: do nothing")
        XCTAssertFalse(watches(place: FieldCoordinates(latitude: 0, longitude: 0)))
        XCTAssertFalse(watches(place: FieldCoordinates(latitude: 120, longitude: 10)))
        XCTAssertFalse(watches(allowed: false), "Location denied or never asked: do nothing")
        XCTAssertFalse(watches(dismissed: true))
    }

    func testOnlyAllowedLocationCounts() {
        XCTAssertTrue(ArrivalNudge.locationAllowed(.authorizedWhenInUse))
        XCTAssertTrue(ArrivalNudge.locationAllowed(.authorizedAlways))
        XCTAssertFalse(ArrivalNudge.locationAllowed(.notDetermined), "Never asks for location itself")
        XCTAssertFalse(ArrivalNudge.locationAllowed(.denied))
        XCTAssertFalse(ArrivalNudge.locationAllowed(.restricted))
    }

    func testADismissedJobIsNotAskedAgainAndTheListStaysSmall() throws {
        let suite = "arrival-nudge-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let dismissals = ArrivalNudgeDismissals(defaults: defaults)
        XCTAssertFalse(dismissals.contains("job-1"))
        dismissals.dismiss("job-1")
        dismissals.dismiss("job-1")
        XCTAssertTrue(ArrivalNudgeDismissals(defaults: defaults).contains("job-1"), "Kept across launches")
        XCTAssertFalse(dismissals.contains("job-2"), "Only that job")
        XCTAssertEqual(defaults.stringArray(forKey: ArrivalNudgeDismissals.key)?.count, 1)
        for index in 0..<(ArrivalNudgeDismissals.limit + 20) { dismissals.dismiss("other-\(index)") }
        XCTAssertEqual(defaults.stringArray(forKey: ArrivalNudgeDismissals.key)?.count, ArrivalNudgeDismissals.limit)
        XCTAssertTrue(dismissals.contains("other-\(ArrivalNudgeDismissals.limit + 19)"))
    }

    func testTheNudgeArrivesWithTheGeofenceMethodOnlineAndQueued() throws {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(FieldProgressRequest.arrived(method: .geofence))) as? [String: Any])
        XCTAssertEqual(body["to"] as? String, "arrived")
        XCTAssertEqual((body["arrival"] as? [String: String])?["method"], "geofence")
        let queued = try XCTUnwrap(OutboxEntry.ProgressPayload(jobID: "job-1", request: .arrived(method: .geofence)))
        XCTAssertEqual(queued.to, "arrived")
        XCTAssertEqual(queued.arrival?.method, "geofence")
    }
}
