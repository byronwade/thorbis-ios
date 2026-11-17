import XCTest
@testable import Thorbis

@MainActor
final class RunningLateTests: XCTestCase {
    private let promised = Date(timeIntervalSinceReferenceDate: 799_999_980) // a whole minute

    func testDelayCountsFromThePromisedTimeWhileItIsAhead() {
        let now = promised.addingTimeInterval(-5 * 60)
        XCTAssertEqual(RunningLateDraft.newArrival(promised: promised, delayMinutes: 20, now: now),
                       promised.addingTimeInterval(20 * 60))
    }

    func testDelayCountsFromNowOncePromisedTimeHasGone() {
        let now = promised.addingTimeInterval(15 * 60)
        XCTAssertEqual(RunningLateDraft.newArrival(promised: promised, delayMinutes: 10, now: now),
                       promised.addingTimeInterval(25 * 60))
    }

    func testNewArrivalRoundsUpToAWholeMinute() {
        let now = promised.addingTimeInterval(30)
        XCTAssertEqual(RunningLateDraft.newArrival(promised: promised, delayMinutes: 10, now: now),
                       promised.addingTimeInterval(11 * 60))
    }

    func testGreetingUsesFirstNameForPeopleAndWholeNameForBusinesses() {
        XCTAssertEqual(RunningLateDraft.greetingName("Danielle Marlowe", commercial: false), "Danielle")
        XCTAssertEqual(RunningLateDraft.greetingName("Birchwood Dental", commercial: true), "Birchwood Dental")
        XCTAssertNil(RunningLateDraft.greetingName("   ", commercial: false))
        XCTAssertNil(RunningLateDraft.greetingName(nil, commercial: false))
    }

    func testMessageInPapersWordsWithAReason() {
        let text = RunningLateDraft.message(customer: "Danielle", tech: "Ramon", company: "Wade's Plumbing",
                                            reason: "my last job ran long.", newTime: "10:50 a.m.", oldTime: "10:30")
        XCTAssertEqual(text, "Hi Danielle, it's Ramon from Wade's Plumbing. My last job ran long, so I'll be there around 10:50 a.m. instead of 10:30. Sorry for the wait.")
    }

    func testMessageWithoutReasonOrNames() {
        let text = RunningLateDraft.message(customer: nil, tech: nil, company: " ", reason: "  ",
                                            newTime: "1:10 p.m.", oldTime: "12:45 p.m.")
        XCTAssertEqual(text, "Hi, I'm running late, so I'll be there around 1:10 p.m. instead of 12:45 p.m. Sorry for the wait.")
    }

    func testMessageWithOnlyTheCompany() {
        let text = RunningLateDraft.message(customer: "Danielle", tech: nil, company: "Wade's Plumbing", reason: "",
                                            newTime: "10:40 a.m.", oldTime: "10:30")
        XCTAssertTrue(text.hasPrefix("Hi Danielle, it's Wade's Plumbing. I'm running late"))
        XCTAssertFalse(text.contains("http"), "No tracking link: there is no tracking page")
    }
}
