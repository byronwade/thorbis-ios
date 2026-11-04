import Foundation

/// The server's job-authorized exact-record projection. It does not include organization ID;
/// organization scope is checked on the selected staff page and the live session separately.
struct CustomerPhotoMetadata: Decodable, Equatable {
    let id: String
    let jobId: String
    let kind: String
    let uploadState: String
    let archived: Bool
}

/// A temporary, explicit selection; it never silently drops or adds a photo.
struct CustomerPhotoSelection {
    enum Invalid: Error { case selection, scope, records }
    static let maximumCount = 50
    let jobID: String
    let organizationID: String
    let selectedIDs: [String]

    init(jobID: String, organizationID: String, selectedIDs: [String]) throws {
        guard !jobID.isEmpty, !organizationID.isEmpty, !selectedIDs.isEmpty, selectedIDs.count <= Self.maximumCount,
              selectedIDs.allSatisfy({ !$0.isEmpty }), Set(selectedIDs).count == selectedIDs.count else {
            throw Invalid.selection
        }
        self.jobID = jobID
        self.organizationID = organizationID
        self.selectedIDs = selectedIDs
    }

    func validatePageMembership(ids: [String], jobID: String, organizationID: String) throws {
        guard self.jobID == jobID, self.organizationID == organizationID,
              Set(selectedIDs).isSubset(of: Set(ids)) else { throw Invalid.scope }
    }

    func validateFresh(_ records: [CustomerPhotoMetadata]) throws -> [CustomerPhotoMetadata] {
        guard records.count == selectedIDs.count,
              Set(records.map(\.id)).count == records.count,
              Set(records.map(\.id)) == Set(selectedIDs),
              records.allSatisfy({ $0.jobId == jobID && $0.kind == "photo" && $0.uploadState == "stored" && !$0.archived }) else {
            throw Invalid.records
        }
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        return selectedIDs.compactMap { byID[$0] }
    }
}

/// Validates a complete selection against fresh job and exact-asset reads before presentation.
@MainActor
struct CustomerPhotoPreparation {
    static func prepare(selection: CustomerPhotoSelection,
                        isCurrent: () -> Bool,
                        loadJob: () async throws -> (String, String),
                        loadAsset: (String) async throws -> CustomerPhotoMetadata) async throws -> [CustomerPhotoMetadata] {
        func checkCurrent() throws {
            try Task.checkCancellation()
            guard isCurrent() else { throw CustomerPhotoSelection.Invalid.scope }
        }
        try checkCurrent()
        let (jobID, organizationID) = try await loadJob()
        try checkCurrent()
        guard jobID == selection.jobID, organizationID == selection.organizationID else {
            throw CustomerPhotoSelection.Invalid.scope
        }
        var records: [CustomerPhotoMetadata] = []
        for id in selection.selectedIDs {
            try checkCurrent()
            let record = try await loadAsset(id)
            try checkCurrent()
            guard record.id == id else { throw CustomerPhotoSelection.Invalid.records }
            records.append(record)
        }
        try checkCurrent()
        return try selection.validateFresh(records)
    }
}
