import Testing
import Foundation
import ThorbisCore
@testable import Thorbis

/// Drives the app model against the in-memory fixture API, the same data the
/// UI tests and SwiftUI previews use. No network, no keychain writes.
@MainActor
struct AppModelTests {
    private func makeModel() -> AppModel {
        let defaults = UserDefaults(suiteName: "ThorbisTests.\(UUID().uuidString)")!
        return AppModel(defaults: defaults, arguments: ["--ui-fixture"])
    }

    @Test func fixtureLaunchSignsInAndLoadsWorkspace() async {
        let model = makeModel()
        await model.bootstrap()
        #expect(model.phase == .signedIn)
        #expect(model.account?.name == "Mike Reyes")
        #expect(!model.jobs.isEmpty)
        #expect(!model.customers.isEmpty)
        #expect(model.refreshError == nil)
    }

    @Test func nextUpIsTheJobAlreadyUnderway() async {
        let model = makeModel()
        await model.bootstrap()
        let agenda = Agenda.build(model.jobs, assignedTo: FixtureTransport.userId)
        let next = Agenda.nextUp(agenda.days.flatMap(\.jobs))
        #expect(next?.status == .enRoute)
        #expect(JobWorkflow.primaryAction(status: .enRoute, allowed: next?.allowedTransitions ?? JobWorkflow.fallbackTransitions(from: .enRoute))?.title == "Arrive")
    }

    @Test func progressingAJobReplacesTheCachedCopy() async throws {
        let model = makeModel()
        await model.bootstrap()
        let job = try #require(model.jobs.first { $0.status == .enRoute })
        model.store(try await model.api.progress(job.id, to: .arrived))
        #expect(model.cached(job: job.id)?.status == .arrived)
    }

    @Test func signOutClearsTheWorkspace() async {
        let model = makeModel()
        await model.bootstrap()
        await model.signOut()
        #expect(model.phase == .signedOut)
        #expect(model.jobs.isEmpty)
        #expect(model.account == nil)
    }
}
