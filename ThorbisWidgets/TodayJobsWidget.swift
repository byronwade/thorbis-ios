// The test bundle also compiles this file; there the shared types live in the app module.
#if WIDGET_TESTS
@testable import Thorbis
#endif
import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let items: [TodaySnapshot.Item]
    /// No snapshot yet: the person has not opened the app signed in.
    let signedOut: Bool
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, items: TodayJobsWidget.sample, signedOut: false)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (TodayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        // Redraw as each booking passes and again at midnight; the app reloads on every change.
        let upcoming = TodaySnapshot.load()?.upcoming(on: now).compactMap(\.at).filter { $0 > now } ?? []
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        let dates = [now] + upcoming.prefix(6) + [midnight]
        completion(Timeline(entries: dates.map(entry(at:)), policy: .after(now.addingTimeInterval(1_800))))
    }

    private func entry(at date: Date) -> TodayEntry {
        guard let snapshot = TodaySnapshot.load() else { return TodayEntry(date: date, items: [], signedOut: true) }
        return TodayEntry(date: date, items: snapshot.upcoming(on: date), signedOut: false)
    }
}

struct TodayJobsWidget: Widget {
    static let sample = [
        TodaySnapshot.Item(id: "1", at: Calendar.current.date(bySettingHour: 10, minute: 30, second: 0, of: .now),
                           title: "AC not cooling", customer: "Danielle Marlowe", status: "dispatched"),
        TodaySnapshot.Item(id: "2", at: Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: .now),
                           title: "Water heater flush", customer: "David Chen", status: "scheduled"),
        TodaySnapshot.Item(id: "3", at: Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: .now),
                           title: "Outlet replacement", customer: "Elena Alvarez", status: "scheduled"),
    ]

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodaySnapshot.widgetKind, provider: TodayProvider()) { entry in
            TodayJobsView(entry: entry)
                .containerBackground(for: .widget) { WidgetInk.ground }
        }
        .configurationDisplayName("Today's jobs")
        .description("Your job under way and what's next today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

enum WidgetInk {
    static let ground = Color(red: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255)
    static let card = Color(red: 0x23 / 255, green: 0x23 / 255, blue: 0x23 / 255)
    static let brand = Color(red: 0x2F / 255, green: 0x6B / 255, blue: 0xFF / 255)
    static let brandText = Color(red: 0x52 / 255, green: 0x85 / 255, blue: 0xFF / 255)
    static let warning = Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
    static let muted = Color.white.opacity(0.6)
}

private func timeText(_ item: TodaySnapshot.Item) -> String {
    if TodaySnapshot.liveStatuses.contains(item.status) {
        return switch item.status {
        case "en_route": "On my way"
        case "arrived": "On site"
        case "paused": "Paused"
        default: "Working"
        }
    }
    return item.at?.formatted(date: .omitted, time: .shortened) ?? "Today"
}

private func statusTint(_ item: TodaySnapshot.Item) -> Color {
    TodaySnapshot.liveStatuses.contains(item.status) && item.status != "en_route" ? WidgetInk.warning : WidgetInk.brandText
}

struct TodayJobsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        case .accessoryInline: inline
        case .systemMedium: medium
        default: small
        }
    }

    @ViewBuilder private var small: some View {
        if let next = entry.items.first {
            VStack(alignment: .leading, spacing: 4) {
                Text(TodaySnapshot.liveStatuses.contains(next.status) ? "Under way" : "Next up")
                    .font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(WidgetInk.muted)
                Text(timeText(next))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(statusTint(next))
                    .minimumScaleFactor(0.7).lineLimit(1)
                Spacer(minLength: 2)
                Text(next.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                Text(next.customer).font(.caption).foregroundStyle(WidgetInk.muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(JobActivityLink.url(jobID: next.id))
        } else {
            empty
        }
    }

    @ViewBuilder private var medium: some View {
        if entry.items.isEmpty {
            empty
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Today").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Spacer()
                    Text("\(entry.items.count) left").font(.caption).foregroundStyle(WidgetInk.muted)
                }
                ForEach(entry.items.prefix(3)) { item in
                    Link(destination: JobActivityLink.url(jobID: item.id) ?? URL(string: "thorbis://schedule")!) {
                        HStack(spacing: 10) {
                            Text(timeText(item))
                                .font(.system(.caption, design: .monospaced).weight(.medium))
                                .foregroundStyle(statusTint(item))
                                .frame(width: 72, alignment: .leading)
                                .lineLimit(1).minimumScaleFactor(0.8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                                Text(item.customer).font(.caption2).foregroundStyle(WidgetInk.muted).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private var rectangular: some View {
        if let next = entry.items.first {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(timeText(next)).font(.headline).widgetAccentable()
                    Spacer(minLength: 4)
                    Text(TodayJobsView.leftText(entry.items.count)).font(.caption2).foregroundStyle(.secondary)
                }
                Text(next.customer).font(.caption).lineLimit(1)
                Text(next.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(JobActivityLink.url(jobID: next.id))
        } else {
            Text(entry.signedOut ? "Open Thorbis to sign in" : "No more jobs today").font(.caption)
        }
    }

    /// Jobs left today, as a number with the word "left" under it.
    @ViewBuilder private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.signedOut {
                Image(systemName: "person.crop.circle").font(.title3)
                    .accessibilityLabel("Open Thorbis to sign in")
            } else {
                VStack(spacing: 0) {
                    Text("\(entry.items.count)").font(.title3.weight(.semibold).monospacedDigit()).widgetAccentable()
                    Text("left").font(.caption2)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TodayJobsView.leftText(entry.items.count) + " today")
            }
        }
        .widgetURL(entry.items.first.flatMap { JobActivityLink.url(jobID: $0.id) } ?? URL(string: "thorbis://schedule"))
    }

    /// One line next to the Lock Screen clock: the next job's time and customer.
    @ViewBuilder private var inline: some View {
        if let next = entry.items.first {
            Text("\(timeText(next)) · \(next.customer)")
                .widgetURL(JobActivityLink.url(jobID: next.id))
        } else {
            Text(entry.signedOut ? "Open Thorbis to sign in" : "No more jobs today")
        }
    }

    static func leftText(_ count: Int) -> String {
        count == 1 ? "1 job left" : "\(count) jobs left"
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: entry.signedOut ? "person.crop.circle" : "checkmark.circle")
                .font(.title3).foregroundStyle(WidgetInk.brandText)
            Spacer(minLength: 0)
            Text(entry.signedOut ? "Open Thorbis to sign in" : "No more jobs today")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            Text(entry.signedOut ? "Your day shows here." : "You're all caught up.")
                .font(.caption).foregroundStyle(WidgetInk.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "thorbis://schedule"))
    }
}

#Preview("Small", as: .systemSmall) { TodayJobsWidget() } timeline: {
    TodayEntry(date: .now, items: TodayJobsWidget.sample, signedOut: false)
    TodayEntry(date: .now, items: [], signedOut: false)
}

#Preview("Medium", as: .systemMedium) { TodayJobsWidget() } timeline: {
    TodayEntry(date: .now, items: TodayJobsWidget.sample, signedOut: false)
}
