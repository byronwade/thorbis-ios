// The test bundle also compiles this file; there the shared types live in the app module.
#if WIDGET_TESTS
@testable import Thorbis
#endif
import SwiftUI
import WidgetKit

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, items: TodayJobsWidget.sample, signedOut: false, progress: .visit(1, of: 3))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (TodayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : Self.entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        // Redraw as each booking passes and again at midnight; the app reloads on every change.
        let upcoming = TodaySnapshot.load()?.upcoming(on: now).compactMap(\.at).filter { $0 > now } ?? []
        // The next calendar day, not now + 24h: on a 25-hour day that is still today.
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let dates = [now] + upcoming.prefix(6) + [midnight]
        completion(Timeline(entries: dates.map(Self.entry(at:)), policy: .after(now.addingTimeInterval(1_800))))
    }

    static func entry(at date: Date) -> TodayEntry {
        guard let snapshot = TodaySnapshot.load() else { return TodayEntry(date: date, items: [], signedOut: true) }
        return TodayEntry(date: date, items: snapshot.upcoming(on: date), signedOut: false, progress: snapshot.progress(on: date))
    }
}

struct TodayJobsWidget: Widget {
    /// Placeholder rows for the widget gallery only (never shown as someone's day).
    nonisolated static let sample = [
        TodaySnapshot.Item(id: "1", at: Calendar.current.date(bySettingHour: 10, minute: 30, second: 0, of: .now),
                           title: "AC not cooling", customer: "Danielle Marlowe", status: "dispatched", street: "412 Birchwood Ln"),
        TodaySnapshot.Item(id: "2", at: Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: .now),
                           title: "Water heater flush", customer: "David Chen", status: "scheduled", street: "88 Pine St"),
        TodaySnapshot.Item(id: "3", at: Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: .now),
                           title: "Outlet replacement", customer: "Elena Alvarez", status: "scheduled"),
    ]

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodaySnapshot.widgetKind, provider: TodayProvider()) { entry in
            TodayJobsView(entry: entry)
                .containerBackground(for: .widget) { WidgetInk.ground }
        }
        .configurationDisplayName("Today's jobs")
        .description("Your job under way, what's next today and how far through the day you are.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

/// "Next stop": the one place to go next, with its next step as a button.
struct NextStopWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodaySnapshot.nextStopKind, provider: TodayProvider()) { entry in
            NextStopView(entry: entry)
                .containerBackground(for: .widget) { WidgetInk.ground }
        }
        .configurationDisplayName("Next stop")
        .description("Where you're headed next, with On my way, Arrived or Start one tap away.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview("Small", as: .systemSmall) { TodayJobsWidget() } timeline: {
    TodayEntry(date: .now, items: TodayJobsWidget.sample, signedOut: false, progress: .visit(3, of: 6))
    TodayEntry(date: .now, items: [], signedOut: false)
}

#Preview("Medium", as: .systemMedium) { TodayJobsWidget() } timeline: {
    TodayEntry(date: .now, items: TodayJobsWidget.sample, signedOut: false, progress: .visit(3, of: 6))
}

#Preview("Large", as: .systemLarge) { TodayJobsWidget() } timeline: {
    TodayEntry(date: .now, items: TodayJobsWidget.sample, signedOut: false, progress: .visit(3, of: 6))
}

#Preview("Next stop", as: .systemSmall) { NextStopWidget() } timeline: {
    TodayEntry(date: .now, items: TodayJobsWidget.sample, signedOut: false, progress: .visit(3, of: 6))
}
