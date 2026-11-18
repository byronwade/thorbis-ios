#if DEBUG
import Foundation

/// Sample records for the DEBUG design preview only (`--paper-preview`), written to a temporary
/// folder so the on-phone places can be compared with Paper's populated artboards. Never used
/// outside the preview; nothing here touches a person's real records.
@MainActor
enum PlacesPreviewData {
    static func folder(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("paper-preview-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private static func at(_ daysAgo: Int, _ hour: Int, _ minute: Int, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// Paper 27: two finished days this week and today's shift running with one break taken.
    static func timeClock(userID: String, organizationID: String) throws -> TimeClockStore {
        let store = try TimeClockStore(userID: userID, organizationID: organizationID, directory: folder("timeclock"))
        let now = Date()
        // The fix preview leaves yesterday open, so only the day before is finished there.
        for days in (PaperPreview.screen == "time-clock-fix" ? [2] : [2, 1]) {
            let lunch = TimeClockBreak(start: at(days, 12, 0), end: at(days, 12, 30))
            let entry = TimeClockEntry(clockIn: at(days, 7, 20), clockOut: at(days, 15, 45), breaks: [lunch])
            try? store.save(entry, now: now)
        }
        if PaperPreview.screen == "time-clock-fix" {
            // Paper 27B: yesterday's shift was never closed.
            try? store.save(TimeClockEntry(clockIn: at(1, 7, 52)), now: now)
            return store
        }
        let started = now.addingTimeInterval(-9876)
        if PaperPreview.screen == "time-clock-break" {
            // Paper 27C: a 30-minute lunch, 13 minutes in.
            let lunch = TimeClockBreak(start: now.addingTimeInterval(-780), plannedMinutes: 30)
            try? store.save(TimeClockEntry(clockIn: started, breaks: [lunch]), now: now)
            return store
        }
        let pause = TimeClockBreak(start: started.addingTimeInterval(3600), end: started.addingTimeInterval(5400))
        try? store.save(TimeClockEntry(clockIn: started, breaks: [pause]), now: now)
        return store
    }

    /// Paper 46: a few receipts this month and last.
    static func receipts(organizationID: String, userID: String) throws -> ReceiptsStore {
        let store = try ReceiptsStore(organizationID: organizationID, userID: userID, directory: folder("receipts"))
        let rows: [(String, Int, Int, Int, Int, ReceiptCategory)] = [
            ("Ferguson Supply", 0, 9, 20, 4680, .parts), ("Shell #4482", 1, 16, 5, 5810, .fuel),
            ("Home Depot #0912", 3, 11, 0, 12460, .tools), ("Denny\u{2019}s #221", 4, 12, 40, 1820, .meals),
            ("CoolAir Supply Co.", 9, 10, 0, 14200, .parts), ("Chevron #883", 12, 8, 0, 4420, .fuel),
            ("NAPA Auto Parts #310", 35, 14, 0, 6735, .parts),
        ]
        for row in rows {
            _ = try? store.save(ReceiptRecord(merchant: row.0, date: at(row.1, row.2, row.3), totalCents: row.4, category: row.5))
        }
        return store
    }

    /// Paper 84: two items under their par and three that are fine.
    static func truckStock(organizationID: String, userID: String) throws -> TruckStockStore {
        let store = try TruckStockStore(organizationID: organizationID, userID: userID, directory: folder("truckstock"))
        let rows: [(String, String?, Int, Int)] = [
            ("Run capacitor 45/5 \u{00B5}F", "CAP-455", 1, 6), ("3/4\" copper coupling", "CU-34C", 2, 12),
            ("Contactor 30A 2-pole", "Bin B4", 5, 4), ("R-410A refrigerant", "Rack", 3, 2), ("16\u{00D7}25\u{00D7}1 filter", "Bin A1", 14, 10),
        ]
        for row in rows {
            try? store.save(TruckStockItem(name: row.0, partNumber: row.1, quantity: row.2, minimum: row.3))
        }
        return store
    }

    /// Paper 28: one license due, two in date, and courses under way.
    static func training(actorID: String, organizationID: String) throws -> TrainingRecords {
        let records = try TrainingRecords(actorID: actorID, organizationID: organizationID, directory: folder("training"))
        func day(_ ahead: Int) -> String {
            LearnDay.string(from: Calendar.current.date(byAdding: .day, value: ahead, to: Date()) ?? Date())
        }
        _ = try? records.save(TrainingCredential(name: "EPA 608 Universal", number: "88213", issuer: "ESCO Institute", expiresOn: day(14)))
        _ = try? records.save(TrainingCredential(name: "State HVAC contractor license", number: "CAC1820455", issuer: "DBPR", expiresOn: day(300)))
        _ = try? records.save(TrainingCredential(name: "OSHA 10", issuer: "CareerSafe"))
        try? records.save(TrainingCourse(title: "Refrigerant handling", link: "https://example.com/course", progress: "Lesson 3 of 8"))
        try? records.save(TrainingCourse(title: "Ladder and lift safety", progress: "Passed the quiz", done: true))
        return records
    }
}
#endif
