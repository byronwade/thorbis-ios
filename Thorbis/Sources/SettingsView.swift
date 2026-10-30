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
    @State private var showWorkspaces = false
    @State private var notifications: UNAuthorizationStatus?
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine)
                }

                Section("Workspace") {
                    Button { showWorkspaces = true } label: {
                        row("Company", symbol: "building.2", value: session.activeOrganization?.name ?? "Choose", opens: true)
                    }
                    NavigationLink { CustomizeMenuView() } label: {
                        row("Customize menu", symbol: "slider.horizontal.3", value: nil)
                    }
                    // Owners reach the business screens here, now that the More screen is off the menu.
                    if session.can("organization.settings.edit") {
                        NavigationLink(value: PaperRoute.businessSetup) {
                            row("Set up your business", symbol: "checklist", value: nil)
                        }
                        NavigationLink(value: PaperRoute.companyDetails) {
                            row("Company details", symbol: "building.2", value: nil)
                        }
                        NavigationLink(value: PaperRoute.payments) {
                            row("Payments", symbol: "creditcard", value: nil)
                        }
                    }
                    // Who hears about booked and changed jobs; the feed itself is Inbox.
                    if MenuItem.notices.permitted(session) {
                        NavigationLink(value: PaperRoute.notices) {
                            row("Notification rules", symbol: "bell.badge", value: nil)
                        }
                    }
                }

                Section("This phone") {
                    ThorbisMenu(items: [
                        ThorbisMenuItem("System", isSelected: appearance == "system") { appearance = "system" },
                        ThorbisMenuItem("Light", isSelected: appearance == "light") { appearance = "light" },
                        ThorbisMenuItem("Dark", isSelected: appearance == "dark") { appearance = "dark" },
                    ], title: "Appearance") {
                        row("Appearance", symbol: "circle.lefthalf.filled",
                            value: appearance == "light" ? "Light" : appearance == "dark" ? "Dark" : "System", opens: true)
                    }
                    Button {
                        Task { await notificationsTapped() }
                    } label: {
                        row("Notifications", symbol: "bell", value: notificationLabel, opens: true)
                    }
                }

                Section {
                    NavigationLink { WhatsNewHistoryView() } label: {
                        row("What's new", symbol: "sparkles", value: nil)
                    }
                }

                Section {
                    Button(role: .destructive) { confirmSignOut = true } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right").foregroundStyle(Theme.destructive)
                    }
                } footer: {
                    Text("Thorbis Field \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.top, 8)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .foregroundStyle(Theme.foreground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .paperDestinations()
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
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

    private func row(_ title: String, symbol: String, value: String?, opens: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.markAccent).frame(width: 22)
            Text(title).foregroundStyle(Theme.foreground)
            Spacer(minLength: 8)
            if let value { Text(value).foregroundStyle(Theme.muted).lineLimit(1) }
            if opens {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted).accessibilityHidden(true)
            }
        }
        .font(Theme.font(15))
    }
}
