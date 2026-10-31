import SwiftUI
import UserNotifications

/// The one Settings: the person on top, then company, business setup, payments, menu, notification
/// rules, appearance, notifications, What's new and sign-out. Opened from the bottom bar's menu,
/// More, and the iPad sidebar.
/// Native grouped lists per D-025 (Apple HIG for settings), Thorbis tokens for color.
struct SettingsView: View {
    @AppStorage("thorbis.appearance") private var appearance = "system"
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @EnvironmentObject private var pendingMedia: PendingMediaStore
    @State private var confirmSignOut = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showWorkspaces = false
    @State private var notifications: UNAuthorizationStatus?
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            // design 2026-10-30: one panel per section with a 13pt label above, neutral glyphs,
            // the value as a quiet word on the right, no separators or chevrons.
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(spacing: 8) {
                        Text(initials(session.user?.name ?? session.user?.email ?? ""))
                            .font(Theme.font(24, weight: .medium)).foregroundStyle(Theme.foreground)
                            .frame(width: 72, height: 72).background(Theme.fill, in: Circle())
                            .overlay(Circle().stroke(Theme.border))
                        Text(session.user?.name ?? "Account").font(Theme.font(20, weight: .medium))
                        if let email = session.user?.email { Text(email).font(Theme.font(15)).foregroundStyle(Theme.muted) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)

                    PaperSection("Workspace") {
                        VStack(spacing: 0) {
                            Button { showWorkspaces = true } label: {
                                row("Company", symbol: "building.2", value: session.activeOrganization?.name ?? "Choose")
                            }
                            .buttonStyle(RowPressStyle())
                            NavigationLink { CustomizeMenuView().thorbisBackButton() } label: {
                                row("Customize menu", symbol: "slider.horizontal.3", value: nil)
                            }
                            .buttonStyle(RowPressStyle())
                            // Owners reach the business screens here, now that the More screen is off the menu.
                            if session.can("organization.settings.edit") {
                                NavigationLink(value: PaperRoute.businessSetup) {
                                    row("Set up your business", symbol: "checklist", value: nil)
                                }
                                .buttonStyle(RowPressStyle())
                                NavigationLink(value: PaperRoute.companyDetails) {
                                    row("Company details", symbol: "building.2", value: nil)
                                }
                                .buttonStyle(RowPressStyle())
                                NavigationLink(value: PaperRoute.payments) {
                                    row("Payments", symbol: "creditcard", value: nil)
                                }
                                .buttonStyle(RowPressStyle())
                            }
                            // Who hears about booked and changed jobs; the feed itself is Inbox.
                            if MenuItem.notices.permitted(session) {
                                NavigationLink(value: PaperRoute.notices) {
                                    row("Notification rules", symbol: "bell.badge", value: nil)
                                }
                                .buttonStyle(RowPressStyle())
                            }
                        }
                        .padding(.vertical, PaperCardMetrics.edge)
                    }

                    PaperSection("This phone") {
                        VStack(spacing: 0) {
                            ThorbisMenu(items: [
                                ThorbisMenuItem("System", isSelected: appearance == "system") { appearance = "system" },
                                ThorbisMenuItem("Light", isSelected: appearance == "light") { appearance = "light" },
                                ThorbisMenuItem("Dark", isSelected: appearance == "dark") { appearance = "dark" },
                            ], title: "Appearance") {
                                row("Appearance", symbol: "circle.lefthalf.filled",
                                    value: appearance == "light" ? "Light" : appearance == "dark" ? "Dark" : "System")
                            }
                            Button {
                                Task { await notificationsTapped() }
                            } label: {
                                row("Notifications", symbol: "bell", value: notificationLabel)
                            }
                            .buttonStyle(RowPressStyle())
                        }
                        .padding(.vertical, PaperCardMetrics.edge)
                    }

                    PaperSection("About") {
                        NavigationLink { WhatsNewHistoryView().thorbisBackButton() } label: {
                            row("What's new", symbol: "sparkles", value: nil)
                        }
                        .buttonStyle(RowPressStyle())
                        .padding(.vertical, PaperCardMetrics.edge)
                    }

                    VStack(spacing: 8) {
                        Button { confirmSignOut = true } label: {
                            Text("Sign out").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.destructive)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: PaperCardMetrics.radius, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: PaperCardMetrics.radius, style: .continuous).strokeBorder(Theme.border))
                        }
                        .buttonStyle(PressStyle())
                        Text("Thorbis Field \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                            .font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 8).padding(.bottom, 32)
            }
            .background(Theme.background)
            .foregroundStyle(Theme.foreground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .paperDestinations()
            .toolbar { ThorbisToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showWorkspaces) { WorkspaceSelectionView() }
            .thorbisConfirm("Sign out of Thorbis?",
                            message: signOutWarning,
                            isPresented: $confirmSignOut,
                            actions: [ThorbisConfirmAction("Sign out", role: .destructive) { Task { dismiss(); await session.signOut() } }])
            .task { notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
        }
    }

    private var signOutWarning: String {
        #if DEBUG
        if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-long-confirmation") {
            return "24 changes on this phone haven't synced yet. Signing out deletes them. 12 saved photos or documents have not uploaded yet. Signing out deletes all of them, including media in other workspaces and older saved photos."
        }
        #endif
        return pendingMedia.signOutWarning(outboxWarning: outbox.signOutWarning)
    }

    private var notificationLabel: String? {
        switch notifications {
        case .authorized, .provisional, .ephemeral: "On"
        case .denied: "Off"
        case .notDetermined: "Turn on"
        default: nil
        }
    }

    /// Not asked yet: ask right here (the system sheet), instead of sending people to Settings
    /// to find a switch that does not exist until the app has asked. Asked before: open Settings.
    private func notificationsTapped() async {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            let granted = await center.notificationSettings().authorizationStatus
            if [.authorized, .provisional, .ephemeral].contains(granted) { UIApplication.shared.registerForRemoteNotifications() }
            notifications = granted
        } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            openURL(url)
        }
    }

    private func row(_ title: String, symbol: String, value: String?) -> some View {
        PaperListRow(leading: .icon(symbol), title: title) {
            if let value { Text(value).font(Theme.font(15)).foregroundStyle(Theme.muted).lineLimit(typeSize.isAccessibilitySize ? 3 : 1) }
        }
    }
}
