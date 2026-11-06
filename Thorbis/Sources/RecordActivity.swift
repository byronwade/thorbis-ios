import SwiftUI

/// One entry in a record's audit trail (`GET /v1/activity/:type/:id`, web record-shell ActivityFeed).
struct RecordActivityItem: Decodable, Identifiable, Hashable {
    let id: String
    let action: String
    let description: String
    let actorType: String?
    let occurredAt: String
    /// Set when the change was made offline and synced later.
    let clientOccurredAt: String?
    let reason: String?
}

extension APIClient {
    /// One page of a record's activity, newest first; `nextCursor` loads earlier entries.
    func recordActivity(_ type: String, id: String, cursor: String? = nil) async throws -> (items: [RecordActivityItem], nextCursor: String?) {
        struct Page: Decodable { let items: [RecordActivityItem]; let nextCursor: String? }
        let key = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let page: Page = try await send("GET", "/v1/activity/\(type)/\(key)",
                                        queryItems: [URLQueryItem(name: "limit", value: "50")], cursor: cursor)
        return (page.items, page.nextCursor)
    }
}

/// Web parity: who did what to an estimate or invoice, and when, in the web's activity grammar
/// (a glyph on a disc, the event, a quiet time). Hidden when the read is refused or the server is older.
struct RecordActivitySection: View {
    /// "estimate" or "invoice", as the web passes it.
    let recordType: String
    let recordID: String
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var items: [RecordActivityItem] = []
    @State private var nextCursor: String?
    @State private var loaded = false
    @State private var loadingMore = false
    @State private var moreFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear.frame(width: 0, height: 0)
            if loaded {
                SectionHeader(title: "Activity", count: items.isEmpty ? nil : items.count)
                if items.isEmpty && nextCursor == nil {
                    Text("Nothing recorded yet.").font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { row($0) }
                    }
                }
                if nextCursor != nil {
                    Button { Task { await loadMore() } } label: {
                        Text(moreFailed ? "Try loading earlier activity" : "Load earlier activity")
                            .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                            .frame(minHeight: 44).padding(.horizontal, 4).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(loadingMore)
                }
            }
        }
        .task(id: "\(recordType)|\(recordID)|\(session.generation)") { await load() }
    }

    private func row(_ item: RecordActivityItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: Self.symbol(item.action)).font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 24, height: 24).background(Theme.fill, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.description).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                let meta = [Self.when(item.occurredAt), item.reason,
                            item.clientOccurredAt != nil ? "done offline, synced later" : nil,
                            item.actorType.flatMap { $0 == "user" ? nil : $0.capitalized }]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
                if !meta.isEmpty {
                    Text(meta).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4).padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    /// The web's mapping (record-shell activityIcon), in SF Symbols.
    static func symbol(_ action: String) -> String {
        if action.contains("payment") { return "creditcard" }
        if action.contains("invoice") { return "doc.plaintext" }
        if action.contains("job") { return "briefcase" }
        if action.contains("estimate") { return "doc.text" }
        if action.contains("note") { return "text.bubble" }
        if action.contains("contact") || action.contains("assign") { return "person.2" }
        return "clock"
    }

    static func when(_ raw: String) -> String? {
        guard let date = JobFiltering.date(raw) else { return nil }
        // The app's trade time ("6:08 p.m."), with the day in front unless it's today.
        return Calendar.current.isDateInToday(date)
            ? date.clockTime
            : "\(date.formatted(.dateTime.month(.abbreviated).day())) \(date.clockTime)"
    }

    private func load() async {
        do {
            let page = try await api.recordActivity(recordType, id: recordID)
            items = page.items
            nextCursor = page.nextCursor
            loaded = true
        } catch is CancellationError {
        } catch {
            // No access, or an older server: leave the section out rather than show a guess.
            loaded = false
        }
    }

    private func loadMore() async {
        guard let cursor = nextCursor, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await api.recordActivity(recordType, id: recordID, cursor: cursor)
            let seen = Set(items.map(\.id))
            items += page.items.filter { !seen.contains($0.id) }
            nextCursor = page.nextCursor == cursor ? nil : page.nextCursor
            moreFailed = false
        } catch is CancellationError {
        } catch {
            moreFailed = true
        }
    }
}
