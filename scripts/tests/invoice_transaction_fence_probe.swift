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
  let recoveryDomain = InvoiceFenceDomain(origin: key.origin, organizationID: key.organizationID, invoiceID: UUID().uuidString.lowercased())
  let actor = UUID().uuidString.lowercased(), customer = UUID().uuidString.lowercased(), job = UUID().uuidString.lowercased()
  let identity = InvoiceIdleCaptureIdentity(domain: recoveryDomain, actorID: actor, customerID: customer, jobID: job)
  let firstCapture = try a.capture(identity: identity, owner: owner, expectedVersion: nil, sequence: 1, bytes: Data("first".utf8))
  let reopened = try InvoiceTransactionFence(path: path)
  let recovery = try reopened.recoverIdle(identity: identity)
  precondition(recovery?.owner == owner && recovery?.version == firstCapture && recovery?.sequence == 1 && recovery?.bytes == Data("first".utf8))
  do { _ = try reopened.loadIdle(domain: recoveryDomain, owner: owner); preconditionFailure("identity bypass") } catch { }
  let secondCapture = try b.capture(identity: identity, owner: owner, expectedVersion: firstCapture, sequence: 2, bytes: Data("second".utf8))
  do { _ = try a.capture(identity: identity, owner: owner, expectedVersion: secondCapture, sequence: 1, bytes: Data("stale".utf8)); preconditionFailure("older sequence accepted") } catch { }
  let newest = try reopened.recoverIdle(identity: identity)
  precondition(newest?.sequence == 2 && newest?.bytes == Data("second".utf8))
  let raceCaptureDomain = InvoiceFenceDomain(origin: key.origin, organizationID: key.organizationID, invoiceID: UUID().uuidString.lowercased())
  let raceIdentity = InvoiceIdleCaptureIdentity(domain: raceCaptureDomain, actorID: actor, customerID: customer, jobID: job)
  let raceVersion = try a.capture(identity: raceIdentity, owner: owner, expectedVersion: nil, sequence: 1, bytes: Data("start".utf8))
  let captureResults = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
   group.addTask { (try? a.capture(identity: raceIdentity, owner: owner, expectedVersion: raceVersion, sequence: 2, bytes: Data("second".utf8))) != nil }
   group.addTask { (try? b.capture(identity: raceIdentity, owner: owner, expectedVersion: raceVersion, sequence: 3, bytes: Data("third".utf8))) != nil }
   var result: [Bool] = []; for await value in group { result.append(value) }; return result
  }
  precondition(captureResults.filter { $0 }.count == 1)
  var raceRecovery = try reopened.recoverIdle(identity: raceIdentity)!
  if raceRecovery.sequence == 2 {
   _ = try a.capture(identity: raceIdentity, owner: owner, expectedVersion: raceRecovery.version, sequence: 3, bytes: Data("third".utf8))
   raceRecovery = try reopened.recoverIdle(identity: raceIdentity)!
  }
  precondition(raceRecovery.sequence == 3 && raceRecovery.bytes == Data("third".utf8))
  let wrongIdentity = InvoiceIdleCaptureIdentity(domain: recoveryDomain, actorID: UUID().uuidString.lowercased(), customerID: customer, jobID: job)
  do { _ = try reopened.recoverIdle(identity: wrongIdentity); preconditionFailure("wrong identity disclosed") } catch { }
  do { _ = try a.save(domain: recoveryDomain, owner: owner, expectedVersion: secondCapture, bytes: Data("bypass".utf8)); preconditionFailure("unsequenced overwrite") } catch { }
  _ = try a.begin(domain: recoveryDomain, owner: owner, expectedVersion: secondCapture, kind: .directUnknown, command: Data("unknown direct".utf8))
  do { _ = try reopened.recoverIdle(identity: identity); preconditionFailure("uncertain draft disclosed") } catch { }
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
