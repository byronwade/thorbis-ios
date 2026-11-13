import Foundation
import SQLite3

/// A storage domain only; callers must derive origin and IDs from trusted session/API state.
struct InvoiceFenceDomain: Sendable {
    let origin: String
    let organizationID: String
    let invoiceID: String

    var valid: Bool {
        guard let parts = URLComponents(string: origin), let scheme = parts.scheme,
              ["https", "http"].contains(scheme), let host = parts.host, host == host.lowercased(),
              !host.isEmpty, parts.user == nil, parts.password == nil, parts.query == nil,
              parts.fragment == nil, parts.path.isEmpty,
              !((scheme == "https" && parts.port == 443) || (scheme == "http" && parts.port == 80)),
              parts.string == origin,
              let org = UUID(uuidString: organizationID), org.uuidString.lowercased() == organizationID,
              let invoice = UUID(uuidString: invoiceID), invoice.uuidString.lowercased() == invoiceID else { return false }
        return true
    }
}

enum InvoiceFencePending: Int32, Sendable { case keyed = 1, directUnknown = 2 }
enum InvoiceFenceError: Error { case invalid, conflict, pending, database(Int32) }

/// Held experiment: one DB shared by all participants, no authorization or transport.
/// Pending markers have no automatic clearing path. SQLite and device data protection
/// must be qualified on real devices before this class can protect a financial write.
final class InvoiceTransactionFence: @unchecked Sendable {
    private let path: String
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        self.path = path
        try connection { db in
            try exec(db, "PRAGMA journal_mode=WAL")
            try exec(db, "PRAGMA synchronous=FULL")
            try exec(db, "CREATE TABLE IF NOT EXISTS heads (origin TEXT NOT NULL, org TEXT NOT NULL, invoice TEXT NOT NULL, owner TEXT NOT NULL, version INTEGER NOT NULL, pending INTEGER NOT NULL DEFAULT 0, command BLOB, PRIMARY KEY(origin,org,invoice))")
            try exec(db, "CREATE TABLE IF NOT EXISTS snapshots (origin TEXT NOT NULL, org TEXT NOT NULL, invoice TEXT NOT NULL, version INTEGER NOT NULL, draft BLOB NOT NULL, PRIMARY KEY(origin,org,invoice,version))")
        }
    }
    private func connection<T>(_ run: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        let code = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard code == SQLITE_OK, let db else { if let db { sqlite3_close(db) }; throw InvoiceFenceError.database(code) }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 5000)
        try exec(db, "PRAGMA synchronous=FULL")
        return try run(db)
    }
    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        let code = sqlite3_exec(db, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw InvoiceFenceError.database(code) }
    }
    private func statement<T>(_ db: OpaquePointer, _ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var stmt: OpaquePointer?
        let code = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard code == SQLITE_OK, let stmt else { throw InvoiceFenceError.database(code) }
        defer { sqlite3_finalize(stmt) }
        return try body(stmt)
    }
    private func bind(_ s: OpaquePointer, _ index: Int32, _ value: String) throws {
        let code = sqlite3_bind_text(s, index, value, -1, Self.transient)
        guard code == SQLITE_OK else { throw InvoiceFenceError.database(code) }
    }
    private func bind(_ s: OpaquePointer, _ index: Int32, _ value: Data) throws {
        let code = value.withUnsafeBytes { sqlite3_bind_blob(s, index, $0.baseAddress, Int32($0.count), Self.transient) }
        guard code == SQLITE_OK else { throw InvoiceFenceError.database(code) }
    }
    private func keys(_ s: OpaquePointer, _ domain: InvoiceFenceDomain) throws {
        try bind(s, 1, domain.origin); try bind(s, 2, domain.organizationID); try bind(s, 3, domain.invoiceID)
    }
    private func transaction<T>(_ domain: InvoiceFenceDomain, _ body: (OpaquePointer) throws -> T) throws -> T {
        guard domain.valid else { throw InvoiceFenceError.invalid }
        return try connection { db in
            try exec(db, "BEGIN IMMEDIATE")
            do { let result = try body(db); try exec(db, "COMMIT"); return result }
            catch { try? exec(db, "ROLLBACK"); throw error }
        }
    }
    private func head(_ db: OpaquePointer, _ domain: InvoiceFenceDomain) throws -> (String, Int64, Int32)? {
        try statement(db, "SELECT owner,version,pending FROM heads WHERE origin=? AND org=? AND invoice=?") { s in
            try keys(s, domain)
            let code = sqlite3_step(s)
            if code == SQLITE_DONE { return nil }
            guard code == SQLITE_ROW, let owner = sqlite3_column_text(s, 0) else { throw InvoiceFenceError.database(code) }
            return (String(cString: owner), sqlite3_column_int64(s, 1), sqlite3_column_int(s, 2))
        }
    }
    func save(domain: InvoiceFenceDomain, owner: UUID, expectedVersion: Int64?, bytes: Data) throws -> Int64 {
        guard !bytes.isEmpty, bytes.count <= Int(Int32.max) else { throw InvoiceFenceError.invalid }
        return try transaction(domain) { db in
            let current = try head(db, domain), ownerID = owner.uuidString.lowercased()
            if let current {
                guard current.2 == 0 else { throw InvoiceFenceError.pending }
                guard current.0 == ownerID, current.1 == expectedVersion, current.1 < Int64.max else { throw InvoiceFenceError.conflict }
            } else if expectedVersion != nil { throw InvoiceFenceError.conflict }
            let version = (current?.1 ?? 0) + 1
            if current == nil {
                try statement(db, "INSERT INTO heads(origin,org,invoice,owner,version) VALUES(?,?,?,?,?)") { s in
                    try keys(s, domain); try bind(s, 4, ownerID); sqlite3_bind_int64(s, 5, version)
                    let code = sqlite3_step(s); guard code == SQLITE_DONE else { throw InvoiceFenceError.database(code) }
                }
            } else {
                try statement(db, "UPDATE heads SET version=? WHERE origin=? AND org=? AND invoice=?") { s in
                    sqlite3_bind_int64(s, 1, version); try bind(s, 2, domain.origin); try bind(s, 3, domain.organizationID); try bind(s, 4, domain.invoiceID)
                    let code = sqlite3_step(s); guard code == SQLITE_DONE else { throw InvoiceFenceError.database(code) }
                }
            }
            try statement(db, "INSERT INTO snapshots(origin,org,invoice,version,draft) VALUES(?,?,?,?,?)") { s in
                try keys(s, domain); sqlite3_bind_int64(s, 4, version); try bind(s, 5, bytes)
                let code = sqlite3_step(s); guard code == SQLITE_DONE else { throw InvoiceFenceError.database(code) }
            }
            return version
        }
    }
    func begin(domain: InvoiceFenceDomain, owner: UUID, expectedVersion: Int64, kind: InvoiceFencePending, command: Data) throws -> Int64 {
        guard !command.isEmpty, command.count <= Int(Int32.max) else { throw InvoiceFenceError.invalid }
        return try transaction(domain) { db in
            guard let current = try head(db, domain) else { throw InvoiceFenceError.conflict }
            guard current.2 == 0 else { throw InvoiceFenceError.pending }
            guard current.0 == owner.uuidString.lowercased(), current.1 == expectedVersion, current.1 < Int64.max else { throw InvoiceFenceError.conflict }
            try statement(db, "UPDATE heads SET version=?,pending=?,command=? WHERE origin=? AND org=? AND invoice=?") { s in
                sqlite3_bind_int64(s, 1, current.1 + 1); sqlite3_bind_int(s, 2, kind.rawValue); try bind(s, 3, command)
                try bind(s, 4, domain.origin); try bind(s, 5, domain.organizationID); try bind(s, 6, domain.invoiceID)
                let code = sqlite3_step(s); guard code == SQLITE_DONE else { throw InvoiceFenceError.database(code) }
            }
            return current.1 + 1
        }
    }
    func pending(domain: InvoiceFenceDomain) throws -> InvoiceFencePending? {
        try transaction(domain) { db in
            guard let current = try head(db, domain), current.2 != 0 else { return nil }
            guard let pending = InvoiceFencePending(rawValue: current.2) else { throw InvoiceFenceError.invalid }
            return pending
        }
    }
    func loadIdle(domain: InvoiceFenceDomain, owner: UUID) throws -> Data? {
        try transaction(domain) { db in
            guard let current = try head(db, domain) else { return nil }
            guard current.2 == 0 else { throw InvoiceFenceError.pending }
            guard current.0 == owner.uuidString.lowercased() else { throw InvoiceFenceError.conflict }
            return try statement(db, "SELECT draft FROM snapshots WHERE origin=? AND org=? AND invoice=? AND version=?") { s in
                try keys(s, domain); sqlite3_bind_int64(s, 4, current.1)
                let code = sqlite3_step(s)
                guard code == SQLITE_ROW, let ptr = sqlite3_column_blob(s, 0) else { throw InvoiceFenceError.database(code) }
                return Data(bytes: ptr, count: Int(sqlite3_column_bytes(s, 0)))
            }
        }
    }
}
