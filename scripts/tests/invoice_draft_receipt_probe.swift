import Foundation
import SQLite3
final class Outcome: @unchecked Sendable { let lock = NSLock(); var succeeded = 0; func add() { lock.lock(); succeeded += 1; lock.unlock() } }
@main struct ReceiptProbe {
 static func main() throws {
  let args = CommandLine.arguments
  let child = args.contains("--child")
  let path = child ? args[args.firstIndex(of: "--child")! + 1] : URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("invoice-receipt-\(UUID()).sqlite").path
  defer { if !child { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } } }
  let d = InvoiceFenceDomain(origin:"https://app.thorbis.com", organizationID:"00000000-0000-4000-8000-000000000001", invoiceID:"00000000-0000-4000-8000-000000000002")
  let i = InvoiceIdleCaptureIdentity(domain:d,actorID:"00000000-0000-4000-8000-000000000003",customerID:"00000000-0000-4000-8000-000000000004",jobID:nil)
  let f = try InvoiceTransactionFence(path:path), owner = child ? UUID(uuidString: args[args.firstIndex(of: "--child")! + 2])! : UUID()
  if child { do { _ = try f.captureWithReceipt(identity:i,owner:owner,expectedVersion:2,sequence:3,bytes:Data([3])) } catch { exit(75) }; exit(0) }
  let first = try f.captureWithReceipt(identity:i,owner:owner,expectedVersion:nil,sequence:1,bytes:Data([1]))
  let second = try f.captureWithReceipt(identity:i,owner:owner,expectedVersion:first.version,sequence:2,bytes:Data([2]))
  do { try f.acknowledgeCapture(first.receipt); fatalError("stale receipt") } catch {}
  let other = try InvoiceTransactionFence(path:path)
  do { try other.acknowledgeCapture(second.receipt); fatalError("cross-process receipt accepted") } catch {}
  #if INVOICE_FENCE_HOST_TEST
  f.testAmbiguousNextCommit = true
  do { try f.acknowledgeCapture(second.receipt); fatalError("ambiguous prune unexpectedly returned") } catch {}
  #endif
  let outcome = Outcome()
  DispatchQueue.concurrentPerform(iterations: 2) { _ in if (try? f.acknowledgeCapture(second.receipt)) != nil { outcome.add() } }
  precondition(outcome.succeeded == 1)
  do { try f.acknowledgeCapture(second.receipt); fatalError("replayed receipt") } catch {}
  let result = try f.recoverIdle(identity:i); precondition(result?.bytes == Data([2]))
  let p = Process(); p.executableURL = URL(fileURLWithPath: args[0]); p.arguments = ["--child", path, owner.uuidString, "--invoice-fence-test-ambiguous-after-commit"]; try p.run(); p.waitUntilExit(); precondition(p.terminationStatus == 75)
  let ambiguous = try f.recoverIdle(identity:i); precondition(ambiguous?.bytes == Data([3]))
  var db: OpaquePointer?; precondition(sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK); defer { sqlite3_close(db) }; var stmt: OpaquePointer?; precondition(sqlite3_prepare_v2(db, "SELECT count(*) FROM snapshots", -1, &stmt, nil) == SQLITE_OK); defer { sqlite3_finalize(stmt) }; precondition(sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_int(stmt,0) == 2)
  #if INVOICE_FENCE_HOST_TEST
  let entered = DispatchSemaphore(value: 0), resume = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0)
  let lateOutcome = Outcome()
  f.testBeforeReceiptRegistration = { version in if version == 4 { entered.signal(); resume.wait() } }
  DispatchQueue.global().async {
    do { let stale = try f.captureWithReceipt(identity:i, owner:owner, expectedVersion:3, sequence:4, bytes:Data([4])); do { try f.acknowledgeCapture(stale.receipt) } catch { lateOutcome.add() } } catch {}
    done.signal()
  }
  precondition(entered.wait(timeout:.now()+10) == .success)
  let newest = try f.captureWithReceipt(identity:i, owner:owner, expectedVersion:4, sequence:5, bytes:Data([5]))
  try f.acknowledgeCapture(newest.receipt)
  resume.signal(); precondition(done.wait(timeout:.now()+10) == .success)
  precondition(lateOutcome.succeeded == 1 && f.testReceiptCount == 0)
  #endif
  print("process-local receipt and ambiguous capture fence passed")
 }
}
