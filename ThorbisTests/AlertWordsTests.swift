import XCTest
@testable import Thorbis

/// What the phone says it alerts about. The server sends "Payment received" only to owners and
/// dispatchers who may view the invoice, so payments are named only for people who could be one,
/// and always with who gets them.
@MainActor
final class AlertWordsTests: XCTestCase {
    // Capability sets shaped like the built-in roles.
    private let owner: Set<String> = ["invoice.view", "job.assign", "job.cancel", "organization.settings.edit"]
    private let officeManager: Set<String> = ["invoice.view", "job.assign", "job.cancel"]
    private let dispatcher: Set<String> = ["invoice.view", "job.assign", "job.cancel"]
    private let technician: Set<String> = ["invoice.view"]
    private let csr: Set<String> = ["invoice.view"]
    private let accountant: Set<String> = ["invoice.view"]
    private let csrWhoAssigns: Set<String> = ["invoice.view", "job.assign"]

    func testOwnersOfficeManagersAndDispatchersSeePayments() {
        XCTAssertTrue(AlertWords.includesPayments(capabilities: owner))
        XCTAssertTrue(AlertWords.includesPayments(capabilities: officeManager))
        XCTAssertTrue(AlertWords.includesPayments(capabilities: dispatcher))
    }

    func testTechnicianIsNotToldAboutPayments() {
        XCTAssertFalse(AlertWords.includesPayments(capabilities: technician))
    }

    func testOtherRolesAndNoCapabilitiesAreNotToldAboutPayments() {
        XCTAssertFalse(AlertWords.includesPayments(capabilities: csr))
        XCTAssertFalse(AlertWords.includesPayments(capabilities: accountant))
        XCTAssertFalse(AlertWords.includesPayments(capabilities: csrWhoAssigns))
        XCTAssertFalse(AlertWords.includesPayments(capabilities: ["job.cancel"]))
        XCTAssertFalse(AlertWords.includesPayments(capabilities: []))
    }

    func testMyNotificationsAndDeviceAccessWords() {
        XCTAssertEqual(AlertWords.summary(payments: false), "New jobs and schedule changes")
        XCTAssertEqual(AlertWords.summary(payments: true),
                       "New jobs and schedule changes. Payments received, for owners and dispatchers")
    }

    func testJoinScreenWords() {
        XCTAssertEqual(AlertWords.joinSummary(payments: false), "New jobs and changes")
        XCTAssertEqual(AlertWords.joinSummary(payments: true), "New jobs and changes. Payments for owners and dispatchers")
    }

    func testPrimerPoints() {
        XCTAssertEqual(AlertWords.primerPoints(payments: false),
                       ["New jobs", "Schedule changes", "The morning digest, if you turn it on"])
        XCTAssertEqual(AlertWords.primerPoints(payments: true),
                       ["New jobs", "Schedule changes", "Payments received, for owners and dispatchers",
                        "The morning digest, if you turn it on"])
    }

    func testEveryPaymentMentionSaysWhoGetsIt() {
        let withPayments = [AlertWords.summary(payments: true), AlertWords.joinSummary(payments: true)]
            + AlertWords.primerPoints(payments: true).filter { $0.contains("Payment") }
        XCTAssertEqual(withPayments.count, 3)
        for words in withPayments { XCTAssertTrue(words.contains("owners and dispatchers"), words) }
        let without = [AlertWords.summary(payments: false), AlertWords.joinSummary(payments: false)]
            + AlertWords.primerPoints(payments: false)
        for words in without { XCTAssertFalse(words.localizedCaseInsensitiveContains("payment"), words) }
    }
}
