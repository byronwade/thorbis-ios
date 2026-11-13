import Foundation
import SQLite3

@main struct Probe {
 static func main() async throws {
  let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("invoice-fence-\(UUID().uuidString).sqlite").path
  defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
  let a = try InvoiceTransactionFence(path: path), b = try InvoiceTransactionFence(path: path)
  let key = InvoiceFenceDomain(origin: "https://app.thorbis.com", organizationID: "00000000-0000-4000-8000-000000000001", invoiceID: "00000000-0000-4000-8000-000000000002")
  let owner = UUID(), draft = Data("raw draft".utf8), command = Data("immutable command".utf8)
  let version = try a.save(domain: key, owner: owner, expectedVersion: nil, bytes: draft)
  let next = try b.begin(domain: key, owner: owner, expectedVersion: version, kind: .keyed, command: command)
  precondition(next > version)
  let pending = try a.pending(domain: key)
  precondition(pending == .keyed)
  do { _ = try a.save(domain: key, owner: owner, expectedVersion: version, bytes: Data("lost".utf8)); preconditionFailure("stale write accepted") } catch { }
  do { _ = try b.loadIdle(domain: key, owner: owner); preconditionFailure("pending draft disclosed") } catch { }
  let restarted = try InvoiceTransactionFence(path: path)
  let recovered = try restarted.pending(domain: key)
  precondition(recovered == .keyed)
  let directKey = InvoiceFenceDomain(origin: key.origin, organizationID: key.organizationID, invoiceID: UUID().uuidString.lowercased())
  let directVersion = try a.save(domain: directKey, owner: owner, expectedVersion: nil, bytes: draft)
  _ = try a.begin(domain: directKey, owner: owner, expectedVersion: directVersion, kind: .directUnknown, command: Data("unknown direct".utf8))
  let direct = try restarted.pending(domain: directKey)
  precondition(direct == .directUnknown)
  do { _ = try b.begin(domain: directKey, owner: owner, expectedVersion: directVersion, kind: .keyed, command: command); preconditionFailure("direct uncertainty replaced") } catch { }
  for _ in 0..<30 {
   let raceKey = InvoiceFenceDomain(origin: key.origin, organizationID: key.organizationID, invoiceID: UUID().uuidString.lowercased())
   let original = try a.save(domain: raceKey, owner: owner, expectedVersion: nil, bytes: draft)
   let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
    group.addTask { (try? a.begin(domain: raceKey, owner: owner, expectedVersion: original, kind: .keyed, command: command)) != nil }
    group.addTask { (try? b.save(domain: raceKey, owner: owner, expectedVersion: original, bytes: Data("new".utf8))) != nil }
    var result: [Bool] = []; for await value in group { result.append(value) }; return result
   }
   precondition(results.filter { $0 }.count == 1)
   let status = try restarted.pending(domain: raceKey)
   if status != nil { do { _ = try a.loadIdle(domain: raceKey, owner: owner); preconditionFailure("pending disclosed") } catch { } }
   else { let saved = try a.loadIdle(domain: raceKey, owner: owner); precondition(saved == Data("new".utf8)) }
  }
  let actorKey = InvoiceFenceDomain(origin: key.origin, organizationID: key.organizationID, invoiceID: UUID().uuidString.lowercased())
  let owner2 = UUID()
  let competing = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
   group.addTask { (try? a.save(domain: actorKey, owner: owner, expectedVersion: nil, bytes: Data("actor 1".utf8))) != nil }
   group.addTask { (try? b.save(domain: actorKey, owner: owner2, expectedVersion: nil, bytes: Data("actor 2".utf8))) != nil }
   var result: [Bool] = []; for await value in group { result.append(value) }; return result
  }
  precondition(competing.filter { $0 }.count == 1)
  let failureKey = InvoiceFenceDomain(origin: key.origin, organizationID: key.organizationID, invoiceID: UUID().uuidString.lowercased())
  var db: OpaquePointer?
  precondition(sqlite3_open(path, &db) == SQLITE_OK)
  precondition(sqlite3_exec(db, "CREATE TRIGGER fail_snapshot BEFORE INSERT ON snapshots BEGIN SELECT RAISE(ABORT, 'injected'); END", nil, nil, nil) == SQLITE_OK)
  sqlite3_close(db)
  do { _ = try a.save(domain: failureKey, owner: owner, expectedVersion: nil, bytes: draft); preconditionFailure("failed transaction accepted") } catch { }
  let missing = try b.loadIdle(domain: failureKey, owner: owner)
  precondition(missing == nil)
  print("30 concurrent save/begin races and injected rollback passed")
  print("invoice transaction fence basic restart passed")
 }
}
