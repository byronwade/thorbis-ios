import SwiftUI
import UIKit
import UserNotifications

// MARK: - My notifications (Paper "Missing screens" 65C)
//
// What this phone tells the person. `/v1/notice-preferences` only stores choices for a customer or
// for a whole staff role (company-wide, owner-only), so it has no place here. What does belong to
// one person: the system's notification permission for this app, and the morning digest switch the
// phone already keeps (PushNotifications, sent with the device registration). Paper's four category
// switches, Quiet hours and Sound have no route yet; one sentence says so instead of fake switches.

/// The words for this app's notification permission, apart from the view so they are unit-tested.
enum NotificationPermissionWords {
    static func value(_ status: UNAuthorizationStatus?) -> String? {
        switch status {
        case .some(.authorized), .some(.ephemeral): return "On"
        case .some(.provisional): return "Quietly"
        case .some(.denied): return "Off"
        case .some(.notDetermined): return "Turn on"
        default: return nil
        }
    }

    static func hint(_ status: UNAuthorizationStatus?) -> String {
        status == .notDetermined ? "Asks to send you notifications" : "Opens this app's notification settings"
    }
}

/// 65C · My notifications. Push it from Settings (Notifications) or Account and data; it wears the
/// Thorbis back button from `thorbisDestination` / `.thorbisBackButton()` at the call site.
struct MyNotificationsView: View {
    @EnvironmentObject private var session: SessionController
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var permission: UNAuthorizationStatus?
    @State private var morningDigest = PushNotifications.morningDigest

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaperPageTitle(title: "My notifications", subtitle: "What this phone tells you about", columnInset: PaperCardMetrics.margin)
                    .padding(.bottom, 16)

                card {
                    Button { Task { await permissionTapped() } } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Notifications").font(Theme.font(16, weight: .medium)).tracking(-0.16).foregroundStyle(Theme.foreground)
                                Text(AlertWords.summary(payments: PushNotifications.receivesPaymentAlerts(session))).font(Theme.font(14)).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if let value = NotificationPermissionWords.value(permission) {
                                Text(value).font(Theme.font(14)).foregroundStyle(Theme.muted)
                            }
                            PaperIcon(.acctChevron, size: 14, color: Theme.muted)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .frame(minHeight: 64).contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityHint(NotificationPermissionWords.hint(permission))
                    .accessibilityIdentifier("my-notifications-permission")

                    // TG-11: the 6:30 digest goes to owners and managers; the switch is per phone.
                    if PushNotifications.receivesMorningDigest(session) {
                        WellDivider(leading: 16)
                        Toggle(isOn: Binding(get: { morningDigest }, set: { next in
                            morningDigest = next
                            PushNotifications.shared.setMorningDigest(next)
                        })) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Morning digest").font(Theme.font(16, weight: .medium)).tracking(-0.16).foregroundStyle(Theme.foreground)
                                Text("At 6:30: yesterday's collections, today's jobs and overdue invoices")
                                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(Theme.brand)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .frame(minHeight: 64)
                        .accessibilityIdentifier("my-notifications-morning-digest")
                    }
                }

                Text("Choosing which updates reach you, quiet hours and sound aren't available yet. For now, notifications are on or off for this whole phone.")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.top, 16)
                    .accessibilityIdentifier("my-notifications-unavailable")

                Text(MenuItem.notices.permitted(session)
                     ? "These are just for you. Rules for the whole company are in Business settings › Notification rules."
                     : "These are just for you.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.top, 12)
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 32)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await readPermission() }
        .onChange(of: scenePhase) { _, phase in
            // Back from the system's Settings: show what the person chose there.
            if phase == .active { Task { await readPermission() } }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func readPermission() async {
        permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Not asked yet: ask right here (the system sheet). Asked before: open the system's settings
    /// for this app's notifications, the only place the answer can change.
    private func permissionTapped() async {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            // Paper 71: say what alerts are for first; "Not now" leaves the system unasked.
            guard await PermissionPrimerPresenter.ask(PushNotifications.receivesPaymentAlerts(session) ? .notificationsWithPayments : .notifications,
                                                     automatic: false) else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            let granted = await center.notificationSettings().authorizationStatus
            if [.authorized, .provisional, .ephemeral].contains(granted) { UIApplication.shared.registerForRemoteNotifications() }
            permission = granted
        } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            openURL(url)
        }
    }
}
