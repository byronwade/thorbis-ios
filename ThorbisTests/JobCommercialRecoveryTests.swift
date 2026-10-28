import XCTest
@testable import Thorbis

final class JobCommercialRecoveryTests: XCTestCase {
    private func requirement(_ nextAction: String?, outcome: String = "blocked", source: String? = nil) -> FieldCloseoutRequirement {
        FieldCloseoutRequirement(requirement: "check:paid", kind: "payment_or_unpaid_disposition", outcome: outcome,
                                 detail: "Payment is outstanding.", nextAction: nextAction, commercialSource: source)
    }

    func testCommercialActionsBecomeOneButtonEach() {
        XCTAssertEqual(CloseoutNextStep(requirement("reconcile_commercial_state")), .createInvoice)
        XCTAssertEqual(CloseoutNextStep(requirement("collect_payment")), .collectPayment)
        XCTAssertEqual(CloseoutNextStep(requirement("record_unpaid_disposition")), .recordUnpaid)
        XCTAssertEqual(CloseoutNextStep(requirement("collect_payment", source: "schedule")), .openBilling)
        XCTAssertEqual(CloseoutNextStep(requirement("reconcile_commercial_state"))?.buttonTitle, "Create invoice")
        XCTAssertEqual(CloseoutNextStep(requirement("record_unpaid_disposition"))?.buttonTitle, "Collect payment")
    }

    func testEvidenceStepsAreWordsAndMachineCodesNeverShow() {
        XCTAssertEqual(CloseoutNextStep(requirement("add_job_photo"))?.detail, "Add photos on the job.")
        XCTAssertNil(CloseoutNextStep(requirement("add_job_photo"))?.buttonTitle)
        XCTAssertEqual(CloseoutNextStep(requirement("acknowledge_check:ladder"))?.detail, "Confirm it below.")
        XCTAssertNil(CloseoutNextStep(requirement("some_future_action")))
        XCTAssertNil(CloseoutNextStep(requirement("collect_payment", outcome: "satisfied")))
    }
}
