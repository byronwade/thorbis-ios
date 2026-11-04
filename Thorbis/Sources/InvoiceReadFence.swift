import CryptoKit
import Darwin
import Foundation

/// Held-only transport fence. No app flow is wired to this prototype.
/// A caller must retain each attempt until every transport callback is terminal,
/// and must independently prove that a `.liveSuccess` covers the full resource.
final class InvoiceReadFence {
    struct Scope {
        let actor: String
        let organization: String
        let origin: String
        let invoice: String
        /// "invoice" and "history" are distinct authority decisions.
        let resource: String
    }
    enum Outcome { case liveSuccess, connectivityFailure, denied }
    enum Completion: Equatable { case committed, held, denied }
    enum Failure: Error { case invalidScope, storage, contended, alreadyFinished }
    private struct Record: Codable {
        let version: Int
        let phase: String
        let epoch: String
        let eligible: Bool
        let priorClean: Bool
        let priorEpoch: String?
        let parentEpoch: String?
    }
    private let directory: URL

    init(directory: URL) { self.directory = directory }

    private func key(_ scope: Scope) throws -> String {
        guard let actor = UUID(uuidString: scope.actor), let org = UUID(uuidString: scope.organization),
              let invoice = UUID(uuidString: scope.invoice), ["invoice", "history"].contains(scope.resource),
              let url = URLComponents(string: scope.origin), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty else { throw Failure.invalidScope }
        let port = url.port.map { ":\($0)" } ?? ""
        let identity = ["invoice-read-fence-v1", actor.uuidString.lowercased(), org.uuidString.lowercased(),
                        "\(scheme)://\(host)\(port)", invoice.uuidString.lowercased(), scope.resource]
        let data = try JSONEncoder().encode(identity)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }
    private func lockFile(_ name: String) throws -> Int32 {
        try prepare()
        let fd = open(directory.appendingPathComponent(name).path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure.storage }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { close(fd); throw Failure.storage }
        return fd
    }
    private func withMetadata<T>(_ key: String, _ work: () throws -> T) throws -> T {
        let fd = try lockFile("\(key).meta.lock")
        defer { _ = flock(fd, LOCK_UN); close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw Failure.contended }
        return try work()
    }
    private func withScopeMetadata<T>(_ key: String, parent: String?, _ work: () throws -> T) throws -> T {
        if let parent { return try withMetadata(parent) { try withMetadata(key, work) } }
        return try withMetadata(key, work)
    }
    private func parentKey(_ scope: Scope) throws -> String? {
        guard scope.resource == "history" else { return nil }
        return try key(Scope(actor: scope.actor, organization: scope.organization, origin: scope.origin,
                             invoice: scope.invoice, resource: "invoice"))
    }
    private func load(_ key: String) throws -> Record? {
        let path = directory.appendingPathComponent("\(key).json").path
        let fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw Failure.storage
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        guard let data = try handle.readToEnd(), let record = try? JSONDecoder().decode(Record.self, from: data),
              record.version == 1, ["pending", "clean", "denied"].contains(record.phase),
              UUID(uuidString: record.epoch) != nil else { throw Failure.storage }
        return record
    }
    private func persist(_ record: Record, _ key: String) throws {
        let data = try JSONEncoder().encode(record)
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp").path
        let fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure.storage }
        var renamed = false
        defer { close(fd); if !renamed { _ = unlink(temporary) } }
        let written = data.withUnsafeBytes { bytes -> Bool in
            guard let base = bytes.baseAddress else { return false }
            var offset = 0
            while offset < bytes.count {
                let amount = Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
                if amount <= 0 { return false }
                offset += amount
            }
            return true
        }
        guard written, fsync(fd) == 0 else { throw Failure.storage }
        guard rename(temporary, directory.appendingPathComponent("\(key).json").path) == 0 else { throw Failure.storage }
        renamed = true
        let folder = open(directory.path, O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW)
        guard folder >= 0 else { throw Failure.storage }
        defer { close(folder) }
        guard fsync(folder) == 0 else { throw Failure.storage }
    }

    func cacheAllowed(_ scope: Scope) -> Bool {
        do {
            let key = try key(scope)
            let parent = try parentKey(scope)
            return try withScopeMetadata(key, parent: parent) {
                guard let record = try load(key), record.phase == "clean" else { return false }
                guard let parent else { return true }
                guard let invoice = try load(parent), invoice.phase == "clean" else { return false }
                return record.parentEpoch == invoice.epoch
            }
        } catch { return false }
    }

    // Held prototype: `write` must be synchronous and durably commit an atomic
    // replacement, and must not reenter the fence. This serializes it against
    // preflight in cooperating processes. It does not manage visible UI state.
    func withCacheWrite(_ scope: Scope, write: () throws -> Void) throws -> Bool {
        let key = try key(scope)
        let parent = try parentKey(scope)
        return try withScopeMetadata(key, parent: parent) {
            guard let record = try load(key), record.phase == "clean" else { return false }
            if let parent {
                guard let invoice = try load(parent), invoice.phase == "clean",
                      invoice.epoch == record.parentEpoch else { return false }
            }
            try persist(Record(version: 1, phase: "pending", epoch: UUID().uuidString,
                               eligible: false, priorClean: false, priorEpoch: nil,
                               parentEpoch: record.parentEpoch), key)
            try write()
            try persist(record, key)
            return true
        }
    }

    func begin(_ scope: Scope) throws -> Attempt {
        let key = try key(scope)
        let parent = try parentKey(scope)
        let transport = try lockFile("\(key).transport.lock")
        var handedOff = false
        defer { if !handedOff { _ = flock(transport, LOCK_UN); close(transport) } }
        // Keep one continuous exclusive lease through terminal handling. This avoids
        // lock-conversion gaps and forbids overlapping observations for this resource.
        guard flock(transport, LOCK_EX | LOCK_NB) == 0 else { throw Failure.contended }
        let epoch = UUID().uuidString
        try withScopeMetadata(key, parent: parent) {
            let invoice = try parent.map { try load($0) } ?? nil
            if parent != nil && invoice?.phase != "clean" { throw Failure.contended }
            let prior = try load(key)
            let parentEpoch = invoice?.epoch
            let priorClean = prior?.phase == "clean" && (parent == nil || prior?.parentEpoch == parentEpoch)
            try persist(Record(version: 1, phase: "pending", epoch: epoch, eligible: true,
                               priorClean: priorClean, priorEpoch: priorClean ? prior?.epoch : nil,
                               parentEpoch: parentEpoch), key)
        }
        handedOff = true
        return Attempt(fence: self, key: key, parent: parent, transport: transport, epoch: epoch)
    }

    final class Attempt {
        private let fence: InvoiceReadFence
        private let key: String
        private var transport: Int32
        private let parent: String?
        private let epoch: String
        private let mutex = NSLock()
        fileprivate init(fence: InvoiceReadFence, key: String, parent: String?, transport: Int32, epoch: String) {
            self.fence = fence; self.key = key; self.parent = parent; self.transport = transport; self.epoch = epoch
        }
        // An abandoned attempt may still have a transport callback in flight.
        // Keep its descriptor open until process exit instead of permitting a
        // later read to erase a denial we can no longer observe. The future
        // transport owner must finish every attempt to avoid this availability
        // cost; this primitive remains unwired until that lifecycle is proven.
        func finish(_ outcome: Outcome) throws -> Completion {
            mutex.lock(); defer { mutex.unlock() }
            guard transport >= 0 else { throw Failure.alreadyFinished }
            let fd = transport
            transport = -1
            defer { _ = flock(fd, LOCK_UN); close(fd) }
            if case .denied = outcome {
                try fence.withMetadata(key) {
                    try fence.persist(Record(version: 1, phase: "denied", epoch: UUID().uuidString,
                                             eligible: false, priorClean: false, priorEpoch: nil, parentEpoch: nil), key)
                }
                return .denied
            }
            // A normal return is not an authorization merely because a ledger transition committed.
            return try fence.withScopeMetadata(key, parent: parent) {
                guard let record = try fence.load(key), record.phase == "pending", record.epoch == epoch,
                      record.eligible else { return .held }
                if let parent {
                    guard let invoice = try fence.load(parent), invoice.phase == "clean",
                          invoice.epoch == record.parentEpoch else { return .held }
                }
                let canRestore: Bool
                switch outcome {
                case .liveSuccess: canRestore = true
                case .connectivityFailure: canRestore = record.priorClean
                case .denied: canRestore = false
                }
                guard canRestore else { return .held }
                let cleanEpoch: String
                if outcome == .connectivityFailure {
                    guard let previous = record.priorEpoch, UUID(uuidString: previous) != nil else { return .held }
                    cleanEpoch = previous
                } else {
                    cleanEpoch = UUID().uuidString
                }
                try fence.persist(Record(version: 1, phase: "clean", epoch: cleanEpoch,
                                         eligible: false, priorClean: false, priorEpoch: nil,
                                         parentEpoch: record.parentEpoch), key)
                return .committed
            }
        }
    }
}
