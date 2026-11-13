import Foundation
import SQLite3

@main struct Probe {
 static func main() throws {
  let path = "/private/tmp/invoice-intent-\(UUID().uuidString).sqlite"
  let d = InvoiceFenceDomain(origin: "https://thorbis.com", organizationID: "00000000-0000-4000-8000-000000000001", invoiceID: "00000000-0000-4000-8000-000000000002")
  let id = InvoiceIdleCaptureIdentity(domain: d, actorID: "00000000-0000-4000-8000-000000000003", customerID: "00000000-0000-4000-8000-000000000004", jobID: nil)
  let owner = UUID(), first = try InvoiceTransactionFence(path: path)
  do { _ = try first.capture(identity: id, owner: owner, expectedVersion: nil, sequence: 1, bytes: Data([9])); fatalError("unguarded capture allowed") } catch InvoiceFenceError.pending { }
  // Seed an already-acknowledged legacy snapshot; direct captures must now use an intent.
  var seed: OpaquePointer?; precondition(sqlite3_open(path, &seed) == SQLITE_OK)
  let seedSQL = "INSERT INTO heads VALUES (\'https://thorbis.com\',\'00000000-0000-4000-8000-000000000001\',\'00000000-0000-4000-8000-000000000002\',\'\(owner.uuidString.lowercased())\',1,0,NULL); INSERT INTO capture_heads VALUES (\'https://thorbis.com\',\'00000000-0000-4000-8000-000000000001\',\'00000000-0000-4000-8000-000000000002\',\'00000000-0000-4000-8000-000000000003\',\'00000000-0000-4000-8000-000000000004\',\'\',1); INSERT INTO snapshots VALUES (\'https://thorbis.com\',\'00000000-0000-4000-8000-000000000001\',\'00000000-0000-4000-8000-000000000002\',1,X\'09\');"
  precondition(sqlite3_exec(seed, seedSQL, nil, nil, nil) == SQLITE_OK); sqlite3_close(seed)
  let intent = try first.registerCaptureIntent(identity: id, owner: owner, expectedVersion: 1, sequence: 2, bytes: Data([1]))
  let second = try InvoiceTransactionFence(path: path)
  let staged = try second.inspectUnresolvedCapture(identity: id)
  precondition(staged?.phase == .registered && staged?.bytes == Data([1]) && staged?.previousVersion == 1)
  let wrong = InvoiceIdleCaptureIdentity(domain: d, actorID: "00000000-0000-4000-8000-000000000099", customerID: id.customerID, jobID: nil)
  do { _ = try second.inspectUnresolvedCapture(identity: wrong); fatalError("wrong actor inspected") } catch InvoiceFenceError.conflict { }
  func blocked(_ body: () throws -> Void) throws {
    do { try body(); fatalError("unresolved capture allowed operation") }
    catch InvoiceFenceError.pending { }
  }
  try blocked { _ = try second.registerCaptureIntent(identity: id, owner: owner, expectedVersion: 1, sequence: 2, bytes: Data([2])) }
  try blocked { _ = try second.capture(identity: id, owner: owner, expectedVersion: 1, sequence: 2, bytes: Data([2])) }
  try blocked { _ = try second.save(domain: d, owner: owner, expectedVersion: 1, bytes: Data([2])) }
  try blocked { _ = try second.recoverIdle(identity: id) }
  try blocked { _ = try second.begin(domain: d, owner: owner, expectedVersion: 2, kind: .directUnknown, command: Data([2])) }
  try first.commitCaptureIntent(intent)
  let committed = try second.inspectUnresolvedCapture(identity: id)
  precondition(committed?.phase == .committed && committed?.bytes == Data([1]) && committed?.previousVersion == 1)
  let decision = UUID()
  do { try second.recordRecoverySelection(identity: wrong, selection: .candidate, decisionID: decision, authorize: { true }); fatalError("wrong scope selected") } catch InvoiceFenceError.conflict { }
  do { try second.recordRecoverySelection(identity: id, selection: .candidate, decisionID: decision, authorize: { false }); fatalError("denied selection accepted") } catch InvoiceFenceError.conflict { }
  try second.recordRecoverySelection(identity: id, selection: .candidate, decisionID: decision, authorize: { true })
  try first.recordRecoverySelection(identity: id, selection: .candidate, decisionID: decision, authorize: { true })
  do { try first.recordRecoverySelection(identity: id, selection: .previous, decisionID: UUID(), authorize: { true }); fatalError("choice silently replaced") } catch InvoiceFenceError.conflict { }
  let selected = try second.inspectUnresolvedCapture(identity: id)
  precondition(selected?.selection == .candidate)
  try blocked { _ = try second.registerCaptureIntent(identity: id, owner: owner, expectedVersion: 2, sequence: 3, bytes: Data([3])) }
  try blocked { _ = try second.capture(identity: id, owner: owner, expectedVersion: 2, sequence: 3, bytes: Data([3])) }
  try blocked { _ = try second.recoverIdle(identity: id) }
  var db: OpaquePointer?; precondition(sqlite3_open(path, &db) == SQLITE_OK); defer { sqlite3_close(db) }
  var statement: OpaquePointer?; precondition(sqlite3_prepare_v2(db, "SELECT count(*) FROM snapshots", -1, &statement, nil) == SQLITE_OK); defer { sqlite3_finalize(statement) }
  precondition(sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_int(statement, 0) == 2, "earlier snapshot lost")
  let pendingPath = "/private/tmp/invoice-selection-precommit-\(UUID().uuidString).sqlite"
  let pending = try InvoiceTransactionFence(path: pendingPath)
  let pendingIntent = try pending.registerCaptureIntent(identity: id, owner: owner, expectedVersion: nil, sequence: 1, bytes: Data([5]))
  do { try pending.recordRecoverySelection(identity: id, selection: .previous, decisionID: UUID(), authorize: { true }); fatalError("missing previous snapshot selected") } catch InvoiceFenceError.conflict { }
  try pending.recordRecoverySelection(identity: id, selection: .candidate, decisionID: UUID(), authorize: { true })
  do { try pending.commitCaptureIntent(pendingIntent); fatalError("capture changed after choice") } catch InvoiceFenceError.conflict { }
  print("unresolved capture fenced across instances; previous snapshot retained")
 }
}
