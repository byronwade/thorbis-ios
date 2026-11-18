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

    /// Who it was for, in the web log's words.
    var roleWord: String {
        switch role {
        case "owner": return "Owner"
        case "dispatcher": return "Dispatcher"
        case "technician": return "Technician"
        case "customer": return "Customer"
        default: return role.statusLabel
        }
    }

    /// How it went out.
    var channelWord: String {
        if channel == "email" { return "Email" }
        if channel == "in_app" { return "In-app" }
        return channel.statusLabel
    }

    /// Why a notice stopped because its channel is switched off; nil for every other notice.
    var channelOffNote: String? {
        guard reason == "preference_off" else { return nil }
        return status == "unresolved" ? "Delivery unconfirmed; channel is now off" : "Stopped because this channel is off"
    }

    /// "Owner · Email · Sent", in the web log's words.
    var summary: String {
        "\(roleWord) · \(channelWord) · \(channelOffNote ?? status.statusLabel)"
    }

    /// The colour of the row's status pill. Only the look: the word is always the server's status.
    var tone: NoticeOutcomeTone {
        if reason == "preference_off" { return .quiet }
        switch status {
        case "sent", "delivered": return .good
        case "failed", "bounced": return .bad
        default: return .quiet
        }
    }
}

enum NoticeOutcomeTone: Equatable {
    case good, bad, quiet
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

/// Paper 96B's chips over the log. They narrow the notices already on this phone; older ones
/// still come from "Show older notices".
private enum NoticeLogFilter: String, CaseIterable, Identifiable {
    case all, failed, email, inApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .failed: return "Failed"
        case .email: return "Email"
        case .inApp: return "In-app"
        }
    }

    func keeps(_ item: NoticeDelivery) -> Bool {
        switch self {
        case .all: return true
        case .failed: return item.tone == .bad
        case .email: return item.channel == "email"
        case .inApp: return item.channel == "in_app"
        }
    }
}

/// Paper 96B: the status as a word in a small tinted pill at the row's trailing edge.
private struct NoticeOutcomePill: View {
    let text: String
    let tone: NoticeOutcomeTone

    var body: some View {
        Text(text).font(Theme.font(13, weight: .semibold))
            .foregroundStyle(word)
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(surface, in: Capsule())
            .fixedSize()
    }

    private var word: Color {
        switch tone {
        case .good: return Theme.success
        case .bad: return Theme.destructive
        case .quiet: return Theme.subtle
        }
    }

    private var surface: Color {
        switch tone {
        case .good: return Theme.successSurface
        case .bad: return Theme.destructiveSurface
        case .quiet: return Theme.fill
        }
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
    @State private var filter: NoticeLogFilter = .all

    private var shown: [NoticeDelivery] { items.filter { filter.keeps($0) } }

    var body: some View {
        ScrollView {
            // Paper 96B: the header, the chips, then one card of rows with a hairline between them.
            LazyVStack(alignment: .leading, spacing: 0) {
                // Paper 96B: a 28 Bold title 20 from the edge, one 15 muted line under it. The
                // log isn't limited to a week here, so the line stops at "sent".
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delivery log").font(Theme.heading()).tracking(-0.56)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("Messages your rules sent")
                        .font(Theme.font(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.gutter).padding(.top, 14).padding(.bottom, 8)
                if let error { ErrorBanner(message: error) { await load() } }
                if !loaded && error == nil { ListRoomSkeleton(count: 6, threeLines: false) }
                if loaded && items.isEmpty && error == nil {
                    ListRoomEmpty(title: "Nothing sent yet.",
                                  message: "Each email or in-app update about a booked, changed or canceled job shows here.")
                }
                if !items.isEmpty { chips }
                let rows = shown
                if !items.isEmpty && rows.isEmpty {
                    ListRoomEmpty(title: "Nothing here.", message: "None of the notices loaded so far match.")
                }
                ForEach(rows) { item in
                    let first = item.id == rows.first?.id
                    let last = item.id == rows.last?.id
                    row(item, first: first)
                        .paperCardSlot(first: first, last: last)
                        .padding(.horizontal, PaperCardMetrics.margin)
                }
                if nextCursor != nil {
                    Button { Task { await loadMore() } } label: {
                        HStack(spacing: 8) {
                            if loadingMore { ProgressView() }
                            Text("Show older notices")
                        }
                        .font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.brandText)
                        .frame(minHeight: 44).padding(.horizontal, ListRoom.gutter).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(loadingMore)
                    .padding(.top, 8)
                }
            }
            .padding(.bottom, 24)
        }
        .foregroundStyle(Theme.foreground)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    /// All · Failed 7 · Email · In-app: 44 tall pills, the chosen one in ink.
    private var chips: some View {
        let failed = items.filter { $0.tone == .bad }.count
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NoticeLogFilter.allCases) { choice in
                    let on = choice == filter
                    let words = choice == .failed && failed > 0 ? "\(choice.title) \(failed)" : choice.title
                    Button { filter = choice } label: {
                        PaperChoiceChipLabel(title: words, isOn: on)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, PaperCardMetrics.margin)
        }
        .padding(.top, 6).padding(.bottom, 10)
    }

    /// The subject in 15 Semibold, who and how under it in 14, the status pill trailing.
    private func row(_ item: NoticeDelivery, first: Bool) -> some View {
        // The day only when there is one: today's notices end at the channel, not at a dot.
        let parts = [item.roleWord, item.channelWord, item.channelOffNote ?? "", relativeDay(item.updatedAt)]
        return VStack(alignment: .leading, spacing: 0) {
            if !first { WellDivider() }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.subject).font(Theme.font(15, weight: .semibold)).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    DotLine(parts)
                        .font(Theme.font(14))
                        .foregroundStyle(item.tone == .bad ? Theme.destructive : Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                NoticeOutcomePill(text: item.status.statusLabel, tone: item.tone)
            }
            .padding(.horizontal, PaperCardMetrics.inset).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
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
