import SwiftUI
import UIKit

// Paper "Can't start" (Job tools): on site, before work starts, the tech says why the job can't
// start and tells dispatch. There is no "can't start" status on the server: from `arrived` the job
// may only go to en_route, in_progress, completed or canceled, and pause needs in_progress. So the
// job's status is left alone and the sheet records a `notify_office` follow-up
// (`POST /v1/jobs/{id}/followups`) with the reason and the note; dispatch decides what happens next.

/// What stops the job from starting (Paper's four choices) and the follow-up it becomes.
enum CantStartReason: String, CaseIterable, Identifiable, Sendable {
    case noOneHome, wrongPart, unsafe, needsApproval

    var id: String { rawValue }

    var label: String {
        switch self {
        case .noOneHome: "No one home"
        case .wrongPart: "Wrong part"
        case .unsafe: "Unsafe"
        case .needsApproval: "Needs approval"
        }
    }

    var symbol: String {
        switch self {
        case .noOneHome: "house"
        case .wrongPart: "shippingbox"
        case .unsafe: "exclamationmark.triangle"
        case .needsApproval: "clock"
        }
    }

    /// The follow-up's required next step; Paper asks no such question, so each reason names one.
    var nextAction: String {
        switch self {
        case .noOneHome: "Reach the customer and book a new visit."
        case .wrongPart: "Get the right part and book a return visit."
        case .unsafe: "Review the safety problem before anyone goes back."
        case .needsApproval: "Get the approval so the work can start."
        }
    }
}

/// The follow-up a "Can't start" sends, built once so the online request and the queued outbox
/// payload carry the same words. Pure; no UI and no main-actor state.
struct CantStartReport: Equatable, Sendable {
    /// `requestFollowUpInputSchema`: reason and nextAction are 1–2000 characters each.
    static let maxLength = 2000

    let reason: CantStartReason
    let note: String

    var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "Can't start: No one home", then the note when there is one.
    var followUpReason: String {
        let head = "Can\u{2019}t start: \(reason.label)"
        return trimmedNote.isEmpty ? head : "\(head). \(trimmedNote)"
    }

    var isTooLong: Bool { followUpReason.utf16.count > Self.maxLength }

    var kind: FieldFollowUpRequest.Kind { .notifyOffice }

    var request: FieldFollowUpRequest {
        FieldFollowUpRequest(kind: kind, reason: followUpReason, nextAction: reason.nextAction)
    }

    func payload(jobID: String) -> OutboxEntry.FollowUpPayload {
        OutboxEntry.FollowUpPayload(jobId: jobID, kind: kind.rawValue, reason: followUpReason, nextAction: reason.nextAction)
    }
}

/// What happened when Tell dispatch was pressed. A queued report never reads as sent.
enum CantStartOutcome: Equatable {
    /// The server stored the follow-up.
    case sent
    /// No signal: kept in the outbox on this phone and sent in order later.
    case queued

    var message: String {
        switch self {
        case .sent: "Sent to the office."
        case .queued: "Saved on this phone · sends to the office when you\u{2019}re back online."
        }
    }
}

/// The "Can't start" sheet. Present it with `.sheet { SheetSurface { CantStartSheet(...) } }` from
/// the job screen while the job is arrived; `onDone` gets the outcome, or nil when cancelled, and
/// the presenter closes the sheet.
struct CantStartSheet: View {
    let jobID: String
    let onDone: (CantStartOutcome?) -> Void

    init(jobID: String, onDone: @escaping (CantStartOutcome?) -> Void) {
        self.jobID = jobID
        self.onDone = onDone
    }

    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @EnvironmentObject private var outbox: FieldOutbox
    @EnvironmentObject private var pendingMedia: PendingMediaStore
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var selection: CantStartReason?
    @State private var note = ""
    @State private var busy = false
    @State private var reasonProblem: String?
    @State private var noteProblem: String?
    @State private var error: String?
    /// Photos taken in this sheet; each is already saved to the job's photo queue.
    @State private var photos: [UIImage] = []
    @State private var showCamera = false

    private var canSend: Bool { session.can("job.edit", feature: "jobs") }
    private var canPhoto: Bool { JobPhotoAttach.canAttach(session) && UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        // Paper F3A: Cancel is the pill beside the centred title; only Tell dispatch sits at the bottom.
        ThorbisModalSheet(title: "Can\u{2019}t start", closeLabel: "Cancel", onClose: busy ? nil : { onDone(nil) },
                          closeStyle: .headerPill, detents: [.large], commitTitle: "Tell dispatch", busy: busy,
                          commitDisabledReason: canSend ? nil : "Your role can\u{2019}t send this to dispatch. Call your office.",
                          commitIdentifier: "cant-start-commit", commit: { attemptSend() }) {
            ThorbisSheetField(label: "What\u{2019}s stopping you?", error: reasonProblem) {
                reasonGrid
            }
            if canPhoto || !photos.isEmpty { photoRow }
            ThorbisSheetField(label: "Note", error: noteProblem ?? error) {
                TextField("Note", text: $note,
                          prompt: .placeholder("Knocked and called twice. Gate code worked, no answer at the door."),
                          axis: .vertical)
                    .font(Theme.font(16)).lineLimit(2...6)
                    .fieldWell()
                    .onChange(of: note) { _, _ in noteProblem = nil }
                    .accessibilityLabel("Note")
                    .accessibilityIdentifier("cant-start-note")
            }
            footer
        }
        .interactiveDismissDisabled(busy || selection != nil || !note.isEmpty || !photos.isEmpty)
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { image in
                showCamera = false
                if let image { attach(image) }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Reasons

    /// Two by two; one column at accessibility sizes so the words stay whole.
    private var reasonGrid: some View {
        let rows: [[CantStartReason]] = typeSize.isAccessibilitySize
            ? CantStartReason.allCases.map { [$0] }
            : [[.noOneHome, .wrongPart], [.unsafe, .needsApproval]]
        return VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row) { reason in reasonTile(reason) }
                }
            }
        }
    }

    private func reasonTile(_ reason: CantStartReason) -> some View {
        let isOn = selection == reason
        return Button {
            selection = reason
            reasonProblem = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: reason.symbol)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(isOn ? Theme.brandText : Theme.muted)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(reason.label)
                    .font(Theme.font(15, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(isOn ? Theme.brandText : Theme.foreground)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(isOn ? Theme.brandSurface : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if isOn {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.brand, lineWidth: 1.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(busy)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("cant-start-reason-\(reason.rawValue)")
    }

    // MARK: Photos

    private var photoRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(photos.indices, id: \.self) { index in
                    Image(uiImage: photos[index])
                        .resizable().scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityLabel("Photo \(index + 1), added to the job")
                }
                if canPhoto {
                    Button { showCamera = true } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 18, weight: .medium)).accessibilityHidden(true)
                            Text("Photo").font(Theme.font(13, weight: .semibold))
                        }
                        .foregroundStyle(Theme.foreground)
                        .frame(width: 96, height: 96)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressStyle())
                    .disabled(busy)
                    .accessibilityLabel("Take photo")
                    .accessibilityHint("Adds the photo to this job")
                    .accessibilityIdentifier("cant-start-photo")
                }
            }
        }
        .scrollClipDisabled()
    }

    private func attach(_ image: UIImage) {
        do {
            try JobPhotoAttach.save(image, jobID: jobID, caption: "Can\u{2019}t start", prefix: "cant-start",
                                    api: api, session: session, pendingMedia: pendingMedia)
            photos.append(image)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Footer

    private var footer: some View {
        Text(session.isOffline
             ? "No signal \u{00B7} saved on this phone and sent to the office when you\u{2019}re back online."
             // The server files it as a follow-up on the job for the office; it does not page anyone.
             : "Goes to the office as a follow-up on this job.")
            .font(Theme.font(14)).foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    // MARK: Send

    /// Never pre-disabled: pressed with nothing chosen, it says so under the question.
    private func attemptSend() {
        guard !busy else { return }
        guard let selection else {
            reasonProblem = "Choose what\u{2019}s stopping you."
            return
        }
        let report = CantStartReport(reason: selection, note: note)
        guard !report.isTooLong else {
            noteProblem = "Keep it under 2,000 characters."
            return
        }
        Task { await send(report) }
    }

    /// The follow-up path the job's Follow-ups screen uses (`JobFollowUpsView.create`): offline goes
    /// to the outbox; a dropped connection is queued as attempted so the resend checks first.
    private func send(_ report: CantStartReport) async {
        busy = true
        defer { busy = false }
        let payload = report.payload(jobID: jobID)
        func keep(attempted: Bool) {
            guard outbox.enqueue(.followUp(payload), policyVersion: session.policyVersion ?? 0, attempted: attempted) != nil else {
                error = "This couldn\u{2019}t be saved on this phone. Try again when you have signal."
                return
            }
            error = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onDone(.queued)
        }
        if session.isOffline { keep(attempted: false); return }
        do {
            _ = try await api.requestFieldFollowUp(jobID, request: report.request)
            error = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onDone(.sent)
        } catch is CancellationError {
        } catch {
            if error.isConnectivityFailure { keep(attempted: true) } else { self.error = error.localizedDescription }
        }
    }
}
