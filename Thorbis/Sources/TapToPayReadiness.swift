import Foundation

/// Release intent is separate from hardware support and never grants an Apple capability.
/// Enabled archives must pass scripts/audit_tap_to_pay_build.py before distribution.
enum TapToPayReadiness {
    static let buildPolicyKey = "ThorbisTapToPayEnabled"

    static var buildEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: buildPolicyKey) as? Bool == true
    }

    static func allows(buildEnabled: Bool, deviceSupported: @autoclosure () -> Bool,
                       featureEnabled: Bool, canCollect: Bool) -> Bool {
        buildEnabled && featureEnabled && canCollect && deviceSupported()
    }
}
