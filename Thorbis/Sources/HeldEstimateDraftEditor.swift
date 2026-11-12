import Foundation

/// Staff-only server response. This is a held contract, not an editing or submission flow.
private struct DraftJSONKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
    init(_ value: String) { stringValue = value }
}

/// Staff-only server response. Unknown fields are rejected to avoid a lossy future edit.
struct HeldEstimateDraftEditorResponse: Decodable {
    let estimate: EstimateRecord
    let draftEditVersion: Int
    let expectedRevisionNumber: Int

    private static func keys(_ decoder: Decoder, allowed: Set<String>) throws -> KeyedDecodingContainer<DraftJSONKey> {
        let container = try decoder.container(keyedBy: DraftJSONKey.self)
        guard container.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else { throw HeldEstimateDraftEditor.unavailable() }
        return container
    }
    private static func checkLines(_ decoder: Decoder) throws {
        var lines = try decoder.unkeyedContainer()
        while !lines.isAtEnd {
            let line = try keys(lines.superDecoder(), allowed: ["id", "description", "quantity", "unitPrice", "source", "group", "showToCustomer"])
            _ = try keys(line.superDecoder(forKey: DraftJSONKey("unitPrice")), allowed: ["amount", "currency"])
            for field in ["group", "showToCustomer"] where line.contains(DraftJSONKey(field)) {
                if try line.decodeNil(forKey: DraftJSONKey(field)) { throw HeldEstimateDraftEditor.unavailable() }
            }
            if line.contains(DraftJSONKey("source")) {
                let source = try keys(line.superDecoder(forKey: DraftJSONKey("source")), allowed: ["kind", "priceBookItemId", "priceBookRevision", "originalDescription", "originalUnitPrice", "addedByUserId", "capturedAt", "overriddenFields"])
                let kind = try source.decode(String.self, forKey: DraftJSONKey("kind"))
                let validKeys: Set<String> = kind == "manual" ? ["kind", "addedByUserId", "capturedAt"] :
                    ["kind", "priceBookItemId", "priceBookRevision", "originalDescription", "originalUnitPrice", "addedByUserId", "capturedAt", "overriddenFields"]
                guard source.allKeys.allSatisfy({ validKeys.contains($0.stringValue) }) else { throw HeldEstimateDraftEditor.unavailable() }
                if source.contains(DraftJSONKey("originalUnitPrice")) {
                    _ = try keys(source.superDecoder(forKey: DraftJSONKey("originalUnitPrice")), allowed: ["amount", "currency"])
                }
            }
        }
    }
    init(from decoder: Decoder) throws {
        let root = try Self.keys(decoder, allowed: ["estimate", "draftEditVersion", "expectedRevisionNumber"])
        draftEditVersion = try root.decode(Int.self, forKey: DraftJSONKey("draftEditVersion"))
        expectedRevisionNumber = try root.decode(Int.self, forKey: DraftJSONKey("expectedRevisionNumber"))
        let document = try root.superDecoder(forKey: DraftJSONKey("estimate"))
        let fields = try Self.keys(document, allowed: ["id", "organizationId", "customerId", "createdByUserId", "locationId", "status", "currentRevisionNumber", "title", "lines", "options", "createdAt", "updatedAt", "sentAt", "approvedAt", "declinedAt"])
        for field in ["locationId", "currentRevisionNumber", "sentAt", "approvedAt", "declinedAt"] where fields.contains(DraftJSONKey(field)) {
            if try fields.decodeNil(forKey: DraftJSONKey(field)) { throw HeldEstimateDraftEditor.unavailable() }
        }
        try Self.checkLines(fields.superDecoder(forKey: DraftJSONKey("lines")))
        if fields.contains(DraftJSONKey("options")) {
            var options = try fields.nestedUnkeyedContainer(forKey: DraftJSONKey("options"))
            while !options.isAtEnd {
                let option = try Self.keys(options.superDecoder(), allowed: ["id", "title", "description", "lines", "totalAmount", "currency"])
                try Self.checkLines(option.superDecoder(forKey: DraftJSONKey("lines")))
            }
        }
        estimate = try EstimateRecord(from: document)
    }
    private func validText(_ text: String, max: Int, empty: Bool = false) -> Bool {
        (empty || !text.isEmpty) && text.utf16.count <= max && !text.contains("\0")
    }
    private func validTimestamp(_ text: String) -> Bool {
        let basic = ISO8601DateFormatter()
        if basic.date(from: text) != nil { return true }
        basic.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return basic.date(from: text) != nil
    }
    func validate(scope: JobDocumentScope, estimateID: String) throws {
        guard let id = UUID(uuidString: estimateID), UUID(uuidString: estimate.id) == id,
              let org = UUID(uuidString: scope.organizationID), UUID(uuidString: estimate.organizationId) == org,
              let customer = UUID(uuidString: scope.customerID), UUID(uuidString: estimate.customerId) == customer,
              UUID(uuidString: scope.jobID) != nil, UUID(uuidString: estimate.createdByUserId) != nil,
              estimate.locationId.map({ UUID(uuidString: $0) != nil }) ?? true,
              estimate.status == "draft", validText(estimate.title, max: 200),
              validTimestamp(estimate.createdAt), validTimestamp(estimate.updatedAt),
              (0..<9_007_199_254_740_991).contains(draftEditVersion),
              (0...9_007_199_254_740_991).contains(expectedRevisionNumber),
              estimate.currentRevisionNumber.map({ $0 > 0 }) ?? true,
              expectedRevisionNumber == (estimate.currentRevisionNumber ?? 0),
              estimate.lines.count <= 500, (estimate.options?.count ?? 0) <= 8
        else { throw HeldEstimateDraftEditor.unavailable() }
        var ids = Set<UUID>(), optionIDs = Set<UUID>()
        func checkLines(_ lines: [FieldLine]) throws -> Int {
            var sum = 0
            for line in lines {
                guard let id = UUID(uuidString: line.id), ids.insert(id).inserted,
                      validText(line.description, max: 200), (1...100_000).contains(line.quantity),
                      (-100_000_000...100_000_000).contains(line.unitPrice.amount), line.unitPrice.currency == "USD",
                      line.group.map({ $0 == "work" || $0 == "material" }) ?? true else { throw HeldEstimateDraftEditor.unavailable() }
                if let source = line.source {
                    guard let actor = source.addedByUserId, UUID(uuidString: actor) != nil,
                          source.capturedAt.map({ validTimestamp($0) }) == true else { throw HeldEstimateDraftEditor.unavailable() }
                    switch source.kind {
                    case "manual":
                        guard source.priceBookItemId == nil, source.priceBookRevision == nil,
                              source.originalDescription == nil, source.originalUnitPrice == nil,
                              source.overriddenFields == nil else { throw HeldEstimateDraftEditor.unavailable() }
                    case "price_book":
                        guard let item = source.priceBookItemId, UUID(uuidString: item) != nil,
                              let revision = source.priceBookRevision, (1...9_007_199_254_740_991).contains(revision),
                              let original = source.originalDescription, validText(original, max: 200),
                              let price = source.originalUnitPrice, (-100_000_000...100_000_000).contains(price.amount), price.currency == "USD",
                              let fields = source.overriddenFields, Set(fields).count == fields.count,
                              fields.allSatisfy({ $0 == "description" || $0 == "unit_price" }) else { throw HeldEstimateDraftEditor.unavailable() }
                    default: throw HeldEstimateDraftEditor.unavailable()
                    }
                }
                let (amount, overflow) = line.unitPrice.amount.multipliedReportingOverflow(by: line.quantity)
                let (next, totalOverflow) = sum.addingReportingOverflow(amount)
                guard !overflow, !totalOverflow else { throw HeldEstimateDraftEditor.unavailable() }
                sum = next
            }
            return sum
        }
        let base = try checkLines(estimate.lines)
        guard (0...9_007_199_254_740_991).contains(base) else { throw HeldEstimateDraftEditor.unavailable() }
        for option in estimate.options ?? [] {
            guard let optionID = UUID(uuidString: option.id), optionIDs.insert(optionID).inserted,
                  validText(option.title, max: 200), validText(option.description, max: 500, empty: true),
                  (1...500).contains(option.lines.count), option.currency == "USD", (0...9_007_199_254_740_991).contains(option.totalAmount) else { throw HeldEstimateDraftEditor.unavailable() }
            guard try checkLines(option.lines) == option.totalAmount else { throw HeldEstimateDraftEditor.unavailable() }
        }
    }
}

/// No view calls this while the server contract, version read and draft recovery remain held.
/// The server response alone does not establish membership in a job; fresh job and link reads do.
@MainActor
enum HeldEstimateDraftEditor {
    private struct LinkPage: Decodable { let items: [JobEstimateLink]; let nextCursor: String? }

    nonisolated static func unavailable() -> Problem {
        Problem(title: "Draft editing is unavailable", status: nil, detail: "Refresh the job and try again.")
    }

    static func load(scope: JobDocumentScope, estimateID: String, api: APIClient,
                     session: SessionController, current: @escaping @MainActor () -> Bool) async throws -> HeldEstimateDraftEditorResponse {
        guard UUID(uuidString: estimateID) != nil, UUID(uuidString: scope.jobID) != nil,
              UUID(uuidString: scope.organizationID) != nil, UUID(uuidString: scope.customerID) != nil,
              let authority = CustomerHandoffExitAuthority.capture(api: api, session: session) else { throw unavailable() }
        func check() throws {
            try Task.checkCancellation()
            guard current(), authority.isCurrent(api: api, session: session),
                  UUID(uuidString: authority.organization) == UUID(uuidString: scope.organizationID),
                  session.can("job.view", feature: "jobs"),
                  session.can("estimate.view", feature: "estimates"),
                  session.can("estimate.create", feature: "estimates"),
                  session.can("estimate.create", feature: "estimate_draft_save") else { throw unavailable() }
        }
        func membership() async throws {
            try check()
            let job = try await api.fieldJob(scope.jobID, requireFresh: true)
            try check()
            guard UUID(uuidString: job.id) == UUID(uuidString: scope.jobID),
                  UUID(uuidString: job.organizationId) == UUID(uuidString: scope.organizationID),
                  UUID(uuidString: job.customerId) == UUID(uuidString: scope.customerID) else { throw unavailable() }
            if let origin = job.estimateId, UUID(uuidString: origin) == UUID(uuidString: estimateID) { return }
            let path = "/v1/jobs/\(scope.jobID)/estimates"
            var cursor: String?
            var seen = Set<String>()
            var found = false
            var pages = 0
            repeat {
                try check()
                let page: LinkPage = try await api.send("GET", path, cursor: cursor, requireFresh: true)
                try check()
                pages += 1
                guard pages <= 100, page.items.allSatisfy({ UUID(uuidString: $0.jobId) == UUID(uuidString: scope.jobID) }) else { throw unavailable() }
                found = found || page.items.contains { UUID(uuidString: $0.estimateId) == UUID(uuidString: estimateID) }
                cursor = page.nextCursor
                if let cursor, cursor.isEmpty || !seen.insert(cursor).inserted { throw unavailable() }
            } while cursor != nil
            guard found else { throw unavailable() }
        }
        try await membership()
        try check()
        let path = try api.financialPath("/v1/estimates", id: estimateID, suffix: "/draft-editor")
        let result: HeldEstimateDraftEditorResponse = try await api.send("GET", path, requireFresh: true)
        try check()
        try result.validate(scope: scope, estimateID: estimateID)
        // Recheck membership after the response; a future save still requires server-side scope validation.
        try await membership()
        try check()
        return result
    }
}
