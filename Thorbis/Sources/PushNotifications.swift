import Foundation
import Security
import UIKit
import UserNotifications

/// Registers this install for job and payment notifications (POST /v1/devices) and routes taps.
/// Push stays dark on the server until the APNs key is configured, so every failure here is
/// silent: a 403, 404 or 503 just means "push unavailable for now".
@MainActor
final class PushNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotifications()

    weak var api: APIClient?
    weak var store: Store?
    private var token: String?
    private var signedIn = false

    func start(api: APIClient, store: Store) {
        self.api = api
        self.store = store
        UNUserNotificationCenter.current().delegate = self
    }

    /// Called whenever the verified identity changes: a signed-in launch, a sign-in or a workspace switch.
    func identityChanged(signedIn: Bool) {
        self.signedIn = signedIn
        guard signedIn, !Self.disabled else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            let granted = await center.notificationSettings().authorizationStatus
            guard [.authorized, .provisional, .ephemeral].contains(granted) else { return }
            UIApplication.shared.registerForRemoteNotifications()
            await register()
        }
    }

    func received(deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await register() }
    }

    /// Before sign-out or a workspace switch, while the session can still authorize the call.
    func unbind() async {
        guard let api, !Self.disabled else { return }
        _ = try? await api.send("POST", "/v1/devices/unregister", body: ["installationId": Self.installationID]) as DeviceRemoval
    }

    private func register() async {
        guard signedIn, let api, let token, !Self.disabled else { return }
        let body = DeviceRegistration(installationId: Self.installationID, token: token, environment: Self.environment,
                                      appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        _ = try? await api.send("POST", "/v1/devices", body: body) as DeviceRegistered
    }

    // MARK: Notification center

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        let jobID = Self.jobID(from: userInfo)
        let record = (userInfo["thorbis"] as? [String: Any]).flatMap(RecordLink.init(push:))
        await MainActor.run {
            if let jobID { store?.requestedJobID = jobID } else if let record { store?.requestedRecord = record }
        }
    }

    nonisolated static func jobID(from userInfo: [AnyHashable: Any]) -> String? {
        guard let thorbis = userInfo["thorbis"] as? [String: Any], let jobID = thorbis["jobId"] as? String,
              !jobID.isEmpty else { return nil }
        return jobID
    }

    // MARK: Install identity

    static var environment: String {
        #if DEBUG
        "development"
        #else
        "production"
        #endif
    }

    private static var disabled: Bool {
        #if DEBUG
        PaperPreview.enabled
        #else
        false
        #endif
    }

    private static var cachedInstallationID: String?

    /// Generated once per install and kept in a device-only Keychain item (and in memory, so it
    /// stays stable for this run even if the Keychain is unavailable).
    static var installationID: String {
        if let cachedInstallationID { return cachedInstallationID }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "com.thorbis.field.push-installation",
                                    kSecAttrAccount as String: "installation-id"]
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, let id = String(data: data, encoding: .utf8) {
            cachedInstallationID = id
            return id
        }
        let id = UUID().uuidString.lowercased()
        cachedInstallationID = id
        var add = query
        add[kSecValueData as String] = Data(id.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
        return id
    }
}

struct DeviceRegistration: Encodable {
    let installationId: String
    let token: String
    let environment: String
    let appVersion: String?
}

private struct DeviceRegistered: Decodable { let installationId: String }
private struct DeviceRemoval: Decodable { let installationId: String }

final class ThorbisAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { PushNotifications.shared.received(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulator or no entitlement: push stays off; nothing to show.
    }
}
