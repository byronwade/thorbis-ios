import XCTest
@testable import Thorbis

/// Customer mode keeps a recovery copy; these tests never save, so the store stays empty.
@MainActor
private final class EmptySelfEditRecoveryStore: CustomerSelfEditRecoveryStoring {
    func load(scope: CustomerSelfEditRecoveryScope) throws -> CustomerSelfEditRecovery? { nil }
    func save(_ recovery: CustomerSelfEditRecovery, scope: CustomerSelfEditRecoveryScope) throws {}
    func remove(scope: CustomerSelfEditRecoveryScope) throws {}
}

/// Plans the company sells (add, edit, stop selling), a customer's membership (edit, remove),
/// who may do it, and the server features that hide a control or skip a call.
@MainActor
final class MembershipEditingTests: XCTestCase {
    private let customerID = "00000000-0000-4000-8000-000000000412"
    private let planID = "00000000-0000-4000-8000-000000006301"
    private let membershipID = "00000000-0000-4000-8000-000000006201"
    private let locationID = "00000000-0000-4000-8000-000000007001"

    private var planReply: String {
        #"{"id":"\#(planID)","organizationId":"o","name":"Comfort Club","kind":"maintenance","visitsPerYear":2,"price":2900,"billingFrequency":"monthly","discountPercent":15,"archived":false,"createdAt":"2026-11-20T12:00:00Z","updatedAt":"2026-11-20T12:00:00Z"}"#
    }

    private var membershipReply: String {
        #"{"id":"\#(membershipID)","organizationId":"o","customerId":"\#(customerID)","locationId":"\#(locationID)","planId":"\#(planID)","name":"Comfort Club","kind":"membership","cadence":"Twice a year","startsOn":"2026-01-15","renewsOn":"2027-01-15","status":"active","discountPercent":15,"notes":"Gate code 4411","createdAt":"2026-11-20T12:00:00Z","updatedAt":"2026-11-20T12:00:00Z"}"#
    }

    private func client(_ replies: [URLProtocolFixture.Reply]) -> APIClient {
        APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")
    }

    private func sentBody() throws -> [String: Any] {
        let request = try XCTUnwrap(URLProtocolFixture.recorded.last)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
    }

    private func record() throws -> MembershipRecord {
        try JSONDecoder().decode(MembershipRecord.self, from: Data(membershipReply.utf8))
    }

    // MARK: Plan requests

    func testANewPlanLeavesEmptyFieldsOutBecauseTheServerRefusesNullThere() async throws {
        let api = client([.init(201, planReply)])
        let plan = try await api.createMembershipPlan(MembershipPlanInput(name: "  Comfort Club ", kind: "maintenance", cadence: " ",
                                                                         visitsPerYear: 2, price: 2900, billingFrequency: "monthly",
                                                                         discountPercent: 15, description: nil))
        XCTAssertEqual(plan.price, 2900)
        let request = try XCTUnwrap(URLProtocolFixture.recorded.last)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url?.path, "/v1/membership-plans")
        let body = try sentBody()
        XCTAssertEqual(body["name"] as? String, "Comfort Club")
        XCTAssertEqual(body["kind"] as? String, "maintenance")
        XCTAssertEqual(body["visitsPerYear"] as? Int, 2)
        XCTAssertEqual(body["price"] as? Int, 2900, "The price is cents")
        XCTAssertEqual(body["billingFrequency"] as? String, "monthly")
        XCTAssertEqual(body["discountPercent"] as? Int, 15)
        XCTAssertNil(body["cadence"])
        XCTAssertNil(body["description"])
        XCTAssertNil(body["archived"])
        XCTAssertEqual(body.count, 6)
    }

    func testAnEditedPlanSendsNullForEveryEmptiedField() async throws {
        let api = client([.init(200, planReply)])
        _ = try await api.updateMembershipPlan(planID.uppercased(), MembershipPlanInput(name: "Comfort Club", kind: "membership"))
        XCTAssertEqual(URLProtocolFixture.recorded.last?.url?.path, "/v1/membership-plans/\(planID)")
        let body = try sentBody()
        XCTAssertEqual(body["kind"] as? String, "membership")
        XCTAssertEqual(body["discountPercent"] as? Int, 0)
        for key in ["cadence", "visitsPerYear", "price", "billingFrequency", "description"] {
            XCTAssertTrue(body[key] is NSNull, "\(key) is cleared with null")
        }
        XCTAssertNil(body["archived"], "Saving a plan never archives it")
        XCTAssertEqual(body.count, 8)
    }

    func testStopSellingSendsOnlyArchived() async throws {
        let api = client([.init(200, planReply.replacingOccurrences(of: #""archived":false"#, with: #""archived":true"#))])
        let plan = try await api.archiveMembershipPlan(planID)
        XCTAssertTrue(plan.archived)
        XCTAssertEqual(URLProtocolFixture.recorded.last?.url?.path, "/v1/membership-plans/\(planID)")
        let body = try sentBody()
        XCTAssertEqual(body["archived"] as? Bool, true)
        XCTAssertEqual(body.count, 1)
    }

    func testAPlanIDThatIsNotAUUIDIsNeverSent() async {
        let api = client([])
        do { _ = try await api.archiveMembershipPlan("../customers"); XCTFail("Expected a refusal") } catch {}
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
    }

    // MARK: Plan form

    func testThePlanFormTurnsDollarsIntoCents() throws {
        var form = MembershipPlanForm()
        form.name = " Comfort Club "
        form.price = "$1,250.50"
        form.visits = "2"
        form.discount = "15%"
        form.billingFrequency = "annual"
        form.cadence = " Twice a year "
        let input = try form.input()
        XCTAssertEqual(input, MembershipPlanInput(name: "Comfort Club", kind: "maintenance", cadence: "Twice a year", visitsPerYear: 2,
                                                  price: 125_050, billingFrequency: "annual", discountPercent: 15, description: nil))
        XCTAssertEqual(MembershipPlanForm.cents("29"), 2900)
        XCTAssertEqual(MembershipPlanForm.cents("29.5"), 2950)
        XCTAssertNil(MembershipPlanForm.cents("29.555"))
        XCTAssertNil(MembershipPlanForm.cents("-1"))
        XCTAssertNil(MembershipPlanForm.cents("21474836.48"), "Past what the server keeps")
        XCTAssertEqual(MembershipPlanForm.cents("21474836.47"), 2_147_483_647)
    }

    func testAnEmptyPlanFormOnlyNeedsAName() throws {
        var form = MembershipPlanForm()
        XCTAssertThrowsError(try form.input()) { XCTAssertEqual(($0 as? MembershipPlanForm.Problem)?.field, .name) }
        form.name = "Gold"
        XCTAssertEqual(try form.input(), MembershipPlanInput(name: "Gold"))
    }

    func testThePlanFormSaysWhichFieldIsWrong() {
        func field(_ change: (inout MembershipPlanForm) -> Void) -> MembershipPlanForm.Field? {
            var form = MembershipPlanForm()
            form.name = "Gold"
            change(&form)
            do { _ = try form.input(); return nil } catch { return (error as? MembershipPlanForm.Problem)?.field }
        }
        XCTAssertEqual(field { $0.name = String(repeating: "a", count: 121) }, .name)
        XCTAssertNil(field { $0.name = String(repeating: "a", count: 120) })
        XCTAssertEqual(field { $0.price = "about 30" }, .price)
        XCTAssertEqual(field { $0.visits = "53" }, .visits)
        XCTAssertEqual(field { $0.visits = "2.5" }, .visits)
        XCTAssertNil(field { $0.visits = "52" })
        XCTAssertEqual(field { $0.discount = "101" }, .discount)
        XCTAssertEqual(field { $0.discount = "-5" }, .discount)
        XCTAssertNil(field { $0.discount = "100" })
        XCTAssertEqual(field { $0.cadence = String(repeating: "a", count: 121) }, .cadence)
        XCTAssertEqual(field { $0.description = String(repeating: "a", count: 2001) }, .description)
    }

    func testAPlanFillsTheFormTheWayItWasSaved() throws {
        let plan = try JSONDecoder().decode(MembershipPlan.self, from: Data(planReply.utf8))
        let form = MembershipPlanForm(plan)
        XCTAssertEqual(form.price, "29")
        XCTAssertEqual(form.visits, "2")
        XCTAssertEqual(form.discount, "15")
        XCTAssertEqual(form.billingFrequency, "monthly")
        XCTAssertEqual(MembershipPlanForm.dollars(2950), "29.50")
        XCTAssertEqual(MembershipPlanForm.dollars(5), "0.05")
        XCTAssertEqual(try form.input().price, 2900, "Opening and saving changes nothing")
        XCTAssertTrue(MembershipPlanForm.frequencies.compactMap(\.value).allSatisfy { ["monthly", "quarterly", "annual", "one_time"].contains($0) })
        XCTAssertEqual(MembershipPlanForm.kinds.map(\.value), ["maintenance", "membership"])
    }

    // MARK: Membership requests

    /// An owner or admin types a new percent off: every field goes, the percent included.
    func testAnEditedMembershipWithANewPercentSendsEveryFieldAndNullForEmptiedOnes() async throws {
        let api = client([.init(200, membershipReply)])
        var form = MembershipForm(try record())
        XCTAssertEqual(form.locationId, locationID)
        form.name = " Comfort Club Gold "
        form.cadence = ""
        form.discount = "20"
        form.renews = nil
        form.locationId = nil
        form.notes = "  "
        let input = try form.input()
        XCTAssertTrue(input.discountChanged)
        let saved = try await api.updateMembership(customerID, membershipID: membershipID, input)
        XCTAssertEqual(saved.id, membershipID)
        let request = try XCTUnwrap(URLProtocolFixture.recorded.last)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url?.path, "/v1/customers/\(customerID)/memberships/\(membershipID)")
        let body = try sentBody()
        XCTAssertEqual(body["name"] as? String, "Comfort Club Gold")
        XCTAssertEqual(body["kind"] as? String, "membership")
        XCTAssertEqual(body["status"] as? String, "active", "Editing never cancels")
        XCTAssertEqual(body["discountPercent"] as? Int, 20)
        XCTAssertEqual(body["startsOn"] as? String, "2026-01-15")
        for key in ["locationId", "cadence", "renewsOn", "notes"] { XCTAssertTrue(body[key] is NSNull, "\(key) is cleared with null") }
        XCTAssertNil(body["customerId"], "The customer is in the route; the server refuses it in the body")
        XCTAssertNil(body["planId"])
        XCTAssertNil(body["originalDiscountPercent"], "The saved percent is the app's to compare, never sent")
        XCTAssertEqual(body.count, 9)
    }

    /// Office staff change everything but the percent off (they see it and can't type it): the
    /// percent is left out, so the server keeps the stored one and asks for no more permission.
    func testAnEditedMembershipWithTheSamePercentLeavesThePercentOut() async throws {
        let api = client([.init(200, membershipReply)])
        var form = MembershipForm(try record())
        form.name = " Comfort Club Gold "
        form.cadence = ""
        form.renews = nil
        form.locationId = nil
        form.notes = "  "
        let input = try form.input()
        XCTAssertFalse(input.discountChanged)
        _ = try await api.updateMembership(customerID, membershipID: membershipID, input)
        XCTAssertEqual(URLProtocolFixture.recorded.last?.url?.path, "/v1/customers/\(customerID)/memberships/\(membershipID)")
        let body = try sentBody()
        XCTAssertEqual(body["name"] as? String, "Comfort Club Gold")
        XCTAssertEqual(body["kind"] as? String, "membership")
        XCTAssertEqual(body["status"] as? String, "active")
        XCTAssertEqual(body["startsOn"] as? String, "2026-01-15")
        for key in ["locationId", "cadence", "renewsOn", "notes"] { XCTAssertTrue(body[key] is NSNull, "\(key) is cleared with null") }
        XCTAssertNil(body["discountPercent"], "An untouched percent is not sent")
        XCTAssertEqual(body.count, 8)
    }

    func testAnUntouchedMembershipIsSentBackAsItWas() throws {
        let input = try MembershipForm(try record()).input()
        XCTAssertEqual(input.discountPercent, 15)
        XCTAssertEqual(input.originalDiscountPercent, 15)
        XCTAssertFalse(input.discountChanged)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
        XCTAssertEqual(body["locationId"] as? String, locationID)
        XCTAssertEqual(body["cadence"] as? String, "Twice a year")
        XCTAssertEqual(body["startsOn"] as? String, "2026-01-15")
        XCTAssertEqual(body["renewsOn"] as? String, "2027-01-15")
        XCTAssertEqual(body["notes"] as? String, "Gate code 4411")
        XCTAssertNil(body["discountPercent"], "The server keeps the stored percent when it is left out")
        XCTAssertEqual(body.count, 8)
    }

    func testOnlyANewPercentIsSent() throws {
        func sent(_ typed: String) throws -> Any? {
            var form = MembershipForm(try record())
            form.discount = typed
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(try form.input())) as? [String: Any])
            return body["discountPercent"]
        }
        XCTAssertNil(try sent("15%"), "The same percent typed another way is not a change")
        XCTAssertNil(try sent(" 15 "))
        XCTAssertEqual(try sent("") as? Int, 0, "Emptying the field takes the percent off")
        XCTAssertEqual(try sent("16") as? Int, 16)

        let free = try JSONDecoder().decode(MembershipRecord.self,
                                            from: Data(membershipReply.replacingOccurrences(of: #""discountPercent":15"#, with: #""discountPercent":0"#).utf8))
        let untouched = try MembershipForm(free).input()
        XCTAssertEqual(untouched.discountPercent, 0)
        XCTAssertFalse(untouched.discountChanged, "No percent off, left empty, is no change")
    }

    func testTheMembershipFormChecksNamePercentAndDates() throws {
        func field(_ change: (inout MembershipForm) -> Void) throws -> MembershipForm.Field? {
            var form = MembershipForm(try record())
            change(&form)
            do { _ = try form.input(); return nil } catch { return (error as? MembershipForm.Problem)?.field }
        }
        XCTAssertEqual(try field { $0.name = "  " }, .name)
        XCTAssertEqual(try field { $0.discount = "150" }, .discount)
        XCTAssertEqual(try field { $0.discount = "ten" }, .discount)
        XCTAssertEqual(try field { $0.renews = EquipmentRecord.day("2025-12-31") }, .dates)
        XCTAssertEqual(try field { $0.notes = String(repeating: "n", count: 2001) }, .notes)
        XCTAssertNil(try field { $0.renews = $0.starts })
        XCTAssertNil(try field { $0.discount = "" })
    }

    func testRemoveGoesToTheRemoveRouteWithNoBody() async throws {
        let api = client([.init(204, "")])
        try await api.removeMembership(customerID, membershipID: membershipID)
        let request = try XCTUnwrap(URLProtocolFixture.recorded.last)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url?.path, "/v1/customers/\(customerID)/memberships/\(membershipID)/remove")
        XCTAssertTrue(request.body?.isEmpty ?? true)
    }

    func testCancelStillSendsOnlyTheStatus() async throws {
        let api = client([.init(200, membershipReply)])
        _ = try await api.cancelMembership(customerID, membershipID: membershipID)
        let body = try sentBody()
        XCTAssertEqual(body["status"] as? String, "cancelled")
        XCTAssertEqual(body.count, 1)
    }

    // MARK: A refused save

    func testARefusedSaveSaysSoInPlainWords() async {
        let api = client([.init(403, #"{"title":"Forbidden","status":403,"detail":"organization.settings.edit required"}"#, contentType: "application/problem+json")])
        do {
            _ = try await api.createMembershipPlan(MembershipPlanInput(name: "Gold"))
            XCTFail("Expected a refusal")
        } catch {
            XCTAssertEqual(MembershipAccess.saveError(error, plan: true), "You can\u{2019}t change plans. Ask an owner or admin to do it.")
            XCTAssertEqual(MembershipAccess.saveError(error, plan: false),
                           "You can\u{2019}t change this membership. Ask an owner or admin to do it.",
                           "The same words are not about the percent unless the request carried one")
            XCTAssertEqual(MembershipAccess.saveError(error, plan: true, discountChanged: true),
                           "You can\u{2019}t change plans. Ask an owner or admin to do it.")
        }
        XCTAssertEqual(MembershipAccess.saveError(URLError(.notConnectedToInternet), plan: true), "Saving needs a connection.")
        XCTAssertEqual(MembershipAccess.saveError(Problem(title: "Conflict", status: 409, detail: "A plan has that name."), plan: true),
                       "A plan has that name.")
    }

    // MARK: Remove, and putting a membership back

    func testRemoveIsOfferedOnlyWhenTheMembershipCouldBePutBack() throws {
        func membership(planned: Bool = true, percent: Int = 15) throws -> MembershipRecord {
            var json = membershipReply.replacingOccurrences(of: #""discountPercent":15"#, with: #""discountPercent":\#(percent)"#)
            if !planned { json = json.replacingOccurrences(of: #""planId":"\#(planID)","#, with: "") }
            let decoded = try JSONDecoder().decode(MembershipRecord.self, from: Data(json.utf8))
            XCTAssertEqual(decoded.planId, planned ? planID : nil)
            XCTAssertEqual(decoded.discountPercent, percent)
            return decoded
        }
        func plan(percent: Int = 15, archived: Bool = false) throws -> MembershipPlan {
            let json = planReply.replacingOccurrences(of: #""discountPercent":15"#, with: #""discountPercent":\#(percent)"#)
                .replacingOccurrences(of: #""archived":false"#, with: #""archived":\#(archived)"#)
            let decoded = try JSONDecoder().decode(MembershipPlan.self, from: Data(json.utf8))
            XCTAssertEqual(decoded.discountPercent, percent)
            XCTAssertEqual(decoded.archived, archived)
            return decoded
        }
        let needs = MembershipAccess.restoreNeedsDiscountAuthority

        XCTAssertFalse(needs(try membership(), [try plan()]), "15% on a plan still sold at 15% is put back as it was")
        XCTAssertTrue(needs(try membership(), [try plan(percent: 10)]), "Put back, 15% would differ from the plan's 10%")
        XCTAssertTrue(needs(try membership(), [try plan(archived: true)]), "An archived plan is not used: 15% differs from 0")
        XCTAssertFalse(needs(try membership(percent: 0), [try plan(archived: true)]), "An archived plan at 0% is put back at 0%")
        XCTAssertFalse(needs(try membership(planned: false, percent: 0), [try plan()]), "No plan and no percent off")
        XCTAssertTrue(needs(try membership(planned: false), [try plan()]), "No plan: 15% differs from 0, whatever the plans are")
        XCTAssertTrue(needs(try membership(), nil), "Plans not loaded: a membership with a plan is not offered on a guess")
        XCTAssertTrue(needs(try membership(planned: false), nil), "Without a plan the plans don't matter: 15% differs from 0")
        XCTAssertFalse(needs(try membership(planned: false, percent: 0), nil))
        XCTAssertFalse(MembershipAccess.removeLocked.contains("office"))
    }

    func testARefusedNewPercentSaysWhoCanChangeIt() {
        let discount = Problem(title: "Forbidden", status: 403, detail: "not permitted: organization.settings.edit (no_grant)")
        XCTAssertEqual(MembershipAccess.saveError(discount, plan: false, discountChanged: true),
                       "You can\u{2019}t change the percent off. Ask an owner or admin to do it.")
        XCTAssertEqual(MembershipAccess.saveError(discount, plan: false, discountChanged: false),
                       "You can\u{2019}t change this membership. Ask an owner or admin to do it.")
        let scope = Problem(title: "Forbidden", status: 403, detail: "not permitted: customer.edit (out_of_scope)")
        XCTAssertEqual(MembershipAccess.saveError(scope, plan: false, discountChanged: true),
                       "You can\u{2019}t change this membership. Ask an owner or admin to do it.",
                       "Refused for the membership itself, not the percent")
        XCTAssertEqual(MembershipAccess.saveError(Problem(title: "Forbidden", status: 403, detail: nil), plan: false, discountChanged: true),
                       "You can\u{2019}t change this membership. Ask an owner or admin to do it.")
        XCTAssertFalse(MembershipAccess.discountRefused.contains("office"))
        XCTAssertFalse(MembershipAccess.membershipRefused.contains("office"))
        XCTAssertFalse(MembershipAccess.discountLocked.contains("office"))
    }

    // MARK: Who may edit, and the server features

    private let actor = "019f0000-0000-7000-8000-000000000011"
    private let organization = "019f0000-0000-7000-8000-000000000001"

    private func session(capabilities: [String], on features: [String] = ["core_crm"], off: [String] = []) async -> SessionController {
        let session = #"{"user":{"id":"\#(actor)","name":"Fixture","email":"fixture@example.invalid","emailVerified":true},"session":{"id":"fixture-session","userId":"\#(actor)","activeOrganizationId":"\#(organization)","expiresAt":"2099-10-27T12:00:00.000Z"}}"#
        let organizations = #"[{"id":"\#(organization)","name":"Fixture workspace"}]"#
        let list = capabilities.map { "\"\($0)\"" }.joined(separator: ",")
        let catalog = #"{"authority":{"actorId":"\#(actor)","organizationId":"\#(organization)","policyVersion":1,"generation":"fixture-generation"},"capabilities":[\#(list)],"resources":[],"views":[]}"#
        let decisions = (features.map { #""\#($0)":{"enabled":true,"released":true,"entitled":true,"stage":"general"}"# }
            + off.map { #""\#($0)":{"enabled":false,"released":true,"entitled":true,"stage":"general","reason":"disabled"}"# }).joined(separator: ",")
        let exposure = #"{"organizationId":"\#(organization)","evaluatedAt":"2026-11-20T12:00:00.000Z","features":{\#(decisions)}}"#
        let api = client([.init(200, session), .init(200, organizations), .init(200, catalog), .init(200, exposure)])
        let controller = SessionController(api: api, defaults: UserDefaults(suiteName: "thorbis.membership.tests.\(UUID().uuidString)")!)
        await controller.restore()
        XCTAssertEqual(controller.phase, .ready)
        return controller
    }

    func testTheMorningDigestSwitchFollowsTheGrantTheServerChecks() async {
        let manager = await session(capabilities: ["job.view", "organization.performance.view"])
        XCTAssertTrue(PushNotifications.receivesMorningDigest(manager))
        let dispatcher = await session(capabilities: ["invoice.create", "job.assign"], on: ["invoicing", "jobs"])
        XCTAssertFalse(PushNotifications.receivesMorningDigest(dispatcher),
                       "The server sends no digest without organization.performance.view")
    }

    func testOnlyPeopleWhoEditCompanySettingsChangePlans() async {
        let owner = await session(capabilities: ["customer.view", "customer.edit", "organization.settings.edit"])
        XCTAssertTrue(MembershipAccess.canEditPlans(owner))
        XCTAssertTrue(MembershipAccess.canEditMemberships(owner))
        XCTAssertTrue(MembershipAccess.canOverrideMembershipDiscount(owner))

        let office = await session(capabilities: ["customer.view", "customer.edit", "pricebook.view"])
        XCTAssertFalse(MembershipAccess.canEditPlans(office), "Office staff see plans and cannot change them")
        XCTAssertTrue(MembershipAccess.canEditMemberships(office))
        XCTAssertFalse(MembershipAccess.canOverrideMembershipDiscount(office),
                       "Office staff see a membership's percent off and cannot change it")

        let tech = await session(capabilities: ["customer.view", "job.view"])
        XCTAssertFalse(MembershipAccess.canEditPlans(tech))
        XCTAssertFalse(MembershipAccess.canEditMemberships(tech))
        XCTAssertFalse(MembershipAccess.canOverrideMembershipDiscount(tech))

        let noCRM = await session(capabilities: ["customer.edit", "organization.settings.edit"], on: [])
        XCTAssertFalse(MembershipAccess.canEditPlans(noCRM), "The routes sit behind core_crm")
        XCTAssertFalse(MembershipAccess.canEditMemberships(noCRM))
        XCTAssertFalse(MembershipAccess.canOverrideMembershipDiscount(noCRM))
    }

    func testServerFlagsMatchTheServerKeys() {
        XCTAssertEqual(ServerFlag.staffPush.rawValue, "staff_push_notifications")
        XCTAssertEqual(ServerFlag.jobTexts.rawValue, "job_sms_notices")
        XCTAssertEqual(ServerFlag.rescheduleUndo.rawValue, "job_schedule_cycle_undo")
    }

    func testAnUnknownOrOffFlagReadsAsOff() async {
        let none = await session(capabilities: ["customer.view"])
        for flag in ServerFlag.allCases { XCTAssertFalse(none.isOn(flag), "\(flag.rawValue) is unknown, so off") }

        let mixed = await session(capabilities: ["customer.view"], on: ["core_crm", "job_sms_notices"],
                                  off: ["staff_push_notifications"])
        XCTAssertTrue(mixed.isOn(.jobTexts))
        XCTAssertFalse(mixed.isOn(.staffPush), "Known and turned off")
        XCTAssertFalse(mixed.isOn(.rescheduleUndo))

        let all = await session(capabilities: [], on: ServerFlag.allCases.map(\.rawValue))
        for flag in ServerFlag.allCases { XCTAssertTrue(all.isOn(flag)) }
    }

    func testCustomerModeSkipsTheTextsReadWhileJobTextsAreOff() async {
        let off = await session(capabilities: ["customer.view", "customer.edit"])
        let customer = #"{"id":"\#(customerID)","organizationId":"\#(organization)","name":"Danielle Marlowe","archived":false,"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}"#
        let api = client([.init(200, customer), .init(200, #"{"items":[]}"#), .init(200, #"{"items":[]}"#)])
        let model = CustomerSelfEditModel(customerID: customerID, recoveryStore: EmptySelfEditRecoveryStore())
        XCTAssertTrue(model.textsOn, "On until the session says otherwise")
        guard model.bindRecovery(api: api, session: off) else { return XCTFail("Expected the session to bind") }
        XCTAssertFalse(model.textsOn)
        await model.load(api: api)
        XCTAssertFalse(URLProtocolFixture.recorded.contains { $0.url?.path.hasSuffix("/sms-consent") == true },
                       "The consent route is refused while the feature is off, so it is not called")
    }
}
