import AVFoundation
import CoreLocation
import EventKit
import Speech
import UserNotifications
import XCTest
@testable import Thorbis

@MainActor
final class AccountScreensTests: XCTestCase {
    // MARK: Edit profile

    func testProfileNameIsTrimmedAndRequired() {
        XCTAssertEqual(ProfileEdit.clean("  Ramon Mendez \n"), "Ramon Mendez")
        XCTAssertEqual(ProfileEdit.nameProblem("   "), "Add your name.")
        XCTAssertNil(ProfileEdit.nameProblem("Ramon"))
    }

    func testProfileChangesIgnoreSurroundingSpaces() {
        XCTAssertFalse(ProfileEdit.hasChanges(original: "Ramon", edited: " Ramon "))
        XCTAssertTrue(ProfileEdit.hasChanges(original: "Ramon", edited: "Ramon Mendez"))
    }

    func testProfileInitialsFallBackToEmail() {
        XCTAssertEqual(ProfileEdit.initials(name: "ramon mendez", email: nil), "RM")
        XCTAssertEqual(ProfileEdit.initials(name: "", email: "ramon@example.com"), "RE")
        XCTAssertEqual(ProfileEdit.initials(name: "", email: nil), "?")
    }

    func testProfileSaveMessages() {
        XCTAssertEqual(ProfileEdit.saveMessage(status: 401, detail: "x"), "Your session ended. Sign in again to change your name.")
        XCTAssertEqual(ProfileEdit.saveMessage(status: 500, detail: "Server said no"), "Server said no")
        XCTAssertEqual(ProfileEdit.saveMessage(status: nil, detail: nil), "Your name wasn't saved. Try again.")
    }

    func testProfileUpdateBodyIsOnlyTheName() throws {
        let data = try JSONEncoder().encode(ProfileNameUpdate(name: "Ramon"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["name"])
    }

    // MARK: Change password

    func testPasswordLengthFollowsBetterAuth() {
        XCTAssertEqual(PasswordChange.minimumLength, 8)
        XCTAssertEqual(PasswordChange.maximumLength, 128)
        XCTAssertFalse(PasswordChange.longEnough("1234567"))
        XCTAssertTrue(PasswordChange.longEnough("12345678"))
        XCTAssertEqual(PasswordChange.newProblem(""), "Enter a new password.")
        XCTAssertEqual(PasswordChange.newProblem("short"), "Use at least 8 characters.")
        XCTAssertEqual(PasswordChange.newProblem(String(repeating: "a", count: 129)), "Use 128 characters or fewer.")
        XCTAssertNil(PasswordChange.newProblem("long enough"))
    }

    func testPasswordConfirmation() {
        XCTAssertFalse(PasswordChange.bothMatch("", ""))
        XCTAssertTrue(PasswordChange.bothMatch("same words", "same words"))
        XCTAssertEqual(PasswordChange.confirmProblem("a", ""), "Type the new password again.")
        XCTAssertEqual(PasswordChange.confirmProblem("a", "b"), "The two new passwords don't match.")
        XCTAssertNil(PasswordChange.confirmProblem("same", "same"))
        XCTAssertEqual(PasswordChange.currentProblem(""), "Enter your current password.")
    }

    func testPasswordServerMessagesNeverEchoThePassword() {
        XCTAssertEqual(PasswordChange.message(code: "INVALID_PASSWORD", status: 400, detail: "Invalid password"),
                       "That isn't your current password. Check it and try again.")
        XCTAssertEqual(PasswordChange.message(code: "PASSWORD_TOO_SHORT", status: 400, detail: nil), "Use at least 8 characters.")
        XCTAssertEqual(PasswordChange.message(code: nil, status: 429, detail: nil), "Too many tries. Wait a minute, then try again.")
        XCTAssertEqual(PasswordChange.message(code: "Network error", status: nil, detail: "No connection."), "No connection.")
    }

    func testPasswordRequestUsesBetterAuthFieldNames() throws {
        let body = PasswordChangeRequest(currentPassword: "old-secret", newPassword: "new-secret", revokeOtherSessions: true)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["currentPassword", "newPassword", "revokeOtherSessions"])
        XCTAssertEqual(object["revokeOtherSessions"] as? Bool, true)
    }

    func testResetLinkMessages() {
        XCTAssertEqual(PasswordChange.resetMessage(status: nil, email: "a@b.co"), "We sent a reset link to a@b.co. It expires in 30 minutes.")
        XCTAssertEqual(PasswordChange.resetMessage(status: 404, email: "a@b.co"),
                       "Password reset is unavailable here. Ask your workspace administrator for help.")
    }

    // MARK: My notifications

    func testNotificationPermissionWords() {
        XCTAssertEqual(NotificationPermissionWords.value(.authorized), "On")
        XCTAssertEqual(NotificationPermissionWords.value(.denied), "Off")
        XCTAssertEqual(NotificationPermissionWords.value(.notDetermined), "Turn on")
        XCTAssertNil(NotificationPermissionWords.value(nil))
        XCTAssertEqual(NotificationPermissionWords.hint(.notDetermined), "Asks to send you notifications")
    }

    // MARK: Privacy and permissions

    func testPermissionStatesReadAsWords() {
        XCTAssertEqual(DevicePermissionState.location(.authorizedWhenInUse).word, "While using")
        XCTAssertEqual(DevicePermissionState.location(.notDetermined).word, "Not asked")
        XCTAssertEqual(DevicePermissionState.capture(.authorized).word, "Allowed")
        XCTAssertEqual(DevicePermissionState.capture(.denied).word, "Off")
        XCTAssertEqual(DevicePermissionState.microphone(.granted).word, "Allowed")
        XCTAssertEqual(DevicePermissionState.speech(.restricted).word, "Restricted")
        XCTAssertEqual(DevicePermissionState.calendar(.writeOnly).word, "Add only")
        XCTAssertEqual(DevicePermissionState.notifications(.provisional).word, "Quietly")
    }

    func testPermissionRowsAreOnlyWhatTheAppAsksFor() {
        let rows = DevicePermissionRow.rows(location: .off, camera: .off, notifications: .off,
                                            microphone: .off, speech: .off, calendar: .off)
        XCTAssertEqual(rows.map(\.id), ["location", "camera", "notifications", "microphone", "speech", "calendar"])
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
        XCTAssertTrue(rows.allSatisfy { !$0.purpose.isEmpty })
    }
}
