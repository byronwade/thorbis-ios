import XCTest
@testable import Thorbis

@MainActor
final class OfflineSessionTests: XCTestCase {
    private let actor = "019f0000-0000-7000-8000-000000000011"
    private let org = "019f0000-0000-7000-8000-000000000001"
    private let session = #"{"user":{"id":"019f0000-0000-7000-8000-000000000011","name":"Fixture technician","email":"fixture@example.invalid"},"session":{"userId":"019f0000-0000-7000-8000-000000000011","activeOrganizationId":"019f0000-0000-7000-8000-000000000001","expiresAt":"2099-10-27T12:00:00.000Z"}}"#
    private let orgs = #"[{"id":"019f0000-0000-7000-8000-000000000001","name":"Fixture workspace"}]"#
    private let catalog = #"{"authority":{"actorId":"019f0000-0000-7000-8000-000000000011","organizationId":"019f0000-0000-7000-8000-000000000001","policyVersion":3,"generation":"g"},"capabilities":["job.view","job.edit"],"resources":[],"views":[]}"#
    private let features = #"{"organizationId":"019f0000-0000-7000-8000-000000000001","evaluatedAt":"2026-10-26T12:00:00.000Z","features":{"jobs":{"enabled":true,"released":true,"entitled":true}}}"#

    private func make(_ replies: [URLProtocolFixture.Reply], snapshots: MemorySessionSnapshotStore = .init(),
                      origin: String = "https://app.thorbis.com") -> SessionController {
        let api = APIClient(session: URLProtocolFixture.session(replies), baseURL: origin)
        return SessionController(api: api, defaults: UserDefaults(suiteName: "thorbis.offline.\(UUID().uuidString)")!, snapshots: snapshots)
    }

    private var signIn: [URLProtocolFixture.Reply] { [.init(200, session), .init(200, orgs), .init(200, catalog), .init(200, features)] }

    func testForegroundCheckWithoutSignalKeepsTheSessionReady() async {
        let controller = make(signIn + [URLProtocolFixture.offline])
        await controller.restore()
        let generation = controller.generation
        let authority = controller.authorityRevision
        let verification = controller.verificationRevision
        let recheck = controller.recheckRevision

        await controller.revalidate()

        XCTAssertEqual(controller.phase, .ready)
        XCTAssertTrue(controller.isOffline)
        XCTAssertEqual(controller.generation, generation, "Navigation and loaded work survive a foreground check")
        XCTAssertTrue(controller.can("job.edit", feature: "jobs"))
        // The server did not answer, so nothing was confirmed or changed.
        XCTAssertEqual(controller.authorityRevision, authority)
        XCTAssertEqual(controller.verificationRevision, verification)
        XCTAssertEqual(controller.recheckRevision, recheck)
    }

    func testForegroundCheckWithSameIdentityRefreshesAuthorityInPlace() async {
        let controller = make(signIn + signIn.filter { $0.body != orgs })
        await controller.restore()
        let generation = controller.generation

        await controller.revalidate()

        XCTAssertEqual(controller.phase, .ready)
        XCTAssertFalse(controller.isOffline)
        XCTAssertEqual(controller.generation, generation)
        XCTAssertEqual(controller.policyVersion, 3)
    }

    func testForegroundAuthorityRefreshChangesPriceBookScopeWithoutChangingSession() async {
        let priceCatalog = catalog.replacingOccurrences(of: "\"job.view\",\"job.edit\"", with: "\"pricebook.view\"")
        let priceFeatures = features.replacingOccurrences(of: "\"jobs\"", with: "\"price_book\"")
        let changedCatalog = priceCatalog.replacingOccurrences(of: "\"generation\":\"g\"", with: "\"generation\":\"g2\"")
        let controller = make([.init(200, session), .init(200, orgs), .init(200, priceCatalog), .init(200, priceFeatures),
                               .init(200, session), .init(200, changedCatalog), .init(200, priceFeatures)])
        await controller.restore()
        let oldScope = controller.priceBookAuthority
        let sessionGeneration = controller.generation
        XCTAssertEqual(oldScope?.generation, "g")
        await controller.revalidate()
        XCTAssertEqual(controller.generation, sessionGeneration)
        XCTAssertEqual(controller.priceBookAuthority?.generation, "g2")
        XCTAssertNotEqual(controller.priceBookAuthority, oldScope)
    }

    func testForegroundCheckWithAnotherIdentityFallsBackToFullRestore() async {
        let otherUser = session.replacingOccurrences(of: "000000000011", with: "000000000099")
        let controller = make(signIn + [.init(200, otherUser), .init(200, "null")])
        await controller.restore()
        let generation = controller.generation

        await controller.revalidate()

        XCTAssertNotEqual(controller.generation, generation)
        XCTAssertEqual(controller.phase, .signedOut)
        XCTAssertFalse(controller.can("job.view"))
    }

    func testColdLaunchWithoutSignalUsesTheLastVerifiedAuthority() async {
        let snapshots = MemorySessionSnapshotStore()
        let online = make(signIn, snapshots: snapshots)
        await online.restore()
        XCTAssertEqual(snapshots.snapshot?.authorityGeneration, "g")
        XCTAssertEqual(snapshots.snapshot?.authorityOrigin, "https://app.thorbis.com")

        let offline = make([URLProtocolFixture.offline], snapshots: snapshots)
        await offline.restore()

        XCTAssertEqual(offline.phase, .ready)
        XCTAssertTrue(offline.isOffline)
        XCTAssertEqual(offline.authorityGeneration, "g")
        XCTAssertEqual(offline.user?.id, actor)
        XCTAssertEqual(offline.activeOrganization?.id, org)
        XCTAssertTrue(offline.can("job.edit", feature: "jobs"))
    }

    func testAServerConfirmedSignedOutSessionForgetsTheOfflineSnapshot() async {
        let snapshots = MemorySessionSnapshotStore()
        let online = make(signIn, snapshots: snapshots)
        await online.restore()
        XCTAssertNotNil(snapshots.snapshot)

        let revoked = make([.init(200, "null")], snapshots: snapshots)
        await revoked.restore()
        XCTAssertEqual(revoked.phase, .signedOut)
        XCTAssertNil(snapshots.snapshot, "A session the server ended must not reopen offline")

        let offline = make([URLProtocolFixture.offline], snapshots: snapshots)
        await offline.restore()
        XCTAssertNotEqual(offline.phase, .ready)
        XCTAssertFalse(offline.can("job.view", feature: "jobs"))
    }

    func testAnActiveCompanyMissingFromTheMembershipListForgetsTheOfflineSnapshot() async {
        let snapshots = MemorySessionSnapshotStore()
        let online = make(signIn, snapshots: snapshots)
        await online.restore()
        XCTAssertNotNil(snapshots.snapshot)

        let otherWorkspace = #"[{"id":"019f0000-0000-7000-8000-000000000002","name":"Another workspace"}]"#
        let removed = make([.init(200, session), .init(200, otherWorkspace)], snapshots: snapshots)
        await removed.restore()
        XCTAssertEqual(removed.phase, .failed)
        XCTAssertNil(snapshots.snapshot)
    }

    /// The server's member removal nulls `activeOrganizationId` on that person's sessions
    /// (services/api member-removal), so these are the answers a removed member really gets.
    private var removedSession: String {
        session.replacingOccurrences(of: #""activeOrganizationId":"019f0000-0000-7000-8000-000000000001""#,
                                     with: #""activeOrganizationId":null"#)
    }

    func testRemovalFromTheOnlyCompanyForgetsTheOfflineSnapshot() async {
        let snapshots = MemorySessionSnapshotStore()
        let online = make(signIn, snapshots: snapshots)
        await online.restore()
        XCTAssertNotNil(snapshots.snapshot)

        let removed = make([.init(200, removedSession), .init(200, "[]")], snapshots: snapshots)
        await removed.restore()
        XCTAssertEqual(removed.phase, .noWorkspace)
        XCTAssertNil(snapshots.snapshot, "A company the person was removed from must not reopen offline")

        let offline = make([URLProtocolFixture.offline], snapshots: snapshots)
        await offline.restore()
        XCTAssertNotEqual(offline.phase, .ready)
        XCTAssertNil(offline.activeOrganization)
        XCTAssertFalse(offline.can("job.view", feature: "jobs"))
    }

    func testRemovalWithTwoOtherCompaniesLeftForgetsTheOfflineSnapshot() async {
        let snapshots = MemorySessionSnapshotStore()
        let online = make(signIn, snapshots: snapshots)
        await online.restore()
        XCTAssertNotNil(snapshots.snapshot)

        let others = #"[{"id":"019f0000-0000-7000-8000-000000000002","name":"Another workspace"},{"id":"019f0000-0000-7000-8000-000000000003","name":"Third workspace"}]"#
        let removed = make([.init(200, removedSession), .init(200, others)], snapshots: snapshots)
        await removed.restore()
        XCTAssertEqual(removed.phase, .choosingWorkspace)
        XCTAssertNil(snapshots.snapshot)

        let offline = make([URLProtocolFixture.offline], snapshots: snapshots)
        await offline.restore()
        XCTAssertNotEqual(offline.phase, .ready)
        XCTAssertNil(offline.activeOrganization)
    }

    func testRemovalWithOneCompanyLeftDoesNotReopenTheOldOneWhenActivationHasNoSignal() async {
        let snapshots = MemorySessionSnapshotStore()
        let online = make(signIn, snapshots: snapshots)
        await online.restore()
        XCTAssertNotNil(snapshots.snapshot)

        let other = #"[{"id":"019f0000-0000-7000-8000-000000000002","name":"Another workspace"}]"#
        let removed = make([.init(200, removedSession), .init(200, other), URLProtocolFixture.offline], snapshots: snapshots)
        await removed.restore()
        XCTAssertNotEqual(removed.phase, .ready)
        XCTAssertNotEqual(removed.activeOrganization?.id, org)
        XCTAssertNil(snapshots.snapshot)
    }

    func testRemovalThenAFailedCompanyListDoesNotReopenTheOldCompany() async {
        let failures: [(String, URLProtocolFixture.Reply)] = [
            ("no signal", URLProtocolFixture.offline),
            ("timeout", URLProtocolFixture.timedOut),
            ("outage", .init(503, #"{"title":"Unavailable","status":503}"#)),
            ("rate limit", .init(429, #"{"title":"Too many requests","status":429}"#)),
        ]
        for (name, failure) in failures {
            let snapshots = MemorySessionSnapshotStore()
            let online = make(signIn, snapshots: snapshots)
            await online.restore()
            XCTAssertNotNil(snapshots.snapshot, name)

            let removed = make([.init(200, removedSession), failure], snapshots: snapshots)
            await removed.restore()
            XCTAssertNotEqual(removed.phase, .ready, "\(name): the server just said this session has no company open")
            XCTAssertNotEqual(removed.activeOrganization?.id, org, name)
            XCTAssertNil(snapshots.snapshot, "\(name): membership could not be confirmed, so the copy is forgotten")

            let offline = make([URLProtocolFixture.offline], snapshots: snapshots)
            await offline.restore()
            XCTAssertNotEqual(offline.phase, .ready, "\(name): a later launch without signal must not reopen it either")
            XCTAssertNil(offline.activeOrganization, name)
        }
    }

    func testForegroundCheckAfterRemovalWithAWeakSignalDoesNotReopenTheOldCompany() async {
        let snapshots = MemorySessionSnapshotStore()
        // Foreground: get-session has no active company, so revalidate restores; the restore's own
        // get-session answers the same, and the company list then has no signal.
        let controller = make(signIn + [.init(200, removedSession), .init(200, removedSession), URLProtocolFixture.offline],
                              snapshots: snapshots)
        var identities: [String?] = []
        controller.onVerifiedIdentity = { _, organization in identities.append(organization) }
        await controller.restore()
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertNotNil(snapshots.snapshot)
        identities = []

        await controller.revalidate()

        XCTAssertNotEqual(controller.phase, .ready)
        XCTAssertNotEqual(controller.activeOrganization?.id, org)
        XCTAssertFalse(controller.can("job.view", feature: "jobs"))
        XCTAssertNil(snapshots.snapshot)
        XCTAssertFalse(identities.contains(org), "The store, saved copies and outbox are not rebound to the removed company")
    }

    func testASessionThatStillNamesTheCompanyOpensOfflineWhenTheCompanyListHasNoSignal() async {
        let snapshots = MemorySessionSnapshotStore()
        let online = make(signIn, snapshots: snapshots)
        await online.restore()

        let weak = make([.init(200, session), URLProtocolFixture.offline], snapshots: snapshots)
        await weak.restore()
        XCTAssertEqual(weak.phase, .ready, "The server still names this company: no signal is not proof of removal")
        XCTAssertTrue(weak.isOffline)
        XCTAssertEqual(weak.activeOrganization?.id, org)
        XCTAssertNotNil(snapshots.snapshot)
    }

    func testAnotherAccountWithNoCompanyForgetsTheOfflineSnapshot() async {
        let snapshots = MemorySessionSnapshotStore()
        let online = make(signIn, snapshots: snapshots)
        await online.restore()
        XCTAssertNotNil(snapshots.snapshot)

        let otherAccount = removedSession.replacingOccurrences(of: "000000000011", with: "000000000099")
        let other = make([.init(200, otherAccount), .init(200, "[]")], snapshots: snapshots)
        await other.restore()
        XCTAssertEqual(other.phase, .noWorkspace)
        XCTAssertNil(snapshots.snapshot, "Another account's offline copy never stays behind")
    }

    func testAMemberStillInTheCompanyKeepsTheOfflineSnapshotAtThePicker() async {
        let snapshots = MemorySessionSnapshotStore()
        let online = make(signIn, snapshots: snapshots)
        await online.restore()

        let both = #"[{"id":"019f0000-0000-7000-8000-000000000001","name":"Fixture workspace"},{"id":"019f0000-0000-7000-8000-000000000002","name":"Another workspace"}]"#
        let picker = make([.init(200, removedSession), .init(200, both)], snapshots: snapshots)
        await picker.restore()
        XCTAssertEqual(picker.phase, .choosingWorkspace)
        XCTAssertEqual(snapshots.snapshot?.organization.id, org, "Still a member: the offline copy is not proof of removal")
    }

    func testNoSignalKeepsTheOfflineSnapshot() async {
        let snapshots = MemorySessionSnapshotStore()
        let online = make(signIn, snapshots: snapshots)
        await online.restore()

        let offline = make([URLProtocolFixture.offline], snapshots: snapshots)
        await offline.restore()
        XCTAssertNotNil(snapshots.snapshot, "No signal is not proof the session ended")
    }

    func testOfflineSnapshotDoesNotAuthorizePriceBookAcrossOrigins() async {
        let snapshots = MemorySessionSnapshotStore()
        let online = make(signIn, snapshots: snapshots)
        await online.restore()
        let offline = make([URLProtocolFixture.offline], snapshots: snapshots, origin: "http://localhost:4321")
        await offline.restore()
        XCTAssertNil(offline.authorityGeneration)
        XCTAssertNil(offline.priceBookAuthority)
    }

    func testLegacyOfflineSnapshotCannotAuthorizeScopedPriceBookCache() async {
        let legacy = SessionSnapshot(user: .init(id: actor, name: "T", email: nil), organization: .init(id: org, name: "W"),
                                     organizations: [.init(id: org, name: "W")], capabilities: ["pricebook.view"],
                                     features: ["price_book": .init(enabled: true, released: true, entitled: true, stage: nil, reason: nil)],
                                     policyVersion: 1, sessionDeadline: Date().addingTimeInterval(3600), authorityDeadline: nil)
        let offline = make([URLProtocolFixture.offline], snapshots: .init(legacy))
        await offline.restore()
        XCTAssertTrue(offline.can("pricebook.view", feature: "price_book"))
        XCTAssertNil(offline.priceBookAuthority)
    }

    func testColdLaunchWithoutSignalAndAnExpiredSnapshotStillAsksToSignIn() async {
        let expired = SessionSnapshot(user: .init(id: actor, name: "T", email: nil), organization: .init(id: org, name: "W"),
                                      organizations: [.init(id: org, name: "W")], capabilities: ["job.view"], features: [:],
                                      policyVersion: 1, sessionDeadline: Date().addingTimeInterval(-60), authorityDeadline: nil)
        let controller = make([URLProtocolFixture.offline], snapshots: .init(expired))

        await controller.restore()

        XCTAssertEqual(controller.phase, .failed)
        XCTAssertFalse(controller.can("job.view"))
    }

    func testSignOutForgetsTheOfflineSnapshot() async {
        let snapshots = MemorySessionSnapshotStore()
        let controller = make(signIn + [.init(200, "{}")], snapshots: snapshots)
        await controller.restore()
        XCTAssertNotNil(snapshots.snapshot)

        await controller.signOut()

        XCTAssertNil(snapshots.snapshot)
    }

    func testAServerOutageOnForegroundKeepsTheSessionInsteadOfSigningOut() async {
        let controller = make(signIn + [.init(503, #"{"title":"Unavailable","status":503}"#)])
        await controller.restore()

        await controller.revalidate()

        XCTAssertEqual(controller.phase, .ready)
        XCTAssertTrue(controller.isOffline)
    }

    func testAnUnauthorizedForegroundCheckStillSignsOut() async {
        let controller = make(signIn + [.init(200, "null"), .init(200, "null")])
        await controller.restore()

        await controller.revalidate()

        XCTAssertEqual(controller.phase, .signedOut)
        XCTAssertFalse(controller.can("job.view"))
    }
}
