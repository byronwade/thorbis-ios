import Foundation
import CryptoKit
import SQLite3

@main struct GrowthProbe {
  static func main() throws {
    let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("invoice-growth-\(UUID().uuidString).sqlite").path
    defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
    let domain = InvoiceFenceDomain(origin: "https://app.thorbis.com", organizationID: "00000000-0000-4000-8000-000000000001", invoiceID: "00000000-0000-4000-8000-000000000002")
    let scope = InvoiceIdleCaptureIdentity(domain: domain, actorID: "00000000-0000-4000-8000-000000000003", customerID: "00000000-0000-4000-8000-000000000004", jobID: nil)
    let fence = try InvoiceTransactionFence(path: path)
    let owner = UUID(), key = SymmetricKey(size: .bits256)
    var version: Int64? = nil
    for sequence in 1...100 {
      let body = Data(repeating: UInt8(sequence), count: 8_192)
      let sealed = try InvoiceDraftCipher.seal(body, identity: scope, owner: owner, sequence: Int64(sequence), key: key)
      version = try fence.capture(identity: scope, owner: owner, expectedVersion: version, sequence: Int64(sequence), bytes: sealed.ciphertext)
    }
    var db: OpaquePointer?; precondition(sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    defer { sqlite3_close(db) }
    var stmt: OpaquePointer?; precondition(sqlite3_prepare_v2(db, "SELECT count(*), sum(length(draft)) FROM snapshots", -1, &stmt, nil) == SQLITE_OK)
    defer { sqlite3_finalize(stmt) }; precondition(sqlite3_step(stmt) == SQLITE_ROW)
    print("100 edits retained \(sqlite3_column_int(stmt, 0)) snapshots and \(sqlite3_column_int64(stmt, 1)) ciphertext bytes")
  }
}
