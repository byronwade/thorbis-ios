import SwiftUI
import UIKit

// Shared plumbing for the on-site tools (data-plate scan, checklists, call the office).
// Each tool is a self-contained sheet; the job screen presents it. Nothing here invents a
// server field: notes go through the same path as the job's note composer, photos through
// the same on-phone queue as the Photos tab.

/// What happened to a note a tool tried to add. The UI words follow it exactly, so a queued
/// note never reads as "Saved" (golden rule 17).
enum JobNotePostResult: Equatable {
    /// The server stored it.
    case saved
    /// No signal: kept in the outbox on this phone and sent in order later.
    case queued
    case failed(String)

    var message: String {
        switch self {
        case .saved: "Added to the job’s notes."
        case .queued: "Saved on this phone · sends when you’re back online."
        case .failed(let reason): reason
        }
    }

    var succeeded: Bool { self == .saved || self == .queued }
}

/// The job note path the job screen uses (`PaperJobDetailView.saveNote`): offline goes straight to
/// the outbox; online posts `POST /v1/jobs/{id}/notes`; a dropped connection falls back to the outbox.
@MainActor
enum JobNotePoster {
    /// `POST /v1/jobs/{id}/notes` accepts 1–10000 UTF-16 units (docs/audits/field-contracts.md).
    static let maxLength = 10_000

    static func canPost(_ session: SessionController) -> Bool { session.can("job.note", feature: "jobs") }

    static func post(_ body: String, jobID: String, api: APIClient, session: SessionController, outbox: FieldOutbox) async -> JobNotePostResult {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failed("There’s nothing to add yet.") }
        guard trimmed.utf16.count <= maxLength else { return .failed("This note is too long for one job note.") }
        guard canPost(session) else { return .failed("Your role can’t add notes to this job.") }
        func queue() -> JobNotePostResult {
            outbox.enqueue(.note(.init(jobId: jobID, body: trimmed)), policyVersion: session.policyVersion ?? 0) == nil
                ? .failed("This phone couldn’t keep the note. Try again.")
                : .queued
        }
        if session.isOffline { return queue() }
        do {
            _ = try await api.addFieldNote(jobID, body: trimmed)
            return .saved
        } catch is CancellationError {
            return .failed("The note wasn’t sent. Try again.")
        } catch {
            return error.isConnectivityFailure ? queue() : .failed(error.localizedDescription)
        }
    }
}

/// Files a photo through the Photos tab's on-phone queue (`JobMediaView.enqueueDerived`): saved to
/// disk first with a fresh client asset ID, then uploaded when the connection allows.
@MainActor
enum JobPhotoAttach {
    enum Failure: LocalizedError {
        case notAllowed, workspaceChanged, tooLarge
        var errorDescription: String? {
            switch self {
            case .notAllowed: "Your role can’t add photos to this job."
            case .workspaceChanged: "Your workspace changed. Return to the original job before adding photos."
            case .tooLarge: "This photo is too large to save."
            }
        }
    }

    static func canAttach(_ session: SessionController) -> Bool { session.can("job.edit", feature: "jobs") }

    static func save(_ image: UIImage, jobID: String, caption: String, prefix: String,
                     api: APIClient, session: SessionController, pendingMedia: PendingMediaStore) throws {
        guard canAttach(session) else { throw Failure.notAllowed }
        guard let actor = session.user?.id, let organization = session.activeOrganization?.id, let origin = api.normalizedOrigin,
              let context = pendingMedia.captureContext(matching: PendingMediaScope(actorID: actor, organizationID: organization, origin: origin))
        else { throw Failure.workspaceChanged }
        guard let data = JobMediaView.jpeg(image) else { throw Failure.tooLarge }
        let capturedAt = Date()
        let stamp = capturedAt.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "")
        let media = PendingMedia(id: UUID().uuidString, jobID: jobID, filename: "\(prefix)-\(stamp).jpg", tags: [],
                                 capturedAt: capturedAt, kind: "photo", mime: "image/jpeg", caption: caption)
        try pendingMedia.save(media, data: data, context: context)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { await pendingMedia.drain(api: api, jobID: jobID, canUpload: { session.can("job.edit", feature: "jobs") }) }
    }
}

// MARK: - Call the office

/// The workspace's business phone: the `primary_phone` organization fact that web Settings ›
/// Organization and Company details edit (`GET /v1/organization/profile`). Nil when the fact is
/// empty or this role can't read the profile; nothing is ever hard-coded.
struct OfficeContact: Equatable {
    let name: String
    let phone: String

    /// Digits and a leading + only, for `tel:` and `sms:`.
    var dialable: String {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.filter(\.isNumber)
        return trimmed.hasPrefix("+") ? "+" + digits : digits
    }
    var callURL: URL? { dialable.count >= 3 ? URL(string: "tel:\(dialable)") : nil }
    var textURL: URL? { dialable.count >= 3 ? URL(string: "sms:\(dialable)") : nil }

    /// The last answer per workspace for this launch, so the buttons don't flicker per screen.
    @MainActor private static var memory: [String: OfficeContact?] = [:]

    @MainActor
    static func load(api: APIClient, session: SessionController) async -> OfficeContact? {
        guard let organization = session.activeOrganization else { return nil }
        if let known = memory[organization.id] { return known }
        do {
            let profile = try await api.organizationProfile()
            guard profile.organizationId == organization.id else { return nil }
            let contact = profile.value("primary_phone").flatMap { raw -> OfficeContact? in
                let phone = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return phone.isEmpty ? nil : OfficeContact(name: organization.name, phone: phone)
            }
            memory[organization.id] = contact
            return contact
        } catch {
            // 403 (role can't read the profile) or no signal: show nothing rather than guess.
            return nil
        }
    }

    @MainActor static func clearAll() { memory = [:] }
}

/// Two quiet circles, Call office and Text office, shown only when the workspace has a business
/// phone this person can read. Drop it in a header or a toolkit row.
struct OfficeContactActions: View {
    var size: CGFloat = 36
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @Environment(\.openURL) private var openURL
    @State private var contact: OfficeContact?

    var body: some View {
        HStack(spacing: 4) {
            if let contact, let call = contact.callURL, let text = contact.textURL {
                PaperCircleButton(symbol: "phone", label: "Call the office, \(contact.phone)", size: size) { openURL(call) }
                PaperCircleButton(symbol: "message", label: "Text the office, \(contact.phone)", size: size) { openURL(text) }
            }
        }
        .task(id: session.activeOrganization?.id) { contact = await OfficeContact.load(api: api, session: session) }
    }
}

#if DEBUG
/// `--paper-preview-screen tool-scan | tool-checklist | tool-checklist-pick`: the on-site tools on
/// fixed data. The scan shows the photo fallback (as in the simulator) with canned OCR lines.
struct OnsiteToolsPreview: View {
    let screen: String
    @EnvironmentObject private var session: SessionController

    static let plateLines = [
        "CARRIER CORPORATION  INDIANAPOLIS, IN",
        "MODEL NO. 24ACC636A003",
        "SERIAL NO. 1219E56789",
        "MFG DATE 03/2019",
        "VOLTS 208/230  PH 1  HZ 60",
        "COMPRESSOR RLA 14.1  LRA 77",
    ]

    var body: some View {
        Group {
            switch screen {
            case "tool-scan":
                DataPlateScannerSheet(jobID: PaperPreview.jobID, customerID: PaperPreview.customerID, previewLines: Self.plateLines) {}
            case "tool-checklist":
                JobChecklistSheet(jobID: PaperPreview.jobID,
                                  previewRun: ChecklistRun(templateID: "hvac-service", done: ["thermostat", "filter", "pressure-suction", "amps"],
                                                           readings: ["pressure-suction": "118", "amps": "14.6"], photos: ["filter": 1])) {}
            default:
                JobChecklistSheet(jobID: PaperPreview.jobID) {}
            }
        }
        .task { if session.phase != .ready { await session.restore() } }
    }
}
#endif
