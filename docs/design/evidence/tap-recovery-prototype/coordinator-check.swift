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
  let lease = TapRecoveryAuthorityLease(scope: scope, sessionGeneration: UUID(), authorityRevision: UUID(), apiGeneration: UUID())
  var admitted = 0
  let broken = TapRecoveryCoordinator(store: TapRecoveryStore(url: root.appendingPathComponent("missing/holds.json")))
  let failedSave = await broken.start(scope: scope, jobID: job, amount: 100, currency: "USD", currentLease: { lease }, termsCurrent: { true }) { _ in admitted += 1; throw URLError(.timedOut) }
  precondition(failedSave == .unresolved && admitted == 0)
  let stale = TapRecoveryCoordinator(store: TapRecoveryStore(url: root.appendingPathComponent("stale.json")))
  let staleResult = await stale.start(scope: scope, jobID: job, amount: 100, currency: "USD", currentLease: { lease }, termsCurrent: { false }) { _ in admitted += 1; throw URLError(.timedOut) }
  precondition(staleResult == .unresolved && admitted == 0)
  let coordinator = TapRecoveryCoordinator(store: TapRecoveryStore(url: url))
  let started = await coordinator.start(scope: scope, jobID: job, amount: 100, currency: "USD", currentLease: { lease }, termsCurrent: { true }) { operation in
   admitted += 1
   let saved = try TapRecoveryStore(url: url).pending(scope: scope)
   precondition(saved?.operationID == operation && saved?.jobID == job)
   throw URLError(.timedOut)
  }
  precondition(started == .unresolved && admitted == 1)
  let restarted = TapRecoveryCoordinator(store: TapRecoveryStore(url: url))
  let pending = try TapRecoveryStore(url: url).pending(scope: scope)!
  precondition(UUID(uuidString: pending.operationID) != nil && pending.jobID == job)
  let anotherStart = await restarted.start(scope: scope, jobID: job, amount: 100, currency: "USD", currentLease: { lease }, termsCurrent: { true }) { _ in admitted += 1; throw URLError(.timedOut) }
  precondition(anotherStart == .unresolved && admitted == 1)
  let otherActor = TapRecoveryScope(origin: scope.origin, organization: scope.organization, actor: "018f0000-0000-7000-8000-00000000000f", invoice: scope.invoice)
  var foreignReads = 0
  let otherActorResult = await restarted.check(scope: otherActor, currentLease: { TapRecoveryAuthorityLease(scope: otherActor, sessionGeneration: lease.sessionGeneration, authorityRevision: lease.authorityRevision, apiGeneration: lease.apiGeneration) }) { _ in foreignReads += 1; throw URLError(.timedOut) }
  precondition(otherActorResult == .unresolved && foreignReads == 0)
  let noStatus = await restarted.check(scope: scope, currentLease: { lease }) { _ in throw URLError(.cannotConnectToHost) }
  precondition(noStatus == .unresolved)
  let badOp = await restarted.check(scope: scope, currentLease: { lease }) { _ in
   .init(operationID: UUID().uuidString, jobID: job, attemptID: attempt, amount: 100, currency: "USD", status: .recorded)
  }
  precondition(badOp == .unresolved)
  let wrongAmount = await restarted.check(scope: scope, currentLease: { lease }) { op in
   .init(operationID: op, jobID: job, attemptID: attempt, amount: 99, currency: "USD", status: .recorded)
  }
  precondition(wrongAmount == .unresolved)
  var authorized = true
  let revoked = await restarted.check(scope: scope, currentLease: { authorized ? lease : nil }) { op in
   authorized = false
   return .init(operationID: op, jobID: job, attemptID: attempt, amount: 100, currency: "USD", status: .recorded)
  }
  precondition(revoked == .unresolved)
  let afterRevocation = try TapRecoveryStore(url: url).pending(scope: scope); precondition(afterRevocation?.attemptID == nil)
  let stillPending = await restarted.check(scope: scope, currentLease: { lease }) { op in
   .init(operationID: op, jobID: job, attemptID: attempt, amount: 100, currency: "USD", status: .pending)
  }
  precondition(stillPending == .unresolved)
  let bound = try TapRecoveryStore(url: url).pending(scope: scope); precondition(bound?.attemptID == attempt)
  let wrongAttempt = await restarted.check(scope: scope, currentLease: { lease }) { op in
   .init(operationID: op, jobID: job, attemptID: UUID().uuidString, amount: 100, currency: "USD", status: .recorded)
  }
  precondition(wrongAttempt == .unresolved)
  let wrong = await restarted.check(scope: scope, currentLease: { lease }) { op in
   .init(operationID: op, jobID: "018f0000-0000-7000-8000-00000000000f", attemptID: attempt, amount: 100, currency: "USD", status: .recorded)
  }
  precondition(wrong == .unresolved)
  let stillHeld = try TapRecoveryStore(url: url).isHeld(scope: scope); precondition(stillHeld)
  let paid = await restarted.check(scope: scope, currentLease: { lease }) { op in
   .init(operationID: op, jobID: job, attemptID: attempt, amount: 100, currency: "USD", status: .recorded)
  }
  precondition(paid == .recorded)
  let held = try TapRecoveryStore(url: url).isHeld(scope: scope); precondition(!held)
  let cancelURL = root.appendingPathComponent("canceled.json")
  let canceledCoordinator = TapRecoveryCoordinator(store: TapRecoveryStore(url: cancelURL))
  let canceledTask = Task { @MainActor in
   await canceledCoordinator.start(scope: scope, jobID: job, amount: 100, currency: "USD", currentLease: { lease }, termsCurrent: { true }) { op in
    withUnsafeCurrentTask { $0?.cancel() }
    return .init(operationID: op, jobID: job, attemptID: attempt, amount: 100, currency: "USD", status: .pending)
   }
  }
  _ = await canceledTask.value
  let canceledHold = try TapRecoveryStore(url: cancelURL).pending(scope: scope)
  precondition(canceledHold != nil && canceledHold?.attemptID == nil, "canceled response bound an attempt")
  let abaURL = root.appendingPathComponent("aba.json")
  let abaCoordinator = TapRecoveryCoordinator(store: TapRecoveryStore(url: abaURL))
  _ = try TapRecoveryStore(url: abaURL).begin(scope: scope, jobID: job, amount: 100, currency: "USD")
  var session = UUID()
  let initialSession = session
  let abaResult = await abaCoordinator.check(scope: scope, currentLease: { TapRecoveryAuthorityLease(scope: scope, sessionGeneration: session, authorityRevision: lease.authorityRevision, apiGeneration: lease.apiGeneration) }) { op in
   session = UUID() // The actor leaves and returns; a Boolean authorization is true again.
   precondition(session != initialSession)
   return .init(operationID: op, jobID: job, attemptID: attempt, amount: 100, currency: "USD", status: .recorded)
  }
  precondition(abaResult == .unresolved, "stale session cleared a hold")
  let abaHold = try TapRecoveryStore(url: abaURL).pending(scope: scope)
  precondition(abaHold != nil && abaHold?.attemptID == nil)
  let cancelCheckURL = root.appendingPathComponent("canceled-check.json")
  _ = try TapRecoveryStore(url: cancelCheckURL).begin(scope: scope, jobID: job, amount: 100, currency: "USD")
  let checkCoordinator = TapRecoveryCoordinator(store: TapRecoveryStore(url: cancelCheckURL))
  let canceledCheck = Task { @MainActor in
   await checkCoordinator.check(scope: scope, currentLease: { lease }) { op in
    withUnsafeCurrentTask { $0?.cancel() }
    return .init(operationID: op, jobID: job, attemptID: attempt, amount: 100, currency: "USD", status: .recorded)
   }
  }
  let canceledCheckResult = await canceledCheck.value
  precondition(canceledCheckResult == .unresolved)
  let canceledCheckHold = try TapRecoveryStore(url: cancelCheckURL).pending(scope: scope)
  precondition(canceledCheckHold != nil && canceledCheckHold?.attemptID == nil, "canceled lookup mutated a hold")
  for field in ["authority", "api"] {
   var current = lease
   let result = await checkCoordinator.check(scope: scope, currentLease: { current }) { op in
    current = TapRecoveryAuthorityLease(scope: scope, sessionGeneration: lease.sessionGeneration,
       authorityRevision: field == "authority" ? UUID() : lease.authorityRevision,
       apiGeneration: field == "api" ? UUID() : lease.apiGeneration)
    return .init(operationID: op, jobID: job, attemptID: attempt, amount: 100, currency: "USD", status: .recorded)
   }
   precondition(result == .unresolved, "changed authority or API generation cleared a hold")
   let hold = try TapRecoveryStore(url: cancelCheckURL).pending(scope: scope)
   precondition(hold != nil && hold?.attemptID == nil)
  }
  print("tap recovery coordinator checks passed")
 }
}
