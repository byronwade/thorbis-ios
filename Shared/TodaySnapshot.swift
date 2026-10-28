import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The few fields of today's jobs the Home Screen widget shows. The app writes it to the
/// shared App Group container whenever the job list changes; the widget only reads it.
struct TodaySnapshot: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        let id: String
        let at: Date?
        let title: String
        let customer: String
        let status: String
    }

    var items: [Item]
    var writtenAt: Date

    static let appGroup = "group.com.thorbis.field"
    static let widgetKind = "TodayJobs"
    static let liveStatuses: Set<String> = ["en_route", "arrived", "in_progress", "paused"]
    static let openStatuses: Set<String> = ["scheduled", "dispatched"]

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("today-snapshot.json")
    }

    /// The job under way first, then what is still booked for `day`, earliest first.
    func upcoming(on day: Date, calendar: Calendar = .current) -> [Item] {
        let live = items.filter { Self.liveStatuses.contains($0.status) }
        let booked = items
            .filter { Self.openStatuses.contains($0.status) }
            .filter { $0.at.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
            .sorted { ($0.at ?? .distantFuture) < ($1.at ?? .distantFuture) }
        return live + booked
    }

    static func load() -> TodaySnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TodaySnapshot.self, from: data)
    }

    static func save(_ snapshot: TodaySnapshot) {
        guard let url = fileURL, load()?.items != snapshot.items,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        reloadWidget()
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
        reloadWidget()
    }

    private static func reloadWidget() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        #endif
    }
}
