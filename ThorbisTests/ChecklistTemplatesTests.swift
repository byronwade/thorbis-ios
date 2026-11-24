import XCTest
@testable import Thorbis

final class ChecklistTemplatesTests: XCTestCase {
    private func decode(_ json: String) throws -> CompanyCloseoutPolicy {
        try JSONDecoder().decode(CompanyCloseoutPolicy.self, from: Data(json.utf8))
    }

    private func check(_ key: String, _ label: String, kind: String? = nil, unpaid: Bool? = nil) -> FieldCloseoutCheckDefinition {
        FieldCloseoutCheckDefinition(key: key, label: label, kind: kind, allowUnpaidDisposition: unpaid)
    }

    private var policy: CompanyCloseoutPolicy {
        CompanyCloseoutPolicy(requireNotes: true, requiredPhotoCount: 2, requiredChecks: [
            check("swept_area", "Swept the work area"),
            check("customer_authorization", "Customer signed", kind: "customer_authorization"),
            check("old_parts", "Showed the old parts", kind: "acknowledgement"),
            check("payment_or_unpaid_disposition", "Paid or a reason", kind: "payment_or_unpaid_disposition", unpaid: true),
            check("gas_off", "Gas shut off"),
        ])
    }

    // MARK: Decoding

    func testDecodesAConfiguredPolicy() throws {
        let decoded = try decode("""
        {"organizationId":"00000000-0000-4000-8000-000000000003","requireNotes":true,"requiredPhotoCount":3,
         "requiredChecks":[{"key":"swept_area","label":"Swept the work area"},
                           {"key":"customer_authorization","label":"Customer signed","kind":"customer_authorization"},
                           {"key":"payment_or_unpaid_disposition","label":"Paid","kind":"payment_or_unpaid_disposition","allowUnpaidDisposition":true}],
         "updatedByUserId":"00000000-0000-4000-8000-000000000001","updatedAt":"2026-11-01T12:00:00.000Z"}
        """)
        XCTAssertTrue(decoded.requireNotes)
        XCTAssertEqual(decoded.requiredPhotoCount, 3)
        XCTAssertEqual(decoded.requiredChecks.map(\.key), ["swept_area", "customer_authorization", "payment_or_unpaid_disposition"])
        XCTAssertNil(decoded.requiredChecks[0].kind)
        XCTAssertEqual(decoded.requiredChecks[2].allowUnpaidDisposition, true)
        XCTAssertEqual(decoded.updatedAt, "2026-11-01T12:00:00.000Z")
        XCTAssertEqual(CloseoutPolicyRules.acknowledgements(decoded).map(\.key), ["swept_area"])
    }

    /// Before anything is configured the server answers with the permissive default and no dates.
    func testDecodesTheUnconfiguredDefault() throws {
        let decoded = try decode(#"{"organizationId":"00000000-0000-4000-8000-000000000003","requireNotes":false,"requiredPhotoCount":0,"requiredChecks":[]}"#)
        XCTAssertEqual(decoded, CompanyCloseoutPolicy())
    }

    func testMissingFieldsMeanNothingRequired() throws {
        XCTAssertEqual(try decode("{}"), CompanyCloseoutPolicy())
        XCTAssertEqual(try decode(#"{"requiredPhotoCount":-4}"#).requiredPhotoCount, 0)
    }

    /// A check that can't be read must fail the load: dropping it would delete it on the next save.
    func testAnUnreadableCheckIsAnErrorNotAGap() {
        XCTAssertThrowsError(try decode(#"{"requiredChecks":[{"key":"swept_area","label":"Swept"},{"key":"no_label"}]}"#))
    }

    // MARK: Writing

    func testWriteBodySendsTheWholePolicyAndLeavesOutEmptyFields() throws {
        let data = try JSONEncoder().encode(policy.write)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["requireNotes", "requiredPhotoCount", "requiredChecks"])
        let checks = try XCTUnwrap(object["requiredChecks"] as? [[String: Any]])
        XCTAssertEqual(checks.count, 5)
        // The server's schema takes a missing `kind`, not a null one.
        XCTAssertEqual(Set(checks[0].keys), ["key", "label"])
        XCTAssertEqual(checks[3]["allowUnpaidDisposition"] as? Bool, true)
    }

    // MARK: Keys

    func testKeyIsMadeFromTheNameAndStaysUnique() {
        XCTAssertEqual(CloseoutPolicyRules.key(for: "Swept & cleaned the work area!", existing: []), "swept_cleaned_the_work_area")
        XCTAssertEqual(CloseoutPolicyRules.key(for: "Gas off", existing: ["gas_off"]), "gas_off_2")
        XCTAssertEqual(CloseoutPolicyRules.key(for: "Gas off", existing: ["gas_off", "gas_off_2"]), "gas_off_3")
        XCTAssertEqual(CloseoutPolicyRules.key(for: "Café ✓", existing: []), "cafe")
        XCTAssertEqual(CloseoutPolicyRules.key(for: "✓✓", existing: []), "check")
    }

    func testKeyNeverTakesAReservedNameOrRunsLong() {
        XCTAssertEqual(CloseoutPolicyRules.key(for: "Customer authorization", existing: []), "customer_authorization_2")
        let long = CloseoutPolicyRules.key(for: String(repeating: "word ", count: 60), existing: [])
        XCTAssertLessThanOrEqual(long.count, CloseoutPolicyRules.maxKey)
        XCTAssertFalse(long.hasSuffix("_"))
    }

    // MARK: Editing

    func testAddingPutsTheCheckAfterTheLastOneATechConfirms() {
        let next = CloseoutPolicyRules.adding("  Hauled away debris ", to: policy)
        XCTAssertEqual(next.requiredChecks.map(\.key),
                       ["swept_area", "customer_authorization", "old_parts", "payment_or_unpaid_disposition", "gas_off", "hauled_away_debris"])
        XCTAssertEqual(next.requiredChecks.last?.label, "Hauled away debris")
        XCTAssertTrue(next.requireNotes)
        XCTAssertEqual(next.requiredPhotoCount, 2)
        let first = CloseoutPolicyRules.adding("Swept", to: CompanyCloseoutPolicy(requiredChecks: [check("customer_authorization", "Signed", kind: "customer_authorization")]))
        XCTAssertEqual(first.requiredChecks.map(\.key), ["swept", "customer_authorization"])
    }

    func testRenamingKeepsTheKeyAndOnlyTouchesThatCheck() {
        let next = CloseoutPolicyRules.renaming("old_parts", to: " Showed the customer the old parts ", in: policy)
        XCTAssertEqual(next.requiredChecks.map(\.key), policy.requiredChecks.map(\.key))
        XCTAssertEqual(next.requiredChecks[2].label, "Showed the customer the old parts")
        XCTAssertEqual(next.requiredChecks[2].kind, "acknowledgement")
        // The signature rule is not a check to rename.
        XCTAssertEqual(CloseoutPolicyRules.renaming("customer_authorization", to: "Other", in: policy), policy)
    }

    func testRemovingLeavesTheOtherRulesAlone() {
        let next = CloseoutPolicyRules.removing("swept_area", from: policy)
        XCTAssertEqual(next.requiredChecks.map(\.key), ["customer_authorization", "old_parts", "payment_or_unpaid_disposition", "gas_off"])
        XCTAssertEqual(CloseoutPolicyRules.removing("payment_or_unpaid_disposition", from: policy), policy)
    }

    // MARK: Ordering

    func testMovingSwapsWithTheNextCheckAndKeepsRulesInPlace() {
        let down = CloseoutPolicyRules.moving("swept_area", by: 1, in: policy)
        XCTAssertEqual(down.requiredChecks.map(\.key),
                       ["old_parts", "customer_authorization", "swept_area", "payment_or_unpaid_disposition", "gas_off"])
        let up = CloseoutPolicyRules.moving("gas_off", by: -1, in: policy)
        XCTAssertEqual(up.requiredChecks.map(\.key),
                       ["swept_area", "customer_authorization", "gas_off", "payment_or_unpaid_disposition", "old_parts"])
        XCTAssertEqual(CloseoutPolicyRules.acknowledgements(up).map(\.key), ["swept_area", "gas_off", "old_parts"])
    }

    func testMovingPastAnEndOrAnUnknownCheckChangesNothing() {
        XCTAssertEqual(CloseoutPolicyRules.moving("swept_area", by: -1, in: policy), policy)
        XCTAssertEqual(CloseoutPolicyRules.moving("gas_off", by: 1, in: policy), policy)
        XCTAssertEqual(CloseoutPolicyRules.moving("missing", by: 1, in: policy), policy)
        XCTAssertEqual(CloseoutPolicyRules.moving("customer_authorization", by: 1, in: policy), policy)
        XCTAssertFalse(CloseoutPolicyRules.canMove("swept_area", by: -1, in: policy))
        XCTAssertTrue(CloseoutPolicyRules.canMove("swept_area", by: 1, in: policy))
        XCTAssertFalse(CloseoutPolicyRules.canMove("gas_off", by: 1, in: policy))
    }

    // MARK: Limits

    func testNameProblems() {
        XCTAssertNotNil(CloseoutPolicyRules.problem(label: "   ", in: policy))
        XCTAssertNotNil(CloseoutPolicyRules.problem(label: String(repeating: "a", count: 201), in: policy))
        XCTAssertNotNil(CloseoutPolicyRules.problem(label: "gas shut off", in: policy))
        // Saving a check under its own name is not a clash.
        XCTAssertNil(CloseoutPolicyRules.problem(label: "Gas shut off", in: policy, replacing: "gas_off"))
        XCTAssertNil(CloseoutPolicyRules.problem(label: "Hauled away debris", in: policy))
        let full = CompanyCloseoutPolicy(requiredChecks: (0..<50).map { check("c\($0)", "Check \($0)") })
        XCTAssertNotNil(CloseoutPolicyRules.problem(label: "One more", in: full))
        XCTAssertNil(CloseoutPolicyRules.problem(label: "Renamed", in: full, replacing: "c3"))
    }

    func testPhotoCountStaysInTheServersRange() {
        XCTAssertEqual(CloseoutPolicyRules.photos(-1), 0)
        XCTAssertEqual(CloseoutPolicyRules.photos(7), 7)
        XCTAssertEqual(CloseoutPolicyRules.photos(99), 50)
    }
}
