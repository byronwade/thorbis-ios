import Foundation
@main struct ProcessCheck {
 @MainActor static func main() throws {
  let args = CommandLine.arguments
  let scope = TapRecoveryScope(origin: "https://api.example", organization: "org", actor: "actor", invoice: "invoice")
  let store = TapRecoveryStore(url: URL(fileURLWithPath: args[2]))
  if args[1] == "write" { try store.begin(scope: scope, amount: 1234, currency: "USD") }
  else {
   let pending = try store.pending(scope: scope)
   guard let pending, pending.amount == 1234, pending.attemptID == nil else { fatalError("hold lost") }
   print("hold restored in separate process")
  }
 }
}
