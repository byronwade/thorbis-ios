import SwiftUI
import UserNotifications

/// The one Settings: the person on top, then company, business setup, payments, menu, notification
/// rules, appearance, notifications, What's new and sign-out. Opened from the bottom bar's menu,
/// More, and the iPad sidebar.
/// Native grouped lists per D-025 (Apple HIG for settings), Thorbis tokens for color.
struct SettingsView: View {
    @AppStorage("thorbis.appearance") private var appearance = "system"
    @EnvironmentObject private var api: APIClient
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
                VStack(alignment: .leading, spacing: 20) {
                    // Paper 65: Account, then each section on its own card with a 13 Semibold label
                    // above it; every row opens a page that saves itself, and Sign out ends App.
                    PaperSection("Account", count: nil) {
                        // Paper 65: one row — the person, then a chevron into Account and data (67).
                        NavigationLink { AccountAndDataView().thorbisBackButton() } label: {
                        HStack(spacing: 12) {
                            Text(initials(session.user?.name ?? session.user?.email ?? "?"))
                                .font(Theme.font(13, weight: .semibold)).foregroundStyle(Color.white)
                                .frame(width: 36, height: 36)
                                .background(Theme.brand, in: Circle())
                                .dynamicTypeSize(...DynamicTypeSize.large)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(session.user?.name ?? "Account").font(Theme.font(16, weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                if let email = session.user?.email {
                                    // An address breaks mid-word when it wraps, so it shrinks on one line instead.
                                    Text(email).font(Theme.font(14)).foregroundStyle(Theme.muted)
                                        .lineLimit(1).minimumScaleFactor(0.6).truncationMode(.middle)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.muted).accessibilityHidden(true)
                        }
                        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                        .frame(minHeight: 64)
                        .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Opens Account and data")
                        .accessibilityIdentifier("settings-account-data")
                    }

                    PaperSection("Workspace", count: nil) {
                        Button { showWorkspaces = true } label: {
                            row("Company", symbol: "building.2", value: session.activeOrganization?.name ?? "Choose", opens: true)
                        }
                        .buttonStyle(RowPressStyle())
                        WellDivider(leading: Self.rowDivider)
                        NavigationLink { CustomizeMenuView().thorbisBackButton() } label: {
                            row("Menu and start screen", symbol: "slider.horizontal.3", value: nil, opens: true)
                        }
                        .buttonStyle(RowPressStyle())
                        // Owners reach the business screens here, now that the More screen is off the menu.
                        if session.can("organization.settings.edit") {
                            WellDivider(leading: Self.rowDivider)
                            NavigationLink(value: PaperRoute.businessSetup) {
                                row("Business settings", symbol: "checklist", value: nil, opens: true)
                            }
                            .buttonStyle(RowPressStyle())
                            WellDivider(leading: Self.rowDivider)
                            NavigationLink(value: PaperRoute.companyDetails) {
                                row("Company profile", symbol: "building.2", value: nil, opens: true)
                            }
                            .buttonStyle(RowPressStyle())
                            WellDivider(leading: Self.rowDivider)
                            NavigationLink(value: PaperRoute.payments) {
                                row("Payments", symbol: "creditcard", value: nil, opens: true)
                            }
                            .buttonStyle(RowPressStyle())
                            WellDivider(leading: Self.rowDivider)
                            NavigationLink { ReviewRequestsView().thorbisBackButton() } label: {
                                row("Review requests", symbol: "star.bubble", value: nil, opens: true)
                            }
                            .buttonStyle(RowPressStyle())
                        }
                        if session.can("customer.create", feature: "core_crm") && session.can("customer.edit", feature: "core_crm") {
                            WellDivider(leading: Self.rowDivider)
                            NavigationLink(value: PaperRoute.importCustomers) {
                                row("Import customers", symbol: "square.and.arrow.down", value: nil, opens: true)
                            }
                            .buttonStyle(RowPressStyle())
                        }
                        // TG-07: whoever may see the team's numbers sets its goals.
                        if session.can("organization.performance.view") {
                            WellDivider(leading: Self.rowDivider)
                            NavigationLink(value: PaperRoute.teamGoals) {
                                row("Team goals", symbol: "target", value: nil, opens: true)
                            }
                            .buttonStyle(RowPressStyle())
                        }
                    }

                    PaperSection("Notifications", count: nil) {
                        // Paper 65C: the person's own notifications page (asks for permission there).
                        NavigationLink { MyNotificationsView().thorbisBackButton() } label: {
                            row("Notifications", symbol: "bell", value: notificationLabel, opens: true)
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityIdentifier("settings-my-notifications")
                        // Who hears about booked and changed jobs; the feed itself is Inbox.
                        if MenuItem.notices.permitted(session) {
                            WellDivider(leading: Self.rowDivider)
                            NavigationLink(value: PaperRoute.notices) {
                                row("Notification rules", symbol: "bell.badge", value: nil, opens: true)
                            }
                            .buttonStyle(RowPressStyle())
                        }
                    }

                    // Paper 65 › 65G: Appearance is its own page.
                    VStack(alignment: .leading, spacing: 8) {
                        PaperSection("Appearance", count: nil) {
                            NavigationLink { SettingsAppearancePage().thorbisBackButton() } label: {
                                row("Appearance", symbol: "circle.lefthalf.filled", value: SettingsAppearancePage.label(appearance), opens: true)
                            }
                            .buttonStyle(RowPressStyle())
                        }
                        // Immediate settings say they are immediate (design.thorbis.com Customize).
                        Text(UIDevice.current.userInterfaceIdiom == .pad ? "Theme changes right away, on this iPad only." : "Theme changes right away, on this phone only.")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }

                    PaperSection("App", count: nil) {
                        NavigationLink { WhatsNewHistoryView().thorbisBackButton() } label: {
                            row("What's new", symbol: "sparkles", value: nil, opens: true)
                        }
                        .buttonStyle(RowPressStyle())
                        WellDivider(leading: Self.rowDivider)
                        // Paper 98: Help and support sits with the app's own pages.
                        NavigationLink(value: PaperRoute.help) {
                            row("Help and support", symbol: "questionmark.circle", value: nil, opens: true)
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityIdentifier("settings-help")
                        WellDivider(leading: Self.rowDivider)
                        // Danger ends the card: the word and its mark in the danger tone.
                        Button { confirmSignOut = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 17))
                                    .foregroundStyle(Theme.destructive)
                                    .frame(width: 24).accessibilityHidden(true)
                                Text("Sign out").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.destructive)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, PaperCardMetrics.inset)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityHint("Asks before signing you out of this phone")
                    }

                    Text("Thorbis \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                        .font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 8).padding(.bottom, 32)
            }
            #if DEBUG
            .modifier(PaperPreviewScrollAnchor())
            #endif
            .background(Theme.canvas)
            .foregroundStyle(Theme.foreground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .paperDestinations()
            // Paper 65: the 44pt back circle at the leading edge closes Settings.
            .toolbar { ThorbisToolbarItem(placement: .topBarLeading) { ThorbisBackButton() } }
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

    /// A settings row (Paper 65): a muted outline glyph, the setting in 16 Medium, its value as a
    /// quiet word, and a chevron when it opens a page.
    private func row(_ title: String, symbol: String, value: String?, opens: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(Theme.muted)
                .frame(width: 24).accessibilityHidden(true)
            PaperListRow(title: title) {
                HStack(spacing: 8) {
                    // A long company name wraps to a second line rather than losing its end.
                    // A value in " · " parts shares one line when it fits, otherwise each part takes its own,
                    // so no line starts with the dot.
                    if let value {
                        let parts = value.components(separatedBy: " \u{00B7} ")
                        if parts.count > 1 {
                            ViewThatFits(in: .horizontal) {
                                valueText(value).fixedSize(horizontal: true, vertical: false)
                                VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 0) {
                                    ForEach(Array(parts.enumerated()), id: \.offset) { valueText($0.element) }
                                }
                            }
                        } else {
                            valueText(value)
                        }
                    }
                    if opens {
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.muted).accessibilityHidden(true)
                    }
                }
            }
            .environment(\.paperRowInset, 0)
        }
        .padding(.horizontal, PaperCardMetrics.inset)
        .contentShape(Rectangle())
    }

    private func valueText(_ text: String) -> some View {
        Text(text).font(Theme.font(15)).foregroundStyle(Theme.subtle)
            // Stacked under its setting at accessibility sizes, the value reads from the left like the title.
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
            .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The hairline between rows starts under the words, past the glyph.
    private static let rowDivider: CGFloat = PaperCardMetrics.inset + 24 + 12
}

/// Paper 65G: how Thorbis looks on this device. Three theme cards (Light, Dark, Match device) bound to
/// the same `thorbis.appearance` setting the app reads. Text size and app icon have no setting yet.
private struct SettingsAppearancePage: View {
    @AppStorage("thorbis.appearance") private var appearance = "system"
    @Environment(\.dynamicTypeSize) private var typeSize

    static func label(_ value: String) -> String {
        switch value {
        case "light": return "Light"
        case "dark": return "Dark"
        default: return "Match device"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    // Paper 65G: the title is 28 Bold.
                    Text("Appearance").font(Theme.heading()).tracking(-0.56)
                        .accessibilityAddTraits(.isHeader)
                    Text(UIDevice.current.userInterfaceIdiom == .pad ? "How Thorbis looks on this iPad" : "How Thorbis looks on this phone")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 14).padding(.bottom, 16)
                Text("Theme").font(Theme.font(13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, Theme.gutter).padding(.bottom, 8)
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                                          : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
                layout {
                    SettingsThemeChoice(value: "light", title: "Light", selection: $appearance)
                    SettingsThemeChoice(value: "dark", title: "Dark", selection: $appearance)
                    SettingsThemeChoice(value: "system", title: "Match device", selection: $appearance)
                }
                .paperCardMargin()
                Text("Changes right away, on this device only.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.gutter).padding(.top, 16)
            }
            .padding(.bottom, 32)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One theme card: a small drawing of the app in that theme, its name under it, and a check on the
/// chosen one. The card is the button.
private struct SettingsThemeChoice: View {
    let value: String
    let title: String
    @Binding var selection: String

    private var chosen: Bool { selection == value }

    var body: some View {
        Button { selection = value } label: {
            VStack(spacing: 8) {
                preview
                    .frame(maxWidth: .infinity).frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(chosen ? Theme.brand : Theme.border, lineWidth: chosen ? 2 : 1))
                HStack(spacing: 6) {
                    if chosen {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.brand)
                            .accessibilityHidden(true)
                    }
                    Text(title).font(Theme.font(15, weight: .semibold))
                        .foregroundStyle(chosen ? Theme.foreground : Theme.subtle)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// Decorative: a sidebar beside a page with a blue button, drawn in the theme's own tones.
    @ViewBuilder private var preview: some View {
        if value == "system" {
            HStack(spacing: 0) {
                SettingsThemeSketch(ground: Color(white: 0.95), panel: .white, line: Color(white: 0.8))
                SettingsThemeSketch(ground: Color(white: 0.08), panel: Color(white: 0.16), line: Color(white: 0.35))
            }
            .accessibilityHidden(true)
        } else if value == "light" {
            SettingsThemeSketch(ground: Color(white: 0.95), panel: .white, line: Color(white: 0.8))
                .accessibilityHidden(true)
        } else {
            SettingsThemeSketch(ground: Color(white: 0.08), panel: Color(white: 0.16), line: Color(white: 0.35))
                .accessibilityHidden(true)
        }
    }
}

/// The drawing inside a theme card. Fixed tones on purpose: it shows the other theme, not this one.
private struct SettingsThemeSketch: View {
    let ground: Color
    let panel: Color
    let line: Color

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(Theme.brand).frame(width: 14, height: 5)
                Capsule().fill(line).frame(width: 12, height: 4)
                Capsule().fill(line).frame(width: 12, height: 4)
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(width: 30)
            .frame(maxHeight: .infinity)
            .background(panel, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(line).frame(width: 26, height: 5)
                Capsule().fill(line).frame(width: 34, height: 4)
                Capsule().fill(line).frame(width: 22, height: 4)
                Spacer(minLength: 0)
                Capsule().fill(Theme.brand).frame(height: 9)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(panel, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ground)
    }
}
