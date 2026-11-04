import Foundation
@MainActor @main struct Check {
 static func main() {
  let registry = EstimateAutomaticCopies<String>(), auto = UUID(), manual = UUID()
  registry.mark(auto, scope: "job")
  precondition(registry.onlyAutomatic([auto], scope: "job"))
  precondition(!registry.onlyAutomatic([auto, manual], scope: "job"))
  precondition(!registry.onlyAutomatic([auto], scope: "other"))
  registry.promote(auto, scope: "job")
  precondition(!registry.onlyAutomatic([auto], scope: "job"))
  registry.mark(auto, scope: "job")
  precondition(!registry.onlyAutomatic([auto], scope: "job"))
  registry.mark(manual, scope: "job")
  registry.clear()
  precondition(!registry.onlyAutomatic([manual], scope: "job"))
  print("PASS: only automatic scoped copies bypass recovery choices; manual promotion restores choice")
 }
}
