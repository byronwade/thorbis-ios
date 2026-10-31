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
        /// The street line of the job's own service location (never the customer's other
        /// addresses), when the app has read it. Optional so older snapshot files still decode.
        var street: String?

        /// Street first; without a recorded site the job's own title leads (BYR-1593).
        var headline: String { street ?? title }
        /// The line under the headline: the problem (when the street leads) and the customer.
        var subline: String {
            [street == nil ? nil : title, customer.isEmpty ? nil : customer].compactMap { $0 }.joined(separator: " · ")
        }
    }

    /// Where the person is in today's visits, mirroring the Today header ("visit 3 of 6").
    enum DayProgress: Equatable {
        case visit(Int, of: Int)
        case allDone(Int)

        var text: String {
            switch self {
            case .visit(let index, let total): "\(index) of \(total) visits"
            case .allDone(let total): total == 1 ? "Visit done" : "All \(total) done"
            }
        }
    }

    var items: [Item]
    var writtenAt: Date

    static let appGroup = "group.com.thorbis.field"
    static let widgetKind = "TodayJobs"
    static let nextStopKind = "NextStop"
    static let controlKind = "com.thorbis.field.next-step"
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

    /// Today's visits (finished ones included, canceled ones not), earliest first, and where the
    /// lead job sits among them: the same count the Today screen's subtitle shows.
    func progress(on day: Date, calendar: Calendar = .current) -> DayProgress? {
        let visits = items
            .filter { $0.status != "canceled" && ($0.at.map { calendar.isDate($0, inSameDayAs: day) } ?? false) }
            .sorted { ($0.at ?? .distantFuture) < ($1.at ?? .distantFuture) }
        guard !visits.isEmpty else { return nil }
        if visits.allSatisfy({ $0.status == "completed" }) { return .allDone(visits.count) }
        guard let lead = upcoming(on: day, calendar: calendar).first,
              let index = visits.firstIndex(where: { $0.id == lead.id }) else { return nil }
        return .visit(index + 1, of: visits.count)
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
        WidgetCenter.shared.reloadTimelines(ofKind: nextStopKind)
        ControlCenter.shared.reloadControls(ofKind: controlKind)
        #endif
    }
}
