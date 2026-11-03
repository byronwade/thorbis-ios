import Foundation
struct Scope: Codable, Equatable, Hashable { let actor, organization, origin, job: String }
struct Draft: Codable, Equatable { let title: String; let lines: [String] }
@MainActor @main struct Main {
 static func main() throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
  let scope=Scope(actor:"a",organization:"o",origin:"https://one.test",job:"1"),other=Scope(actor:"a",organization:"other",origin:scope.origin,job:scope.job)
  let draft=Draft(title:"unsaved",lines:["detailed work"]), memory=VolatileDraftRecovery<Scope,Draft>(),attempts=EstimateRecoveryCopyAttempts<Scope,Draft>()
  var fail=true,seen:[UUID]=[]
  let store=EstimateRecoveryCopyStore<Scope,Draft>(directory:root,inspectRead:{data in if fail {throw CocoaError(.fileReadUnknown)};return data})
  let result=EstimateTeardownPreservation.preserve(draft,scope:scope,intentID:nil,attempts:attempts,hold:{memory.hold(draft,for:scope);return true},install:{id,value in seen.append(id);try store.install(value,scope:scope,id:id)})
  precondition(result == .memoryOnly && memory.read(for:scope) == draft && memory.read(for:other) == nil)
  fail=false
  let again=EstimateTeardownPreservation.preserve(draft,scope:scope,intentID:nil,attempts:attempts,hold:{memory.hold(draft,for:scope);return true},install:{id,value in seen.append(id);try store.install(value,scope:scope,id:id)})
  precondition(again == .copyConfirmed && seen.count == 2 && seen[0] == seen[1])
  let copies=try store.list(scope:scope),saved=try store.read(scope:scope,id:seen[0]);precondition(copies == [seen[0]] && saved == draft)
  var wrote=false
  let refused=EstimateTeardownPreservation.preserve(draft,scope:other,intentID:nil,attempts:attempts,hold:{false},install:{_,_ in wrote=true})
  precondition(refused == .notCaptured && !wrote)
  print("PASS: teardown retains original scope in memory, retries exact copy ID, and never writes if capture fails")
 }
}
