import SwiftUI

/// `GET/POST /v1/notice-preferences` (communications NoticePreferenceView).
struct NoticePreference: Codable, Hashable {
    let subjectKind: String
    let subjectKey: String
    let channel: String
    let enabled: Bool
}

extension APIClient {
    func roleNoticePreferences() async throws -> [NoticePreference] {
        struct Page: Decodable { let items: [NoticePreference] }
        let page: Page = try await send("GET", "/v1/notice-preferences", queryItems: [URLQueryItem(name: "subjectKind", value: "role")])
        return page.items
    }

    func setNoticePreference(_ preference: NoticePreference) async throws -> NoticePreference {
        try await send("POST", "/v1/notice-preferences", body: preference)
    }
}

/// Web Settings › Job notices: who is told when a job is booked, changed or canceled.
struct NoticeSettingsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var stored: [NoticePreference] = []
    @State private var loaded = false
    @State private var saving: String?
    @State private var error: String?
    @State private var morningDigest = PushNotifications.morningDigest

    private var managesRoles: Bool { session.can("organization.settings.edit", feature: "job_booking_notices") }
    private let roles = [("owner", "Owner"), ("dispatcher", "Dispatcher"), ("technician", "Technician")]
    private let channels = [("email", "Email"), ("in_app", "In-app")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notices").font(Theme.font(30, weight: .medium)).tracking(-0.6).accessibilityAddTraits(.isHeader)
                    Text(managesRoles ? "Who hears when a job is booked, changed or canceled" : "What this phone tells you")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                }
                .padding(.bottom, 12)
                if PushNotifications.receivesMorningDigest(session) {
                    // TG-11: one push at 6:30, the off switch lives here. Per phone, saved offline.
                    PaperGroupHeader(title: "This phone").padding(.top, 6)
                    Toggle(isOn: Binding(get: { morningDigest }, set: { next in
                        morningDigest = next
                        PushNotifications.shared.setMorningDigest(next)
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Morning digest").font(Theme.font(15, weight: .medium))
                            Text("At 6:30: yesterday's collections, today's jobs and overdue invoices")
                                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.brand)
                    .frame(minHeight: 52)
                }
                if managesRoles {
                    if let error { ErrorBanner(message: error) { await load() }.padding(.horizontal, -Theme.gutter) }
                    if !loaded && error == nil { SkeletonRows(count: 4, leading: false, inset: 0) }
                    if loaded {
                        ForEach(roles, id: \.0) { role, label in
                            PaperGroupHeader(title: label).padding(.top, 6)
                            ForEach(channels, id: \.0) { channel, channelName in
                                let key = "\(role):\(channel)"
                                Toggle(isOn: Binding(get: { isOn(role, channel) }, set: { next in Task { await save(role, channel, next) } })) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(channelName).font(Theme.font(15, weight: .medium))
                                        Text(channel == "email" ? "\(label) email for booked, changed and canceled jobs" : "\(label) in-app feed for the same updates")
                                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                                    }
                                }
                                .tint(Theme.brand)
                                .disabled(saving == key)
                                .frame(minHeight: 52)
                            }
                        }
                    }
                    PaperGroupHeader(title: "History").padding(.top, 6)
                    NavigationLink { NoticeDeliveryLogView() } label: {
                        PaperMenuRow("Delivery log", symbol: "clock.arrow.circlepath", subtitle: "Recent notices and whether each was sent")
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 4).padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { if managesRoles { await load() } }
        .task { if managesRoles { await load() } }
    }

    /// Missing rows are reported as on by the server; mirror that.
    private func isOn(_ role: String, _ channel: String) -> Bool {
        stored.first { $0.subjectKey == role && $0.channel == channel }?.enabled ?? true
    }

    private func load() async {
        let generation = session.generation
        do {
            let items = try await api.roleNoticePreferences()
            guard session.generation == generation else { return }
            stored = items
            loaded = true
            error = nil
        } catch is CancellationError {} catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
        }
    }

    private func save(_ role: String, _ channel: String, _ enabled: Bool) async {
        let key = "\(role):\(channel)"
        guard saving == nil else { return }
        saving = key
        defer { saving = nil }
        do {
            let saved = try await api.setNoticePreference(.init(subjectKind: "role", subjectKey: role, channel: channel, enabled: enabled))
            stored.removeAll { $0.subjectKey == role && $0.channel == channel }
            stored.append(saved)
            error = nil
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}
