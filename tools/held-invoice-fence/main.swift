import Foundation
import Darwin

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--crash-after-begin" {
    let childFence = InvoiceReadFence(directory: URL(fileURLWithPath: CommandLine.arguments[2]))
    let childScope = InvoiceReadFence.Scope(actor: "018f0000-0000-7000-8000-000000000001", organization: "018f0000-0000-7000-8000-000000000002", origin: "https://example.invalid", invoice: "018f0000-0000-7000-8000-000000000005", resource: "invoice")
    _ = try childFence.begin(childScope)
    Darwin._exit(0)
}

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--hold-transport" {
    let childFence = InvoiceReadFence(directory: URL(fileURLWithPath: CommandLine.arguments[2]))
    let childScope = InvoiceReadFence.Scope(actor: "018f0000-0000-7000-8000-000000000001", organization: "018f0000-0000-7000-8000-000000000002", origin: "https://example.invalid", invoice: "018f0000-0000-7000-8000-000000000006", resource: "invoice")
    let attempt = try childFence.begin(childScope)
    FileHandle.standardOutput.write(Data("READY".utf8))
    _ = FileHandle.standardInput.readDataToEndOfFile()
    _ = try attempt.finish(.denied)
    exit(0)
}

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--deny-publication-race" {
    let childFence = InvoiceReadFence(directory: URL(fileURLWithPath: CommandLine.arguments[2]))
    let childScope = InvoiceReadFence.Scope(actor: "018f0000-0000-7000-8000-000000000001", organization: "018f0000-0000-7000-8000-000000000002", origin: "https://example.invalid", invoice: "018f0000-0000-7000-8000-000000000007", resource: "invoice")
    let attempt = try childFence.begin(childScope)
    _ = try attempt.finish(.denied)
    exit(0)
}

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--probe-publication-lock" {
    let childFence = InvoiceReadFence(directory: URL(fileURLWithPath: CommandLine.arguments[2]))
    let childScope = InvoiceReadFence.Scope(actor: "018f0000-0000-7000-8000-000000000001", organization: "018f0000-0000-7000-8000-000000000002", origin: "https://example.invalid", invoice: "018f0000-0000-7000-8000-000000000007", resource: "invoice")
    do { _ = try childFence.begin(childScope); exit(2) } catch { exit(0) }
}

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--crash-during-cache-write" {
    let childFence = InvoiceReadFence(directory: URL(fileURLWithPath: CommandLine.arguments[2]))
    let childScope = InvoiceReadFence.Scope(actor: "018f0000-0000-7000-8000-000000000001", organization: "018f0000-0000-7000-8000-000000000002", origin: "https://example.invalid", invoice: "018f0000-0000-7000-8000-000000000008", resource: "invoice")
    let data = Data("after crash".utf8)
    let attempt = try childFence.begin(childScope)
    guard case let .committed(receipt) = try attempt.finish(.liveSuccess(data)) else { exit(2) }
    _ = try childFence.withCacheWrite(childScope, receipt: receipt, payload: data) { bytes in
        try bytes.write(to: URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("cached-document-test"), options: .atomic)
        Darwin._exit(0)
    }
    exit(3)
}

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--probe-parent-presentation" {
    let childFence = InvoiceReadFence(directory: URL(fileURLWithPath: CommandLine.arguments[2]))
    let childScope = InvoiceReadFence.Scope(actor: "018f0000-0000-7000-8000-000000000001", organization: "018f0000-0000-7000-8000-000000000002", origin: "https://example.invalid", invoice: "018f0000-0000-7000-8000-000000000006", resource: "invoice")
    do { _ = try childFence.begin(childScope); exit(2) } catch { exit(0) }
}

let livePayload = Data("verified response".utf8)
let dir = FileManager.default.temporaryDirectory.appendingPathComponent("invoice-fence-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: dir) }
let fence = InvoiceReadFence(directory: dir)
let scope = InvoiceReadFence.Scope(actor: "018f0000-0000-7000-8000-000000000001", organization: "018f0000-0000-7000-8000-000000000002", origin: "https://example.invalid", invoice: "018f0000-0000-7000-8000-000000000003", resource: "invoice")
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
require(!fence.cacheAllowed(scope, payload: livePayload), "unverified scope must start held")
let initial = try fence.begin(scope)
require(!fence.cacheAllowed(scope, payload: livePayload), "live read must hold cache")
let initialResult = try initial.finish(.liveSuccess(livePayload))
if case .committed = initialResult {} else { require(false, "complete live success must explicitly commit") }
func receipt(_ completion: InvoiceReadFence.Completion) -> InvoiceReadFence.Receipt {
    guard case let .committed(receipt) = completion else { fatalError("expected committed result") }
    return receipt
}
require(fence.cacheAllowed(scope, payload: livePayload), "isolated complete live success can authorize cache")
let failed = try fence.begin(scope)
let offlineCompletion = try failed.finish(.connectivityFailure)
require(offlineCompletion == .restored, "connectivity restoration must not issue a live-write receipt")
require(fence.cacheAllowed(scope, payload: livePayload), "isolated connectivity failure can restore prior grant")
let first = try fence.begin(scope)
var refusedOverlap = false
do { _ = try fence.begin(scope) } catch { refusedOverlap = true }
require(refusedOverlap, "a competing transport must not start")
let denialResult = try first.finish(.denied)
require(denialResult == .denied, "denial must be explicit")
require(!fence.cacheAllowed(scope, payload: livePayload), "denial must hold the saved copy")
let fresh = try fence.begin(scope)
_ = try fresh.finish(.liveSuccess(livePayload))
require(fence.cacheAllowed(scope, payload: livePayload), "new isolated live read may recover")
let crashScope = InvoiceReadFence.Scope(actor: scope.actor, organization: scope.organization, origin: scope.origin, invoice: "018f0000-0000-7000-8000-000000000005", resource: "invoice")
let crashInitial = try fence.begin(crashScope)
_ = try crashInitial.finish(.liveSuccess(livePayload))
require(fence.cacheAllowed(crashScope, payload: livePayload), "crash setup must be authorized")
let child = Process()
child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
child.arguments = ["--crash-after-begin", dir.path]
try child.run()
child.waitUntilExit()
require(child.terminationStatus == 0, "child must reach durable hold")
require(!fence.cacheAllowed(crashScope, payload: livePayload), "crash after preflight must leave cache held")
let crashRecover = try fence.begin(crashScope)
_ = try crashRecover.finish(.connectivityFailure)
require(!fence.cacheAllowed(crashScope, payload: livePayload), "offline after crash cannot recover old grant")
let crashLive = try fence.begin(crashScope)
_ = try crashLive.finish(.liveSuccess(livePayload))
require(fence.cacheAllowed(crashScope, payload: livePayload), "fresh live read can recover after crash")
let sharedScope = InvoiceReadFence.Scope(actor: scope.actor, organization: scope.organization, origin: scope.origin, invoice: "018f0000-0000-7000-8000-000000000006", resource: "invoice")
let sharedHistory = InvoiceReadFence.Scope(actor: scope.actor, organization: scope.organization, origin: scope.origin, invoice: sharedScope.invoice, resource: "history")
let initialInvoice = try fence.begin(sharedScope)
_ = try initialInvoice.finish(.liveSuccess(livePayload))
let initialHistory = try fence.begin(sharedHistory)
_ = try initialHistory.finish(.liveSuccess(livePayload))
require(fence.cacheAllowed(sharedHistory, payload: livePayload), "history starts authorized under its invoice")
let parentOffline = try fence.begin(sharedScope)
_ = try parentOffline.finish(.connectivityFailure)
require(fence.cacheAllowed(sharedHistory, payload: livePayload), "isolated parent connectivity failure preserves verified history")
let otherActor = InvoiceReadFence.Scope(actor: "018f0000-0000-7000-8000-00000000000a", organization: scope.organization, origin: scope.origin, invoice: sharedScope.invoice, resource: "invoice")
let otherOrg = InvoiceReadFence.Scope(actor: scope.actor, organization: "018f0000-0000-7000-8000-00000000000b", origin: scope.origin, invoice: sharedScope.invoice, resource: "invoice")
let otherOrigin = InvoiceReadFence.Scope(actor: scope.actor, organization: scope.organization, origin: "https://other.invalid", invoice: sharedScope.invoice, resource: "invoice")
require(!fence.cacheAllowed(otherActor, payload: livePayload) && !fence.cacheAllowed(otherOrg, payload: livePayload) && !fence.cacheAllowed(otherOrigin, payload: livePayload), "scope changes never inherit a grant")
let invalid = InvoiceReadFence.Scope(actor: "invalid", organization: scope.organization, origin: scope.origin, invoice: sharedScope.invoice, resource: "invoice")
var invalidRejected = false
do { _ = try fence.begin(invalid) } catch { invalidRejected = true }
require(invalidRejected, "invalid scope cannot start a request")
let holder = Process()
let input = Pipe(), output = Pipe()
holder.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
holder.arguments = ["--hold-transport", dir.path]
holder.standardInput = input; holder.standardOutput = output
try holder.run()
require(String(data: output.fileHandleForReading.readData(ofLength: 5), encoding: .utf8) == "READY", "child lease started")
var blockedByProcess = false
do { _ = try fence.begin(sharedScope) } catch { blockedByProcess = true }
require(blockedByProcess, "another process must not start an overlapping transport")
require(!fence.cacheAllowed(sharedHistory, payload: livePayload), "pending invoice read must also hold its history")
var blockedHistory = false
do { _ = try fence.begin(sharedHistory) } catch { blockedHistory = true }
require(blockedHistory, "history cannot start while parent invoice is held")
input.fileHandleForWriting.closeFile()
holder.waitUntilExit()
require(holder.terminationStatus == 0, "child denial finished")
require(!fence.cacheAllowed(sharedScope, payload: livePayload), "cross-process denial leaves invoice held")
require(!fence.cacheAllowed(sharedHistory, payload: livePayload), "invoice denial must also hold its history")
// Delayed cache publication must not reuse an earlier authorization after a
// different process has retired the resource.
let publicationRaceScope = InvoiceReadFence.Scope(actor: scope.actor, organization: scope.organization, origin: scope.origin, invoice: "018f0000-0000-7000-8000-000000000007", resource: "invoice")
let publicationInitial = try fence.begin(publicationRaceScope)
let oldReceipt = receipt(try publicationInitial.finish(.liveSuccess(livePayload)))
require(fence.cacheAllowed(publicationRaceScope, payload: livePayload), "publication setup starts clean")
let denialProcess = Process()
denialProcess.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
denialProcess.arguments = ["--deny-publication-race", dir.path]
try denialProcess.run()
denialProcess.waitUntilExit()
require(denialProcess.terminationStatus == 0, "independent process denied invoice")
var publishedStale = false
_ = try fence.withCacheWrite(publicationRaceScope, receipt: oldReceipt, payload: livePayload) { _ in publishedStale = true }
require(!publishedStale, "a stale authorization must not publish after cross-process denial")
let newerRecovery = try fence.begin(publicationRaceScope)
_ = try newerRecovery.finish(.liveSuccess(livePayload))
var delayedOldWrite = false
_ = try fence.withCacheWrite(publicationRaceScope, receipt: oldReceipt, payload: livePayload) { _ in delayedOldWrite = true }
require(!delayedOldWrite, "old response must not publish under the newer authorization epoch")
let resetRace = try fence.begin(publicationRaceScope)
_ = try resetRace.finish(.denied)
let writeRecovery = try fence.begin(publicationRaceScope)
let currentReceipt = receipt(try writeRecovery.finish(.liveSuccess(livePayload)))
var wrongScopeWrite = false
_ = try fence.withCacheWrite(scope, receipt: currentReceipt, payload: livePayload) { _ in wrongScopeWrite = true }
require(!wrongScopeWrite, "receipt cannot authorize a different invoice")
let alteredPayload = Data("different response".utf8)
var wroteAltered = false
_ = try fence.withCacheWrite(publicationRaceScope, receipt: currentReceipt, payload: alteredPayload) { _ in
    _ = alteredPayload
    wroteAltered = true
}
require(!wroteAltered, "a receipt must not authorize different response bytes")
var publishedFresh = false
let wrote = try fence.withCacheWrite(publicationRaceScope, receipt: currentReceipt, payload: livePayload) { bytes in
    require(bytes == livePayload, "writer receives exact verified bytes")
    let contender = Process()
    contender.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    contender.arguments = ["--probe-publication-lock", dir.path]
    try contender.run()
    contender.waitUntilExit()
    require(contender.terminationStatus == 0, "cross-process preflight must not overlap publication")
    publishedFresh = true
}
require(wrote && publishedFresh, "current clean scope can publish")
enum InjectedWriteError: Error { case failed }
var threwWrite = false
do { _ = try fence.withCacheWrite(publicationRaceScope, receipt: currentReceipt, payload: livePayload) { _ in throw InjectedWriteError.failed } } catch { threwWrite = true }
require(threwWrite, "cache failure must reach caller")
require(!fence.cacheAllowed(publicationRaceScope, payload: livePayload), "failed cache write leaves a durable hold")
let restoredInvoice = try fence.begin(sharedScope)
_ = try restoredInvoice.finish(.liveSuccess(livePayload))
require(!fence.cacheAllowed(sharedHistory, payload: livePayload), "invoice recovery must not restore old history")
let verifiedHistory = try fence.begin(sharedHistory)
_ = try verifiedHistory.finish(.liveSuccess(livePayload))
require(fence.cacheAllowed(sharedHistory, payload: livePayload), "history needs its own fresh verification")
var historyVisible = false
let wrongHistory = try fence.present(sharedHistory, payload: Data("not history".utf8)) { historyVisible = true }
require(wrongHistory == nil && !historyVisible, "wrong history bytes cannot be displayed")
let historyPresentation = try fence.present(sharedHistory, payload: livePayload) { historyVisible = true }
require(historyPresentation != nil && historyVisible, "current history has a presentation lease")
let parentProbe = Process()
parentProbe.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
parentProbe.arguments = ["--probe-parent-presentation", dir.path]
try parentProbe.run()
parentProbe.waitUntilExit()
require(parentProbe.terminationStatus == 0, "history presentation blocks parent invoice preflight")
historyPresentation!.retire { historyVisible = false }
require(!historyVisible, "history is cleared before its parent lease is released")
let historyBeforeChange = try fence.begin(sharedHistory)
let oldHistoryReceipt = receipt(try historyBeforeChange.finish(.liveSuccess(livePayload)))
let parentNewEpoch = try fence.begin(sharedScope)
_ = try parentNewEpoch.finish(.liveSuccess(livePayload))
let historyAfterChange = try fence.begin(sharedHistory)
_ = try historyAfterChange.finish(.liveSuccess(livePayload))
var delayedHistoryWrite = false
_ = try fence.withCacheWrite(sharedHistory, receipt: oldHistoryReceipt, payload: livePayload) { _ in delayedHistoryWrite = true }
require(!delayedHistoryWrite, "old history cannot publish after parent and history epochs change")
let pendingHistory = try fence.begin(sharedHistory)
let denyingParent = try fence.begin(sharedScope)
_ = try denyingParent.finish(.denied)
let deniedParentResult = try pendingHistory.finish(.liveSuccess(livePayload))
require(deniedParentResult == .held, "parent denial must return an explicit held result")
require(!fence.cacheAllowed(sharedHistory, payload: livePayload), "parent denial must prevent history publication")
let parentRecovery = try fence.begin(sharedScope)
_ = try parentRecovery.finish(.liveSuccess(livePayload))
let pendingChangedHistory = try fence.begin(sharedHistory)
let changedParent = try fence.begin(sharedScope)
_ = try changedParent.finish(.liveSuccess(livePayload))
let changedParentResult = try pendingChangedHistory.finish(.liveSuccess(livePayload))
require(changedParentResult == .held, "parent epoch change must return an explicit held result")
require(!fence.cacheAllowed(sharedHistory, payload: livePayload), "changed parent must prevent old history publication")
let failedDeny = try fence.begin(scope)
require(chmod(dir.path, 0o500) == 0, "set read-only cache directory")
var denialWriteFailed = false
do { _ = try failedDeny.finish(.denied) } catch { denialWriteFailed = true }
require(chmod(dir.path, 0o700) == 0, "restore directory access")
require(denialWriteFailed, "denial marker write failure must be observable")
require(!fence.cacheAllowed(scope, payload: livePayload), "failed denial write must leave preflight hold")
let offlineRetry = try fence.begin(scope)
_ = try offlineRetry.finish(.connectivityFailure)
require(!fence.cacheAllowed(scope, payload: livePayload), "offline retry cannot undo failed denial")
let onlineRetry = try fence.begin(scope)
_ = try onlineRetry.finish(.liveSuccess(livePayload))
require(fence.cacheAllowed(scope, payload: livePayload), "new live read may recover a held scope")
let presentationInitial = try fence.begin(publicationRaceScope)
_ = try presentationInitial.finish(.liveSuccess(livePayload))
var displayed = false
let presentation = try fence.present(publicationRaceScope, payload: livePayload) { displayed = true }
require(presentation != nil && displayed, "validated content is published with a lease")
let presentationContender = Process()
presentationContender.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
presentationContender.arguments = ["--probe-publication-lock", dir.path]
try presentationContender.run()
presentationContender.waitUntilExit()
require(presentationContender.terminationStatus == 0, "cross-process refresh cannot start while content is displayed")
presentation!.retire { displayed = false }
let presentationDenial = Process()
presentationDenial.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
presentationDenial.arguments = ["--deny-publication-race", dir.path]
try presentationDenial.run()
presentationDenial.waitUntilExit()
require(presentationDenial.terminationStatus == 0, "denial can proceed after retirement")
require(!displayed, "content is cleared before the denial request begins")
var stalePresented = false
let deniedPresentation = try fence.present(publicationRaceScope, payload: livePayload) { stalePresented = true }
require(deniedPresentation == nil && !stalePresented, "denied content cannot be presented")
// An old installed payload must not become readable just because a newer
// live response was authorized before its bytes reached the cache.
let versionedScope = InvoiceReadFence.Scope(actor: scope.actor, organization: scope.organization, origin: scope.origin, invoice: "018f0000-0000-7000-8000-000000000008", resource: "invoice")
let cachedFile = dir.appendingPathComponent("cached-document-test")
let versionA = try fence.begin(versionedScope)
let receiptA = receipt(try versionA.finish(.liveSuccess(livePayload)))
let installedA = try fence.withCacheWrite(versionedScope, receipt: receiptA, payload: livePayload) { try $0.write(to: cachedFile, options: .atomic) }
require(installedA, "A cache installed")
let versionDenial = try fence.begin(versionedScope)
_ = try versionDenial.finish(.denied)
let versionB = try fence.begin(versionedScope)
let newPayload = Data("new response".utf8)
let receiptB = receipt(try versionB.finish(.liveSuccess(newPayload)))
let installedBefore = try Data(contentsOf: cachedFile)
require(!fence.cacheAllowed(versionedScope, payload: installedBefore), "old cached A must not become readable under B before replacement")
let installedB = try fence.withCacheWrite(versionedScope, receipt: receiptB, payload: newPayload) { try $0.write(to: cachedFile, options: .atomic) }
require(installedB, "B cache installed")
let installedAfter = try Data(contentsOf: cachedFile)
require(fence.cacheAllowed(versionedScope, payload: installedAfter), "installed B matches the current grant")
let versionFailure = try fence.begin(versionedScope)
let failedPayload = Data("write failed after replace".utf8)
let failedReceipt = receipt(try versionFailure.finish(.liveSuccess(failedPayload)))
var replacedThenFailed = false
do {
    _ = try fence.withCacheWrite(versionedScope, receipt: failedReceipt, payload: failedPayload) { bytes in
        try bytes.write(to: cachedFile, options: .atomic)
        throw InjectedWriteError.failed
    }
} catch { replacedThenFailed = true }
require(replacedThenFailed, "post-replacement failure is surfaced")
let bytesAfterFailure = try Data(contentsOf: cachedFile)
require(!fence.cacheAllowed(versionedScope, payload: bytesAfterFailure), "failed publication keeps replacement held")
let cacheCrash = Process()
cacheCrash.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
cacheCrash.arguments = ["--crash-during-cache-write", dir.path]
try cacheCrash.run()
cacheCrash.waitUntilExit()
require(cacheCrash.terminationStatus == 0, "child exited during cache publication")
let afterCrash = try Data(contentsOf: cachedFile)
require(afterCrash == Data("after crash".utf8), "child replaced bytes before exit")
require(!fence.cacheAllowed(versionedScope, payload: afterCrash), "interrupted cache write leaves old bytes held")
let missingDir = dir.appendingPathComponent("missing-marker")
let missingFence = InvoiceReadFence(directory: missingDir)
let missingAttempt = try missingFence.begin(scope)
let marker = try FileManager.default.contentsOfDirectory(at: missingDir, includingPropertiesForKeys: nil).first { $0.pathExtension == "json" }
require(marker != nil, "pending marker exists")
try FileManager.default.removeItem(at: marker!)
let missingResult = try missingAttempt.finish(.liveSuccess(livePayload))
require(missingResult == .held, "missing pending marker must not report authorization")
require(!missingFence.cacheAllowed(scope, payload: livePayload), "missing marker cannot authorize a cache")
let abandonedScope = InvoiceReadFence.Scope(actor: scope.actor, organization: scope.organization, origin: scope.origin, invoice: "018f0000-0000-7000-8000-000000000004", resource: "invoice")
var abandoned: InvoiceReadFence.Attempt? = try fence.begin(abandonedScope)
require(abandoned != nil, "attempt created")
abandoned = nil
var blockedAfterDrop = false
do { _ = try fence.begin(abandonedScope) } catch { blockedAfterDrop = true }
require(blockedAfterDrop, "dropping an uncompleted attempt must retain the lease")
print("PASS")
