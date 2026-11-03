import Foundation

@MainActor final class TestQuarantineStore: CustomerQuarantineStore {
    var records: [CustomerQuarantineScope: CustomerQuarantineState] = [:]
    var failRead = false
    var failWrite = false
    func read(_ scope: CustomerQuarantineScope) throws -> CustomerQuarantineState? {
        if failRead { throw TestFailure.storage }
        return records[scope]
    }
    func write(_ state: CustomerQuarantineState, for scope: CustomerQuarantineScope) throws {
        if failWrite { throw TestFailure.storage }
        records[scope] = state
    }
}

enum TestFailure: Error { case storage }

@main struct QuarantineHarness {
    @MainActor static func main() throws {
        let scope = try CustomerQuarantineScope(actorID: "abcdefab-0000-4000-8000-000000000001", organizationID: "abcdefab-0000-4000-8000-000000000002", origin: "https://app.thorbis.com", customerID: "abcdefab-0000-4000-8000-000000000003")
        if CommandLine.arguments.count == 3 {
            if CommandLine.arguments[1] == "--try-lease" {
                do {
                    _ = try CustomerQuarantineLease(url: URL(fileURLWithPath: CommandLine.arguments[2]))
                    print("FAIL: another process acquired the active lease")
                    exit(1)
                } catch {
                    print("PASS: another process cannot acquire the active lease")
                    return
                }
            }
            let store = KeychainCustomerQuarantineStore(service: CommandLine.arguments[2])
            let guardState = CustomerQuarantine(store: store)
            let ticket = try guardState.begin(scope)
            if CommandLine.arguments[1] == "--write-pending" {
                guard ticket.requiresLive else { print("FAIL: first adoption did not require online verification"); exit(1) }
                print("PASS: first process left a pending marker")
                return
            }
            if CommandLine.arguments[1] == "--read-pending" {
                guard ticket.requiresLive else { print("FAIL: a new process did not see pending work"); exit(1) }
                print("PASS: new process requires a live read")
                return
            }
            print("FAIL: unknown harness mode")
            exit(1)
        }
        let store = TestQuarantineStore()
        let first = CustomerQuarantine(store: store)
        let pending = try first.begin(scope)
        guard pending.requiresLive else { print("FAIL: first adoption did not require online verification"); exit(1) }
        guard store.records[scope]?.pending.contains(pending.id) == true else {
            print("FAIL: request starts without a durable pending marker")
            exit(1)
        }
        print("PASS: pending marker precedes customer reads")
        let upgradeStore = TestQuarantineStore()
        let upgrade = CustomerQuarantine(store: upgradeStore)
        let overviewOnly = try upgrade.begin(scope)
        _ = try upgrade.finish(overviewOnly, outcome: .liveActivity)
        let laterCompilation = try upgrade.begin(scope)
        guard laterCompilation.requiresLive else {
            print("FAIL: overview-only verification unlocked legacy customer cache")
            exit(1)
        }
        print("PASS: overview-only verification does not unlock compilation")
        let afterCrash = CustomerQuarantine(store: store)
        let retry = try afterCrash.begin(scope)
        guard retry.requiresLive, retry.cacheEpoch != pending.cacheEpoch else {
            print("FAIL: a request interrupted by a crash allowed offline reuse")
            exit(1)
        }
        print("PASS: interrupted reads require a live check after relaunch")
        let concurrentStore = TestQuarantineStore()
        let concurrent = CustomerQuarantine(store: concurrentStore)
        let firstRead = try concurrent.begin(scope)
        let secondRead = try concurrent.begin(scope)
        let firstPublish = try concurrent.finish(firstRead, outcome: .liveCompilation)
        guard concurrentStore.records[scope]?.pending.contains(secondRead.id) == true else {
            print("FAIL: one successful read cleared another pending read")
            exit(1)
        }
        guard !firstPublish else {
            print("FAIL: a result published while another scoped read was unresolved")
            exit(1)
        }
        guard try !concurrent.finish(secondRead, outcome: .denied) else { print("FAIL: denied read was publishable"); exit(1) }
        guard concurrentStore.records[scope]?.denied == true else {
            print("FAIL: a denied read did not persist quarantine")
            exit(1)
        }
        let recovery = try CustomerQuarantine(store: concurrentStore).begin(scope)
        guard recovery.requiresLive else { print("FAIL: denial was not durable"); exit(1) }
        print("PASS: concurrent denial survives a different successful read")
        let orderedStore = TestQuarantineStore()
        let ordered = CustomerQuarantine(store: orderedStore)
        let slower = try ordered.begin(scope)
        let faster = try ordered.begin(scope)
        let fasterMayPublish = try ordered.finish(faster, outcome: .liveActivity)
        let slowerMayPublish = try ordered.finish(slower, outcome: .liveCompilation)
        guard !fasterMayPublish && slowerMayPublish else {
            print("FAIL: two successful overlapping reads left no publishable result")
            exit(1)
        }
        print("PASS: the final successful overlapping read may publish")
        let mixedStore = TestQuarantineStore()
        let mixed = CustomerQuarantine(store: mixedStore)
        let upperScope = try CustomerQuarantineScope(actorID: "ABCDEFAB-0000-4000-8000-000000000001", organizationID: "ABCDEFAB-0000-4000-8000-000000000002", origin: "HTTPS://APP.THORBIS.COM", customerID: "ABCDEFAB-0000-4000-8000-000000000003")
        let lowerTicket = try mixed.begin(scope)
        let upperTicket = try mixed.begin(upperScope)
        _ = try mixed.finish(lowerTicket, outcome: .liveCompilation)
        guard mixedStore.records[scope]?.pending.contains(upperTicket.id) == true else {
            print("FAIL: equivalent scope spellings lost a pending read")
            exit(1)
        }
        print("PASS: equivalent scope spellings share the same pending set")
        let slashStore = TestQuarantineStore()
        let slash = CustomerQuarantine(store: slashStore)
        let withSlash = try CustomerQuarantineScope(actorID: scope.actorID, organizationID: scope.organizationID, origin: "https://app.thorbis.com/", customerID: scope.customerID)
        let noSlashTicket = try slash.begin(scope)
        let slashTicket = try slash.begin(withSlash)
        _ = try slash.finish(noSlashTicket, outcome: .liveCompilation)
        guard slashStore.records[scope]?.pending.contains(slashTicket.id) == true else {
            print("FAIL: equivalent origin spellings lost a pending read")
            exit(1)
        }
        print("PASS: equivalent origin spellings share the same pending set")
        let withPort = try CustomerQuarantineScope(actorID: scope.actorID, organizationID: scope.organizationID, origin: "https://app.thorbis.com:443/", customerID: scope.customerID)
        guard withPort == scope else { print("FAIL: default port split an origin"); exit(1) }
        do {
            _ = try CustomerQuarantineScope(actorID: "invalid", organizationID: scope.organizationID, origin: scope.origin, customerID: scope.customerID)
            print("FAIL: invalid actor identity was accepted")
            exit(1)
        } catch { }
        do {
            _ = try CustomerQuarantineScope(actorID: scope.actorID, organizationID: scope.organizationID, origin: "https://app.thorbis.com/path", customerID: scope.customerID)
            print("FAIL: non-origin URL was accepted")
            exit(1)
        } catch { print("PASS: malformed scope identities and origins are rejected") }
        let raceStore = TestQuarantineStore()
        let race = CustomerQuarantine(store: raceStore)
        let olderSuccess = try race.begin(scope)
        let newerDenial = try race.begin(scope)
        guard try !race.finish(newerDenial, outcome: .denied) else { print("FAIL: denied read was publishable"); exit(1) }
        guard try !race.finish(olderSuccess, outcome: .liveCompilation) else { print("FAIL: stale success was publishable"); exit(1) }
        guard raceStore.records[scope]?.denied == true else {
            print("FAIL: an older success cleared a later denial")
            exit(1)
        }
        print("PASS: stale success cannot clear a newer denial")
        let epochStore = TestQuarantineStore()
        let epochGuard = CustomerQuarantine(store: epochStore)
        let beforeDenial = try epochGuard.begin(scope)
        let otherScope = try CustomerQuarantineScope(actorID: scope.actorID, organizationID: scope.organizationID, origin: scope.origin, customerID: "abcdefab-0000-4000-8000-000000000004")
        let otherVerification = try epochGuard.begin(otherScope)
        guard try epochGuard.finish(otherVerification, outcome: .liveCompilation) else { print("FAIL: unrelated customer could not be verified"); exit(1) }
        let otherBefore = try epochGuard.begin(otherScope)
        guard try epochGuard.finish(otherBefore, outcome: .cached) else { print("FAIL: unrelated customer could not use its cache"); exit(1) }
        _ = try epochGuard.finish(beforeDenial, outcome: .denied)
        let afterDenial = try epochGuard.begin(scope)
        let otherAfter = try epochGuard.begin(otherScope)
        guard beforeDenial.cacheNamespace != afterDenial.cacheNamespace else {
            print("FAIL: denial reused the old customer cache generation")
            exit(1)
        }
        guard otherBefore.cacheNamespace == otherAfter.cacheNamespace else {
            print("FAIL: denial changed an unrelated customer's cache generation")
            exit(1)
        }
        print("PASS: denial retires the previous customer cache generation")
        let authorityStore = TestQuarantineStore()
        let authorityGuard = CustomerQuarantine(store: authorityStore)
        let broad = CustomerQuarantineAuthority(actorID: scope.actorID, organizationID: scope.organizationID, origin: scope.origin, policyVersion: 1, serverGeneration: "generation", capabilities: ["customer.view", "job.view"], features: ["jobs": true], deadline: Date().addingTimeInterval(3600))
        let narrow = CustomerQuarantineAuthority(actorID: scope.actorID, organizationID: scope.organizationID, origin: scope.origin, policyVersion: 1, serverGeneration: "generation", capabilities: ["customer.view"], features: ["jobs": false], deadline: Date().addingTimeInterval(3600))
        let verified = try authorityGuard.begin(scope, authority: broad)
        guard try authorityGuard.finish(verified, outcome: .liveCompilation) else { print("FAIL: initial authority verification failed"); exit(1) }
        let underNarrowAuthority = try authorityGuard.begin(scope, authority: narrow)
        guard underNarrowAuthority.requiresLive, underNarrowAuthority.cacheNamespace != verified.cacheNamespace else {
            print("FAIL: changed role or features reused a broader cache")
            exit(1)
        }
        print("PASS: changed authority requires a new live cache generation")
        let restartAuthorityStore = TestQuarantineStore()
        let originalCoordinator = CustomerQuarantine(store: restartAuthorityStore)
        let originalGrant = try originalCoordinator.begin(scope, authority: broad)
        _ = try originalCoordinator.finish(originalGrant, outcome: .liveCompilation)
        let restartedCoordinator = CustomerQuarantine(store: restartAuthorityStore)
        let downgradedAfterRestart = try restartedCoordinator.begin(scope, authority: narrow)
        guard downgradedAfterRestart.requiresLive, downgradedAfterRestart.cacheNamespace != originalGrant.cacheNamespace else {
            print("FAIL: downgraded authority reused cache after coordinator restart")
            exit(1)
        }
        print("PASS: changed authority rotates the cache after coordinator restart")
        let expiryStore = TestQuarantineStore()
        let expiryGuard = CustomerQuarantine(store: expiryStore)
        let shortAuthority = CustomerQuarantineAuthority(actorID: scope.actorID, organizationID: scope.organizationID, origin: scope.origin, policyVersion: 1, serverGeneration: "expiring", capabilities: [], features: [:], deadline: Date().addingTimeInterval(0.05))
        let expiringRead = try expiryGuard.begin(scope, authority: shortAuthority)
        Thread.sleep(forTimeInterval: 0.08)
        guard try !expiryGuard.finish(expiringRead, outcome: .liveCompilation) else { print("FAIL: expired authority published a result"); exit(1) }
        guard expiryStore.records[scope]?.compilationVerified == false else { print("FAIL: expired authority verified offline cache"); exit(1) }
        do {
            _ = try expiryGuard.begin(scope, authority: shortAuthority)
            print("FAIL: an expired authority started a read")
            exit(1)
        } catch { print("PASS: expired authority cannot start or publish reads") }
        let expiryAfterGrantStore = TestQuarantineStore()
        let expiryAfterGrant = CustomerQuarantine(store: expiryAfterGrantStore)
        let longGrant = CustomerQuarantineAuthority(actorID: scope.actorID, organizationID: scope.organizationID, origin: scope.origin, policyVersion: 1, serverGeneration: "same", capabilities: [], features: [:], deadline: Date().addingTimeInterval(3600))
        let firstGrant = try expiryAfterGrant.begin(scope, authority: longGrant)
        _ = try expiryAfterGrant.finish(firstGrant, outcome: .liveCompilation)
        let shortGrant = CustomerQuarantineAuthority(actorID: scope.actorID, organizationID: scope.organizationID, origin: scope.origin, policyVersion: 1, serverGeneration: "same", capabilities: [], features: [:], deadline: Date().addingTimeInterval(0.05))
        let expiringAfterGrant = try expiryAfterGrant.begin(scope, authority: shortGrant)
        Thread.sleep(forTimeInterval: 0.08)
        _ = try expiryAfterGrant.finish(expiringAfterGrant, outcome: .liveCompilation)
        let renewed = try expiryAfterGrant.begin(scope, authority: longGrant)
        guard renewed.requiresLive, renewed.cacheNamespace != firstGrant.cacheNamespace else {
            print("FAIL: expired in-flight authority left an older verified cache reusable")
            exit(1)
        }
        print("PASS: an expired in-flight authority retires previously verified cache")
        let unavailable = TestQuarantineStore()
        unavailable.failWrite = true
        do {
            _ = try CustomerQuarantine(store: unavailable).begin(scope)
            print("FAIL: a request started after durable storage failed")
            exit(1)
        } catch { print("PASS: failed marker writes prevent the read") }
        let failureStore = TestQuarantineStore()
        let beforeFailure = CustomerQuarantine(store: failureStore)
        let inFlight = try beforeFailure.begin(scope)
        failureStore.failWrite = true
        do {
            _ = try beforeFailure.finish(inFlight, outcome: .denied)
            print("FAIL: failed denial persistence was treated as success")
            exit(1)
        } catch { }
        failureStore.failWrite = false
        let afterFailure = CustomerQuarantine(store: failureStore)
        let retryAfterFailure = try afterFailure.begin(scope)
        guard retryAfterFailure.requiresLive else { print("FAIL: failed denial write lost quarantine"); exit(1) }
        guard try afterFailure.finish(retryAfterFailure, outcome: .liveCompilation) else { print("FAIL: fresh recovery was not publishable"); exit(1) }
        let authorized = try afterFailure.begin(scope)
        guard authorized.requiresLive else { print("FAIL: recovered scope reused offline data without relationship proof"); exit(1) }
        print("PASS: recovered scope keeps requiring live relationship verification")
        let sameProcessStore = TestQuarantineStore()
        let sameProcess = CustomerQuarantine(store: sameProcessStore)
        let outstanding = try sameProcess.begin(scope)
        sameProcessStore.failWrite = true
        do { _ = try sameProcess.finish(outstanding, outcome: .denied); print("FAIL: denial write unexpectedly succeeded"); exit(1) }
        catch { }
        sameProcessStore.failWrite = false
        _ = try sameProcess.finish(outstanding, outcome: .uncertain)
        let sameProcessRetry = try sameProcess.begin(scope)
        guard sameProcessRetry.requiresLive else { print("FAIL: in-process retry lost quarantine"); exit(1) }
        _ = try sameProcess.finish(sameProcessRetry, outcome: .liveCompilation)
        let sameProcessAuthorized = try sameProcess.begin(scope)
        guard sameProcessAuthorized.requiresLive else { print("FAIL: in-process recovery enabled unverified offline relationships"); exit(1) }
        print("PASS: in-process recovery preserves live relationship requirement")
        failureStore.failRead = true
        do {
            _ = try afterFailure.begin(scope)
            print("FAIL: a read started while marker storage was unavailable")
            exit(1)
        } catch { print("PASS: failed marker reads prevent the request") }
        let uncertainStore = TestQuarantineStore()
        let uncertain = CustomerQuarantine(store: uncertainStore)
        let canceled = try uncertain.begin(scope)
        let publishCanceled = try uncertain.finish(canceled, outcome: .uncertain)
        let retryCanceled = try uncertain.begin(scope)
        guard !publishCanceled, retryCanceled.requiresLive else {
            print("FAIL: an uncertain canceled read allowed offline reuse")
            exit(1)
        }
        print("PASS: cancellation requires fresh authorization")
        let partialStore = TestQuarantineStore()
        let partial = CustomerQuarantine(store: partialStore)
        let denied = try partial.begin(scope)
        _ = try partial.finish(denied, outcome: .denied)
        let overview = try partial.begin(scope)
        _ = try partial.finish(overview, outcome: .liveActivity)
        guard partialStore.records[scope]?.denied == true else {
            print("FAIL: a partial activity read cleared a compilation denial")
            exit(1)
        }
        let offline = try partial.begin(scope)
        do {
            _ = try partial.finish(offline, outcome: .cached)
            print("FAIL: a blocked ticket published cached data")
            exit(1)
        } catch {
            guard partialStore.records[scope]?.pending.contains(offline.id) == false else {
                print("FAIL: rejected cached data stranded an active ticket")
                exit(1)
            }
            let sameProcessRecovery = try partial.begin(scope)
            guard sameProcessRecovery.requiresLive else { print("FAIL: cached rejection cleared quarantine"); exit(1) }
            _ = try partial.finish(sameProcessRecovery, outcome: .liveCompilation)
            print("PASS: partial activity and offline copies cannot clear denial")
        }
        let keychain = KeychainCustomerQuarantineStore(service: "com.thorbis.field.test-quarantine.\(UUID().uuidString)")
        var persistentState = CustomerQuarantineState()
        persistentState.denied = true
        try keychain.write(persistentState, for: scope)
        guard try keychain.read(scope)?.denied == true else {
            print("FAIL: durable adapter did not restore the denial")
            exit(1)
        }
        print("PASS: durable adapter restores denial")
        let leasePath = FileManager.default.temporaryDirectory.appendingPathComponent("thorbis-quarantine-\(UUID().uuidString).lock")
        let firstLease = try CustomerQuarantineLease(url: leasePath)
        do {
            _ = try CustomerQuarantineLease(url: leasePath)
            print("FAIL: two coordinators acquired the same exclusive lease")
            exit(1)
        } catch { print("PASS: a second coordinator cannot acquire the active lease") }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--try-lease", leasePath.path]
        try child.run()
        child.waitUntilExit()
        guard child.terminationStatus == 0 else { print("FAIL: cross-process lease test failed"); exit(1) }
        withExtendedLifetime(firstLease) {}
        let factoryPath = FileManager.default.temporaryDirectory.appendingPathComponent("thorbis-quarantine-retry-\(UUID().uuidString).lock")
        var occupied: CustomerQuarantineLease? = try CustomerQuarantineLease(url: factoryPath)
        let factory = CustomerQuarantineFactory(store: TestQuarantineStore(), leaseURL: factoryPath)
        guard factory.acquire() == nil else { print("FAIL: busy lease was ignored"); exit(1) }
        occupied = nil
        guard factory.acquire() != nil else { print("FAIL: coordinator could not retry after lease release"); exit(1) }
        withExtendedLifetime(occupied) {}
        print("PASS: unavailable lease can be retried without restarting")
    }
}
