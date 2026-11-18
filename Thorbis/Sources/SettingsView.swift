import SwiftUI
import UserNotifications

/// The one Settings (Paper 65, "just me"): the person on top, notifications, appearance and the
/// menu, work preferences (with what is saved on this phone), the places no menu row leads to,
/// help and sign-out. Opened from the menu's gear, Search, and the iPad sidebar.
/// Native grouped lists per D-025 (Apple HIG for settings), Thorbis tokens for color.
struct SettingsView: View {
    @AppStorage("thorbis.appearance") private var appearance = "system"
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @EnvironmentObject private var pendingMedia: PendingMediaStore
    @EnvironmentObject private var store: Store
    @State private var confirmSignOut = false
    /// Saved on this phone: the review of what has not synced yet (it used to hang off the gear).
    @State private var reviewScope: SavedWorkScope?
    @Environment(\.dismiss) private var dismiss
    @State private var notifications: UNAuthorizationStatus?
    /// Paper 65 "Saved signature · On file": whether this person has drawn one on this phone.
    @State private var signatureOnFile = false
    @Environment(\.openURL) private var openURL

    /// People who hold a company-side permission but not the Business settings menu row (it is
    /// the owner's) still need a way to the company pages they may open.
    private var reachesBusinessSettingsHere: Bool {
        guard !session.can("organization.settings.edit") else { return false }
        return (session.can("customer.create", feature: "core_crm") && session.can("customer.edit", feature: "core_crm"))
            || session.can("organization.performance.view") || MenuItem.notices.permitted(session)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Paper 65: the 44pt back circle, 14 under it "Settings" in 34 Bold.
                    ThorbisBackButton()
                        .padding(.top, 2)
                    AccountPageTitle(title: "Settings")
                        .padding(.top, 14)

                    // Paper 65: the person, then a chevron into Account and data (67).
                    AccountGroup(title: "Account") {
                        NavigationLink { AccountAndDataView().thorbisBackButton() } label: {
                            AccountPersonRow(name: session.user?.name ?? session.user?.email ?? "Account",
                                             email: session.user?.name == nil ? nil : session.user?.email)
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Opens Account and data")
                        .accessibilityIdentifier("settings-account-data")
                    }
                    .padding(.top, 20)

                    // Paper 65 draws three category switches and Quiet hours here; the server keeps
                    // no per-person choices yet, so this is the one real row: the phone's own
                    // permission, opening My notifications (65C).
                    AccountGroup(title: "Notifications") {
                        NavigationLink { MyNotificationsView().thorbisBackButton() } label: {
                            AccountRow(glyph: .setBell, title: "My notifications", value: notificationLabel)
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityIdentifier("settings-my-notifications")
                    }
                    .padding(.top, 22)

                    // Paper 65 "Appearance": theme lives on its own page; the menu and the screen
                    // the app opens to are 65A. (Sidebar / Bottom bar has no setting on a phone.)
                    AccountGroup(title: "Appearance") {
                        NavigationLink { SettingsAppearancePage().thorbisBackButton() } label: {
                            AccountRow(glyph: .setTheme, title: "Theme", value: SettingsAppearancePage.label(appearance))
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityIdentifier("settings-appearance")
                        WellDivider(leading: AccountRow<EmptyView>.dividerInset)
                        NavigationLink { CustomizeMenuView().thorbisBackButton() } label: {
                            AccountRow(glyph: .setSidebar, glyphSize: 17, title: "Menu and start screen")
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityIdentifier("settings-menu")
                    }
                    .padding(.top, 22)

                    // Paper 65 "Work preferences": the person's own saved signature. Offline mode has
                    // no switch: the app always keeps jobs for low signal.
                    AccountGroup(title: "Work preferences") {
                        NavigationLink { SavedSignatureView().thorbisBackButton() } label: {
                            AccountRow(glyph: .setPencil, title: "Saved signature", value: signatureOnFile ? "On file" : "Not set")
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityIdentifier("settings-saved-signature")
                        // Work this phone still holds, with its review. Shown only while there is some.
                        if let savedWork {
                            WellDivider(leading: AccountRow<EmptyView>.dividerInset)
                            Button { reviewScope = savedWorkScope } label: {
                                AccountRow(symbol: savedWork.needsPerson ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath",
                                           glyphColor: savedWork.needsPerson ? Theme.warning : Theme.muted,
                                           title: "Saved on this phone", subtitle: savedWork.words)
                            }
                            .buttonStyle(RowPressStyle())
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Saved on this phone")
                            .accessibilityValue(savedWork.words)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("Review what is waiting to sync")
                            .accessibilityIdentifier("settings-saved-work")
                        }
                        // Owners have Business settings in their menu; everyone else who may open
                        // one of its pages gets the row here.
                        if reachesBusinessSettingsHere {
                            WellDivider(leading: AccountRow<EmptyView>.dividerInset)
                            NavigationLink(value: PaperRoute.businessSetup) {
                                AccountRow(glyph: .bizCompany, glyphSize: 18, title: "Business settings")
                            }
                            .buttonStyle(RowPressStyle())
                            .accessibilityIdentifier("settings-business")
                        }
                    }
                    .padding(.top, 22)
                    // Coming back from the page shows what it left: On file, or Not set.
                    .onAppear { signatureOnFile = SavedSignatureStore.isOnFile(actorID: session.user?.id) }

                    // Places this role's menu does not list and no other screen leads to. Paper
                    // gives them no parent for this role, so they stay one row away here.
                    PlaceDoorRows(door: .settings, title: "Other places")
                        .padding(.top, 22)

                    AccountGroup(title: "App") {
                        NavigationLink(value: PaperRoute.help) {
                            AccountRow(glyph: .setHelp, title: "Help and support", end: .arrowOut)
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityIdentifier("settings-help")
                        WellDivider(leading: AccountRow<EmptyView>.dividerInset)
                        // Danger ends the card: the word and its mark in the danger tone.
                        Button { confirmSignOut = true } label: {
                            AccountRow(glyph: .setSignOut, glyphColor: Theme.destructive, title: "Sign out",
                                       titleColor: Theme.destructive, end: .none)
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityHint("Asks before signing you out of this phone")
                    }
                    .padding(.top, 22)

                    Text("Thorbis \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 4).padding(.top, 24)
                }
                .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 40)
            }
            #if DEBUG
            .modifier(PaperPreviewScrollAnchor())
            #endif
            .background(Theme.background.ignoresSafeArea())
            .foregroundStyle(Theme.foreground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .paperDestinations()
            .sheet(item: $reviewScope) { value in SheetSurface { SavedWorkReviewView(scope: value) } }
            .onChange(of: reviewScope?.isCurrent(session: session, api: api, media: pendingMedia, outbox: outbox) ?? true) { _, valid in
                if !valid { reviewScope = nil }
            }
            .sheet(isPresented: $confirmSignOut) {
                SignOutSheet(company: session.activeOrganization?.name, warning: signOutWarning) {
                    Task { dismiss(); await session.signOut() }
                }
            }
            .task {
                #if DEBUG
                if PaperPreview.enabled, ProcessInfo.processInfo.arguments.contains("--paper-preview-sign-out") { confirmSignOut = true }
                #endif
                notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            }
        }
        // Paper 65 is a page, not a panel: the page ground with cards on it.
        .paperPageGround()
    }

    private var savedWorkScope: SavedWorkScope? {
        .capture(session: session, api: api, media: pendingMedia, outbox: outbox)
    }

    /// What the phone still holds, in the words the menu's gear reads out.
    private var savedWork: AppBottomBar.Sync? {
        guard let scope = savedWorkScope else { return nil }
        return .savedWork(.make(scope: scope, entries: outbox.entries, media: pendingMedia.items,
                                mediaErrors: pendingMedia.errors, unverifiedMediaIDs: pendingMedia.unverifiedIDs,
                                uploadingMediaID: pendingMedia.uploadingID, commandsSyncing: outbox.syncing,
                                jobs: store.jobs, listingWarning: pendingMedia.storageWarning))
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
}

/// Paper 65E "Sign out": the question in 22 Bold with one muted line, what is still on this phone
/// on the warning surface, then Cancel beside the red Sign out. Unsynced work is deleted by
/// signing out (it does not "sync first" as Paper's sample says), so the card says that.
struct SignOutSheet: View {
    let company: String?
    let warning: String
    let signOut: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 320

    private var unsynced: Bool { warning.contains("Signing out deletes") }

    var body: some View {
        // The sheet is as tall as its words. A long warning at the largest text sizes is taller than
        // the screen, so the words scroll and Cancel and Sign out can always be reached.
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sign out of \(company ?? "Thorbis")?")
                    .font(Theme.font(22, weight: .bold)).tracking(-0.22).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(unsynced ? "You'll need your password to get back in." : warning)
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
            if unsynced {
                HStack(alignment: .top, spacing: 10) {
                    PaperIcon(.signOutSync, size: 20, color: Theme.warning).accessibilityHidden(true)
                    Text(warning).font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Text("Cancel").font(Theme.font(17, weight: .semibold)).foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.fill, in: Capsule()).contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                Button { dismiss(); signOut() } label: {
                    Text("Sign out").font(Theme.font(17, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.destructiveFill, in: Capsule()).contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("sign-out-confirm")
            }
        }
        .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PaperGlyph {
    /// Paper 65E's "still saving" mark: an open ring with its arrow head.
    static let signOutSync = PaperGlyph(box: 20, [.stroke("M16 10A6 6 0 1 1 13.5 5.1", 1.8), .stroke("M13.5 2.5V5.5H16.5", 1.8)])
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
