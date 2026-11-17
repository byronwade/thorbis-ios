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
                    // Paper 24 "Activity": one card (radius 20), a 56pt row per event with a
                    // hairline starting at the words.
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            row(item, divided: item.id != items.first?.id)
                        }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
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

    /// Paper 24: a small dot in a 20pt column, the event at 15 in the body grey, its time at 14
    /// muted on the trailing edge; why it happened (and "done offline") on a second line at 13.
    private func row(_ item: RecordActivityItem, divided: Bool) -> some View {
        let meta = [item.reason,
                    item.clientOccurredAt != nil ? "done offline, synced later" : nil,
                    item.actorType.flatMap { $0 == "user" ? nil : $0.capitalized }]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        return HStack(alignment: .center, spacing: 12) {
            Circle().fill(Theme.muted.opacity(0.6)).frame(width: 8, height: 8)
                .frame(width: 20)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.description).font(Theme.font(15)).foregroundStyle(Theme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                    if !meta.isEmpty {
                        Text(meta).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let when = Self.when(item.occurredAt) {
                    Text(when).font(Theme.font(14)).monospacedDigit().foregroundStyle(Theme.muted)
                        .lineLimit(1).fixedSize()
                }
            }
            .padding(.trailing, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .overlay(alignment: .top) {
                if divided { Rectangle().fill(Theme.hairline).frame(height: 1).accessibilityHidden(true) }
            }
        }
        .padding(.leading, 16)
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
