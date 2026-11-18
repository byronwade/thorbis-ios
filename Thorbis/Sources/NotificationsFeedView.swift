import SwiftUI

/// Paper 77 "Notifications": the 34 Bold title and "3 unread", All and Unread, then the staff
/// notices on a card: the dot and a bell on brand while unread, what happened, how long ago and
/// the job. A row opens its job; the check circle marks the feed read.
///
/// The same notices show in Messages under Job notices; this is the bell's own screen.
struct NotificationsFeedView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var notices: [StaffNotice] = []
    @State private var nextCursor: String?
    @State private var readCursor: String?
    @State private var unreadState: StaffUnreadState = .unknown
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    @State private var filter = NotificationsFilter.all.rawValue

    /// The access Messages' Job notices section uses: job.view with job_booking_notices.
    private var available: Bool { CommsInboxAccess(session).notices }
    private var chosen: NotificationsFilter { NotificationsFilter(rawValue: filter) ?? .all }
    private var canMarkRead: Bool { available && (unreadState == .present || readCursor != nil || NotificationsFeed.unreadCount(notices) > 0) }

    var body: some View {
        let groups = NotificationsFeed.groups(notices, filter: chosen)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PaperPageTitle(title: "Notifications", subtitle: subtitle, titleIdentifier: "notifications-title", subtitleIdentifier: "notifications-subtitle")
                    .padding(.bottom, 14)
                if !available {
                    // Permission names what is missing (design.thorbis.com States).
                    ListRoomEmpty(symbol: "lock", title: "Your role can\u{2019}t see notices", message: "Ask your office for access to job notices.")
                } else {
                    // Paper 77: "Search or ask" with the filter circle, then the segments 16 under it.
                    PaperSearchBar(placeholder: "Search or ask") {
                        ThorbisMenu(items: NotificationsFilter.allCases.map { item in
                            ThorbisMenuItem(item.rawValue, isSelected: item == chosen) { filter = item.rawValue }
                        }, title: "Show", accessibilityLabel: "Filter notifications") {
                            PaperFilterCircle(active: chosen != .all)
                        }
                        .accessibilityValue(filter)
                    }
                    .paperCardMargin()
                    PaperTabs(options: NotificationsFilter.allCases.map(\.rawValue), selection: $filter).padding(.top, 16)
                    if let error { ErrorBanner(message: notices.isEmpty ? "Notices did not load. \(error)" : error) { await refresh() } }
                    if !loaded && notices.isEmpty && error == nil { ListRoomSkeleton(count: 6, threeLines: false) }
                    ForEach(groups) { group in
                        CommsDayCard(title: group.title) {
                            ForEach(Array(group.notices.enumerated()), id: \.element.id) { index, notice in
                                // The hairline starts at the words, past the dot and bell.
                                if index > 0 { WellDivider(leading: 76) }
                                row(notice)
                            }
                        }
                        // Paper: the first card sits 16 under the segments (the card's own top is 20).
                        .padding(.top, group.id == groups.first?.id && group.title.isEmpty ? 0 : 4)
                    }
                    if nextCursor != nil {
                        Button { Task { await loadMore() } } label: {
                            Text(loading ? "Loading\u{2026}" : "Load older notices")
                                .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .disabled(loading)
                        .padding(.top, 12)
                        .accessibilityIdentifier("notifications-older")
                    }
                    if groups.isEmpty && loaded && error == nil {
                        if chosen == .unread && !notices.isEmpty {
                            ListRoomEmpty(title: "No unread notices", message: "All shows every notice.")
                        } else {
                            ListRoomEmpty(title: "No notices yet", message: "New assignments and job changes land here.")
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("notifications")
        .toolbar {
            if canMarkRead {
                ThorbisToolbarItem(placement: .topBarTrailing) {
                    // Paper 77: the 44pt card circle with a check.
                    Button { Task { await markRead() } } label: { CreamCircleLabel(symbol: "checkmark") }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel(readCursor == nil ? "Mark all read" : "Continue marking read")
                        .disabled(loading)
                        .accessibilityIdentifier("notifications-mark-read")
                }
            }
        }
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private var subtitle: String {
        guard available else { return "Job updates" }
        return NotificationsFeed.subtitle(notices: notices, complete: loaded && nextCursor == nil,
                                          unreadState: unreadState, loading: loading)
    }

    /// A notice opens the job it is about. There is no per-notice Read: the notices API marks the
    /// whole feed read (POST /v1/staff/notices/read).
    private func row(_ notice: StaffNotice) -> some View {
        NavigationLink(value: PaperRoute.job(notice.jobId)) {
            CommsNoticeRow(notice: notice, relativeTime: true)
        }
        .buttonStyle(RowPressStyle())
        .background(Theme.card)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([notice.title, notice.meta, spokenTime(notice.at), notice.read ? "Read" : "Unread"]
            .filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityHint("Opens the job")
        .accessibilityIdentifier("notifications-row-\(notice.id)")
    }

    /// How long ago, for VoiceOver ("5 min. ago"), in whole words where the row shows "12m".
    private func spokenTime(_ raw: String?) -> String {
        guard let raw, let date = JobFiltering.date(raw) else { return "" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    private func refresh() async {
        guard available, !loading else { return }
        loading = true
        defer { loading = false; loaded = true }
        do {
            let page = try await api.staffNotices()
            notices = NotificationsFeed.merged([], adding: page.items)
            nextCursor = page.nextCursor
            unreadState = page.unreadState
            error = nil
        } catch is CancellationError {
        } catch { self.error = error.isConnectivityFailure ? "Notices need a connection." : error.localizedDescription }
    }

    private func loadMore() async {
        guard available, !loading, let cursor = nextCursor else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await api.staffNotices(cursor: cursor)
            guard page.nextCursor != cursor else {
                throw Problem(title: "Notice pagination stopped", status: nil, detail: "The server repeated its cursor.")
            }
            notices = NotificationsFeed.merged(notices, adding: page.items)
            nextCursor = page.nextCursor
            unreadState = page.unreadState
            error = nil
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    /// The server marks the feed read in batches; a second press continues a long feed.
    private func markRead() async {
        guard available, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await api.markStaffNoticesRead(cursor: readCursor)
            guard result.nextCursor != readCursor || result.nextCursor == nil else {
                throw Problem(title: "Notice acknowledgement stopped", status: nil, detail: "The server repeated its cursor.")
            }
            readCursor = result.nextCursor
            let page = try await api.staffNotices()
            notices = NotificationsFeed.merged([], adding: page.items)
            nextCursor = page.nextCursor
            unreadState = page.unreadState
            error = nil
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }
}
