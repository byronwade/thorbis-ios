import XCTest
@testable import Thorbis

@MainActor final class TerminalOwnershipTests: XCTestCase {
    func testBoundBootstrapInstallsTokenBeforeProactiveSDKRequest() throws {
        var initialized = false
        var installed = false
        let owner = TerminalOwnership(isInitialized: { initialized }, initialize: {
            XCTAssertTrue(installed, "The SDK can request a token during initialization")
            initialized = true
        })
        try owner.claimBound { installed = true }
        XCTAssertTrue(initialized)
    }

    func testBoundOwnerUsesSingleInitializationAndBlocksLegacy() throws {
        var initialized = false
        var count = 0
        let owner = TerminalOwnership(isInitialized: { initialized }, initialize: { count += 1; initialized = true })
        try owner.claimBound {}
        try owner.claimBound { XCTFail("Must not replace active token provider") }
        XCTAssertEqual(count, 1)
        XCTAssertThrowsError(try owner.claimLegacy {})
        XCTAssertFalse(owner.legacyAvailable)
    }

    func testLegacyOwnerPreventsBoundTakeover() throws {
        var initialized = false
        let owner = TerminalOwnership(isInitialized: { initialized }, initialize: { initialized = true })
        try owner.claimLegacy {}
        XCTAssertThrowsError(try owner.claimBound {})
    }

    func testUnknownSingletonIsNeverClaimed() {
        let owner = TerminalOwnership(isInitialized: { true }, initialize: { XCTFail("Unexpected reinitialization") })
        XCTAssertThrowsError(try owner.claimBound {})
    }

    func testLegacyCollectionExcludesAnotherControllerAndBoundOwner() throws {
        var initialized = false
        let owner = TerminalOwnership(isInitialized: { initialized }, initialize: { initialized = true })
        XCTAssertTrue(owner.beginLegacyCollection())
        XCTAssertFalse(owner.beginLegacyCollection())
        XCTAssertThrowsError(try owner.claimBound {})
        owner.endLegacyCollection()
        XCTAssertTrue(owner.beginLegacyCollection())
    }
}
