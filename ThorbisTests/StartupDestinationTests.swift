import XCTest
@testable import Thorbis

final class StartupDestinationTests: XCTestCase {
    func testPreferenceIsScopedToActorWorkspaceAndOrigin() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let preferences = StartupDestinationPreferences(defaults: defaults)
        let scope = StartupDestinationScope(actor: "actor", workspace: "one", origin: "https://one.example")
        preferences.set(.schedule, for: scope)
        XCTAssertEqual(preferences.get(for: scope), .schedule)
        XCTAssertEqual(preferences.get(for: .init(actor: "other", workspace: "one", origin: "https://one.example")), .automatic)
        XCTAssertEqual(preferences.get(for: .init(actor: "actor", workspace: "two", origin: "https://one.example")), .automatic)
        XCTAssertEqual(preferences.get(for: .init(actor: "actor", workspace: "one", origin: "https://two.example")), .automatic)
    }

    func testDeniedPreferenceFallsBackAndExplicitNavigationWins() {
        XCTAssertNil(StartupDestination.schedule.launchTarget(isPermitted: false, openedForReason: false))
        XCTAssertNil(StartupDestination.schedule.launchTarget(isPermitted: true, openedForReason: true))
        XCTAssertEqual(StartupDestination.schedule.launchTarget(isPermitted: true, openedForReason: false), .schedule)
        XCTAssertNil(StartupDestination.automatic.launchTarget(isPermitted: true, openedForReason: false))
    }
    func testAllRootDestinationsAreRepresented() {
        let menuIDs = Set(MenuItem.allCases.map(\.rawValue))
        let localIDs = Set(LocalWorkspaceSection.allCases.map { "local-" + $0.rawValue })
        XCTAssertEqual(Set(StartupDestination.allCases.map(\.rawValue)), menuIDs.union(localIDs).union(["automatic"]))
    }

    func testUnknownPreferenceAndAmbiguousScopeComponents() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let preferences = StartupDestinationPreferences(defaults: defaults)
        let first = StartupDestinationScope(actor: "a.b", workspace: "c", origin: "https://one")
        let second = StartupDestinationScope(actor: "a", workspace: "b.c", origin: "https://one")
        preferences.set(.invoices, for: first)
        XCTAssertEqual(preferences.get(for: second), .automatic)
        defaults.set("removed-destination", forKey: first.key)
        XCTAssertEqual(preferences.get(for: first), .automatic)
        preferences.set(.automatic, for: first)
        XCTAssertNil(defaults.object(forKey: first.key))
    }

    @MainActor func testScheduleShortcutIsConsumedOnlyOnceAcrossRootRecreation() {
        let store = Store()
        let session = UUID()
        store.rememberRoot("customers", session: session)
        store.requestedSchedule += 1
        XCTAssertTrue(store.consumeScheduleRequest(session: session))
        XCTAssertEqual(store.rememberedRoot(session: session), "schedule")
        // A new compact or regular root must not replay the old shortcut after the user navigates.
        XCTAssertFalse(store.consumeScheduleRequest(session: session))
        store.requestedSchedule += 1
        XCTAssertTrue(store.consumeScheduleRequest(session: session))
        XCTAssertFalse(store.consumeScheduleRequest(session: session))
    }

    @MainActor func testLaunchDecisionIsConsumedOnceAcrossRootRecreation() {
        let store = Store()
        let session = UUID()
        XCTAssertTrue(store.consumeStartupSelection(session: session))
        // Replacing a phone shell with a tablet shell cannot reapply a start choice.
        XCTAssertFalse(store.consumeStartupSelection(session: session))
        XCTAssertTrue(store.consumeStartupSelection(session: UUID()))
    }

    @MainActor func testRememberedRootIsSharedOnlyWithinSession() {
        let store = Store()
        let session = UUID()
        store.rememberRoot("customers", session: session)
        XCTAssertEqual(store.rememberedRoot(session: session), "customers")
        XCTAssertNil(store.rememberedRoot(session: UUID()))
        store.rememberRoot("local-fleet", session: session)
        XCTAssertEqual(store.rememberedRoot(session: session), "local-fleet")
    }

    @MainActor func testHandledJobAndRecordRequestsReplaceStaleRememberedRoot() {
        let store = Store()
        let session = UUID()
        store.rememberRoot("customers", session: session)
        store.requestedJobID = "job-1"
        store.requestedJobID = nil
        store.rememberHandledRequest("schedule", session: session)
        XCTAssertEqual(store.rememberedRoot(session: session), "schedule")
        store.requestedRecord = .customer("customer-1")
        store.requestedRecord = nil
        store.rememberHandledRequest("customers", session: session)
        XCTAssertEqual(store.rememberedRoot(session: session), "customers")
        store.requestedSearch = "AC"
        store.requestedSearch = nil
        store.rememberHandledRequest("jobs", session: session)
        XCTAssertEqual(store.rememberedRoot(session: session), "jobs")
    }

    @MainActor func testHandledRequestsDoNotBlockStartupForALaterSession() {
        let store = Store()
        let first = UUID()
        store.requestedJobID = "job-1"
        XCTAssertTrue(store.openedForReason(session: first))
        store.requestedJobID = nil
        store.rememberHandledRequest("schedule", session: first)
        XCTAssertTrue(store.openedForReason(session: first))
        store.requestedSchedule += 1
        XCTAssertTrue(store.consumeScheduleRequest(session: first))
        XCTAssertTrue(store.openedForReason(session: first))
        let second = UUID()
        XCTAssertTrue(store.consumeStartupSelection(session: second))
        XCTAssertFalse(store.openedForReason(session: second))
        XCTAssertTrue(store.openedForRecord)
        XCTAssertGreaterThan(store.requestedSchedule, 0)
    }

    @MainActor func testPendingRequestsBlockStartupBeforeTheyAreOpened() {
        let store = Store()
        let session = UUID()
        store.requestedJobID = "job-1"
        XCTAssertTrue(store.openedForReason(session: session))
        store.requestedJobID = nil
        store.requestedRecord = .invoice("invoice-1")
        XCTAssertTrue(store.openedForReason(session: session))
        store.requestedRecord = nil
        store.requestedSearch = "Birch"
        XCTAssertTrue(store.openedForReason(session: session))
        store.requestedSearch = nil
        store.requestedSchedule += 1
        XCTAssertTrue(store.openedForReason(session: session))
        XCTAssertTrue(store.consumeScheduleRequest(session: session))
        XCTAssertTrue(store.openedForReason(session: session))
        XCTAssertFalse(store.openedForReason(session: UUID()))
    }

}
