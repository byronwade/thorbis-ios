import Foundation

struct JobEstimateLink: Codable { let id: String; let jobId: String; let estimateId: String }
struct JobEstimateLinkPage: Decodable { let items: [JobEstimateLink]; let nextCursor: String? }
struct APIReadProvenance {
    enum Source { case urlSession(cacheBypassed: Bool); case savedCopy(Date) }
    let generation: UUID
    let savedCopyScopeRevision: UUID
    let origin: String
    let source: Source
}
struct APIRead<Value> { let value: Value; let provenance: APIReadProvenance }
@MainActor final class APIClient {
    var requestGeneration = UUID()
    var savedCopyScopeRevision = UUID()
    var normalizedOrigin: String? = "https://app.thorbis.com"
    var observed: [(String?, Bool)] = []
    var mutateScope = false
    static func normalizedOrigin(_ value: String) -> String? { value.lowercased() }
    func fieldPath(_ base: String, id: String, suffix: String = "") throws -> String { "\(base)/\(id)\(suffix)" }
    func sendWithProvenance<T: Decodable>(_ path: String, cursor: String? = nil, requireFresh: Bool = false) async throws -> APIRead<T> {
        observed.append((cursor, requireFresh))
        let generation = requestGeneration, revision = savedCopyScopeRevision
        if mutateScope { savedCopyScopeRevision = UUID() }
        let value = try JSONDecoder().decode(T.self, from: Data("{\"items\":[],\"nextCursor\":\"next\"}".utf8))
        return .init(value: value, provenance: .init(generation: generation, savedCopyScopeRevision: revision,
                     origin: "https://APP.THORBIS.COM", source: requireFresh ? .urlSession(cacheBypassed: true) : .savedCopy(Date())))
    }
    // PAGE_ADAPTER
}
@main struct Probe {
    @MainActor static func main() async throws {
        let client = APIClient()
        let first = try await client.fieldJobEstimateLinkPage("job", requireFresh: true, isCurrent: { true })
        precondition(first.value.nextCursor == "next" && client.observed.count == 1 && client.observed[0].1)
        let cached = try await client.fieldJobEstimateLinkPage("job", cursor: "next", isCurrent: { true })
        guard case .savedCopy = cached.provenance.source else { fatalError("lost copy provenance") }
        precondition(client.observed.count == 2 && client.observed[1].0 == "next")
        client.mutateScope = true
        do { _ = try await client.fieldJobEstimateLinkPage("job", isCurrent: { true }); fatalError("scope change accepted") }
        catch is CancellationError {}
        print("PASS extracted page adapter: one request, cursor, provenance, scope retirement")
    }
}
