import Foundation

// Paper 77 "Notifications": the drawer's bell opens the person's staff notices (GET
// /v1/staff/notices), newest first on one card, with All and Unread. Paper also draws a search
// field, a Mentions tab and a snooze bar; the notices API has none of those, so they are not drawn.

enum NotificationsFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
}

/// One card of notices under a label. Paper 77 puts every notice on one card; Unread narrows it.
struct NotificationsGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let notices: [StaffNotice]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.notices.map(\.id) == rhs.notices.map(\.id)
            && lhs.notices.map(\.read) == rhs.notices.map(\.read)
    }
}

enum NotificationsFeed {
    /// The feed with another page added. A notice the server sends twice (a page read again after
    /// new notices arrived) shows once, in its first place, with the newer copy's read state.
    static func merged(_ existing: [StaffNotice], adding page: [StaffNotice]) -> [StaffNotice] {
        var order: [String] = []
        var byID: [String: StaffNotice] = [:]
        for notice in existing + page {
            if byID[notice.id] == nil { order.append(notice.id) }
            byID[notice.id] = notice
        }
        return order.compactMap { byID[$0] }
    }

    /// Newest first. Notices without a time keep the server's order after the dated ones.
    static func ordered(_ notices: [StaffNotice]) -> [StaffNotice] {
        notices.enumerated().sorted { a, b in
            switch (JobFiltering.date(a.element.at), JobFiltering.date(b.element.at)) {
            case let (x?, y?): x == y ? a.offset < b.offset : x > y
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.offset < b.offset
            }
        }.map(\.element)
    }

    static func visible(_ notices: [StaffNotice], filter: NotificationsFilter) -> [StaffNotice] {
        let list = ordered(notices)
        return filter == .unread ? list.filter { !$0.read } : list
    }

    static func unreadCount(_ notices: [StaffNotice]) -> Int { notices.filter { !$0.read }.count }

    /// What the screen shows under the tabs: Paper 77's one card, newest first, with no labels.
    /// A notice's dot, brand bell and Semibold words say it is unread.
    static func groups(_ notices: [StaffNotice], filter: NotificationsFilter) -> [NotificationsGroup] {
        let list = visible(notices, filter: filter)
        return list.isEmpty ? [] : [NotificationsGroup(id: "all", title: "", notices: list)]
    }

    /// Paper 77's line under the title: "3 unread", counted only once every page is here so it is
    /// never short; otherwise what the server says about the rest.
    static func subtitle(notices: [StaffNotice], complete: Bool, unreadState: StaffUnreadState, loading: Bool) -> String {
        let unread = unreadCount(notices)
        if complete && unread > 0 { return "\(unread) unread" }
        switch unreadState {
        case .present: return unread > 0 ? "\(unread) unread so far" : "Unread notices waiting"
        case .unknown: return loading ? "Checking for new notices\u{2026}" : "Job updates"
        case .none: return notices.isEmpty && loading ? "Checking for new notices\u{2026}" : "All caught up"
        }
    }
}
