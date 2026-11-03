import Foundation
@main struct Checks {
 @MainActor static func main() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let file = root.appendingPathComponent("holds.json")
  let a = TapRecoveryScope(origin: "https://api.thorbis.com", organization: "org-a", actor: "user-a", invoice: "invoice-a")
  let other = TapRecoveryScope(origin: a.origin, organization: a.organization, actor: "user-b", invoice: a.invoice)
  let unrelated = TapRecoveryScope(origin: a.origin, organization: a.organization, actor: a.actor, invoice: "invoice-b")
  let broken = TapRecoveryStore(url: root.appendingPathComponent("missing").appendingPathComponent("holds.json"))
  do { try broken.begin(scope: a, amount: 1250, currency: "USD"); fatalError("write failure ignored") } catch {}
  let store = TapRecoveryStore(url: file)
  try store.begin(scope: a, amount: 1250, currency: "USD")
  let restarted = TapRecoveryStore(url: file)
  let pendingA = try restarted.pending(scope: a); precondition(pendingA?.attemptID == nil)
  let pendingOther = try restarted.pending(scope: other); precondition(pendingOther == nil)
  let heldA = try restarted.isHeld(scope: a); precondition(heldA)
  let heldOther = try restarted.isHeld(scope: other); precondition(heldOther)
  let heldUnrelated = try restarted.isHeld(scope: unrelated); precondition(!heldUnrelated)
  let id = "018f0000-0000-7000-8000-00000000000a"
  try restarted.bindAttempt(scope: a, attemptID: id)
  do { try restarted.bindAttempt(scope: a, attemptID: "018f0000-0000-7000-8000-00000000000b"); fatalError("rebind accepted") } catch {}
  do { try restarted.confirmReceipt(scope: other, attemptID: id, amount: 1250, currency: "USD"); fatalError("wrong actor cleared") } catch {}
  do { try restarted.confirmReceipt(scope: a, attemptID: id, amount: 1200, currency: "USD"); fatalError("wrong amount cleared") } catch {}
  try restarted.confirmReceipt(scope: a, attemptID: id, amount: 1250, currency: "USD")
  let heldAfter = try TapRecoveryStore(url: file).isHeld(scope: a); precondition(!heldAfter)
  try Data("corrupt".utf8).write(to: file)
  do { _ = try restarted.isHeld(scope: unrelated); fatalError("corruption ignored") } catch {}
  print("tap recovery foundation checks passed")
 }
}
