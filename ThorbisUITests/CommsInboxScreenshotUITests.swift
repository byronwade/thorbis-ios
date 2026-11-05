import XCTest

/// Screenshots of the Inbox preview for design review: every section, a folder, each kind of
/// thread, light and dark, and the largest text size. Each is attached to the result; with
/// `TEST_RUNNER_INBOX_SHOTS_DIR` set, it is also written there as a PNG.
@MainActor
final class CommsInboxScreenshotUITests: XCTestCase {
    /// Opt-in: about thirty launches, so ordinary UI runs skip it.
    override func setUpWithError() throws {
        try XCTSkipUnless(!(ProcessInfo.processInfo.environment["INBOX_SHOTS_DIR"] ?? "").isEmpty,
                          "Set TEST_RUNNER_INBOX_SHOTS_DIR to capture the Inbox screenshots.")
    }

    private func capture(_ name: String, _ arguments: [String], wait identifier: String? = nil, text: String? = nil) {
        let app = XCUIApplication()
        app.launchArguments = ["--paper-preview", "--paper-preview-screen", "inbox"] + arguments
        app.launch()
        if let identifier { _ = app.descendants(matching: .any)[identifier].waitForExistence(timeout: 30) }
        if let text { _ = app.staticTexts[text].firstMatch.waitForExistence(timeout: 30) }
        sleep(2)
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["INBOX_SHOTS_DIR"], !folder.isEmpty {
            let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(device)-\(name).png"))
        }
        app.terminate()
    }

    private func sweep(_ mode: String, extra: [String] = [], prefix: String) {
        let base = ["-thorbis.appearance", mode] + extra
        capture("\(prefix)-all", base, wait: "inbox-section-menu")
        for section in ["calls", "voicemail", "texts", "email", "notices"] {
            capture("\(prefix)-\(section)", base + ["--paper-preview-inbox-section", section], wait: "inbox-section-menu")
        }
        capture("\(prefix)-drafts", base + ["--paper-preview-inbox-folder", "drafts"], wait: "inbox-folder-menu")
        capture("\(prefix)-call-thread", base + ["--paper-preview-inbox-thread", "calls"], text: "Incoming call")
        capture("\(prefix)-text-thread", base + ["--paper-preview-inbox-thread", "text"], wait: "inbox-text-field")
        capture("\(prefix)-email-thread", base + ["--paper-preview-inbox-thread", "email"], wait: "inbox-email-reply")
    }

    func testLightScreens() { sweep("light", prefix: "light") }
    func testDarkScreens() { sweep("dark", prefix: "dark") }

    func testLargestTextScreens() {
        let big = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        capture("xxxl-all", ["-thorbis.appearance", "light"] + big, wait: "inbox-section-menu")
        capture("xxxl-calls", ["-thorbis.appearance", "light", "--paper-preview-inbox-section", "calls"] + big, wait: "inbox-section-menu")
        capture("xxxl-call-thread", ["-thorbis.appearance", "light", "--paper-preview-inbox-thread", "calls"] + big, text: "Incoming call")
        capture("xxxl-text-thread", ["-thorbis.appearance", "light", "--paper-preview-inbox-thread", "text"] + big, wait: "inbox-text-field")
    }
}
