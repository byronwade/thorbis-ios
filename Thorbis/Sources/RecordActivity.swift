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
        let kind = try Self.pathSegment(type)
        let key = try Self.pathSegment(id)
        let page: Page = try await send("GET", "/v1/activity/\(kind)/\(key)",
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

    @State private var showAll = false

    /// Paper 35C "Activity": one card row (16 in, at least 56 tall). The latest event in 15, when
    /// and who in a 13 muted line under it, and "All activity" in 14 Semibold brand text, which
    /// opens the whole trail. Nothing recorded draws nothing.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(width: 0, height: 0)
            if loaded, let latest = items.first {
                Button { showAll = true } label: {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(latest.description).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            let line = Self.line(latest)
                            if !line.isEmpty {
                                Text(line).font(Theme.font(13)).foregroundStyle(Theme.muted)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("All activity").font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.brandText)
                            .lineLimit(1).fixedSize()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
                .buttonStyle(PressStyle())
                .accessibilityElement(children: .combine)
                .accessibilityHint("Shows all activity")
                .accessibilityIdentifier("record-activity")
            }
        }
        .task(id: "\(recordType)|\(recordID)|\(session.generation)") { await load() }
        .sheet(isPresented: $showAll) {
            SheetSurface { allActivity.presentationDetents([.medium, .large]) }
        }
    }

    /// "Sat 2:15 PM · Ramon M.": when, then why and who where the server says.
    static func line(_ item: RecordActivityItem) -> String {
        ([when(item.occurredAt)] + meta(item)).compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    private static func meta(_ item: RecordActivityItem) -> [String?] {
        [item.reason,
         item.clientOccurredAt != nil ? "done offline, synced later" : nil,
         item.actorType.flatMap { $0 == "user" ? nil : $0.capitalized }]
    }

    /// The whole trail, newest first, behind "All activity".
    private var allActivity: some View {
        VStack(alignment: .leading, spacing: 0) {
            ThorbisSheetHeader(title: "Activity", onClose: { showAll = false })
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // Paper 24 "Activity": one card (radius 20), a 56pt row per event with a
                    // hairline starting at the words.
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            row(item, divided: item.id != items.first?.id)
                        }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
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
                .padding(.horizontal, PaperCardMetrics.margin).padding(.top, 8).padding(.bottom, 24)
            }
        }
    }

    /// Paper 24: a small dot in a 20pt column, the event at 15 in the body grey, its time at 14
    /// muted on the trailing edge; why it happened (and "done offline") on a second line at 13.
    private func row(_ item: RecordActivityItem, divided: Bool) -> some View {
        let meta = Self.meta(item).compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        return HStack(alignment: .center, spacing: 12) {
            Circle().fill(Theme.muted.opacity(0.6)).frame(width: 8, height: 8)
                .frame(width: 20)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.description).font(Theme.font(15)).foregroundStyle(Theme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                    if !meta.isEmpty {
                        Text(meta).font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let when = Self.when(item.occurredAt) {
                    Text(when).font(Theme.font(14)).foregroundStyle(Theme.muted)
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
