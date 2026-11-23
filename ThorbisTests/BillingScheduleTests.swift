import XCTest
@testable import Thorbis

final class BillingScheduleTests: XCTestCase {
    func testScheduleProgressDecodesAndTotals() throws {
        let json = #"{"schedule":{"id":"00000000-0000-4000-8000-000000009501","organizationId":"o","customerId":"c","jobId":"j","createdByUserId":"u","retainageRateBps":1000,"status":"open","lines":[{"id":"l1","position":0,"description":"Rough-in","scheduledAmount":{"amount":4000,"currency":"USD"}},{"id":"l2","position":1,"description":"Trim","scheduledAmount":{"amount":6000,"currency":"USD"}}],"createdAt":"2026-10-01T12:00:00Z","updatedAt":"2026-10-01T12:00:00Z"},"lines":[{"lineId":"l1","billedToDate":4000,"remaining":0},{"lineId":"l2","billedToDate":1000,"remaining":5000}],"invoiceIds":[],"retainedToDate":500,"releasedToDate":0,"retainageOutstanding":500,"depositsBilled":0,"depositCredited":0,"depositOutstanding":0,"readyToBill":true}"#
        let progress = try JSONDecoder().decode(BillingScheduleProgress.self, from: Data(json.utf8))
        XCTAssertEqual(progress.schedule.total, 10_000)
        XCTAssertEqual(progress.billedToDate, 5_000)
        XCTAssertEqual(progress.remaining, 5_000)
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "BillingScheduleTests.\(UUID().uuidString)")!
    }

    // A reopened deposit sheet is a new view with a new store value; the key lives in the defaults.
    func testSameDepositAfterReopeningTheSheetReusesTheKey() throws {
        let defaults = makeDefaults()
        let request = BillingMoneyIntents.Request.deposit(jobID: "job-1", amountCents: 15_000)
        let first = try XCTUnwrap(BillingMoneyIntents(defaults: defaults).key(for: request, actorID: "A", organizationID: "O"))
        let reopened = BillingMoneyIntents(defaults: defaults)
        XCTAssertEqual(reopened.key(for: .deposit(jobID: "job-1", amountCents: 15_000), actorID: "A", organizationID: "O"), first)
    }

    func testADifferentAmountJobPersonOrCompanyGetsANewKey() throws {
        let store = BillingMoneyIntents(defaults: makeDefaults())
        let first = try XCTUnwrap(store.key(for: .deposit(jobID: "job-1", amountCents: 15_000), actorID: "A", organizationID: "O"))
        let others = [
            store.key(for: .deposit(jobID: "job-1", amountCents: 15_001), actorID: "A", organizationID: "O"),
            store.key(for: .deposit(jobID: "job-2", amountCents: 15_000), actorID: "A", organizationID: "O"),
            store.key(for: .deposit(jobID: "job-1", amountCents: 15_000), actorID: "B", organizationID: "O"),
            store.key(for: .deposit(jobID: "job-1", amountCents: 15_000), actorID: "A", organizationID: "P"),
        ]
        for other in others {
            XCTAssertNotNil(other)
            XCTAssertNotEqual(other, first)
        }
        XCTAssertEqual(Set(others.compactMap { $0 }).count, others.count)
        // The first request still has its own key.
        XCTAssertEqual(store.key(for: .deposit(jobID: "job-1", amountCents: 15_000), actorID: "A", organizationID: "O"), first)
    }

    func testEachScheduleCommandHasItsOwnKeyAndOnlySuccessClearsIt() throws {
        let store = BillingMoneyIntents(defaults: makeDefaults())
        let remainder = BillingMoneyIntents.Request.scheduleCommand(scheduleID: "s1", command: "bill-remainder")
        let retainage = BillingMoneyIntents.Request.scheduleCommand(scheduleID: "s1", command: "release-retainage")
        let key = try XCTUnwrap(store.key(for: remainder, actorID: "A", organizationID: "O"))
        XCTAssertNotEqual(store.key(for: retainage, actorID: "A", organizationID: "O"), key)
        XCTAssertNotEqual(store.key(for: .scheduleCommand(scheduleID: "s2", command: "bill-remainder"),
                                    actorID: "A", organizationID: "O"), key)
        // No answer yet (a timeout): the retry sends the same key.
        XCTAssertEqual(store.key(for: remainder, actorID: "A", organizationID: "O"), key)
        // A key that is no longer the saved one is not removed by a late success.
        store.complete(remainder, key: "another-key", actorID: "A", organizationID: "O")
        XCTAssertEqual(store.key(for: remainder, actorID: "A", organizationID: "O"), key)
        // After a 2xx the next request is a new one.
        store.complete(remainder, key: key, actorID: "A", organizationID: "O")
        let next = try XCTUnwrap(store.key(for: remainder, actorID: "A", organizationID: "O"))
        XCTAssertNotEqual(next, key)
    }

    // The sheet calls complete only after a 2xx, so a refusal leaves the key saved. That is safe:
    // the server undoes a refused command, so the same request sent later is new to it, and a
    // different amount never reaches this key.
    func testARefusalKeepsTheKeyOnlyForTheSameRequest() throws {
        let store = BillingMoneyIntents(defaults: makeDefaults())
        let refused = BillingMoneyIntents.Request.deposit(jobID: "job-1", amountCents: 900_000)
        let key = try XCTUnwrap(store.key(for: refused, actorID: "A", organizationID: "O"))
        XCTAssertEqual(store.key(for: refused, actorID: "A", organizationID: "O"), key)
        XCTAssertNotEqual(store.key(for: .deposit(jobID: "job-1", amountCents: 15_000), actorID: "A", organizationID: "O"), key)
    }

    func testNoKeyWithoutAPersonAndACompany() {
        let store = BillingMoneyIntents(defaults: makeDefaults())
        let request = BillingMoneyIntents.Request.deposit(jobID: "job-1", amountCents: 15_000)
        XCTAssertNil(store.key(for: request, actorID: nil, organizationID: "O"))
        XCTAssertNil(store.key(for: request, actorID: "A", organizationID: nil))
    }

    func testSignOutClearsEveryKey() throws {
        let defaults = makeDefaults()
        let request = BillingMoneyIntents.Request.deposit(jobID: "job-1", amountCents: 15_000)
        let key = try XCTUnwrap(BillingMoneyIntents(defaults: defaults).key(for: request, actorID: "A", organizationID: "O"))
        BillingMoneyIntents(defaults: defaults).clearAll()
        XCTAssertNotEqual(BillingMoneyIntents(defaults: defaults).key(for: request, actorID: "A", organizationID: "O"), key)
    }
}
