import XCTest
@testable import Thorbis

@MainActor
final class WebParityTests: XCTestCase {
    func testDeliveryLogSpeaksLikeTheWebLog() throws {
        let body = #"{"items":[{"id":"n1","role":"owner","channel":"email","status":"sent","subject":"Job booked: Water heater","updatedAt":"2026-10-28T12:00:00.000Z"},{"id":"n2","role":"technician","channel":"in_app","status":"unresolved","reason":"preference_off","subject":"Job changed","updatedAt":"2026-10-28T12:00:00.000Z"}],"nextCursor":"abc"}"#
        let page = try JSONDecoder().decode(NoticeDeliveryPage.self, from: Data(body.utf8))
        XCTAssertEqual(page.items.map(\.summary), [
            "Owner · Email · Sent",
            "Technician · In-app · Delivery unconfirmed; channel is now off",
        ])
        XCTAssertEqual(page.nextCursor, "abc")
    }

    func testActivityReportPicksTheTopFivePayingCustomers() throws {
        let rows = (1...7).map { #"{"customerId":"c\#($0)","estimates":1,"jobs":\#($0),"invoices":1,"revenue":\#($0 == 3 ? 0 : $0 * 1000)}"# }
        let body = #"{"freshness":"live","generatedAt":"2026-10-28T12:00:00.000Z","customers":[\#(rows.joined(separator: ","))],"locations":[],"truncated":false}"#
        let report = try JSONDecoder().decode(CustomerActivityReport.self, from: Data(body.utf8))
        XCTAssertEqual(report.topCustomers.map(\.customerId), ["c7", "c6", "c5", "c4", "c2"])
    }

    func testExportsCoverEveryWebReportFile() {
        XCTAssertEqual(Set(ReportExport.all.map(\.path)), [
            "/v1/reports/operations.xlsx", "/v1/reports/activity.xlsx", "/v1/reports/schedule.xlsx",
            "/v1/reports/revenue.xlsx", "/v1/reports/payment-activity.xlsx",
        ])
        let day = ISO8601DateFormatter().date(from: "2026-10-28T12:00:00Z")!
        XCTAssertEqual(ReportExport.all[3].fileName(on: day), "thorbis-revenue-2026-10-28.xlsx")
    }

    func testPropertiesUnionSkipsArchivedCapsAtFiftyAndSortsByAddress() {
        let customers = (0..<60).map { Customer(id: "c\($0)", name: "Customer \($0)", archived: $0 == 0, createdAt: nil) }
        let union = PropertiesUnion.customers(from: customers)
        XCTAssertEqual(union.included.count, 50)
        XCTAssertEqual(union.included.first?.id, "c1")
        XCTAssertTrue(union.capped)

        func location(_ id: String, _ address: String, kind: String = "service") -> ServiceLocationRecord {
            ServiceLocationRecord(id: id, organizationId: "o", customerId: "c1", label: "Home", kind: kind, address: address,
                                  notes: nil, coordinates: nil, gateCode: nil, alarmCode: nil, dogOnSite: nil, parking: nil,
                                  createdAt: "2026-10-28T12:00:00Z", updatedAt: "2026-10-28T12:00:00Z")
        }
        let rows = PropertiesUnion.rows([(customers[1], [location("b", "9 Oak St"), location("a", "12 Elm St", kind: "billing")])])
        XCTAssertEqual(rows.map(\.id), ["a", "b"])
        XCTAssertEqual(rows[0].kindLabel, "Billing")
        XCTAssertTrue(rows[1].matches("oak"))
        XCTAssertTrue(rows[1].matches("customer 1"))
        XCTAssertFalse(rows[1].matches("pine"))
    }
}
