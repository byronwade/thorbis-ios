import Foundation
import CryptoKit
import Darwin

/// Storage only. No draft is submitted, retried, or made visible by this type.
/// Callers must provide a bounded fresh session, tenant and record authority check.
/// Restored or unacknowledged entries must be reconciled before any future transport.
/// Atomic rename is not a power-loss durability guarantee.
actor EstimateDraftRecovery {
    struct Owner: Codable, Equatable, Sendable {
        let origin: String
        let organizationID: UUID
        let actorID: UUID
        let estimateID: UUID
    }
    struct Lease: Equatable, Sendable {
        let owner: Owner
        let sessionGeneration: UUID
        let authorityRevision: UUID
        let apiGeneration: UUID
        let savedCopyRevision: UUID
    }
    private struct Partition: Codable { let origin: String; let organizationID: UUID }
    struct Entry: Codable, Equatable, Sendable {
        let owner: Owner
        let operationID: UUID
        let payload: Data
    }
    enum Failure: Error { case unavailable, invalidIntent, conflict, corrupt }
    private struct Identity: Decodable {
        let contractVersion: Int
        let operationId: UUID
        let estimateId: UUID
        let expectedDraftVersion: Int
        let expectedRevisionNumber: Int
    }
    private let directory: URL
    private let isCurrent: @Sendable (Lease) async -> Bool
    private let writeData: @Sendable (Data, URL) throws -> Void
    private var uncertain = false

    init(directory: URL, isCurrent: @escaping @Sendable (Lease) async -> Bool,
         writeData: @escaping @Sendable (Data, URL) throws -> Void = { data, file in
             try data.write(to: file, options: [.atomic, .completeFileProtection])
         }) throws {
        self.directory = directory
        self.isCurrent = isCurrent
        self.writeData = writeData
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func file(for owner: Owner) throws -> URL {
        guard let parts = URLComponents(string: owner.origin), parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.path.isEmpty,
              parts.host == parts.host?.lowercased(), parts.string == owner.origin else { throw Failure.unavailable }
        let production = parts.scheme == "https" && parts.host == "app.thorbis.com" && parts.port == nil
        #if DEBUG
        let local = parts.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(parts.host ?? "")
        #else
        let local = false
        #endif
        guard production || local else { throw Failure.unavailable }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let digest = SHA256.hash(data: try encoder.encode(Partition(origin: owner.origin, organizationID: owner.organizationID))).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".json")
    }

    private func locked<T>(lease: Lease, _ body: (URL) throws -> T) async throws -> T {
        guard !uncertain else { throw Failure.unavailable }
        let file = try file(for: lease.owner)
        let lockPath = file.path + ".lock"
        let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Failure.unavailable }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw Failure.unavailable }
        defer { flock(descriptor, LOCK_UN) }
        guard !Task.isCancelled, await isCurrent(lease), !Task.isCancelled, !uncertain else { throw Failure.unavailable }
        return try body(file)
    }

    private func valid(_ payload: Data, owner: Owner, operationID: UUID) -> Bool {
        guard let identity = try? JSONDecoder().decode(Identity.self, from: payload) else { return false }
        return identity.contractVersion == 1 && identity.operationId == operationID &&
            identity.estimateId == owner.estimateID && identity.expectedDraftVersion >= 0 &&
            identity.expectedDraftVersion < 9_007_199_254_740_991 &&
            identity.expectedRevisionNumber >= 0 && identity.expectedRevisionNumber <= 9_007_199_254_740_991
    }

    private func read(_ file: URL, owner: Owner) throws -> [Entry] {
        let data: Data
        do { data = try Data(contentsOf: file) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return [] }
        catch { throw Failure.unavailable }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data),
              entries.allSatisfy({ $0.owner.origin == owner.origin && $0.owner.organizationID == owner.organizationID && valid($0.payload, owner: $0.owner, operationID: $0.operationID) }),
              Set(entries.map(\.operationID)).count == entries.count else { throw Failure.corrupt }
        return entries
    }

    func load(lease: Lease) async throws -> [Entry] {
        guard !Task.isCancelled, await isCurrent(lease), !Task.isCancelled, !uncertain else { throw Failure.unavailable }
        let entries = try await locked(lease: lease) { try read($0, owner: lease.owner).filter { $0.owner == lease.owner } }
        guard !Task.isCancelled, await isCurrent(lease), !Task.isCancelled, !uncertain else { throw Failure.unavailable }
        return entries
    }

    func save(lease: Lease, operationID: UUID, payload: Data) async throws {
        guard !Task.isCancelled, await isCurrent(lease), !Task.isCancelled, !uncertain else { throw Failure.unavailable }
        let owner = lease.owner
        guard valid(payload, owner: owner, operationID: operationID) else { throw Failure.invalidIntent }
        try await locked(lease: lease) { file in
            var entries = try read(file, owner: owner)
            if let old = entries.first(where: { $0.operationID == operationID }) {
                guard old.owner == owner, old.payload == payload else { throw Failure.conflict }
                return
            }
            entries.append(Entry(owner: owner, operationID: operationID, payload: payload))
            guard !Task.isCancelled else { throw Failure.unavailable }
            do {
                let data = try JSONEncoder().encode(entries)
                try writeData(data, file)
            } catch {
                uncertain = true
                throw Failure.unavailable
            }
        }
        // A failed post-write check may leave a saved, unacknowledged entry; reconcile before retrying.
        guard !Task.isCancelled, await isCurrent(lease), !Task.isCancelled, !uncertain else { throw Failure.unavailable }
    }
}
