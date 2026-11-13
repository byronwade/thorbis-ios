import Foundation
import Darwin

@main struct CrashProbe {
 static let domain = InvoiceFenceDomain(origin: "https://thorbis.com", organizationID: "00000000-0000-4000-8000-000000000001", invoiceID: "00000000-0000-4000-8000-000000000002")
 static let identity = InvoiceIdleCaptureIdentity(domain: domain, actorID: "00000000-0000-4000-8000-000000000003", customerID: "00000000-0000-4000-8000-000000000004", jobID: nil)
 static let owner = UUID(uuidString: "00000000-0000-4000-8000-000000000005")!
 static func spawn(_ path: String, _ mode: String) throws -> Process {
  let p = Process(); p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); p.arguments = [mode, path]
  p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; try p.run(); return p
 }
 static func main() throws {
  let args = CommandLine.arguments
  if args.count == 3 {
   let f = try InvoiceTransactionFence(path: args[2])
   do {
    let token = try f.registerCaptureIntent(identity: identity, owner: owner, expectedVersion: nil, sequence: 1, bytes: Data([42]))
    if args[1] == "commit-kill" || args[1] == "choice-kill" { try f.commitCaptureIntent(token) }
    if args[1] == "choice-kill" { try f.recordRecoverySelection(identity: identity, selection: .candidate, decisionID: UUID(uuidString: "00000000-0000-4000-8000-000000000009")!, authorize: { true }) }
    if args[1] != "register" { kill(getpid(), SIGKILL) }
   } catch { exit(3) }
   exit(0)
  }
  let clean = try InvoiceTransactionFence(path: "/private/tmp/invoice-intent-clean-\(UUID().uuidString).sqlite")
  _ = try clean.registerCaptureIntent(identity: identity, owner: owner, expectedVersion: nil, sequence: 1, bytes: Data([42]))
  for phase in ["intent-kill", "commit-kill", "choice-kill"] {
   let path = "/private/tmp/invoice-intent-crash-\(UUID().uuidString).sqlite"
   let p = try spawn(path, phase); p.waitUntilExit(); precondition(p.terminationReason == .uncaughtSignal)
   let f = try InvoiceTransactionFence(path: path)
   let evidence = try f.inspectUnresolvedCapture(identity: identity)
   precondition(evidence?.phase == (phase == "intent-kill" ? .registered : .committed) && evidence?.bytes == Data([42]))
   if phase == "choice-kill" {
    precondition(evidence?.selection == .candidate)
    try f.recordRecoverySelection(identity: identity, selection: .candidate, decisionID: UUID(uuidString: "00000000-0000-4000-8000-000000000009")!, authorize: { true })
    do { try f.recordRecoverySelection(identity: identity, selection: .candidate, decisionID: UUID(), authorize: { true }); fatalError("different decision accepted") } catch InvoiceFenceError.conflict { }
   }
   do { _ = try f.registerCaptureIntent(identity: identity, owner: owner, expectedVersion: phase == "intent-kill" ? nil : 1, sequence: 2, bytes: Data([43])); fatalError("crash left fence open") } catch InvoiceFenceError.pending { }
   do { _ = try f.recoverIdle(identity: identity); fatalError("uncertain recovery allowed") } catch InvoiceFenceError.pending { }
   do { _ = try f.begin(domain: domain, owner: owner, expectedVersion: 1, kind: .directUnknown, command: Data([1])); fatalError("uncertain submission allowed") } catch InvoiceFenceError.pending { }
  }
  let path = "/private/tmp/invoice-intent-race-\(UUID().uuidString).sqlite"
  _ = try InvoiceTransactionFence(path: path)
  let a = try spawn(path, "register"), b = try spawn(path, "register"); a.waitUntilExit(); b.waitUntilExit()
  precondition([a.terminationStatus,b.terminationStatus].sorted() == [0,3])
  print("intent and capture process deaths remain fenced; one concurrent writer admitted")
 }
}
