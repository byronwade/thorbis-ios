import XCTest
@testable import Thorbis

@MainActor
final class TapToPayReadinessTests: XCTestCase {
    func testUnqualifiedBuildOverridesAnOtherwiseEligibleWorkspaceAndPhone() {
        XCTAssertFalse(TapToPayReadiness.allows(
            buildEnabled: false, deviceSupported: true, featureEnabled: true, canCollect: true
        ))
    }

    func testQualifiedBuildStillNeedsTheDeviceFeatureAndPermission() {
        XCTAssertTrue(TapToPayReadiness.allows(
            buildEnabled: true, deviceSupported: true, featureEnabled: true, canCollect: true
        ))
        XCTAssertFalse(TapToPayReadiness.allows(
            buildEnabled: true, deviceSupported: false, featureEnabled: true, canCollect: true
        ))
        XCTAssertFalse(TapToPayReadiness.allows(
            buildEnabled: true, deviceSupported: true, featureEnabled: false, canCollect: true
        ))
        XCTAssertFalse(TapToPayReadiness.allows(
            buildEnabled: true, deviceSupported: true, featureEnabled: true, canCollect: false
        ))
    }

    func testUnqualifiedBuildDoesNotInitializeAReaderProbe() {
        var probed = false
        func probe() -> Bool { probed = true; return true }
        XCTAssertFalse(TapToPayReadiness.allows(
            buildEnabled: false, deviceSupported: probe(), featureEnabled: true, canCollect: true
        ))
        XCTAssertFalse(probed)
    }

    func testUnavailableBuildNeverCreatesACardPresentIntent() async {
        let api = APIClient(session: URLProtocolFixture.session([]), baseURL: "https://app.thorbis.com")
        let controller = TapToPayController(invoiceID: "00000000-0000-4000-8000-00000000000a")
        var refreshed = false

        await controller.charge(api: api) {
            refreshed = true
            return false
        }

        XCTAssertEqual(controller.phase, .unavailable)
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
        XCTAssertFalse(refreshed)
    }
}
