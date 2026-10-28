import SwiftUI
import UserNotifications

/// Settings as grouped lists with the person on top, opened from the side menu's gear.
/// Native grouped lists per D-025 (Apple HIG for settings), Thorbis tokens for color.
struct SettingsView: View {
    @AppStorage("thorbis.appearance") private var appearance = "system"
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
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
                        row("Company", symbol: "building.2", value: session.activeOrganization?.name ?? "Choose")
                    }
                    NavigationLink { CustomizeMenuView() } label: {
                        row("Customize menu", symbol: "slider.horizontal.3", value: nil)
                    }
                }

                Section("This phone") {
                    Picker(selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    } label: { row("Appearance", symbol: "circle.lefthalf.filled", value: nil) }
                    Button {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    } label: {
                        row("Notifications", symbol: "bell", value: notificationLabel)
                    }
                }

                Section {
                    Button(role: .destructive) { confirmSignOut = true } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right").foregroundStyle(Theme.destructive)
                    }
                } footer: {
                    Text("Thorbis Field \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                        .frame(maxWidth: .infinity).padding(.top, 8)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .foregroundStyle(Theme.foreground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showWorkspaces) { WorkspaceSelectionView() }
            .confirmationDialog("Sign out of Thorbis?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { dismiss(); await session.signOut() } }
            } message: {
                Text(outbox.signOutWarning)
            }
            .task { notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
        }
    }

    private var notificationLabel: String? {
        switch notifications {
        case .authorized, .provisional, .ephemeral: "On"
        case .denied: "Off"
        case .notDetermined: "Not set"
        default: nil
        }
    }

    private func row(_ title: String, symbol: String, value: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.markAccent).frame(width: 22)
            Text(title).foregroundStyle(Theme.foreground)
            Spacer(minLength: 8)
            if let value { Text(value).foregroundStyle(Theme.muted).lineLimit(1) }
        }
        .font(Theme.font(15))
    }
}
