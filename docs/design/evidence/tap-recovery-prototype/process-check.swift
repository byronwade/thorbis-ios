import Foundation
@main struct ProcessCheck {
 @MainActor static func main() throws {
  let args = CommandLine.arguments
  let scope = TapRecoveryScope(origin: "https://app.thorbis.com", organization: "018f0000-0000-7000-8000-00000000001a", actor: "018f0000-0000-7000-8000-00000000001b", invoice: "018f0000-0000-7000-8000-00000000001c")
  let store = TapRecoveryStore(url: URL(fileURLWithPath: args[2]))
  if args[1] == "write" { _ = try store.begin(scope: scope, jobID: scope.invoice, amount: 1234, currency: "USD") }
  else {
   let pending = try store.pending(scope: scope)
   guard let pending, pending.amount == 1234, pending.attemptID == nil, pending.jobID == scope.invoice, UUID(uuidString: pending.operationID) != nil else { fatalError("hold lost") }
   print("hold restored in separate process")
  }
 }
}
