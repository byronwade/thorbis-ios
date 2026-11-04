import Foundation
struct Scope: Codable, Equatable, Hashable { let actor: String; let job: String }
struct Draft: Codable, Equatable { let text: String }
@MainActor @main struct Check {
 static func main() throws {
  let scope = Scope(actor: "a", job: "1"), other = Scope(actor: "b", job: "2")
  let primary = VolatileDraftRecovery<Scope,Draft>()
  let edits = VolatileDraftRecovery<RecoveryCopyEditKey<Scope>,RecoveryCopyEditState<Draft>>()
  let attempts = EstimateRecoveryCopyAttempts<Scope,Draft>()
  let source = UUID(), session = UUID()
  primary.hold(Draft(text: "one"), for: scope)
  edits.hold(.init(draft: Draft(text: "two"), sessionID: session), for: .init(scope: other, sourceID: source))
  var failed = true; var installed: [UUID:Draft] = [:]
  let first = EstimateTransitionMemory.retire(primary: primary, edits: edits, attempts: attempts) { id, _, draft in
   if failed { throw CocoaError(.fileWriteNoPermission) }; installed[id] = draft
  }
  precondition(!first && primary.read(for: scope)?.text == "one" && edits.read(for: .init(scope: other, sourceID: source))?.draft.text == "two")
  failed = false
  let second = EstimateTransitionMemory.retire(primary: primary, edits: edits, attempts: attempts) { id, _, draft in installed[id] = draft }
  precondition(second && primary.read(for: scope) == nil && edits.read(for: .init(scope: other, sourceID: source)) == nil && installed.count == 2)
  let third = VolatileDraftRecovery<Scope,Draft>()
  let emptyEdits = VolatileDraftRecovery<RecoveryCopyEditKey<Scope>,RecoveryCopyEditState<Draft>>()
  let retryAttempts = EstimateRecoveryCopyAttempts<Scope,Draft>()
  third.hold(Draft(text: "ambiguous"), for: scope)
  var observed: [UUID] = []
  let uncertain = EstimateTransitionMemory.retire(primary: third, edits: emptyEdits, attempts: retryAttempts) { id, _, _ in
   observed.append(id); throw CocoaError(.fileReadUnknown)
  }
  precondition(!uncertain && third.read(for: scope)?.text == "ambiguous")
  let resolved = EstimateTransitionMemory.retire(primary: third, edits: emptyEdits, attempts: retryAttempts) { id, _, _ in observed.append(id) }
  precondition(resolved && observed.count == 3 && observed.allSatisfy { $0 == observed[0] } && third.read(for: scope) == nil)
  let orphanAttempts = EstimateRecoveryCopyAttempts<Scope,Draft>()
  try? orphanAttempts.perform(Draft(text: "pending"), scope: other) { _, _ in throw CocoaError(.fileReadUnknown) }
  third.hold(Draft(text: "still held"), for: scope)
  let orphan = EstimateTransitionMemory.retire(primary: third, edits: emptyEdits, attempts: orphanAttempts) { _, _, _ in throw CocoaError(.fileWriteNoPermission) }
  precondition(!orphan && third.read(for: scope)?.text == "still held")
  let recoveredOrphan = EstimateTransitionMemory.retire(primary: third, edits: emptyEdits, attempts: orphanAttempts) { _, _, _ in }
  precondition(recoveredOrphan && third.read(for: scope) == nil)
  print("PASS: failed, ambiguous and orphan attempts retain memory; confirmed scoped copies retire it")
 }
}
