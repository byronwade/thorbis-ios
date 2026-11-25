import XCTest
@testable import Thorbis

/// Access just for one person: a save replaces the whole policy, so a permission set on the web
/// (a limit, a block, or more than one grant) is kept exactly as loaded and the rest is edited.
final class MemberOverrideRulesTests: XCTestCase {
    private typealias Rules = MemberOverrideRules

    private func snapshot(kind: String = "active", grants: String, denies: String = "[]") throws -> PermissionOverrideSnapshot {
        let json = #"{"kind":"\#(kind)","expectedVersion":4,"policy":{"grants":\#(grants),"userDenies":\#(denies)}}"#
        return try JSONDecoder().decode(PermissionOverrideSnapshot.self, from: Data(json.utf8))
    }

    private let limited = #"{"capability":"estimate.discount","scope":"assigned","effect":"allow","conditions":{"maxDiscountPercent":10}}"#
    private let blocked = #"{"capability":"invoice.refund","scope":"organization","effect":"deny"}"#
    private let plain = #"{"capability":"job.assign","scope":"team","effect":"allow"}"#

    func testALimitSurvivesASaveThatChangesAnotherPermission() throws {
        let loaded = Rules.load(try snapshot(grants: "[\(limited),\(plain)]"))
        XCTAssertEqual(loaded.locked, ["estimate.discount"])
        XCTAssertNil(loaded.choices["estimate.discount"])
        var choices = loaded.choices
        choices["customer.edit"] = .allow
        XCTAssertTrue(Rules.changed(choices: choices, scopes: loaded.scopes, from: loaded))
        let sent = Rules.policy(choices: choices, scopes: loaded.scopes, loaded: loaded)
        XCTAssertEqual(sent.grants, [
            RoleGrant(capability: "estimate.discount", scope: "assigned", conditions: ["maxDiscountPercent": 10], effect: "allow"),
            RoleGrant(capability: "customer.edit", scope: "organization"),
            RoleGrant(capability: "job.assign", scope: "team"),
        ])
        XCTAssertEqual(sent.denies, [])
    }

    func testADenyEffectGrantSurvives() throws {
        let loaded = Rules.load(try snapshot(grants: "[\(blocked),\(plain)]"))
        XCTAssertEqual(loaded.locked, ["invoice.refund"])
        var choices = loaded.choices
        choices["job.assign"] = .role
        let sent = Rules.policy(choices: choices, scopes: loaded.scopes, loaded: loaded)
        XCTAssertEqual(sent.grants, [RoleGrant(capability: "invoice.refund", scope: "organization", effect: "deny")])
    }

    func testAPermissionWithTwoGrantsSurvivesWithBoth() throws {
        let second = #"{"capability":"job.assign","scope":"organization","effect":"allow"}"#
        let loaded = Rules.load(try snapshot(grants: "[\(plain),\(second)]", denies: #"["job.assign","customer.edit"]"#))
        XCTAssertEqual(loaded.locked, ["job.assign"])
        XCTAssertEqual(loaded.choices, ["customer.edit": .never])
        let sent = Rules.policy(choices: loaded.choices, scopes: loaded.scopes, loaded: loaded)
        XCTAssertEqual(sent.grants, [RoleGrant(capability: "job.assign", scope: "team", effect: "allow"),
                                     RoleGrant(capability: "job.assign", scope: "organization", effect: "allow")])
        // A locked permission's deny is kept as loaded, beside the editable Never.
        XCTAssertEqual(sent.denies, ["customer.edit", "job.assign"])
    }

    func testAPlainAllowCanStillBeChangedAndRemoved() throws {
        let loaded = Rules.load(try snapshot(grants: "[\(plain)]"))
        XCTAssertTrue(loaded.locked.isEmpty)
        XCTAssertEqual(loaded.choices, ["job.assign": .allow])
        XCTAssertEqual(loaded.scopes, ["job.assign": "team"])
        XCTAssertFalse(Rules.changed(choices: loaded.choices, scopes: loaded.scopes, from: loaded))

        var scopes = loaded.scopes
        scopes["job.assign"] = "organization"
        XCTAssertTrue(Rules.changed(choices: loaded.choices, scopes: scopes, from: loaded))
        XCTAssertEqual(Rules.policy(choices: loaded.choices, scopes: scopes, loaded: loaded).grants,
                       [RoleGrant(capability: "job.assign", scope: "organization")])

        let removed = Rules.policy(choices: ["job.assign": .role], scopes: loaded.scopes, loaded: loaded)
        XCTAssertEqual(removed.grants, [])
        XCTAssertEqual(removed.denies, [])
    }

    func testNeverStillWorks() throws {
        let loaded = Rules.load(try snapshot(grants: "[]", denies: #"["customer.edit"]"#))
        XCTAssertEqual(loaded.choices, ["customer.edit": .never])
        var choices = loaded.choices
        choices["job.assign"] = .never
        let sent = Rules.policy(choices: choices, scopes: [:], loaded: loaded)
        XCTAssertEqual(sent.grants, [])
        XCTAssertEqual(sent.denies, ["customer.edit", "job.assign"])
    }

    /// A plain grant whose permission is also in the denies loads as Never. Its scope is still in the
    /// loaded scopes, and that alone must not make an untouched screen look changed.
    func testAnUntouchedScreenIsNotChangedWhenAPlainGrantIsAlsoDenied() throws {
        let loaded = Rules.load(try snapshot(grants: "[\(plain)]", denies: #"["job.assign"]"#))
        XCTAssertEqual(loaded.choices["job.assign"], .never)
        XCTAssertFalse(Rules.changed(choices: loaded.choices, scopes: loaded.scopes, from: loaded))
    }

    func testNothingChosenAndNothingKeptRevokes() throws {
        let loaded = Rules.load(try snapshot(grants: "[\(plain)]"))
        let sent = Rules.policy(choices: ["job.assign": .role], scopes: loaded.scopes, loaded: loaded)
        XCTAssertTrue(sent.grants.isEmpty && sent.denies.isEmpty)
    }

    func testSomethingKeptAndNothingChosenDoesNotRevoke() throws {
        let loaded = Rules.load(try snapshot(grants: "[\(blocked),\(plain)]"))
        let sent = Rules.policy(choices: ["job.assign": .role], scopes: loaded.scopes, loaded: loaded)
        XCTAssertFalse(sent.grants.isEmpty && sent.denies.isEmpty)
        XCTAssertEqual(sent.grants, [RoleGrant(capability: "invoice.refund", scope: "organization", effect: "deny")])
    }

    func testAnExpiredOverrideKeepsNothing() throws {
        let loaded = Rules.load(try snapshot(kind: "expired", grants: "[\(limited),\(blocked)]", denies: #"["customer.edit"]"#))
        XCTAssertTrue(loaded.locked.isEmpty)
        XCTAssertTrue(loaded.choices.isEmpty)
        XCTAssertTrue(loaded.keptGrants.isEmpty && loaded.keptDenies.isEmpty)
        let sent = Rules.policy(choices: [:], scopes: [:], loaded: loaded)
        XCTAssertTrue(sent.grants.isEmpty && sent.denies.isEmpty)
    }

    func testTheRetryKeyCoversKeptLimits() throws {
        let ten = Rules.load(try snapshot(grants: "[\(limited)]"))
        let fifteen = Rules.load(try snapshot(grants: "[\(limited.replacingOccurrences(of: ":10", with: ":15"))]"))
        let a = Rules.policy(choices: [:], scopes: [:], loaded: ten)
        let b = Rules.policy(choices: [:], scopes: [:], loaded: fifteen)
        XCTAssertNotEqual(Rules.changeKey(grants: a.grants, denies: a.denies, expectedVersion: 4),
                          Rules.changeKey(grants: b.grants, denies: b.denies, expectedVersion: 4))
    }

    func testTheBodyCarriesLimitsAndEffectOnlyForKeptGrants() throws {
        let loaded = Rules.load(try snapshot(grants: "[\(limited),\(blocked)]"))
        let sent = Rules.policy(choices: ["job.assign": .allow], scopes: ["job.assign": "team"], loaded: loaded)
        let encoded = try JSONEncoder().encode(sent.grants)
        let grants = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        XCTAssertEqual(grants.count, 3)
        guard grants.count == 3 else { return }
        XCTAssertEqual(grants[0]["capability"] as? String, "estimate.discount")
        XCTAssertEqual(grants[0]["effect"] as? String, "allow")
        XCTAssertEqual(grants[0]["conditions"] as? [String: Int], ["maxDiscountPercent": 10])
        XCTAssertEqual(grants[1]["capability"] as? String, "invoice.refund")
        XCTAssertEqual(grants[1]["effect"] as? String, "deny")
        XCTAssertNil(grants[1]["conditions"])
        XCTAssertEqual(Set(grants[2].keys), ["capability", "scope"])
        XCTAssertEqual(grants[2]["capability"] as? String, "job.assign")
        XCTAssertEqual(grants[2]["scope"] as? String, "team")
    }

    func testARefusalWhileAnExpiryIsBeingRecordedHasItsOwnWords() {
        let pending = Problem(title: "Conflict", status: 409,
                              detail: "permission override expiry is still being recorded; reload and try again",
                              code: "permission_override_expiry_pending", category: "conflict")
        XCTAssertEqual(MemberOverrideRules.refusal(pending), MemberOverrideRules.expiryPendingNote)
        let stale = Problem(title: "Conflict", status: 409, detail: "the override changed; reload", code: "stale_version", category: "conflict")
        XCTAssertNil(MemberOverrideRules.refusal(stale))
        XCTAssertNil(MemberOverrideRules.refusal(Problem(title: "Conflict", status: 409, detail: nil)))
        XCTAssertNil(MemberOverrideRules.refusal(URLError(.timedOut)))
    }
}
