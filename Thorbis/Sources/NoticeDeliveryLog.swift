import SwiftUI

/// `GET /v1/notice-deliveries` and `/v1/notice-deliveries/continue/{cursor}` (web Settings › Job notices › Delivery log).
/// Addresses and message text never reach this screen; only who, how, and what happened.
struct NoticeDelivery: Decodable, Identifiable, Hashable {
    let id: String
    let role: String
    let channel: String
    let status: String
    let reason: String?
    let subject: String
    let updatedAt: String

    /// "Owner · Email · Sent", in the web log's words.
    var summary: String {
        let who = switch role {
        case "owner": "Owner"
        case "dispatcher": "Dispatcher"
        case "technician": "Technician"
        case "customer": "Customer"
        default: role.statusLabel
        }
        let how = channel == "email" ? "Email" : channel == "in_app" ? "In-app" : channel.statusLabel
        let outcome: String
        if reason == "preference_off" {
            outcome = status == "unresolved" ? "Delivery unconfirmed; channel is now off" : "Stopped because this channel is off"
        } else {
            outcome = status.statusLabel
        }
        return "\(who) · \(how) · \(outcome)"
    }
}

struct NoticeDeliveryPage: Decodable {
    let items: [NoticeDelivery]
    let nextCursor: String?
}

extension APIClient {
    func noticeDeliveries(after cursor: String? = nil) async throws -> NoticeDeliveryPage {
        let limit = [URLQueryItem(name: "limit", value: "50")]
        guard let cursor else { return try await send("GET", "/v1/notice-deliveries", queryItems: limit) }
        guard let safe = cursor.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) else {
            throw Problem(title: "Invalid page", status: nil, detail: "The next page could not be requested.")
        }
        return try await send("GET", "/v1/notice-deliveries/continue/\(safe)", queryItems: limit)
    }
}

struct NoticeDeliveryLogView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var items: [NoticeDelivery] = []
    @State private var nextCursor: String?
    @State private var loaded = false
    @State private var loadingMore = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("Recent job notices. Addresses and message text stay off this screen.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, Theme.gutter).padding(.bottom, 8)
                if let error { ErrorBanner(message: error) { await load() } }
                if !loaded && error == nil { SkeletonRows(count: 6, leading: false) }
                if loaded && items.isEmpty {
                    PaperEmptyState(symbol: "envelope", title: "Nothing sent yet",
                                    message: "Each email or in-app update about a booked, changed or canceled job shows here.")
                }
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.subject).font(Theme.font(15, weight: .medium)).lineLimit(2)
                        Text("\(item.summary) · \(relativeDay(item.updatedAt))")
                            .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .padding(.horizontal, Theme.gutter)
                    .accessibilityElement(children: .combine)
                    Divider().padding(.leading, Theme.gutter)
                }
                if nextCursor != nil {
                    Button { Task { await loadMore() } } label: {
                        HStack(spacing: 8) {
                            if loadingMore { ProgressView() }
                            Text("Show older notices")
                        }
                        .font(Theme.font(15, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.border))
                    }
                    .buttonStyle(PressStyle())
                    .disabled(loadingMore)
                    .padding(Theme.gutter)
                }
            }
            .padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.background)
        .navigationTitle("Delivery log")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        let generation = session.generation
        do {
            let page = try await api.noticeDeliveries()
            guard session.generation == generation else { return }
            items = page.items
            nextCursor = page.nextCursor
            loaded = true
            error = nil
        } catch is CancellationError {} catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard let cursor = nextCursor, !loadingMore else { return }
        let generation = session.generation
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await api.noticeDeliveries(after: cursor)
            guard session.generation == generation else { return }
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            nextCursor = page.nextCursor == cursor ? nil : page.nextCursor
        } catch is CancellationError {} catch {
            guard session.generation == generation else { return }
            self.error = error.localizedDescription
        }
    }
}
