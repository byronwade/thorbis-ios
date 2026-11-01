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
        UNUserNotificationCenter.current().setNotificationCategories(NotificationActions.categories)
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
                                      appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                                      timeZone: TimeZone.current.identifier, morningDigest: Self.morningDigest)
        _ = try? await api.send("POST", "/v1/devices", body: body) as DeviceRegistered
    }

    // MARK: Morning digest (design.thorbis.com/team-goals TG-11)

    private static let morningDigestKey = "thorbis.push.morningDigest"

    /// The 6:30 digest switch for this phone. On until turned off. Kept on the phone and sent with
    /// every registration, so a change made offline reaches the server on the next launch.
    static var morningDigest: Bool {
        get { UserDefaults.standard.object(forKey: morningDigestKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: morningDigestKey) }
    }

    func setMorningDigest(_ on: Bool) {
        Self.morningDigest = on
        Task { await register() }
    }

    /// Owners and managers: the people the server sends a digest to (it decides; this only hides the switch).
    static func receivesMorningDigest(_ session: SessionController) -> Bool {
        session.can("invoice.create", feature: "invoicing") && session.can("job.assign", feature: "jobs")
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
        // "On my way" runs in the background through the same path as the Lock Screen card; if it
        // can't (signed out, no permission, the job already moved on) the phone says so and the
        // job opens next time Thorbis does.
        if response.actionIdentifier == NotificationActions.onMyWay, let jobID {
            do {
                try await JobStepIntentRunner.run(jobID: jobID, target: "en_route")
            } catch {
                await MainActor.run { store?.requestedJobID = jobID }
                await NotificationActions.reportFailure(error, jobID: jobID)
            }
            return
        }
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        let digest = Self.isMorningDigest(userInfo)
        await MainActor.run {
            // TG-11: the digest opens Today.
            if digest { store?.openedForRecord = true; store?.requestedSchedule += 1 }
            else if let jobID { store?.requestedJobID = jobID } else if let record { store?.requestedRecord = record }
        }
    }

    nonisolated static func isMorningDigest(_ userInfo: [AnyHashable: Any]) -> Bool {
        (userInfo["thorbis"] as? [String: Any])?["kind"] as? String == "morning.digest"
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

/// Actions on job, estimate and payment notifications. A push shows them when it names one of
/// these categories in `aps.category` and carries the matching id under `thorbis`.
enum NotificationActions {
    static let job = "thorbis.job"
    static let estimate = "thorbis.estimate"
    static let invoice = "thorbis.invoice"
    static let open = "thorbis.open"
    static let onMyWay = "thorbis.on-my-way"

    static var categories: Set<UNNotificationCategory> {
        let open = UNNotificationAction(identifier: open, title: "Open", options: [.foreground],
                                        icon: UNNotificationActionIcon(systemImageName: "arrow.up.forward.app"))
        // Marks the job On my way (the customer may be told), so it asks for Face ID or the passcode.
        let onMyWay = UNNotificationAction(identifier: onMyWay, title: "On my way", options: [.authenticationRequired],
                                           icon: UNNotificationActionIcon(systemImageName: "car"))
        return [UNNotificationCategory(identifier: job, actions: [open, onMyWay], intentIdentifiers: []),
                UNNotificationCategory(identifier: estimate, actions: [open], intentIdentifiers: []),
                UNNotificationCategory(identifier: invoice, actions: [open], intentIdentifiers: [])]
    }

    /// A step from a notification didn't go through: say so with the reason, and offer the job.
    static func reportFailure(_ error: Error, jobID: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Couldn't mark On my way"
        content.body = error.localizedDescription
        content.categoryIdentifier = job
        content.userInfo = ["thorbis": ["jobId": jobID]]
        let request = UNNotificationRequest(identifier: "on-my-way-failed-\(jobID)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

struct DeviceRegistration: Encodable {
    let installationId: String
    let token: String
    let environment: String
    let appVersion: String?
    let timeZone: String?
    let morningDigest: Bool
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
