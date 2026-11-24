import XCTest
@testable import Thorbis

final class EstimateCreationRecoveryTests: XCTestCase {
    func testSubmittingLocksEditingUntilTheResultIsKnown() {
        let pending = EstimateCreationRecovery(isSaving: true, savedEstimateID: nil)
        XCTAssertFalse(pending.canEdit)
        XCTAssertFalse(pending.mayProceed(validDraft: true))
    }

    func testSavedEstimateIsLockedAndLinkCanRetryWithoutRevalidatingDraft() {
        let saved = EstimateCreationRecovery(isSaving: false, savedEstimateID: "saved-estimate")
        XCTAssertFalse(saved.canEdit)
        XCTAssertTrue(saved.mayProceed(validDraft: false))
    }

    func testUnsavedEstimateRemainsEditableAndRequiresAValidDraft() {
        let draft = EstimateCreationRecovery(isSaving: false, savedEstimateID: nil)
        XCTAssertTrue(draft.canEdit)
        XCTAssertFalse(draft.mayProceed(validDraft: false))
        XCTAssertTrue(draft.mayProceed(validDraft: true))
    }
}

extension EstimateCreationRecoveryTests {
    func testUncertainCreateKeepsTextEditableButBlocksAnotherCreate() {
        let uncertain = EstimateCreationRecovery(isSaving: false, savedEstimateID: nil, createOutcomeUncertain: true)
        XCTAssertTrue(uncertain.canEdit)
        XCTAssertFalse(uncertain.mayProceed(validDraft: true))
    }

    func testOnlyExplicitInputRejectionsAllowAnotherAttempt() {
        XCTAssertTrue(EstimateCreationRecovery.isDefinitiveRejection(Problem(title: "Invalid", status: 422, detail: nil)))
        XCTAssertFalse(EstimateCreationRecovery.isDefinitiveRejection(Problem(title: "Network error", status: nil, detail: nil)))
        XCTAssertFalse(EstimateCreationRecovery.isDefinitiveRejection(Problem(title: "Invalid API response", status: 201, detail: nil)))
        XCTAssertFalse(EstimateCreationRecovery.isDefinitiveRejection(Problem(title: "Server error", status: 500, detail: nil)))
    }

    /// The create response a real server gave for a member customer (10% off): the price-book
    /// line comes back at the member price with the list price kept as the original.
    func testAMemberPricedPriceBookLineIsStillTheSubmittedLine() throws {
        let item = "f2f95c70-7153-8303-a8f2-eca16dd834d6"
        func response(saved: Int, original: Int, overridden: [String]) throws -> EstimateRecord {
            let json = """
            {"id":"01a1fe75-3e8c-7364-86a0-097adbd433c3","organizationId":"01a1fe69-9ccf-731d-8377-21bd9280a0aa",
             "customerId":"01a1fe6a-0f4f-76b0-95ba-c24b732cca6d","createdByUserId":"01a1fe69-8674-7829-952d-b7ef4b15b6d4",
             "status":"draft","title":"Water heater not heating","createdAt":"2026-11-21T14:14:18.993Z","updatedAt":"2026-11-21T14:14:18.993Z",
             "lines":[{"id":"01a1fe75-3ea2-748c-8f31-7fdcf821665f","group":"work","quantity":1,"description":"Replace anode rod",
               "unitPrice":{"amount":\(saved),"currency":"USD"},
               "source":{"kind":"price_book","capturedAt":"2026-11-21T14:14:18.993Z","addedByUserId":"01a1fe69-8674-7829-952d-b7ef4b15b6d4",
                 "priceBookItemId":"\(item)","priceBookRevision":1,"overriddenFields":\(overridden),
                 "originalUnitPrice":{"amount":\(original),"currency":"USD"},"originalDescription":"Replace anode rod"}}]}
            """
            return try JSONDecoder().decode(EstimateRecord.self, from: Data(json.utf8))
        }
        let list = FieldMoney(amount: 18500, currency: "USD")
        let submitted = FieldEstimateCreate(customerId: "01a1fe6a-0f4f-76b0-95ba-c24b732cca6d", title: "Water heater not heating", lines: [
            .init(description: "Replace anode rod", quantity: 1, unitPrice: list, source: .priceBookSelection(itemID: item, revision: 1), group: "work")
        ])
        XCTAssertTrue(EstimateCreationRecovery.matchesSubmittedTerms(submitted, created: try response(saved: 16650, original: 18500, overridden: ["unit_price"])))
        XCTAssertTrue(EstimateCreationRecovery.matchesSubmittedTerms(submitted, created: try response(saved: 18500, original: 18500, overridden: [])))
        // A higher price, an unmarked change, or a different list price is not the submitted line.
        XCTAssertFalse(EstimateCreationRecovery.matchesSubmittedTerms(submitted, created: try response(saved: 19000, original: 18500, overridden: ["unit_price"])))
        XCTAssertFalse(EstimateCreationRecovery.matchesSubmittedTerms(submitted, created: try response(saved: 16650, original: 18500, overridden: [])))
        XCTAssertFalse(EstimateCreationRecovery.matchesSubmittedTerms(submitted, created: try response(saved: 16650, original: 17000, overridden: ["unit_price"])))
        // A hand-typed line never gets this allowance.
        let manual = FieldEstimateCreate(customerId: submitted.customerId, title: submitted.title, lines: [
            .init(description: "Replace anode rod", quantity: 1, unitPrice: list, source: .manual)
        ])
        XCTAssertFalse(EstimateCreationRecovery.matchesSubmittedTerms(manual, created: try response(saved: 16650, original: 18500, overridden: ["unit_price"])))
    }

    func testCreatedResponseMustMatchSubmittedLineTermsAndProvenance() throws {
        var fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(PaperPreview.estimate)) as? [String: Any])
        fixture["status"] = "draft"
        fixture.removeValue(forKey: "options")
        fixture.removeValue(forKey: "sentAt")
        let created = try JSONDecoder().decode(EstimateRecord.self, from: JSONSerialization.data(withJSONObject: fixture))
        let inputs = created.lines.map { line in
            FieldEstimateLineInput(description: line.description, quantity: line.quantity, unitPrice: line.unitPrice,
                source: line.source?.kind == "price_book" ? .priceBookSelection(itemID: line.source!.priceBookItemId!, revision: line.source!.priceBookRevision!) : .manual)
        }
        let submitted = FieldEstimateCreate(customerId: created.customerId, title: created.title, lines: inputs)
        XCTAssertTrue(EstimateCreationRecovery.matchesSubmittedTerms(submitted, created: created))
        var changedLines = inputs
        changedLines[0] = .init(description: created.lines[0].description, quantity: 99, unitPrice: created.lines[0].unitPrice, source: .manual)
        let changed = FieldEstimateCreate(customerId: created.customerId, title: created.title, lines: changedLines)
        XCTAssertFalse(EstimateCreationRecovery.matchesSubmittedTerms(changed, created: created))
        let wrongTitle = FieldEstimateCreate(customerId: created.customerId, title: "Different", lines: inputs)
        XCTAssertFalse(EstimateCreationRecovery.matchesSubmittedTerms(wrongTitle, created: created))
        var hiddenMaterial = inputs
        hiddenMaterial[0] = .init(description: created.lines[0].description, quantity: created.lines[0].quantity,
                                  unitPrice: created.lines[0].unitPrice, source: .manual, group: "material", showToCustomer: false)
        XCTAssertFalse(EstimateCreationRecovery.matchesSubmittedTerms(.init(customerId: created.customerId, title: created.title, lines: hiddenMaterial), created: created))
        var explicitlyVisible = inputs
        explicitlyVisible[0] = .init(description: created.lines[0].description, quantity: created.lines[0].quantity,
                                     unitPrice: created.lines[0].unitPrice, source: .manual, showToCustomer: true)
        var hiddenResponse = fixture
        var hiddenLines = try XCTUnwrap(hiddenResponse["lines"] as? [[String: Any]])
        hiddenLines[0]["showToCustomer"] = false
        hiddenResponse["lines"] = hiddenLines
        let hidden = try JSONDecoder().decode(EstimateRecord.self, from: JSONSerialization.data(withJSONObject: hiddenResponse))
        XCTAssertFalse(EstimateCreationRecovery.matchesSubmittedTerms(.init(customerId: created.customerId, title: created.title, lines: explicitlyVisible), created: hidden))
        XCTAssertFalse(EstimateCreationRecovery.matchesSubmittedTerms(submitted, created: hidden), "Omitted visibility means visible")
        let requestedGroup = FieldEstimateCreate(customerId: created.customerId, title: created.title, lines: hiddenMaterial)
        XCTAssertEqual(EstimateCreationRecovery.groupResult(requestedGroup, created: created), .missing)
        var wrongGroupJSON = fixture
        var wrongGroupLines = try XCTUnwrap(wrongGroupJSON["lines"] as? [[String: Any]])
        wrongGroupLines[0]["group"] = "work"
        wrongGroupJSON["lines"] = wrongGroupLines
        let wrongGroup = try JSONDecoder().decode(EstimateRecord.self, from: JSONSerialization.data(withJSONObject: wrongGroupJSON))
        XCTAssertEqual(EstimateCreationRecovery.groupResult(requestedGroup, created: wrongGroup), .conflicting)
        var wrongSource = inputs
        let line = created.lines[1]
        wrongSource[1] = .init(description: line.description, quantity: line.quantity, unitPrice: line.unitPrice, source: .manual)
        XCTAssertFalse(EstimateCreationRecovery.matchesSubmittedTerms(.init(customerId: created.customerId, title: created.title, lines: wrongSource), created: created))
    }

    func testReauthorizationIgnoresRecordTimestampsButRejectsChangedCommercialTerms() throws {
        let original = PaperPreview.estimate
        func changing(_ edit: (inout [String: Any]) -> Void) throws -> EstimateRecord {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
            edit(&json)
            return try JSONDecoder().decode(EstimateRecord.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let timestamps = try changing { $0["createdAt"] = "2026-07-18T12:00:00.000Z"; $0["updatedAt"] = "2026-07-20T12:00:00.000Z" }
        XCTAssertTrue(EstimateCreationRecovery.matchesSavedEstimate(original, latest: timestamps))
        let changedTitle = try changing { $0["title"] = "Other work" }
        XCTAssertFalse(EstimateCreationRecovery.matchesSavedEstimate(original, latest: changedTitle))
        let changedLine = try changing { json in
            var lines = json["lines"] as! [[String: Any]]
            lines[0]["quantity"] = 99
            json["lines"] = lines
        }
        XCTAssertFalse(EstimateCreationRecovery.matchesSavedEstimate(original, latest: changedLine))
        let otherLocation = try changing { $0["locationId"] = "00000000-0000-4000-8000-000000009999" }
        XCTAssertFalse(EstimateCreationRecovery.matchesSavedEstimate(original, latest: otherLocation))
        let otherStatus = try changing { $0["status"] = "approved" }
        XCTAssertFalse(EstimateCreationRecovery.matchesSavedEstimate(original, latest: otherStatus))
    }

    func testOnlyTheRequestedJobAndEstimateConfirmTheLink() {
        let correct = JobEstimateLink(id: "link", jobId: "job", estimateId: "estimate", linkedAt: nil)
        let wrongJob = JobEstimateLink(id: "link", jobId: "other-job", estimateId: "estimate", linkedAt: nil)
        let wrongEstimate = JobEstimateLink(id: "link", jobId: "job", estimateId: "other-estimate", linkedAt: nil)
        XCTAssertTrue(EstimateCreationRecovery.isExpectedLink(correct, jobID: "job", estimateID: "estimate"))
        XCTAssertFalse(EstimateCreationRecovery.isExpectedLink(wrongJob, jobID: "job", estimateID: "estimate"))
        XCTAssertFalse(EstimateCreationRecovery.isExpectedLink(wrongEstimate, jobID: "job", estimateID: "estimate"))
    }

    func testScopeRejectsChangedIdentitySessionTransportOrOrigin() {
        let session = UUID(), authority = UUID(), request = UUID()
        let original = EstimateCreationScope(actorID: "actor", organizationID: "org", sessionGeneration: session, authorityRevision: authority,
                                             requestGeneration: request, origin: "https://app.thorbis.com")
        XCTAssertNotEqual(original, .init(actorID: "other", organizationID: "org", sessionGeneration: session, authorityRevision: authority, requestGeneration: request, origin: original.origin))
        XCTAssertNotEqual(original, .init(actorID: "actor", organizationID: "other", sessionGeneration: session, authorityRevision: authority, requestGeneration: request, origin: original.origin))
        XCTAssertNotEqual(original, .init(actorID: "actor", organizationID: "org", sessionGeneration: UUID(), authorityRevision: authority, requestGeneration: request, origin: original.origin))
        let refreshed = EstimateCreationScope(actorID: "actor", organizationID: "org", sessionGeneration: session, authorityRevision: UUID(), requestGeneration: request, origin: original.origin)
        XCTAssertNotEqual(original, refreshed)
        XCTAssertTrue(original.sameIdentityAndTransport(as: refreshed))
        let otherOrganization = EstimateCreationScope(actorID: "actor", organizationID: "other", sessionGeneration: session, authorityRevision: authority, requestGeneration: request, origin: original.origin)
        XCTAssertFalse(original.sameIdentityAndTransport(as: otherOrganization))
        XCTAssertNotEqual(original, .init(actorID: "actor", organizationID: "org", sessionGeneration: session, authorityRevision: authority, requestGeneration: UUID(), origin: original.origin))
        XCTAssertNotEqual(original, .init(actorID: "actor", organizationID: "org", sessionGeneration: session, authorityRevision: authority, requestGeneration: request, origin: "https://other.example"))
    }
}
