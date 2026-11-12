import Foundation

struct User { var id: String }
struct Organization { var id: String }
enum Phase { case ready, failed }
@MainActor final class SessionController {
    var phase: Phase = .ready
    var user: User? = User(id: "actor")
    var activeOrganization: Organization? = Organization(id: "org")
    var generation = UUID()
    var authorityRevision = UUID()
}
@MainActor final class APIClient {
    var normalizedOrigin: String? = "https://app.thorbis.com"
    var requestGeneration = UUID()
    var savedCopyScopeRevision = UUID()
}

// The test runner substitutes this marker with the actual production authority type.
// OVERVIEW_AUTHORITY_SOURCE

@main struct Probe {
    @MainActor static func main() {
        let api = APIClient(), session = SessionController()
        func check(_ name: String, _ mutate: () -> Void, _ reset: () -> Void) {
            guard let snapshot = CustomerHandoffExitAuthority.capture(api: api, session: session),
                  snapshot.isCurrent(api: api, session: session) else { fatalError("capture failed") }
            mutate()
            guard !snapshot.isCurrent(api: api, session: session) else { fatalError("not retired: " + name) }
            reset()
            print("PASS", name)
        }
        let revision = session.authorityRevision
        check("same-session authority change", { session.authorityRevision = UUID() }, { session.authorityRevision = revision })
        let generation = session.generation
        check("session replacement", { session.generation = UUID() }, { session.generation = generation })
        check("workspace change", { session.activeOrganization = Organization(id: "other") }, { session.activeOrganization = Organization(id: "org") })
        check("actor change", { session.user = User(id: "other") }, { session.user = User(id: "actor") })
        check("sign out", { session.phase = .failed }, { session.phase = .ready })
        let request = api.requestGeneration
        check("request generation", { api.requestGeneration = UUID() }, { api.requestGeneration = request })
        let scope = api.savedCopyScopeRevision
        check("saved scope revision", { api.savedCopyScopeRevision = UUID() }, { api.savedCopyScopeRevision = scope })
        check("origin change", { api.normalizedOrigin = "https://other.invalid" }, { api.normalizedOrigin = "https://app.thorbis.com" })
    }
}
