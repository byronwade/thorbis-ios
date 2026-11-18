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

    /// One customer's job-email switch (web customer record); no row means on.
    func customerJobEmailsEnabled(_ customerID: String) async throws -> Bool {
        struct Page: Decodable { let items: [NoticePreference] }
        let key = customerID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? customerID
        let page: Page = try await send("GET", "/v1/notice-preferences/customer/\(key)")
        return page.items.first?.enabled ?? true
    }

    func setNoticePreference(_ preference: NoticePreference) async throws -> NoticePreference {
        try await send("POST", "/v1/notice-preferences", body: preference)
    }
}

/// Settings › Notification rules (web Settings › Job notices): who is told when a job is booked, changed or canceled.
struct NoticeSettingsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var stored: [NoticePreference] = []
    @State private var loaded = false
    @State private var saving: String?
    @State private var error: String?
    @State private var openLog = false
    @State private var morningDigest = PushNotifications.morningDigest

    private var managesRoles: Bool { session.can("organization.settings.edit", feature: "job_booking_notices") }
    private let roles = [("owner", "Owner"), ("dispatcher", "Dispatcher"), ("technician", "Technician")]
    private let channels = [("email", "Email"), ("in_app", "In-app")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Paper 96: the title in 34 Bold, one muted line, then one card per group of switches.
                PaperPageTitle(title: "Notification rules", subtitle: managesRoles ? "Who hears when a job is booked, changed or canceled" : "What this phone tells you", columnInset: PaperCardMetrics.margin)
                    .padding(.bottom, 16)
                if PushNotifications.receivesMorningDigest(session) {
                    // TG-11: one push at 6:30, the off switch lives here. Per phone, saved offline.
                    PaperSection("This phone", count: nil) {
                        Toggle(isOn: Binding(get: { morningDigest }, set: { next in
                            morningDigest = next
                            PushNotifications.shared.setMorningDigest(next)
                        })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Morning digest").font(Theme.font(16, weight: .medium))
                                Text("At 6:30: yesterday's collections, today's jobs and overdue invoices")
                                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                            }
                        }
                        .tint(Theme.brand)
                        .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                        .frame(minHeight: 52)
                    }
                    .padding(.bottom, 20)
                }
                if managesRoles {
                    if let error { ErrorBanner(message: error) { await load() }.padding(.horizontal, -PaperCardMetrics.margin).padding(.bottom, 12) }
                    if !loaded && error == nil { SkeletonRows(count: 4, leading: false, inset: 0) }
                    if loaded {
                        // One card per role; the label names the role, so the rows don't.
                        ForEach(roles, id: \.0) { role, label in
                            PaperSection(label, count: nil) {
                                ForEach(channels, id: \.0) { channel, channelName in
                                    let key = "\(role):\(channel)"
                                    if channel != channels.first?.0 { WellDivider() }
                                    Toggle(isOn: Binding(get: { isOn(role, channel) }, set: { next in Task { await save(role, channel, next) } })) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(channelName).font(Theme.font(16, weight: .medium))
                                            Text(channel == "email" ? "When a job is booked, changed or canceled" : "The same updates, in the app")
                                                .font(Theme.font(14)).foregroundStyle(Theme.muted)
                                        }
                                    }
                                    .tint(Theme.brand)
                                    .disabled(saving == key)
                                    .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 12)
                                    .frame(minHeight: 52)
                                    .accessibilityLabel("\(label) \(channelName.lowercased())")
                                }
                            }
                            .padding(.bottom, 20)
                        }
                    }
                    // Paper 96: the delivery log is its own card at the end, a row with a chevron.
                    PaperCard {
                        Button { openLog = true } label: {
                            HStack(spacing: 8) {
                                Text("Delivery log").font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.muted).accessibilityHidden(true)
                            }
                            .padding(.leading, PaperCardMetrics.inset).padding(.trailing, 14).padding(.vertical, 9)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                    }
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin).padding(.bottom, 32)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .thorbisDestination(isPresented: $openLog) { NoticeDeliveryLogView() }
        .refreshable { if managesRoles { await load() } }
        #if DEBUG
        // `--paper-preview-screen notice-log`: Notification rules, then straight into the log.
        .task { if PaperPreview.enabled, PaperPreview.screen == "notice-log" { openLog = true } }
        #endif
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
