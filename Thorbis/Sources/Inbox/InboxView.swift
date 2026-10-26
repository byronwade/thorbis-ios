import SwiftUI
import ThorbisCore

/// Job notices addressed to the signed-in staff member (`/v1/staff/notices`).
/// Notification bodies never carry customer details by default (HIG-014).
struct InboxView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        LoadState(
            isLoading: model.isRefreshing,
            error: model.refreshError,
            isEmpty: model.notices.isEmpty,
            emptyTitle: "You're caught up",
            emptySymbol: "tray",
            emptyMessage: "Updates about your jobs land here.",
            retry: { await model.refreshNotices() }
        ) {
            List {
                ForEach(model.notices) { notice in
                    NavigationLink(value: Route.job(notice.jobId)) {
                        HStack(alignment: .top, spacing: Theme.Space.m) {
                            Circle()
                                .fill(notice.read ? Color.clear : Theme.accent)
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(notice.title)
                                    .font(.body.weight(notice.read ? .regular : .medium))
                                    .foregroundStyle(Theme.ink)
                                Text(notice.meta).font(.subheadline).foregroundStyle(Theme.inkSecondary)
                                Text(Format.relative(Timestamp.parse(notice.at))).font(.footnote).foregroundStyle(Theme.inkQuiet)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(notice.read ? "" : "Unread. ")\(notice.title). \(notice.meta)")
                    }
                    .sheetRow()
                }
            }
            .thorbisList()
        }
        .navigationTitle("Inbox")
        .refreshable { await model.refreshNotices() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Mark all read") { Task { await model.markNoticesRead() } }
                    .disabled(model.unreadNotices == 0)
            }
            AccountToolbarItem()
        }
    }
}
