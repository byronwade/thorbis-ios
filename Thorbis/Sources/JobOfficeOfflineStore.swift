import CryptoKit
import Combine
import Foundation

/// A cache grant never crosses identity, origin, job, policy, session or API generations.
struct JobOfficeOfflineScope: Codable, Hashable {
    let actor: String
    let organization: String
    let origin: String
    let job: String
    let policyVersion: Int
    let authorityGeneration: String
    let session: UUID
    let authority: UUID
    let api: UUID

    init(actor: String, organization: String, origin: String, job: String, policyVersion: Int,
         authorityGeneration: String, session: UUID, authority: UUID, api: UUID) {
        self.actor = actor.lowercased(); self.organization = organization.lowercased()
        self.origin = origin; self.job = job.lowercased(); self.policyVersion = policyVersion
        self.authorityGeneration = authorityGeneration; self.session = session; self.authority = authority; self.api = api
    }
    var isValid: Bool {
        [actor, organization, job].allSatisfy { UUID(uuidString: $0) != nil && $0 == $0.lowercased() } &&
        policyVersion > 0 && !authorityGeneration.isEmpty
    }
}

/// This held store is not connected to a screen or the generic job cache. The
/// caller must begin a live read before sending it, then recheck its complete
/// session/authority binding before accepting or restoring any result.
@MainActor final class JobOfficeOfflineStore: ObservableObject {
    @Published private(set) var revision = UUID()
    struct Snapshot: Codable {
        let job: JobRecord
        let epoch: UUID
        let savedAt: Date
    }
    private struct Entry: Codable {
        enum State: String, Codable { case available, pending, denied }
        let scope: JobOfficeOfflineScope
        let state: State
        let ticket: UUID?
        let snapshot: Snapshot?
    }
    enum StoreError: Error { case invalidScope, unavailable, invalidJob }
    static let shared = JobOfficeOfflineStore()
    private static var unsafeScopes: Set<JobOfficeOfflineScope> = []
    private let directory: URL
    private let write: (Data, URL) throws -> Void

    init(directory: URL? = nil, write: ((Data, URL) throws -> Void)? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JobOfficeOffline", isDirectory: true)
        self.write = write ?? { data, url in try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    }
    private func file(_ scope: JobOfficeOfflineScope) throws -> URL {
        guard scope.isValid, APIClient.normalizedOrigin(scope.origin) == scope.origin else { throw StoreError.invalidScope }
        let parts = [scope.actor, scope.organization, scope.origin, scope.job, String(scope.policyVersion),
                     scope.authorityGeneration, scope.session.uuidString, scope.authority.uuidString, scope.api.uuidString]
        let key = parts.map { "\($0.utf8.count):\($0)" }.joined()
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(hash).json")
    }
    private func read(_ scope: JobOfficeOfflineScope) throws -> Entry? {
        guard !Self.unsafeScopes.contains(scope) else { throw StoreError.unavailable }
        do {
            let path = try file(scope)
            guard FileManager.default.fileExists(atPath: path.path) else { return nil }
            let entry = try JSONDecoder().decode(Entry.self, from: Data(contentsOf: path))
            guard entry.scope == scope else { throw StoreError.unavailable }
            return entry
        } catch {
            // A failed read must retire already-rendered snapshots in other views
            // before any caller can fall back to a general job request.
            if Self.unsafeScopes.insert(scope).inserted { revision = UUID() }
            throw error
        }
    }
    private func persist(_ entry: Entry) throws {
        do {
            #if DEBUG
            if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-office-completion-failure"),
               entry.state == .available { throw StoreError.unavailable }
            #endif
            let path = try file(entry.scope)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var folder = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            try write(JSONEncoder().encode(entry), path)
            revision = UUID()
        } catch {
            Self.unsafeScopes.insert(entry.scope)
            revision = UUID()
            throw error
        }
    }
    /// A failure here means no request may be sent: a denial must never be
    /// observed without a durable hold already replacing the old grant.
    func beginLive(scope: JobOfficeOfflineScope) throws -> UUID {
        let prior = try read(scope)
        let token = UUID()
        // A newer overlapping read carries forward the last verified snapshot;
        // a denied entry has no snapshot and can never recover one this way.
        let previous = prior?.state == .available || prior?.state == .pending ? prior?.snapshot : nil
        try persist(.init(scope: scope, state: .pending, ticket: token, snapshot: previous))
        return token
    }
    func completeLive(scope: JobOfficeOfflineScope, ticket: UUID, job: JobRecord,
                      stillAuthorized: Bool) throws -> Snapshot? {
        guard let current = try read(scope), current.state == .pending, current.ticket == ticket,
              stillAuthorized else { return nil }
        guard job.id.lowercased() == scope.job, job.organizationId.lowercased() == scope.organization else {
            throw StoreError.invalidJob
        }
        let snapshot = Snapshot(job: job, epoch: UUID(), savedAt: .now)
        try persist(.init(scope: scope, state: .available, ticket: nil, snapshot: snapshot))
        return snapshot
    }
    /// Only a connectivity failure for the latest in-flight attempt may restore
    /// its own prior snapshot; explicit server denial must call deny instead.
    func restoreAfterConnectivityFailure(scope: JobOfficeOfflineScope, ticket: UUID,
                                         stillAuthorized: Bool) throws -> Snapshot? {
        guard let current = try read(scope), current.state == .pending, current.ticket == ticket,
              stillAuthorized, let prior = current.snapshot else { return nil }
        try persist(.init(scope: scope, state: .available, ticket: nil, snapshot: prior))
        return prior
    }
    func deny(scope: JobOfficeOfflineScope) throws {
        try persist(.init(scope: scope, state: .denied, ticket: nil, snapshot: nil))
    }
    func isPending(scope: JobOfficeOfflineScope, ticket: UUID) -> Bool {
        (try? pendingStatus(scope: scope, ticket: ticket)) ?? false
    }
    func pendingStatus(scope: JobOfficeOfflineScope, ticket: UUID) throws -> Bool {
        #if DEBUG
        if PaperPreview.enabled && ProcessInfo.processInfo.arguments.contains("--paper-preview-office-precommit-read-failure") {
            if Self.unsafeScopes.insert(scope).inserted { revision = UUID() }
            throw StoreError.unavailable
        }
        #endif
        guard let entry = try read(scope) else { return false }
        return entry.state == .pending && entry.ticket == ticket
    }
    func offline(scope: JobOfficeOfflineScope, authorized: Bool) -> Snapshot? {
        guard authorized, let entry = try? read(scope), entry.state == .available,
              let snapshot = entry.snapshot, snapshot.job.id.lowercased() == scope.job,
              snapshot.job.organizationId.lowercased() == scope.organization else { return nil }
        return snapshot
    }
    func clearAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}
