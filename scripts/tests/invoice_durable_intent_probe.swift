import Foundation
import SQLite3

@main struct Probe {
 static func main() throws {
  let path = "/private/tmp/invoice-intent-\(UUID().uuidString).sqlite"
  let d = InvoiceFenceDomain(origin: "https://thorbis.com", organizationID: "00000000-0000-4000-8000-000000000001", invoiceID: "00000000-0000-4000-8000-000000000002")
  let id = InvoiceIdleCaptureIdentity(domain: d, actorID: "00000000-0000-4000-8000-000000000003", customerID: "00000000-0000-4000-8000-000000000004", jobID: nil)
  let owner = UUID(), first = try InvoiceTransactionFence(path: path)
  _ = try first.capture(identity: id, owner: owner, expectedVersion: nil, sequence: 1, bytes: Data([9]))
  let intent = try first.registerCaptureIntent(identity: id, owner: owner, expectedVersion: 1, sequence: 2, bytes: Data([1]))
  let second = try InvoiceTransactionFence(path: path)
  func blocked(_ body: () throws -> Void) throws {
    do { try body(); fatalError("unresolved capture allowed operation") }
    catch InvoiceFenceError.pending { }
  }
  try blocked { _ = try second.capture(identity: id, owner: owner, expectedVersion: 1, sequence: 2, bytes: Data([2])) }
  try blocked { _ = try second.save(domain: d, owner: owner, expectedVersion: 1, bytes: Data([2])) }
  try blocked { _ = try second.recoverIdle(identity: id) }
  try blocked { _ = try second.begin(domain: d, owner: owner, expectedVersion: 2, kind: .directUnknown, command: Data([2])) }
  try first.commitCaptureIntent(intent)
  try blocked { _ = try second.capture(identity: id, owner: owner, expectedVersion: 2, sequence: 3, bytes: Data([3])) }
  try blocked { _ = try second.recoverIdle(identity: id) }
  var db: OpaquePointer?; precondition(sqlite3_open(path, &db) == SQLITE_OK); defer { sqlite3_close(db) }
  var statement: OpaquePointer?; precondition(sqlite3_prepare_v2(db, "SELECT count(*) FROM snapshots", -1, &statement, nil) == SQLITE_OK); defer { sqlite3_finalize(statement) }
  precondition(sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_int(statement, 0) == 2, "earlier snapshot lost")
  print("unresolved capture fenced across instances; previous snapshot retained")
 }
}
