import Foundation
@main struct Checks {
 @MainActor static func main() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  precondition(APIOrigin.normalized("https://APP.THORBIS.COM/") == "https://app.thorbis.com")
  precondition(APIOrigin.normalized("https://app.thorbis.com/a") == nil)
  precondition(APIOrigin.normalized("https://user@app.thorbis.com") == nil)
  #if DEBUG
  precondition(APIOrigin.normalized("http://localhost:1234/") == "http://localhost:1234")
  #else
  precondition(APIOrigin.normalized("http://localhost:1234/") == nil)
  #endif
  let caseFile = root.appendingPathComponent("case-holds.json")
  let caseStore = TapRecoveryStore(url: caseFile)
  let base = TapRecoveryScope(origin: "https://app.thorbis.com", organization: "018f0000-0000-7000-8000-00000000000a", actor: "018f0000-0000-7000-8000-00000000000b", invoice: "018f0000-0000-7000-8000-00000000000c")
  let alias = TapRecoveryScope(origin: "https://APP.THORBIS.COM/", organization: base.organization.uppercased(), actor: base.actor.uppercased(), invoice: base.invoice.uppercased())
  let caseHold = try caseStore.begin(scope: base, jobID: base.invoice, amount: 100, currency: "USD")
  let matches = try caseStore.isHeld(scope: alias); precondition(matches, "alternate representation bypassed hold")
  let sameOwner = try caseStore.pending(scope: alias); precondition(sameOwner != nil, "alternate owner was not recognized")
  do { _ = try caseStore.begin(scope: alias, jobID: base.invoice, amount: 100, currency: "USD"); fatalError("duplicate representation accepted") } catch {}
  let differentActor = TapRecoveryScope(origin: alias.origin, organization: alias.organization, actor: "018f0000-0000-7000-8000-00000000000f", invoice: alias.invoice)
  let heldForOther = try caseStore.isHeld(scope: differentActor); precondition(heldForOther)
  let otherPending = try caseStore.pending(scope: differentActor); precondition(otherPending == nil)
  for invalid in [
    TapRecoveryScope(origin: "https://app.thorbis.com.evil.example", organization: base.organization, actor: base.actor, invoice: base.invoice),
    TapRecoveryScope(origin: "https://app.thorbis.com:443", organization: base.organization, actor: base.actor, invoice: base.invoice),
    TapRecoveryScope(origin: base.origin, organization: "bad", actor: base.actor, invoice: base.invoice),
    TapRecoveryScope(origin: base.origin, organization: base.organization, actor: "bad", invoice: base.invoice),
    TapRecoveryScope(origin: base.origin, organization: base.organization, actor: base.actor, invoice: "bad"),
  ] { do { _ = try caseStore.isHeld(scope: invalid); fatalError("invalid scope accepted") } catch {} }
  let attempt = "018f0000-0000-7000-8000-00000000000d"
  try caseStore.bindAttempt(scope: alias, operationID: caseHold.operationID, jobID: base.invoice, attemptID: attempt.uppercased())
  try caseStore.bindAttempt(scope: base, operationID: caseHold.operationID, jobID: base.invoice, attemptID: attempt)
  try caseStore.confirmReceipt(scope: alias, operationID: caseHold.operationID, jobID: base.invoice, attemptID: attempt, amount: 100, currency: "USD")
  let duplicateFile = root.appendingPathComponent("duplicate-holds.json")
  try JSONEncoder().encode([TapRecoveryHold(scope: base, operationID: caseHold.operationID, jobID: base.invoice, amount: 100, currency: "USD", attemptID: nil), TapRecoveryHold(scope: alias, operationID: caseHold.operationID, jobID: base.invoice, amount: 100, currency: "USD", attemptID: nil)]).write(to: duplicateFile)
  do { _ = try TapRecoveryStore(url: duplicateFile).isHeld(scope: base); fatalError("duplicate equivalent holds ignored") } catch {}
  let duplicateOperationFile = root.appendingPathComponent("duplicate-operation.json")
  let anotherInvoice = TapRecoveryScope(origin: base.origin, organization: base.organization, actor: base.actor, invoice: "018f0000-0000-7000-8000-00000000000e")
  try JSONEncoder().encode([TapRecoveryHold(scope: base, operationID: caseHold.operationID, jobID: base.invoice, amount: 100, currency: "USD", attemptID: nil), TapRecoveryHold(scope: anotherInvoice, operationID: caseHold.operationID.uppercased(), jobID: base.invoice, amount: 100, currency: "USD", attemptID: nil)]).write(to: duplicateOperationFile)
  do { _ = try TapRecoveryStore(url: duplicateOperationFile).isHeld(scope: base); fatalError("duplicate operation ignored") } catch {}
  let file = root.appendingPathComponent("holds.json")
  let a = TapRecoveryScope(origin: "https://app.thorbis.com", organization: "018f0000-0000-7000-8000-00000000001a", actor: "018f0000-0000-7000-8000-00000000001b", invoice: "018f0000-0000-7000-8000-00000000001c")
  let other = TapRecoveryScope(origin: a.origin, organization: a.organization, actor: "018f0000-0000-7000-8000-00000000001d", invoice: a.invoice)
  let unrelated = TapRecoveryScope(origin: a.origin, organization: a.organization, actor: a.actor, invoice: "018f0000-0000-7000-8000-00000000001e")
  let broken = TapRecoveryStore(url: root.appendingPathComponent("missing").appendingPathComponent("holds.json"))
  do { _ = try broken.begin(scope: a, jobID: a.invoice, amount: 1250, currency: "USD"); fatalError("write failure ignored") } catch {}
  let store = TapRecoveryStore(url: file)
  let savedHold = try store.begin(scope: a, jobID: a.invoice, amount: 1250, currency: "USD")
  let restarted = TapRecoveryStore(url: file)
  let pendingA = try restarted.pending(scope: a); precondition(pendingA?.attemptID == nil)
  let pendingOther = try restarted.pending(scope: other); precondition(pendingOther == nil)
  let heldA = try restarted.isHeld(scope: a); precondition(heldA)
  let heldOther = try restarted.isHeld(scope: other); precondition(heldOther)
  let heldUnrelated = try restarted.isHeld(scope: unrelated); precondition(!heldUnrelated)
  let id = "018f0000-0000-7000-8000-00000000000a"
  try restarted.bindAttempt(scope: a, operationID: savedHold.operationID, jobID: a.invoice, attemptID: id)
  do { try restarted.bindAttempt(scope: a, operationID: savedHold.operationID, jobID: a.invoice, attemptID: "018f0000-0000-7000-8000-00000000000b"); fatalError("rebind accepted") } catch {}
  do { try restarted.confirmReceipt(scope: other, operationID: savedHold.operationID, jobID: a.invoice, attemptID: id, amount: 1250, currency: "USD"); fatalError("wrong actor cleared") } catch {}
  do { try restarted.confirmReceipt(scope: a, operationID: savedHold.operationID, jobID: a.invoice, attemptID: id, amount: 1200, currency: "USD"); fatalError("wrong amount cleared") } catch {}
  try restarted.confirmReceipt(scope: a, operationID: savedHold.operationID, jobID: a.invoice, attemptID: id, amount: 1250, currency: "USD")
  let heldAfter = try TapRecoveryStore(url: file).isHeld(scope: a); precondition(!heldAfter)
  try Data("corrupt".utf8).write(to: file)
  do { _ = try restarted.isHeld(scope: unrelated); fatalError("corruption ignored") } catch {}
  print("tap recovery foundation checks passed")
 }
}
