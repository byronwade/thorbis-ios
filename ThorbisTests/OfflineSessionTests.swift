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

    private func make(_ replies: [URLProtocolFixture.Reply], snapshots: MemorySessionSnapshotStore = .init()) -> SessionController {
        let api = APIClient(session: URLProtocolFixture.session(replies), baseURL: "https://app.thorbis.com")
        return SessionController(api: api, defaults: UserDefaults(suiteName: "thorbis.offline.\(UUID().uuidString)")!, snapshots: snapshots)
    }

    private var signIn: [URLProtocolFixture.Reply] { [.init(200, session), .init(200, orgs), .init(200, catalog), .init(200, features)] }

    func testForegroundCheckWithoutSignalKeepsTheSessionReady() async {
        let controller = make(signIn + [URLProtocolFixture.offline])
        await controller.restore()
        let generation = controller.generation

        await controller.revalidate()

        XCTAssertEqual(controller.phase, .ready)
        XCTAssertTrue(controller.isOffline)
        XCTAssertEqual(controller.generation, generation, "Navigation and loaded work survive a foreground check")
        XCTAssertTrue(controller.can("job.edit", feature: "jobs"))
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
        XCTAssertNotNil(snapshots.snapshot)

        let offline = make([URLProtocolFixture.offline], snapshots: snapshots)
        await offline.restore()

        XCTAssertEqual(offline.phase, .ready)
        XCTAssertTrue(offline.isOffline)
        XCTAssertEqual(offline.user?.id, actor)
        XCTAssertEqual(offline.activeOrganization?.id, org)
        XCTAssertTrue(offline.can("job.edit", feature: "jobs"))
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
