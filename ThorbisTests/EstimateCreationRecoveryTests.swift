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
