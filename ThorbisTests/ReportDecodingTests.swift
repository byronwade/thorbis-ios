import XCTest
@testable import Thorbis

final class ReportDecodingTests: XCTestCase {
    func testOperationsAndScheduleReportsDecodeTheServerShapes() throws {
        let operations = #"{"freshness":"live","generatedAt":"2026-10-27T12:00:00.000Z","periodBasis":"utc-month","reportVersion":1,"estimates":{"drafts":1,"presented":10,"approved":6,"declined":2,"conversionBps":6000},"jobs":{"booked":12,"completed":9,"canceled":1,"open":2},"months":[{"month":"2026-10","booked":12,"completed":9}],"truncated":false}"#
        let report = try JSONDecoder().decode(OperationsReport.self, from: Data(operations.utf8))
        XCTAssertEqual(report.estimates.conversionBps, 6000)
        XCTAssertEqual(report.months.first?.completed, 9)

        let schedule = #"{"freshness":"live","generatedAt":"2026-10-27T12:00:00.000Z","periodBasis":"utc-day","reportVersion":1,"capacityModel":"booked-time-only","days":[{"day":"2026-10-27","scheduled":7,"completed":2}],"assignees":[{"userId":"u","scheduled":3,"completed":1,"open":2}],"backlog":{"unscheduledOpenJobs":3,"overdueScheduledJobs":1},"truncated":false}"#
        let days = try JSONDecoder().decode(ScheduleReport.self, from: Data(schedule.utf8))
        XCTAssertEqual(days.backlog.unscheduledOpenJobs, 3)
    }

    func testTeamMembersShowCustomRoleOrBuiltInRole() throws {
        let json = #"{"items":[{"member":{"memberId":"m1","userId":"u1","displayName":"Byron Wade","email":"b@x.co","isLegalOwner":true,"legalMembershipRoles":[{"id":"owner","label":"Owner"}]},"authority":{"kind":"legacy_fallback","currentAssignmentVersion":0,"reason":"never_assigned","roles":[{"id":"owner","label":"Owner"}]}},{"member":{"memberId":"m2","userId":"u2","displayName":"Maria Chen","email":"m@x.co","isLegalOwner":false,"legalMembershipRoles":[{"id":"office","label":"Office"}]},"authority":{"kind":"tenant_role","assignmentId":"a","currentAssignmentVersion":1,"assignedRoleRevision":1,"role":{"roleId":"r","currentRevision":2,"name":"Dispatcher","description":""}}}],"nextCursor":null}"#
        let page = try JSONDecoder().decode(Items<RoleMember>.self, from: Data(json.utf8))
        XCTAssertEqual(page.items.map(\.roleLabel), ["Owner", "Dispatcher"])
    }
}
