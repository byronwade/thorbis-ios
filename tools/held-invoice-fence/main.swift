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
    try attempt.finish(.denied)
    exit(0)
}

let dir = FileManager.default.temporaryDirectory.appendingPathComponent("invoice-fence-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: dir) }
let fence = InvoiceReadFence(directory: dir)
let scope = InvoiceReadFence.Scope(actor: "018f0000-0000-7000-8000-000000000001", organization: "018f0000-0000-7000-8000-000000000002", origin: "https://example.invalid", invoice: "018f0000-0000-7000-8000-000000000003", resource: "invoice")
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
require(!fence.cacheAllowed(scope), "unverified scope must start held")
let initial = try fence.begin(scope)
require(!fence.cacheAllowed(scope), "live read must hold cache")
try initial.finish(.liveSuccess)
require(fence.cacheAllowed(scope), "isolated complete live success can authorize cache")
let failed = try fence.begin(scope)
try failed.finish(.connectivityFailure)
require(fence.cacheAllowed(scope), "isolated connectivity failure can restore prior grant")
let first = try fence.begin(scope)
var refusedOverlap = false
do { _ = try fence.begin(scope) } catch { refusedOverlap = true }
require(refusedOverlap, "a competing transport must not start")
try first.finish(.denied)
require(!fence.cacheAllowed(scope), "denial must hold the saved copy")
let fresh = try fence.begin(scope)
try fresh.finish(.liveSuccess)
require(fence.cacheAllowed(scope), "new isolated live read may recover")
let crashScope = InvoiceReadFence.Scope(actor: scope.actor, organization: scope.organization, origin: scope.origin, invoice: "018f0000-0000-7000-8000-000000000005", resource: "invoice")
let crashInitial = try fence.begin(crashScope)
try crashInitial.finish(.liveSuccess)
require(fence.cacheAllowed(crashScope), "crash setup must be authorized")
let child = Process()
child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
child.arguments = ["--crash-after-begin", dir.path]
try child.run()
child.waitUntilExit()
require(child.terminationStatus == 0, "child must reach durable hold")
require(!fence.cacheAllowed(crashScope), "crash after preflight must leave cache held")
let crashRecover = try fence.begin(crashScope)
try crashRecover.finish(.connectivityFailure)
require(!fence.cacheAllowed(crashScope), "offline after crash cannot recover old grant")
let crashLive = try fence.begin(crashScope)
try crashLive.finish(.liveSuccess)
require(fence.cacheAllowed(crashScope), "fresh live read can recover after crash")
let sharedScope = InvoiceReadFence.Scope(actor: scope.actor, organization: scope.organization, origin: scope.origin, invoice: "018f0000-0000-7000-8000-000000000006", resource: "invoice")
let sharedHistory = InvoiceReadFence.Scope(actor: scope.actor, organization: scope.organization, origin: scope.origin, invoice: sharedScope.invoice, resource: "history")
let initialInvoice = try fence.begin(sharedScope)
try initialInvoice.finish(.liveSuccess)
let initialHistory = try fence.begin(sharedHistory)
try initialHistory.finish(.liveSuccess)
require(fence.cacheAllowed(sharedHistory), "history starts authorized under its invoice")
let parentOffline = try fence.begin(sharedScope)
try parentOffline.finish(.connectivityFailure)
require(fence.cacheAllowed(sharedHistory), "isolated parent connectivity failure preserves verified history")
let otherActor = InvoiceReadFence.Scope(actor: "018f0000-0000-7000-8000-00000000000a", organization: scope.organization, origin: scope.origin, invoice: sharedScope.invoice, resource: "invoice")
let otherOrg = InvoiceReadFence.Scope(actor: scope.actor, organization: "018f0000-0000-7000-8000-00000000000b", origin: scope.origin, invoice: sharedScope.invoice, resource: "invoice")
let otherOrigin = InvoiceReadFence.Scope(actor: scope.actor, organization: scope.organization, origin: "https://other.invalid", invoice: sharedScope.invoice, resource: "invoice")
require(!fence.cacheAllowed(otherActor) && !fence.cacheAllowed(otherOrg) && !fence.cacheAllowed(otherOrigin), "scope changes never inherit a grant")
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
require(!fence.cacheAllowed(sharedHistory), "pending invoice read must also hold its history")
var blockedHistory = false
do { _ = try fence.begin(sharedHistory) } catch { blockedHistory = true }
require(blockedHistory, "history cannot start while parent invoice is held")
input.fileHandleForWriting.closeFile()
holder.waitUntilExit()
require(holder.terminationStatus == 0, "child denial finished")
require(!fence.cacheAllowed(sharedScope), "cross-process denial leaves invoice held")
require(!fence.cacheAllowed(sharedHistory), "invoice denial must also hold its history")
let restoredInvoice = try fence.begin(sharedScope)
try restoredInvoice.finish(.liveSuccess)
require(!fence.cacheAllowed(sharedHistory), "invoice recovery must not restore old history")
let verifiedHistory = try fence.begin(sharedHistory)
try verifiedHistory.finish(.liveSuccess)
require(fence.cacheAllowed(sharedHistory), "history needs its own fresh verification")
let failedDeny = try fence.begin(scope)
require(chmod(dir.path, 0o500) == 0, "set read-only cache directory")
var denialWriteFailed = false
do { try failedDeny.finish(.denied) } catch { denialWriteFailed = true }
require(chmod(dir.path, 0o700) == 0, "restore directory access")
require(denialWriteFailed, "denial marker write failure must be observable")
require(!fence.cacheAllowed(scope), "failed denial write must leave preflight hold")
let offlineRetry = try fence.begin(scope)
try offlineRetry.finish(.connectivityFailure)
require(!fence.cacheAllowed(scope), "offline retry cannot undo failed denial")
let onlineRetry = try fence.begin(scope)
try onlineRetry.finish(.liveSuccess)
require(fence.cacheAllowed(scope), "new live read may recover a held scope")
let abandonedScope = InvoiceReadFence.Scope(actor: scope.actor, organization: scope.organization, origin: scope.origin, invoice: "018f0000-0000-7000-8000-000000000004", resource: "invoice")
var abandoned: InvoiceReadFence.Attempt? = try fence.begin(abandonedScope)
require(abandoned != nil, "attempt created")
abandoned = nil
var blockedAfterDrop = false
do { _ = try fence.begin(abandonedScope) } catch { blockedAfterDrop = true }
require(blockedAfterDrop, "dropping an uncompleted attempt must retain the lease")
print("PASS")
