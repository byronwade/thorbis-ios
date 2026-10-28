import SwiftUI

/// The technician's own week of job hours (design.thorbis.com/job-hours, JH-05, JH-06).
/// Read-only: every number comes from a visit step, and nothing here can be edited (JH-07).
struct MyWeekView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var session: SessionController

    var body: some View {
        TimelineView(.everyMinute) { context in
            let week = JobWeek.make(store.jobs, userID: session.user?.id, now: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Pushed screen: system Back only (MA-05).
                    VStack(alignment: .leading, spacing: 4) {
                        Text("My week").font(Theme.font(30, weight: .medium)).tracking(-0.6)
                            .accessibilityAddTraits(.isHeader)
                        Text("Job hours from On my way, Mark arrived and Wrap up")
                            .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, Theme.gutter).padding(.bottom, 12)

                    if let error = store.error {
                        ErrorBanner(message: error) { _ = await store.refresh(api) }
                            .padding(.bottom, 12)
                    }
                    // Nothing loaded yet is not a week of zero hours.
                    if store.jobs.isEmpty, store.loading, store.error == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else if !store.jobs.isEmpty || store.error == nil {
                        weekList(week)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .refreshable { _ = await store.refresh(api) }
    }

    @ViewBuilder
    private func weekList(_ week: JobWeek) -> some View {
        PaperDetailRow(label: "Total") {
            Text(JobHours.minutes(week.minutes)).font(Theme.monoFont(15, weight: .medium))
        }
        .padding(.horizontal, Theme.gutter)

        ForEach(week.days.reversed()) { day in
            PaperGroupHeader(title: day.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) {
                if !day.rows.isEmpty {
                    Text(JobHours.minutes(day.minutes)).font(Theme.monoFont(12)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 16)
            if day.rows.isEmpty {
                Text("No jobs recorded").font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, Theme.gutter).padding(.vertical, 10)
            }
            ForEach(day.rows) { row in
                NavigationLink(value: PaperRoute.job(row.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(Theme.font(15, weight: .medium)).lineLimit(1)
                        Text("\(row.reference) · \(row.hours.line)")
                            .font(row.hours.hasDuration ? Theme.monoFont(12) : Theme.font(13))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .padding(.horizontal, Theme.gutter)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
