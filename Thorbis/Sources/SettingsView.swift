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
                VStack(alignment: .leading, spacing: 24) {
                    // v2 Settings room: a column. The person, then each section on its own; every
                    // row opens a page that saves itself, and danger sits apart at the end.
                    HStack(spacing: 12) {
                        InitialsAvatar(name: session.user?.name ?? session.user?.email ?? "?", size: 44)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.user?.name ?? "Account").font(Theme.font(17, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                            if let email = session.user?.email {
                                Text(email).font(Theme.font(14)).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                    .accessibilityElement(children: .combine)

                    PaperSection("Workspace") {
                        VStack(spacing: 0) {
                            Button { showWorkspaces = true } label: {
                                row("Company", symbol: "building.2", value: session.activeOrganization?.name ?? "Choose")
                            }
                            .buttonStyle(RowPressStyle())
                            WellDivider(leading: Self.rowDivider)
                            NavigationLink { CustomizeMenuView().thorbisBackButton() } label: {
                                row("Customize menu", symbol: "slider.horizontal.3", value: nil)
                            }
                            .buttonStyle(RowPressStyle())
                            // Owners reach the business screens here, now that the More screen is off the menu.
                            if session.can("organization.settings.edit") {
                                WellDivider(leading: Self.rowDivider)
                                NavigationLink(value: PaperRoute.businessSetup) {
                                    row("Set up your business", symbol: "checklist", value: nil)
                                }
                                .buttonStyle(RowPressStyle())
                                WellDivider(leading: Self.rowDivider)
                                NavigationLink(value: PaperRoute.companyDetails) {
                                    row("Company details", symbol: "building.2", value: nil)
                                }
                                .buttonStyle(RowPressStyle())
                                WellDivider(leading: Self.rowDivider)
                                NavigationLink(value: PaperRoute.payments) {
                                    row("Payments", symbol: "creditcard", value: nil)
                                }
                                .buttonStyle(RowPressStyle())
                            }
                            // Who hears about booked and changed jobs; the feed itself is Inbox.
                            if MenuItem.notices.permitted(session) {
                                WellDivider(leading: Self.rowDivider)
                                NavigationLink(value: PaperRoute.notices) {
                                    row("Notification rules", symbol: "bell.badge", value: nil)
                                }
                                .buttonStyle(RowPressStyle())
                            }
                        }
                        .padding(.vertical, PaperCardMetrics.edge)
                    }

                    PaperSection(UIDevice.current.userInterfaceIdiom == .pad ? "This iPad" : "This phone") {
                        VStack(spacing: 0) {
                            ThorbisMenu(items: [
                                ThorbisMenuItem("System", isSelected: appearance == "system") { appearance = "system" },
                                ThorbisMenuItem("Light", isSelected: appearance == "light") { appearance = "light" },
                                ThorbisMenuItem("Dark", isSelected: appearance == "dark") { appearance = "dark" },
                            ], title: "Appearance") {
                                row("Appearance", symbol: "circle.lefthalf.filled",
                                    value: appearance == "light" ? "Light" : appearance == "dark" ? "Dark" : "System")
                            }
                            WellDivider(leading: Self.rowDivider)
                            Button {
                                Task { await notificationsTapped() }
                            } label: {
                                row("Notifications", symbol: "bell", value: notificationLabel)
                            }
                            .buttonStyle(RowPressStyle())
                        }
                        .padding(.vertical, PaperCardMetrics.edge)
                    }
                    // Immediate settings say they are immediate (design.thorbis.com Customize).
                    Text(UIDevice.current.userInterfaceIdiom == .pad ? "Appearance changes right away, on this iPad only." : "Appearance changes right away, on this phone only.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4).padding(.top, -14)

                    PaperSection("About") {
                        NavigationLink { WhatsNewHistoryView().thorbisBackButton() } label: {
                            row("What's new", symbol: "sparkles", value: nil)
                        }
                        .buttonStyle(RowPressStyle())
                        .padding(.vertical, PaperCardMetrics.edge)
                    }

                    // Danger sits apart: its own group after a wider pause, the word in the danger tone.
                    VStack(alignment: .leading, spacing: 8) {
                        Button { confirmSignOut = true } label: {
                            HStack(spacing: 12) {
                                PlaceMark(symbol: "rectangle.portrait.and.arrow.right", tint: Theme.destructive)
                                Text("Sign out").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.destructive)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, PaperCardMetrics.inset)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .panelBackground(cornerRadius: Theme.cardRadius)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityHint("Asks before signing you out of this phone")
                        Text("Thorbis Field \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                            .font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                            .padding(.horizontal, 4)
                    }
                    .padding(.top, 24)
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 8).padding(.bottom, 32)
                // Medium section headers over grouped wells (v2: 500 is the heaviest weight).
                .environment(\.paperGroupedWells, true)
            }
            #if DEBUG
            .modifier(PaperPreviewScrollAnchor())
            #endif
            .background(Theme.canvas)
            .foregroundStyle(Theme.foreground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .paperDestinations()
            .toolbar { ThorbisToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showWorkspaces) { SheetSurface { WorkspaceSelectionView() } }
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

    /// A settings row, Linear style: a tinted place mark, the setting, its value as a quiet word.
    private func row(_ title: String, symbol: String, value: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            PlaceMark(symbol: symbol, tint: Self.markTint(symbol))
            PaperListRow(title: title) {
                if let value { Text(value).font(Theme.font(15)).foregroundStyle(Theme.subtle).lineLimit(typeSize.isAccessibilitySize ? 3 : 1) }
            }
            .environment(\.paperRowInset, 0)
        }
        .padding(.horizontal, PaperCardMetrics.inset)
        .contentShape(Rectangle())
    }

    /// The hairline between rows starts under the words, past the place mark.
    private static let rowDivider: CGFloat = PaperCardMetrics.inset + 26 + 12

    /// One hue per kind of setting, from the place-mark palette (decorative; the word carries it).
    private static func markTint(_ symbol: String) -> Color {
        switch symbol {
        case "building.2": Theme.markOlive
        case "slider.horizontal.3": Theme.markAccent
        case "checklist": Theme.markForest
        case "creditcard": Theme.markPumpkin
        case "bell.badge", "bell": Theme.markBurnt
        case "circle.lefthalf.filled": Theme.markAccent
        case "sparkles": Theme.markPumpkin
        default: Theme.markGrey
        }
    }
}
