import XCTest
import StripeTerminal
@testable import Thorbis

@MainActor
final class TapToPayReadinessTests: XCTestCase {
    func testTechnicianReaderConfigurationCannotPresentMerchantTerms() throws {
        let configuration = try TerminalSetup.connectionConfiguration(locationID: "tml_test_location")
        XCTAssertFalse(configuration.isTOSAcceptancePermitted)
    }

    func testUnacceptedMerchantTermsDirectTechnicianToAdministrator() {
        let error = NSError(domain: ErrorDomain, code: ErrorCode.Code.tapToPayReaderTOSNotYetAccepted.rawValue)
        XCTAssertEqual(TapToPayController.message(for: error),
                       "Tap to Pay needs setup. Ask your business administrator to complete the merchant terms, or use another payment method.")
    }

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

        await controller.charge(api: api) { _ in
            refreshed = true
            return false
        }

        XCTAssertEqual(controller.phase, .unavailable)
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
        XCTAssertFalse(refreshed)
    }
}
