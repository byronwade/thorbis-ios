import XCTest
@testable import Thorbis

@MainActor
private final class MemoryCustomerSelfEditRecoveryStore: CustomerSelfEditRecoveryStoring {
    var entries: [(CustomerSelfEditRecoveryScope, CustomerSelfEditRecovery)] = []
    var rejectWrites = false
    var rejectRemovals = false
    func load(scope: CustomerSelfEditRecoveryScope) throws -> CustomerSelfEditRecovery? { entries.first { $0.0 == scope }?.1 }
    func save(_ recovery: CustomerSelfEditRecovery, scope: CustomerSelfEditRecoveryScope) throws {
        if rejectWrites { throw NSError(domain: "test", code: 1) }
        entries.removeAll { $0.0 == scope }; entries.append((scope, recovery))
    }
    func remove(scope: CustomerSelfEditRecoveryScope) throws {
        if rejectRemovals { throw NSError(domain: "test", code: 2) }
        entries.removeAll { $0.0 == scope }
    }
}

final class CustomerSelfEditTests: XCTestCase {
    private var recoveryScope: CustomerSelfEditRecoveryScope {
        .init(actorID: "actor", organizationID: "org", customerID: "00000000-0000-4000-8000-000000000001", origin: "https://app.thorbis.com")
    }
    private func record(name: String = "Dana Customer", email: String? = "dana@example.com", phone: String? = "555-0100",
                        address: String? = "1 Main St", preferred: String? = nil) -> CustomerRecord {
        CustomerRecord(id: "00000000-0000-4000-8000-000000000001", organizationId: "org", name: name, locationId: nil,
                       email: email, phone: phone, address: address, accountType: "residential", industry: nil,
                       referralSource: nil, website: nil, preferredContact: preferred, billingTerms: "net_30",
                       creditLimit: 50000, taxExempt: false, taxExemptId: nil, archived: false,
                       archiveCycleAuditId: nil, createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
    }

    private func contact(_ id: String = "c1", name: String = "Sam", phone: String? = "555-0101") -> CustomerContactRecord {
        CustomerContactRecord(id: id, organizationId: "org", customerId: "cust", name: name, role: nil, email: nil,
                              phone: phone, primary: false, createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
    }

    private func location(_ id: String = "l1", kind: String = "service", address: String = "1 Main St") -> ServiceLocationRecord {
        ServiceLocationRecord(id: id, organizationId: "org", customerId: "cust", label: "Home", kind: kind, address: address,
                              notes: "Side gate", coordinates: nil, gateCode: "1234", alarmCode: nil, dogOnSite: nil,
                              parking: nil, createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
    }

    private func json(_ value: some Encodable) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] ?? [:]
    }

    @MainActor
    func testRecoveryKeychainKeepsDraftScopedToActorAndOrigin() throws {
        let customerID = UUID().uuidString
        let scope = CustomerSelfEditRecoveryScope(actorID: UUID().uuidString, organizationID: "org", customerID: customerID, origin: "https://app.thorbis.com")
        let otherActor = CustomerSelfEditRecoveryScope(actorID: UUID().uuidString, organizationID: "org", customerID: customerID, origin: scope.origin)
        let otherOrigin = CustomerSelfEditRecoveryScope(actorID: scope.actorID, organizationID: "org", customerID: customerID, origin: "https://other.example")
        let store = KeychainCustomerSelfEditRecoveryStore.shared
        defer { try? store.remove(scope: scope) }
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: nil)
        draft.newContactName = "Sam"
        try store.save(.init(draft: draft, pending: .createContact, consentKey: "key"), scope: scope)
        XCTAssertEqual(try store.load(scope: scope)?.draft.newContactName, "Sam")
        XCTAssertNil(try store.load(scope: otherActor))
        XCTAssertNil(try store.load(scope: otherOrigin))
    }

    @MainActor
    func testConditionalWriteSupportComesOnlyFromFreshCustomerResponse() async throws {
        let json = String(decoding: try JSONEncoder().encode(record()), as: UTF8.self)
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, json, headers: ["X-Thorbis-Customer-Conditional-Writes": "1"]),
            .init(200, json),
            .init(200, json, headers: ["X-Thorbis-Customer-Conditional-Writes": "2"])
        ]), baseURL: "https://app.thorbis.com")
        let supported = try await api.customerConditionalRead(record().id)
        let missing = try await api.customerConditionalRead(record().id)
        let malformed = try await api.customerConditionalRead(record().id)
        XCTAssertTrue(supported.supportsConditionalWrites)
        XCTAssertFalse(missing.supportsConditionalWrites)
        XCTAssertFalse(malformed.supportsConditionalWrites)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 3, "Capability must not come from a cached earlier response")
    }

    @MainActor
    func testConditionalSupportReadIsCancelledWhenAPIAuthorityChanges() async throws {
        let gate = URLProtocolFixture.Gate()
        let json = String(decoding: try JSONEncoder().encode(record()), as: UTF8.self)
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, json, gate: gate, headers: ["X-Thorbis-Customer-Conditional-Writes": "1"])
        ]), baseURL: "https://app.thorbis.com")
        let task = Task { try await api.customerConditionalRead(record().id) }
        defer { gate.release(); task.cancel() }
        for _ in 0..<100 where URLProtocolFixture.recorded.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        api.invalidateRequests(); gate.release()
        do { _ = try await task.value; XCTFail("A retired response cannot advertise support") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testNoEditsMeansNothingToSave() {
        let draft = CustomerSelfEditDraft(record: record(), contacts: [contact()], locations: [location()], smsConsent: nil)
        XCTAssertFalse(draft.hasChanges)
        XCTAssertTrue(draft.customerUpdate.isEmpty)
        XCTAssertTrue(draft.contactUpdates.isEmpty)
        XCTAssertNil(draft.newContact)
        XCTAssertTrue(draft.locationChanges.isEmpty)
    }

    func testConditionalCustomerPatchIncludesExactNullBaseline() throws {
        var draft = CustomerSelfEditDraft(record: record(phone: nil), contacts: [], locations: [], smsConsent: nil)
        draft.phone = "555-0100"
        let body = try json(draft.conditionalCustomerUpdate())
        let expected = try XCTUnwrap(body["expected"] as? [String: Any])
        XCTAssertTrue(expected["phone"] is NSNull)
        XCTAssertNil(expected["email"], "Unchanged fields must not be included in the baseline")
        XCTAssertEqual(body["phone"] as? String, "555-0100")
    }

    func testConditionalContactPatchPreservesNullAndEmptyBaselines() throws {
        let nullable = ConditionalContactUpdate(update: .init(phone: .value("555")), original: contact(phone: nil))
        let empty = ConditionalContactUpdate(update: .init(phone: .value("555")), original: contact(phone: ""))
        XCTAssertTrue((try XCTUnwrap(json(nullable)["expected"] as? [String: Any]))["phone"] is NSNull)
        XCTAssertEqual((try XCTUnwrap(json(empty)["expected"] as? [String: Any]))["phone"] as? String, "")
    }

    func testConditionalLocationPatchGuardsAndClearsOriginalPin() throws {
        let original = ServiceLocationRecord(id: "l1", organizationId: "org", customerId: "cust", label: "Home", kind: "service", address: "1 Main St", notes: nil,
            coordinates: .init(latitude: 36.5, longitude: -121.9), gateCode: nil, alarmCode: nil, dogOnSite: nil, parking: nil,
            createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
        let body = try json(ConditionalLocationUpdate(address: "2 Main St", original: original))
        let expected = try XCTUnwrap(body["expected"] as? [String: Any])
        let coordinates = try XCTUnwrap(expected["coordinates"] as? [String: Double])
        XCTAssertEqual(coordinates["latitude"], 36.5)
        XCTAssertEqual(coordinates["longitude"], -121.9)
        XCTAssertTrue(body["coordinates"] is NSNull)
        XCTAssertNil(body["notes"])
        XCTAssertEqual(expected["address"] as? String, "1 Main St")
    }

    @MainActor
    func testMissingConditionalCapabilityKeepsDraftWithoutWriting() async throws {
        let body = String(decoding: try JSONEncoder().encode(record()), as: UTF8.self)
        let api = APIClient(session: URLProtocolFixture.session([.init(200, body)]), baseURL: "https://app.thorbis.com")
        let store = MemoryCustomerSelfEditRecoveryStore()
        let model = CustomerSelfEditModel(customerID: record().id, recoveryStore: store, recoveryScope: recoveryScope)
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: nil)
        draft.name = "Edited"
        model.draft = draft
        await model.save(api: api)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        XCTAssertEqual(URLProtocolFixture.recorded.first?.method, "GET")
        XCTAssertEqual(try store.load(scope: recoveryScope)?.draft.name, "Edited")
        XCTAssertFalse(model.savedAll)
        XCTAssertNotNil(model.saveError)
    }

    @MainActor
    func testSupportedCustomerSaveSendsGuardedPatch() async throws {
        let before = record(phone: nil), after = record(phone: "555-0100")
        let beforeJSON = String(decoding: try JSONEncoder().encode(before), as: UTF8.self)
        let afterJSON = String(decoding: try JSONEncoder().encode(after), as: UTF8.self)
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, beforeJSON, headers: ["X-Thorbis-Customer-Conditional-Writes": "1"]), .init(200, afterJSON)
        ]), baseURL: "https://app.thorbis.com")
        let model = CustomerSelfEditModel(customerID: before.id, recoveryStore: MemoryCustomerSelfEditRecoveryStore(), recoveryScope: recoveryScope)
        var draft = CustomerSelfEditDraft(record: before, contacts: [], locations: [], smsConsent: nil)
        draft.phone = "555-0100"
        model.draft = draft
        await model.save(api: api)
        XCTAssertTrue(model.savedAll, model.saveError ?? "")
        XCTAssertEqual(URLProtocolFixture.recorded.map(\.method), ["GET", "POST"])
        let data = try XCTUnwrap(URLProtocolFixture.recorded.last?.body)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue((try XCTUnwrap(body["expected"] as? [String: Any]))["phone"] is NSNull)
    }

    @MainActor
    func testOldDraftWithoutLosslessBaselinesIsHeldForReview() async throws {
        let oldContact = CustomerContactRecord(id: "c1", organizationId: "org", customerId: record().id, name: "Sam", role: nil,
            email: nil, phone: nil, primary: false, createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
        var draft = CustomerSelfEditDraft(record: record(), contacts: [oldContact], locations: [], smsConsent: nil)
        draft.contacts[0].phone = "555-0199"
        var serialized = try json(draft)
        serialized.removeValue(forKey: "conditionalContactBaselines")
        serialized.removeValue(forKey: "conditionalLocationBaselines")
        let oldDraft = try JSONDecoder().decode(CustomerSelfEditDraft.self, from: JSONSerialization.data(withJSONObject: serialized))
        let body = String(decoding: try JSONEncoder().encode(record()), as: UTF8.self)
        let api = APIClient(session: URLProtocolFixture.session([.init(200, body, headers: ["X-Thorbis-Customer-Conditional-Writes": "1"])]), baseURL: "https://app.thorbis.com")
        let store = MemoryCustomerSelfEditRecoveryStore()
        let model = CustomerSelfEditModel(customerID: record().id, recoveryStore: store, recoveryScope: recoveryScope)
        model.draft = oldDraft
        await model.save(api: api)
        XCTAssertEqual(URLProtocolFixture.recorded.map(\.method), ["GET"])
        XCTAssertTrue(model.saveNeedsReconciliation)
        XCTAssertEqual(try store.load(scope: recoveryScope)?.draft.contacts[0].phone, "555-0199")
    }

    func testOnlyChangedCustomerFieldsAreSentAndClearedOnesAreNull() throws {
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: nil)
        draft.email = "  dana.new@example.com "
        draft.phone = ""
        draft.preferredContact = "sms"
        let body = try json(draft.customerUpdate)
        XCTAssertEqual(body["email"] as? String, "dana.new@example.com")
        XCTAssertTrue(body["phone"] is NSNull)
        XCTAssertEqual(body["preferredContact"] as? String, "sms")
        XCTAssertNil(body["name"])
        XCTAssertNil(body["address"])
        // Billing terms, credit limit and tax fields are never part of the customer's edit.
        XCTAssertEqual(Set(body.keys), ["email", "phone", "preferredContact"])
    }

    func testOnlyServiceAddressesAreOfferedAndChangesAreTrimmed() {
        var draft = CustomerSelfEditDraft(record: record(), contacts: [],
                                          locations: [location("l1"), location("b1", kind: "billing")], smsConsent: nil)
        XCTAssertEqual(draft.locations.map(\.id), ["l1"])
        draft.locations[0].address = " 2 Oak Ave "
        XCTAssertEqual(draft.locationChanges.first?.address, "2 Oak Ave")
        XCTAssertTrue(draft.changeSummary.contains("Home: 2 Oak Ave"))
    }

    func testContactEditsAndNewContact() throws {
        var draft = CustomerSelfEditDraft(record: record(), contacts: [contact()], locations: [], smsConsent: nil)
        draft.contacts[0].phone = "555-0199"
        draft.newContactName = "Alex"
        draft.newContactEmail = "alex@example.com"
        let update = try XCTUnwrap(draft.contactUpdates.first)
        let body = try json(update.request)
        XCTAssertEqual(body["phone"] as? String, "555-0199")
        XCTAssertNil(body["name"])
        XCTAssertEqual(draft.newContact?.name, "Alex")
        XCTAssertEqual(draft.newContact?.email, "alex@example.com")
    }

    func testValidationBlocksEmptyNameAndBadEmail() {
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: nil)
        draft.name = "  "
        draft.email = "not-an-email"
        XCTAssertNotNil(draft.nameError)
        XCTAssertNotNil(draft.emailError)
        XCTAssertFalse(draft.isValid)
        draft.name = "Dana"
        draft.email = ""
        XCTAssertTrue(draft.isValid)
    }

    func testTextsChangeOnlyWhenTheAnswerMoves() {
        let consent = CustomerSmsConsent(decision: "grant", version: "v1", recordedAt: "2026-10-01T00:00:00Z")
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: consent)
        XCTAssertNil(draft.textsChange)
        draft.allowsTexts = false
        XCTAssertEqual(draft.textsChange, false)
        XCTAssertTrue(draft.changeSummary.contains("Asked to stop job texts"))
    }

    @MainActor
    func testConsentSaveUsesOriginalVersionAndPreservesConflict() async throws {
        let api = APIClient(session: URLProtocolFixture.session([
            .init(409, "{\"title\":\"sms_consent_conflict\",\"detail\":\"Stale consent\"}")
        ]), baseURL: "https://app.thorbis.com")
        let store = MemoryCustomerSelfEditRecoveryStore()
        let model = CustomerSelfEditModel(customerID: record().id, recoveryStore: store, recoveryScope: recoveryScope)
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [],
            smsConsent: .init(decision: "grant", version: "original-version", recordedAt: "2026-10-01T00:00:00Z"))
        draft.allowsTexts = false
        model.draft = draft
        await model.save(api: api)
        XCTAssertEqual(URLProtocolFixture.recorded.map(\.method), ["POST"])
        let data = try XCTUnwrap(URLProtocolFixture.recorded.first?.body)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(body["expectedVersion"] as? String, "original-version")
        XCTAssertTrue(model.saveNeedsReconciliation)
        XCTAssertEqual(try store.load(scope: recoveryScope)?.draft.allowsTexts, false)
    }

    @MainActor
    func testAuthorityChangeDuringCustomerSaveStopsFollowingContactWrite() async throws {
        let gate = URLProtocolFixture.Gate()
        let body = String(decoding: try JSONEncoder().encode(record(name: "Updated Customer")), as: UTF8.self)
        let api = APIClient(session: URLProtocolFixture.session([.init(200, body, headers: ["X-Thorbis-Customer-Conditional-Writes": "1"]), .init(200, body, gate: gate), .init(200, "{}")]), baseURL: "https://app.thorbis.com")
        let model = CustomerSelfEditModel(customerID: record().id, recoveryStore: MemoryCustomerSelfEditRecoveryStore(), recoveryScope: recoveryScope)
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: nil)
        draft.name = "Updated Customer"
        draft.newContactName = "New contact"
        draft.newContactPhone = "555-0102"
        model.draft = draft
        var permitted = true
        let task = Task { await model.save(api: api, currentAuthority: { permitted }) }
        defer { gate.release(); task.cancel() }
        for _ in 0..<100 where URLProtocolFixture.recorded.count < 2 { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2)
        permitted = false
        gate.release()
        await task.value
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2, "No contact write should follow a retired customer save")
        XCTAssertFalse(model.savedAll)
        XCTAssertTrue(model.saveNeedsReconciliation)
        permitted = true
        await model.save(api: api, currentAuthority: { permitted })
        XCTAssertEqual(URLProtocolFixture.recorded.count, 2, "An uncertain write must not be retried without checking the customer record")
    }

    @MainActor
    func testUncertainContactCreationCannotBeRetriedAsADuplicate() async throws {
        let gate = URLProtocolFixture.Gate()
        let created = CustomerContactRecord(id: "new-contact", organizationId: "org", customerId: record().id,
            name: "Sam", role: nil, email: nil, phone: "555-0101", primary: false,
            createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
        let body = String(decoding: try JSONEncoder().encode(created), as: UTF8.self)
        let api = APIClient(session: URLProtocolFixture.session([.init(200, body, gate: gate), .init(200, body)]), baseURL: "https://app.thorbis.com")
        let store = MemoryCustomerSelfEditRecoveryStore()
        let model = CustomerSelfEditModel(customerID: record().id, recoveryStore: store, recoveryScope: recoveryScope)
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: nil)
        draft.newContactName = "Sam"; draft.newContactPhone = "555-0101"; draft.allowsTexts = true
        model.draft = draft
        var permitted = true
        let task = Task { await model.save(api: api, currentAuthority: { permitted }) }
        defer { gate.release(); task.cancel() }
        for _ in 0..<100 where URLProtocolFixture.recorded.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        permitted = false; gate.release(); await task.value
        XCTAssertTrue(model.saveNeedsReconciliation)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        permitted = true
        let reopened = CustomerSelfEditModel(customerID: record().id, recoveryStore: store, recoveryScope: recoveryScope)
        let recordJSON = String(decoding: try JSONEncoder().encode(record()), as: UTF8.self)
        let reopenAPI = APIClient(session: URLProtocolFixture.session([
            .init(200, recordJSON), .init(200, "{\"items\":[],\"nextCursor\":null}"),
            .init(200, "{\"items\":[],\"nextCursor\":null}"), .init(200, "null")
        ]), baseURL: "https://app.thorbis.com")
        await reopened.load(api: reopenAPI, currentAuthority: { permitted })
        XCTAssertTrue(reopened.saveNeedsReconciliation)
        XCTAssertEqual(reopened.draft?.newContactName, "Sam")
        await reopened.save(api: reopenAPI, currentAuthority: { permitted })
        XCTAssertEqual(URLProtocolFixture.recorded.count, 4)
        let found = created
        let contactJSON = String(decoding: try JSONEncoder().encode(found), as: UTF8.self)
        let fresh = APIClient(session: URLProtocolFixture.session([
            .init(200, recordJSON), .init(200, "{\"items\":[],\"nextCursor\":\"page-two\"}"),
            .init(200, "{\"items\":[\(contactJSON)],\"nextCursor\":null}"),
            .init(200, "{\"items\":[],\"nextCursor\":null}"), .init(200, "null")
        ]), baseURL: "https://app.thorbis.com")
        await reopened.inspectRecovery(api: fresh, currentAuthority: { permitted })
        XCTAssertEqual(reopened.matchingNewContacts.map(\.id), ["new-contact"])
        reopened.resolveRecovery(contactAlreadySaved: true, keepConflictingEdits: nil, currentAuthority: { permitted })
        XCTAssertFalse(reopened.saveNeedsReconciliation)
        XCTAssertEqual(reopened.draft?.newContactName, "")
        XCTAssertEqual(reopened.draft?.allowsTexts, true, "Other unsaved changes must remain")
        let recovered = try XCTUnwrap(store.load(scope: recoveryScope))
        XCTAssertNil(recovered.pending)
    }

    @MainActor
    func testRecoveryStorageFailurePreventsTheCustomerWrite() async throws {
        let store = MemoryCustomerSelfEditRecoveryStore(); store.rejectWrites = true
        let model = CustomerSelfEditModel(customerID: record().id, recoveryStore: store, recoveryScope: recoveryScope)
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: nil)
        draft.name = "Updated Customer"; model.draft = draft
        let api = APIClient(session: URLProtocolFixture.session([.init(200, "{}")]), baseURL: "https://app.thorbis.com")
        await model.save(api: api)
        XCTAssertTrue(URLProtocolFixture.recorded.isEmpty)
        XCTAssertNotNil(model.saveError)
        XCTAssertFalse(model.savedAll)
    }

    @MainActor
    func testCompletedRecoveryIsNotRestoredWhenKeychainRemovalFails() async throws {
        let store = MemoryCustomerSelfEditRecoveryStore(); store.rejectRemovals = true
        let model = CustomerSelfEditModel(customerID: record().id, recoveryStore: store, recoveryScope: recoveryScope)
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: nil)
        draft.name = "Updated Customer"; model.draft = draft
        let updated = String(decoding: try JSONEncoder().encode(record(name: "Updated Customer")), as: UTF8.self)
        let api = APIClient(session: URLProtocolFixture.session([.init(200, updated)]), baseURL: "https://app.thorbis.com")
        await model.save(api: api)
        XCTAssertTrue(model.savedAll)
        XCTAssertEqual(try store.load(scope: recoveryScope)?.completed, true)
        let fresh = APIClient(session: URLProtocolFixture.session([
            .init(200, updated), .init(200, "{\"items\":[],\"nextCursor\":null}"),
            .init(200, "{\"items\":[],\"nextCursor\":null}"), .init(200, "null")
        ]), baseURL: "https://app.thorbis.com")
        let reopened = CustomerSelfEditModel(customerID: record().id, recoveryStore: store, recoveryScope: recoveryScope)
        await reopened.load(api: fresh)
        XCTAssertFalse(reopened.saveNeedsReconciliation)
        XCTAssertEqual(reopened.draft?.name, "Updated Customer")
        XCTAssertFalse(reopened.hasChanges)
    }

    @MainActor
    func testRecoveryDoesNotRevealDraftWhenSavedContactCannotBeVerified() async throws {
        let store = MemoryCustomerSelfEditRecoveryStore()
        let draft = CustomerSelfEditDraft(record: record(), contacts: [contact()], locations: [], smsConsent: nil)
        try store.save(.init(draft: draft, pending: .contact("c1"), consentKey: "key"), scope: recoveryScope)
        let customerJSON = String(decoding: try JSONEncoder().encode(record()), as: UTF8.self)
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, customerJSON), .init(200, "{\"items\":[],\"nextCursor\":null}"),
            .init(200, "{\"items\":[],\"nextCursor\":null}")
        ]), baseURL: "https://app.thorbis.com")
        let model = CustomerSelfEditModel(customerID: record().id, recoveryStore: store, recoveryScope: recoveryScope)
        await model.load(api: api)
        XCTAssertNil(model.draft)
        XCTAssertNotNil(model.loadError)
        XCTAssertNotNil(try store.load(scope: recoveryScope), "Unverified edits remain protected on device")
    }

    @MainActor
    func testRestoredDraftWithoutPendingWriteStillRequiresFreshReview() async throws {
        let store = MemoryCustomerSelfEditRecoveryStore()
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: nil)
        draft.name = "Customer edit"
        try store.save(.init(draft: draft, pending: nil, consentKey: "key"), scope: recoveryScope)
        let latest = String(decoding: try JSONEncoder().encode(record(name: "Office edit")), as: UTF8.self)
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, latest), .init(200, "{\"items\":[],\"nextCursor\":null}"),
            .init(200, "{\"items\":[],\"nextCursor\":null}")
        ]), baseURL: "https://app.thorbis.com")
        let model = CustomerSelfEditModel(customerID: record().id, recoveryStore: store, recoveryScope: recoveryScope)
        await model.load(api: api)
        XCTAssertTrue(model.saveNeedsReconciliation)
        XCTAssertEqual(model.draft?.name, "Customer edit")
        await model.save(api: api)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 3, "A restored draft must not write before review")
    }

    @MainActor
    func testMissingLocationDoesNotDiscardUnsavedAddress() async throws {
        let store = MemoryCustomerSelfEditRecoveryStore()
        let location = ServiceLocationRecord(id: UUID().uuidString, organizationId: "org", customerId: record().id,
            label: "Home", kind: "service", address: "1 Main St", notes: nil, coordinates: nil,
            gateCode: nil, alarmCode: nil, dogOnSite: nil, parking: nil,
            createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [location], smsConsent: nil)
        draft.locations[0].address = "2 Main St"
        let model = CustomerSelfEditModel(customerID: record().id, recoveryStore: store, recoveryScope: recoveryScope)
        model.draft = draft
        let api = APIClient(session: URLProtocolFixture.session([.init(200, "{\"items\":[],\"nextCursor\":null}")]), baseURL: "https://app.thorbis.com")
        await model.save(api: api)
        XCTAssertFalse(model.savedAll)
        XCTAssertNotNil(model.saveError)
        XCTAssertEqual(try store.load(scope: recoveryScope)?.draft.locations.first?.address, "2 Main St")
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
    }

    @MainActor
    func testChangedLocationOnSecondPageIsSaved() async throws {
        let store = MemoryCustomerSelfEditRecoveryStore()
        let location = ServiceLocationRecord(id: UUID().uuidString, organizationId: "org", customerId: record().id,
            label: "Home", kind: "service", address: "1 Main St", notes: nil, coordinates: nil,
            gateCode: nil, alarmCode: nil, dogOnSite: nil, parking: nil,
            createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [location], smsConsent: nil)
        draft.locations[0].address = "2 Main St"
        let locationJSON = String(decoding: try JSONEncoder().encode(location), as: UTF8.self)
        let updatedJSON = locationJSON.replacingOccurrences(of: "1 Main St", with: "2 Main St")
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, "{\"items\":[],\"nextCursor\":\"page-two\"}"),
            .init(200, "{\"items\":[\(locationJSON)],\"nextCursor\":null}"), .init(200, updatedJSON)
        ]), baseURL: "https://app.thorbis.com")
        let model = CustomerSelfEditModel(customerID: record().id, recoveryStore: store, recoveryScope: recoveryScope)
        model.draft = draft
        await model.save(api: api)
        XCTAssertTrue(model.savedAll)
        XCTAssertEqual(URLProtocolFixture.recorded.count, 3)
    }

    func testRecoveryKeepsEditedFieldsAndAdoptsConcurrentUneditedValues() {
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: nil)
        draft.name = "Dana Q. Customer"
        let latest = record(email: "office-updated@example.com")
        let merged = draft.mergingRecovery(record: latest, contacts: [], locations: [])
        XCTAssertEqual(merged.name, "Dana Q. Customer")
        XCTAssertEqual(merged.email, "office-updated@example.com")
        XCTAssertEqual(merged.customerUpdate.name, "Dana Q. Customer")
        if case .unchanged = merged.customerUpdate.email {} else { XCTFail("Unedited email must not overwrite the newer server value") }
    }

    func testRecoveryRequiresChoiceForConcurrentEditToSameField() {
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: nil)
        draft.name = "Customer edit"
        let latest = record(name: "Office edit")
        XCTAssertEqual(draft.recoveryConflicts(record: latest, contacts: [], locations: []).map(\.label), ["Customer name"])
        XCTAssertEqual(draft.mergingRecovery(record: latest, contacts: [], locations: [], preferServerForConflicts: false).name, "Customer edit")
        let useRecord = draft.mergingRecovery(record: latest, contacts: [], locations: [], preferServerForConflicts: true)
        XCTAssertEqual(useRecord.name, "Office edit")
        XCTAssertNil(useRecord.customerUpdate.name)
    }

    @MainActor
    func testRecoveryRequiresChoiceWhenTextConsentChangedDifferently() async throws {
        let store = MemoryCustomerSelfEditRecoveryStore()
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: nil)
        draft.allowsTexts = true
        try store.save(.init(draft: draft, pending: .consent, consentKey: "same-key"), scope: recoveryScope)
        let customerJSON = String(decoding: try JSONEncoder().encode(record()), as: UTF8.self)
        let consent = CustomerSmsConsent(decision: "revoke", version: "v2", recordedAt: "2026-10-01T00:00:00Z")
        let consentJSON = String(decoding: try JSONEncoder().encode(consent), as: UTF8.self)
        let api = APIClient(session: URLProtocolFixture.session([
            .init(200, customerJSON), .init(200, "{\"items\":[],\"nextCursor\":null}"), .init(200, "{\"items\":[],\"nextCursor\":null}"),
            .init(200, "null"),
            .init(200, customerJSON), .init(200, "{\"items\":[],\"nextCursor\":null}"),
            .init(200, "{\"items\":[],\"nextCursor\":null}"), .init(200, consentJSON)
        ]), baseURL: "https://app.thorbis.com")
        let model = CustomerSelfEditModel(customerID: record().id, recoveryStore: store, recoveryScope: recoveryScope)
        await model.load(api: api)
        await model.inspectRecovery(api: api, currentAuthority: { true })
        XCTAssertEqual(model.recoveryConflicts.map(\.label), ["Job texts"])
        model.resolveRecovery(contactAlreadySaved: false, keepConflictingEdits: nil, currentAuthority: { true })
        XCTAssertTrue(model.saveNeedsReconciliation)
        model.resolveRecovery(contactAlreadySaved: false, keepConflictingEdits: false, currentAuthority: { true })
        XCTAssertEqual(model.draft?.allowsTexts, false)
        XCTAssertNil(model.draft?.textsChange)
    }

    func testRebasingAfterTheCustomerSaveLeavesNothingToRepeat() {
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: nil)
        draft.name = "Dana Q. Customer"
        let rebased = draft.rebased(record: record(name: "Dana Q. Customer"))
        XCTAssertTrue(rebased.customerUpdate.isEmpty)
    }
}
