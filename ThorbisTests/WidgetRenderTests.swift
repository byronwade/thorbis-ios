import SwiftUI
import XCTest
@testable import Thorbis

@MainActor
final class WidgetRenderTests: XCTestCase {
    func testTodaySnapshotPutsTheJobUnderWayFirstAndDropsOtherDays() {
        let calendar = Calendar(identifier: .gregorian)
        let day = Date(timeIntervalSince1970: 1_793_000_000)
        let item = { (id: String, status: String, hours: Double) in
            TodaySnapshot.Item(id: id, at: day.addingTimeInterval(hours * 3600), title: id, customer: "", status: status)
        }
        let snapshot = TodaySnapshot(items: [item("late", "scheduled", 3), item("early", "dispatched", 1),
                                             item("working", "in_progress", -2), item("tomorrow", "scheduled", 30),
                                             item("done", "completed", 0.5)], writtenAt: day)
        XCTAssertEqual(snapshot.upcoming(on: day, calendar: calendar).map(\.id), ["working", "early", "late"])
    }

    /// Outside a widget the family reads as medium, so the today render uses the medium size.
    /// Writes PNGs of the widget surfaces when THORBIS_RENDER_DIR is set (for release notes).
    func testRenderWidgetSurfaces() throws {
        let views: [(String, AnyView, CGSize)] = [
            ("live-activity", AnyView(JobLockScreenView(
                attributes: JobActivityAttributes(jobID: "1", jobNumber: "JOB-2214", title: "AC not cooling",
                                                  customer: "Danielle Marlowe", address: "412 Birchwood Ln"),
                state: .init(status: "en_route", since: .now.addingTimeInterval(-420), waitingToSync: false))
                .background(Color(red: 0.12, green: 0.12, blue: 0.12))), CGSize(width: 360, height: 150)),
            ("today-medium", AnyView(TodayJobsView(entry: TodayEntry(date: .now, items: TodayJobsWidget.sample, signedOut: false))
                .padding(16).background(WidgetInk.ground)), CGSize(width: 340, height: 170)),
        ]
        for (name, view, size) in views {
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .dark))
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage, name)
            if let dir = ProcessInfo.processInfo.environment["THORBIS_RENDER_DIR"] {
                try image.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            }
        }
    }
}
