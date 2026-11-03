import Foundation
import Combine

@MainActor final class OwnerTestStore: CustomerQuarantineStore {
    var records: [CustomerQuarantineScope: CustomerQuarantineState] = [:]
    var failWrites = false
    var failReads = false
    func read(_ scope: CustomerQuarantineScope) throws -> CustomerQuarantineState? {
        if failReads { throw CustomerQuarantineError.storage }
        return records[scope]
    }
    func write(_ state: CustomerQuarantineState, for scope: CustomerQuarantineScope) throws {
        if failWrites { throw CustomerQuarantineError.storage }
        records[scope] = state
    }
}

@main struct OwnerHarness {
    @MainActor static func main() async throws {
        let scope = try CustomerQuarantineScope(actorID: "abcdefab-0000-4000-8000-000000000001", organizationID: "abcdefab-0000-4000-8000-000000000002", origin: "https://app.thorbis.com", customerID: "abcdefab-0000-4000-8000-000000000003")
        let authority = CustomerQuarantineAuthority(actorID: scope.actorID, organizationID: scope.organizationID, origin: scope.origin, policyVersion: 1, serverGeneration: "test", capabilities: ["customer.view"], features: ["core_crm": true], deadline: Date().addingTimeInterval(3600))
        let sessionID = UUID()
        let store = OwnerTestStore()
        let quarantine = CustomerQuarantine(store: store)
        let owner = CustomerGuardedReadOwner<String>(quarantine: quarantine)
        var ownerEvents = 0
        let ownerObserver = owner.$snapshot.dropFirst().sink { _ in ownerEvents += 1 }
        do {
            try await owner.refresh(scope: scope, authority: authority, sessionID: sessionID, isCurrent: { true }) {
                guard CustomerGuardedTransport.liveOnly, CustomerGuardedTransport.namespace != nil else {
                    throw CustomerGuardedReadError.transportNotScoped
                }
                return CustomerGuardedValue(value: "Authorized", evidence: .completeLive)
            }
        } catch {
            print("FAIL: owner did not provide scoped live transport")
            exit(1)
        }
        guard owner.visibleValue(scope: scope, authority: authority, sessionID: sessionID) == "Authorized" else { print("FAIL: authorized result was not published"); exit(1) }
        guard ownerEvents > 0 else { print("FAIL: owner did not publish loaded value"); exit(1) }
        let anotherOwner = CustomerGuardedReadOwner<String>(quarantine: quarantine)
        var revisionEvents = 0
        let observer = quarantine.$revision.dropFirst().sink { _ in revisionEvents += 1 }
        do {
            try await anotherOwner.refresh(scope: scope, authority: authority, sessionID: sessionID, isCurrent: { true }) {
                throw CustomerGuardedReadError.denied
            }
        } catch { }
        guard owner.visibleValue(scope: scope, authority: authority, sessionID: sessionID) == nil else {
            print("FAIL: denial in another owner left the old value visible"); exit(1)
        }
        guard owner.snapshot == nil else { print("FAIL: denial did not publish a cleared snapshot"); exit(1) }
        guard revisionEvents > 0 else { print("FAIL: denial did not publish invalidation"); exit(1) }
        withExtendedLifetime(observer) { }
        withExtendedLifetime(ownerObserver) { }
        var resumeFirst: CheckedContinuation<Void, Never>?
        let first = Task { @MainActor in
            try await owner.refresh(scope: scope, authority: authority, sessionID: sessionID, isCurrent: { true }) {
                await withCheckedContinuation { resumeFirst = $0 }
                return CustomerGuardedValue(value: "Old", evidence: .completeLive)
            }
        }
        while resumeFirst == nil { await Task.yield() }
        do {
            try await owner.refresh(scope: scope, authority: authority, sessionID: sessionID, isCurrent: { true }) {
                CustomerGuardedValue(value: "New", evidence: .completeLive)
            }
        } catch { }
        resumeFirst?.resume()
        _ = try? await first.value
        guard owner.visibleValue(scope: scope, authority: authority, sessionID: sessionID) != "Old" else { print("FAIL: superseded request published old data"); exit(1) }
        do {
            try await owner.refresh(scope: scope, authority: authority, sessionID: sessionID, isCurrent: { true }) {
                throw CustomerGuardedReadError.denied
            }
            print("FAIL: denied read succeeded"); exit(1)
        } catch { }
        guard owner.visibleValue(scope: scope, authority: authority, sessionID: sessionID) == nil, store.records[scope]?.denied == true else {
            print("FAIL: denial did not retire visible data and persist denial"); exit(1)
        }
        do {
            try await owner.refresh(scope: scope, authority: authority, sessionID: sessionID, isCurrent: { false }) {
                CustomerGuardedValue(value: "Wrong session", evidence: .completeLive)
            }
            print("FAIL: stale session succeeded"); exit(1)
        } catch { }
        guard owner.visibleValue(scope: scope, authority: authority, sessionID: sessionID) == nil else { print("FAIL: stale session was published"); exit(1) }
        do {
            try await owner.refresh(scope: scope, authority: authority, sessionID: sessionID, isCurrent: { true }) {
                guard CustomerGuardedTransport.liveOnly else { throw CustomerGuardedReadError.transportNotScoped }
                return CustomerGuardedValue(value: "Offline copy", evidence: .cached)
            }
            print("FAIL: cached result accepted after denial"); exit(1)
        } catch { }
        guard owner.visibleValue(scope: scope, authority: authority, sessionID: sessionID) == nil else { print("FAIL: offline result was published after denial"); exit(1) }
        let otherScope = try CustomerQuarantineScope(actorID: scope.actorID, organizationID: scope.organizationID, origin: scope.origin, customerID: "abcdefab-0000-4000-8000-000000000004")
        resumeFirst = nil
        let previous = Task { @MainActor in
            try await owner.refresh(scope: scope, authority: authority, sessionID: sessionID, isCurrent: { true }) {
                await withCheckedContinuation { resumeFirst = $0 }
                return CustomerGuardedValue(value: "Previous customer", evidence: .completeLive)
            }
        }
        while resumeFirst == nil { await Task.yield() }
        try await owner.refresh(scope: otherScope, authority: authority, sessionID: sessionID, isCurrent: { true }) {
            CustomerGuardedValue(value: "Current customer", evidence: .completeLive)
        }
        resumeFirst?.resume()
        _ = try? await previous.value
        guard owner.visibleValue(scope: otherScope, authority: authority, sessionID: sessionID) == "Current customer" else { print("FAIL: previous scope cleared current customer"); exit(1) }
        guard owner.visibleValue(scope: otherScope, authority: authority, sessionID: sessionID) == "Current customer" else {
            print("FAIL: current scope lost its value"); exit(1)
        }
        do {
            try await owner.refresh(scope: scope, authority: authority, sessionID: sessionID, isCurrent: { false }) {
                CustomerGuardedValue(value: "Retired", evidence: .completeLive)
            }
        } catch { }
        guard owner.visibleValue(scope: otherScope, authority: authority, sessionID: sessionID) == "Current customer" else {
            print("FAIL: stale queued refresh cleared current customer"); exit(1)
        }
        guard owner.visibleValue(scope: scope, authority: authority, sessionID: sessionID) == nil else {
            print("FAIL: value leaked across scopes"); exit(1)
        }
        let changedAuthority = CustomerQuarantineAuthority(actorID: scope.actorID, organizationID: scope.organizationID, origin: scope.origin, policyVersion: 2, serverGeneration: "test", capabilities: ["customer.view"], features: ["core_crm": true], deadline: Date().addingTimeInterval(3600))
        guard owner.visibleValue(scope: otherScope, authority: changedAuthority, sessionID: sessionID) == nil else {
            print("FAIL: changed authority reused old value"); exit(1)
        }
        guard owner.visibleValue(scope: otherScope, authority: authority, sessionID: UUID()) == nil else {
            print("FAIL: replaced session reused old value"); exit(1)
        }
        owner.invalidate()
        guard owner.visibleValue(scope: otherScope, authority: authority, sessionID: sessionID) == nil else {
            print("FAIL: invalidation kept the value"); exit(1)
        }
        store.failWrites = true
        do {
            try await owner.refresh(scope: otherScope, authority: authority, sessionID: sessionID, isCurrent: { true }) {
                CustomerGuardedValue(value: "Unrecorded", evidence: .completeLive)
            }
            print("FAIL: storage failure was accepted"); exit(1)
        } catch { }
        guard owner.visibleValue(scope: otherScope, authority: authority, sessionID: sessionID) == nil else {
            print("FAIL: storage failure published a value"); exit(1)
        }
        let readStore = OwnerTestStore()
        let readGuard = CustomerQuarantine(store: readStore)
        let readOwner = CustomerGuardedReadOwner<String>(quarantine: readGuard)
        try await readOwner.refresh(scope: scope, authority: authority, sessionID: sessionID, isCurrent: { true }) {
            CustomerGuardedValue(value: "Prior value", evidence: .completeLive)
        }
        readStore.failReads = true
        _ = try? readGuard.begin(otherScope, authority: authority)
        await Task.yield()
        guard readOwner.snapshot == nil else { print("FAIL: read error kept snapshot"); exit(1) }
        readStore.failReads = false
        let retry = try readGuard.begin(scope, authority: authority)
        guard retry.requiresLive else { print("FAIL: read error allowed offline retry"); exit(1) }
        let expiring = CustomerQuarantineAuthority(actorID: scope.actorID, organizationID: scope.organizationID, origin: scope.origin, policyVersion: 1, serverGeneration: "test", capabilities: ["customer.view"], features: ["core_crm": true], deadline: Date().addingTimeInterval(0.2))
        let expiryOwner = CustomerGuardedReadOwner<String>(quarantine: CustomerQuarantine(store: OwnerTestStore()))
        try await expiryOwner.refresh(scope: scope, authority: expiring, sessionID: sessionID, isCurrent: { true }) {
            CustomerGuardedValue(value: "Expiring", evidence: .completeLive)
        }
        expiryOwner.recheckDeadline(now: expiring.deadline.addingTimeInterval(1))
        guard expiryOwner.snapshot == nil else { print("FAIL: clock change retained expired value"); exit(1) }
        try await expiryOwner.refresh(scope: scope, authority: expiring, sessionID: sessionID, isCurrent: { true }) {
            CustomerGuardedValue(value: "Expiring", evidence: .completeLive)
        }
        try await Task.sleep(for: .milliseconds(350))
        guard expiryOwner.snapshot == nil else { print("FAIL: expired snapshot stayed published"); exit(1) }
        print("PASS: guarded owner publishes a current, fully verified read")
    }
}
