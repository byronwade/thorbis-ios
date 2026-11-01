import XCTest
@testable import Thorbis

@MainActor
final class OperatingDetailsTests: XCTestCase {
    func testAWeekWritesTheServersCanonicalJSONAndReadsItBack() throws {
        var week = SetupWeek.standard
        week.days["sat"] = .init(open: true, from: 9 * 60, to: 13 * 60 + 30)
        XCTAssertEqual(week.json,
                       #"{"mon":["08:00","17:00"],"tue":["08:00","17:00"],"wed":["08:00","17:00"],"thu":["08:00","17:00"],"fri":["08:00","17:00"],"sat":["09:00","13:30"],"sun":null}"#)
        XCTAssertEqual(SetupWeek.parse(week.json), week)
        XCTAssertNil(SetupWeek.parse("Mon-Fri 8-5"))
        XCTAssertNil(SetupWeek.parse(nil))
    }

    func testAWeekTheServerWouldRefuseSaysWhy() {
        var week = SetupWeek.standard
        XCTAssertNil(week.problem)
        week.days["tue"]?.to = 7 * 60
        XCTAssertEqual(week.problem, "Tue closes before it opens.")
        for day in SetupWeek.days { week.days[day]?.open = false }
        XCTAssertEqual(week.problem, "Open at least one day, or skip this for now.")
    }

    func testTimeZoneChoicesPutThePhoneFirstAndKeepASavedZone() {
        let list = SetupTimeZones.choices(current: "Europe/London", device: "America/Chicago")
        XCTAssertEqual(list.first, "America/Chicago")
        XCTAssertEqual(list.filter { $0 == "America/Chicago" }.count, 1)
        XCTAssertEqual(list.last, "Europe/London")
    }

    func testTheStepShowsOnlyWhenTheServerKnowsTheFacts() {
        func profile(_ keys: [String]) -> OrganizationProfile {
            OrganizationProfile(organizationId: "org", facts: [],
                                catalog: keys.map { .init(factKey: $0, label: $0, tier: 1, required: false, confirmed: false) },
                                coreReady: false, missingCore: [])
        }
        XCTAssertFalse(OperatingFacts.offered(nil))
        XCTAssertFalse(OperatingFacts.offered(profile(["legal_name", "timezone"])))
        XCTAssertTrue(OperatingFacts.offered(profile(["legal_name"] + OperatingFacts.keys)))
        XCTAssertTrue(SetupStep.hours.facts.allSatisfy(OperatingFacts.keys.contains))
        XCTAssertTrue(SetupStep.hours.required.isEmpty)
    }
}
