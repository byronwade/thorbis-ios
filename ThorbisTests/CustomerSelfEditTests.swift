import XCTest
@testable import Thorbis

@MainActor
private final class MemoryCustomerSelfEditRecoveryStore: CustomerSelfEditRecoveryStoring {
    var entries: [(CustomerSelfEditRecoveryScope, CustomerSelfEditRecovery)] = []
    var rejectWrites = false
    func load(scope: CustomerSelfEditRecoveryScope) throws -> CustomerSelfEditRecovery? { entries.first { $0.0 == scope }?.1 }
    func save(_ recovery: CustomerSelfEditRecovery, scope: CustomerSelfEditRecoveryScope) throws {
        if rejectWrites { throw NSError(domain: "test", code: 1) }
        entries.removeAll { $0.0 == scope }; entries.append((scope, recovery))
    }
    func remove(scope: CustomerSelfEditRecoveryScope) throws { entries.removeAll { $0.0 == scope } }
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

    func testNoEditsMeansNothingToSave() {
        let draft = CustomerSelfEditDraft(record: record(), contacts: [contact()], locations: [location()], smsConsent: nil)
        XCTAssertFalse(draft.hasChanges)
        XCTAssertTrue(draft.customerUpdate.isEmpty)
        XCTAssertTrue(draft.contactUpdates.isEmpty)
        XCTAssertNil(draft.newContact)
        XCTAssertTrue(draft.locationChanges.isEmpty)
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
    func testAuthorityChangeDuringCustomerSaveStopsFollowingContactWrite() async throws {
        let gate = URLProtocolFixture.Gate()
        let body = String(decoding: try JSONEncoder().encode(record(name: "Updated Customer")), as: UTF8.self)
        let api = APIClient(session: URLProtocolFixture.session([.init(200, body, gate: gate), .init(200, "{}")]), baseURL: "https://app.thorbis.com")
        let model = CustomerSelfEditModel(customerID: record().id, recoveryStore: MemoryCustomerSelfEditRecoveryStore(), recoveryScope: recoveryScope)
        var draft = CustomerSelfEditDraft(record: record(), contacts: [], locations: [], smsConsent: nil)
        draft.name = "Updated Customer"
        draft.newContactName = "New contact"
        draft.newContactPhone = "555-0102"
        model.draft = draft
        var permitted = true
        let task = Task { await model.save(api: api, currentAuthority: { permitted }) }
        defer { gate.release(); task.cancel() }
        for _ in 0..<100 where URLProtocolFixture.recorded.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        permitted = false
        gate.release()
        await task.value
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1, "No contact write should follow a retired customer save")
        XCTAssertFalse(model.savedAll)
        XCTAssertTrue(model.saveNeedsReconciliation)
        permitted = true
        await model.save(api: api, currentAuthority: { permitted })
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1, "An uncertain write must not be retried without checking the customer record")
    }

    @MainActor
    func testUncertainContactCreationCannotBeRetriedAsADuplicate() async throws {
        let gate = URLProtocolFixture.Gate()
        let body = String(decoding: try JSONEncoder().encode(contact()), as: UTF8.self)
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
        let reopenAPI = APIClient(session: URLProtocolFixture.session([.init(200, recordJSON)]), baseURL: "https://app.thorbis.com")
        await reopened.load(api: reopenAPI, currentAuthority: { permitted })
        XCTAssertTrue(reopened.saveNeedsReconciliation)
        XCTAssertEqual(reopened.draft?.newContactName, "Sam")
        await reopened.save(api: reopenAPI, currentAuthority: { permitted })
        XCTAssertEqual(URLProtocolFixture.recorded.count, 1)
        let found = CustomerContactRecord(id: "new-contact", organizationId: "org", customerId: record().id,
            name: "Sam", role: nil, email: nil, phone: "555-0101", primary: false,
            createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
        let contactJSON = String(decoding: try JSONEncoder().encode(found), as: UTF8.self)
        let fresh = APIClient(session: URLProtocolFixture.session([
            .init(200, recordJSON), .init(200, "{\"items\":[],\"nextCursor\":\"page-two\"}"),
            .init(200, "{\"items\":[\(contactJSON)],\"nextCursor\":null}"),
            .init(200, "{\"items\":[],\"nextCursor\":null}")
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
            .init(200, customerJSON), .init(200, customerJSON), .init(200, "{\"items\":[],\"nextCursor\":null}"),
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
