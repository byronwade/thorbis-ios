import Foundation
@main struct CoordinatorChecks {
 @MainActor static func main() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let url = root.appendingPathComponent("holds.json")
  let scope = TapRecoveryScope(origin: "https://app.thorbis.com", organization: "018f0000-0000-7000-8000-00000000000a", actor: "018f0000-0000-7000-8000-00000000000b", invoice: "018f0000-0000-7000-8000-00000000000c")
  let job = "018f0000-0000-7000-8000-00000000000d"
  let attempt = "018f0000-0000-7000-8000-00000000000e"
  var admitted = 0
  let broken = TapRecoveryCoordinator(store: TapRecoveryStore(url: root.appendingPathComponent("missing/holds.json")))
  let failedSave = await broken.start(scope: scope, jobID: job, amount: 100, currency: "USD", authorized: { true }, termsCurrent: { true }) { _ in admitted += 1; throw URLError(.timedOut) }
  precondition(failedSave == .unresolved && admitted == 0)
  let stale = TapRecoveryCoordinator(store: TapRecoveryStore(url: root.appendingPathComponent("stale.json")))
  let staleResult = await stale.start(scope: scope, jobID: job, amount: 100, currency: "USD", authorized: { true }, termsCurrent: { false }) { _ in admitted += 1; throw URLError(.timedOut) }
  precondition(staleResult == .unresolved && admitted == 0)
  let coordinator = TapRecoveryCoordinator(store: TapRecoveryStore(url: url))
  let started = await coordinator.start(scope: scope, jobID: job, amount: 100, currency: "USD", authorized: { true }, termsCurrent: { true }) { operation in
   admitted += 1
   let saved = try TapRecoveryStore(url: url).pending(scope: scope)
   precondition(saved?.operationID == operation && saved?.jobID == job)
   throw URLError(.timedOut)
  }
  precondition(started == .unresolved && admitted == 1)
  let restarted = TapRecoveryCoordinator(store: TapRecoveryStore(url: url))
  let pending = try TapRecoveryStore(url: url).pending(scope: scope)!
  precondition(UUID(uuidString: pending.operationID) != nil && pending.jobID == job)
  let anotherStart = await restarted.start(scope: scope, jobID: job, amount: 100, currency: "USD", authorized: { true }, termsCurrent: { true }) { _ in admitted += 1; throw URLError(.timedOut) }
  precondition(anotherStart == .unresolved && admitted == 1)
  let otherActor = TapRecoveryScope(origin: scope.origin, organization: scope.organization, actor: "018f0000-0000-7000-8000-00000000000f", invoice: scope.invoice)
  var foreignReads = 0
  let otherActorResult = await restarted.check(scope: otherActor, authorized: { true }) { _ in foreignReads += 1; throw URLError(.timedOut) }
  precondition(otherActorResult == .unresolved && foreignReads == 0)
  let noStatus = await restarted.check(scope: scope, authorized: { true }) { _ in throw URLError(.cannotConnectToHost) }
  precondition(noStatus == .unresolved)
  let badOp = await restarted.check(scope: scope, authorized: { true }) { _ in
   .init(operationID: UUID().uuidString, jobID: job, attemptID: attempt, amount: 100, currency: "USD", status: .recorded)
  }
  precondition(badOp == .unresolved)
  let wrongAmount = await restarted.check(scope: scope, authorized: { true }) { op in
   .init(operationID: op, jobID: job, attemptID: attempt, amount: 99, currency: "USD", status: .recorded)
  }
  precondition(wrongAmount == .unresolved)
  var authorized = true
  let revoked = await restarted.check(scope: scope, authorized: { authorized }) { op in
   authorized = false
   return .init(operationID: op, jobID: job, attemptID: attempt, amount: 100, currency: "USD", status: .recorded)
  }
  precondition(revoked == .unresolved)
  let afterRevocation = try TapRecoveryStore(url: url).pending(scope: scope); precondition(afterRevocation?.attemptID == nil)
  let stillPending = await restarted.check(scope: scope, authorized: { true }) { op in
   .init(operationID: op, jobID: job, attemptID: attempt, amount: 100, currency: "USD", status: .pending)
  }
  precondition(stillPending == .unresolved)
  let bound = try TapRecoveryStore(url: url).pending(scope: scope); precondition(bound?.attemptID == attempt)
  let wrongAttempt = await restarted.check(scope: scope, authorized: { true }) { op in
   .init(operationID: op, jobID: job, attemptID: UUID().uuidString, amount: 100, currency: "USD", status: .recorded)
  }
  precondition(wrongAttempt == .unresolved)
  let wrong = await restarted.check(scope: scope, authorized: { true }) { op in
   .init(operationID: op, jobID: "018f0000-0000-7000-8000-00000000000f", attemptID: attempt, amount: 100, currency: "USD", status: .recorded)
  }
  precondition(wrong == .unresolved)
  let stillHeld = try TapRecoveryStore(url: url).isHeld(scope: scope); precondition(stillHeld)
  let paid = await restarted.check(scope: scope, authorized: { true }) { op in
   .init(operationID: op, jobID: job, attemptID: attempt, amount: 100, currency: "USD", status: .recorded)
  }
  precondition(paid == .recorded)
  let held = try TapRecoveryStore(url: url).isHeld(scope: scope); precondition(!held)
  print("tap recovery coordinator checks passed")
 }
}
