import XCTest

final class PrivacyPurposeTests: XCTestCase {
    // App Store Connect warns (ITMS-90683) when a linked API has no purpose string: the schedule map's
    // location button needs location, and the Stripe Terminal SDK links Bluetooth and location.
    func testEveryLinkedPermissionHasAPurpose() {
        let info = Bundle.main.infoDictionary ?? [:]
        for key in ["NSCameraUsageDescription", "NSFaceIDUsageDescription",
                    "NSBluetoothAlwaysUsageDescription", "NSLocationWhenInUseUsageDescription"] {
            let purpose = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            XCTAssertFalse(purpose.isEmpty, "\(key) is missing from the app's Info.plist")
        }
    }
}
