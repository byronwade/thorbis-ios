#if DEBUG
import SwiftUI

/// Screenshot harness for the first-run and edge states (see PaperPreview.statesScreen).
/// Every screen here is the shipping view; only the session's phase is forced, and the
/// galleries show the shipping components with the copy their call sites use.
struct StatesPreview: View {
    let screen: String
    @EnvironmentObject private var session: SessionController
    @State private var forced = false

    var body: some View {
        Group {
            switch screen {
            case "state-opening": SessionLoadingView(message: "Opening your workspace…")
            case "state-signing-out": SessionLoadingView(message: "Signing out…")
            case "state-empty": NavigationStack { EmptyStatesGallery() }
            case "state-errors": NavigationStack { ErrorStatesGallery() }
            case "state-loading": NavigationStack { LoadingStatesGallery() }
            case "state-customer": NavigationStack { CustomerStatesGallery() }
            case "state-sheets": SheetStatesGallery()
            case "state-toasts": NavigationStack { ToastStatesGallery() }
            case "state-workspaces":
                if forced { WorkspaceGateView() } else { SessionLoadingView(message: "Opening your workspace…") }
            default:
                if forced { LoginView(attempted: screen == "state-login-error") } else { SessionLoadingView(message: "Opening your workspace…") }
            }
        }
        .task {
            // Let the preview session settle first, then show the state being captured.
            while session.phase == .restoring { try? await Task.sleep(for: .milliseconds(100)) }
            switch screen {
            case "state-login": session.previewForce(.signedOut)
            case "state-login-error": session.previewForce(.failed, error: "Invalid email or password")
            case "state-session-expired": session.previewForce(.failed, error: "Your session expired. Sign in again.")
            case "state-restore-failed": session.previewForce(.failed, error: "No connection. Check your signal and try again.")
            case "state-workspaces": session.previewForce(.choosingWorkspace)
            default: break
            }
            forced = true
        }
    }
}

private struct EmptyStatesGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PaperSection("Jobs") { PaperEmptyState(symbol: "briefcase", title: "No open jobs", actionTitle: "Book a job") {} }
                PaperSection("Photos") { PaperEmptyState(symbol: "camera", title: "No photos yet", actionTitle: "Take a photo") {} }
                PaperSection("Follow-ups") { PaperEmptyState(symbol: "list.bullet", title: "No follow-ups on this job") }
                PaperSection("Search") { PaperEmptyState.search("Hartley") }
                PaperSection("Assign") {
                    PaperEmptyState(symbol: "person.crop.circle.badge.xmark", title: "Assignment is off for your role",
                                    message: "Ask your office for access to assign jobs.")
                }
            }
            .paperCardMargin().padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle("Empty states")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ErrorStatesGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                label("No signal")
                ErrorBanner(error: Problem(title: "Network error", status: nil, detail: "No connection. Check your signal and try again."),
                            retry: {})
                label("Server trouble")
                ErrorBanner(error: Problem(title: "HTTP 503", status: 503, detail: nil), retry: {})
                label("No access")
                ErrorBanner(error: Problem(title: "Forbidden", status: 403, detail: nil), subject: "invoices", retry: {})
                label("Session ended")
                ErrorBanner(error: Problem(title: nil, status: 401, detail: nil))
                label("Settings")
                PermissionNotice(permission: .camera, purpose: "add photos to jobs")
                PermissionNotice(permission: .microphone, purpose: "dictate notes",
                                 message: "Dictation needs Microphone and Speech Recognition. Turn them on for Thorbis in Settings.")
                PermissionNotice(permission: .location, purpose: "see the drive to your next stop")
                PermissionNotice(permission: .notifications, purpose: "hear about new jobs")
                label("Next to a field")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Email").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
                    Text("ramon@").font(Theme.font(16)).fieldWell()
                    FieldProblem(message: "That doesn’t look like an email. Check it and try again.")
                }
                .padding(.horizontal, Theme.gutter)
            }
            .padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle("Errors")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted)
            .padding(.horizontal, Theme.gutter + 4).padding(.top, 14)
    }
}

/// The customer-facing states (2026-10-31 leftovers), with the copy their call sites use.
private struct CustomerStatesGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                label("Loading an estimate")
                CustomerSkeleton(caption: "Opening your estimate…", lines: 2)
                label("No signal while opening")
                CustomerStateMessage(symbol: "wifi.slash", title: "We couldn’t open your estimate",
                                     message: Problem(title: "Network error", status: nil, detail: nil)
                                        .customerSentence(.openEstimate))
                label("Changed under the customer")
                CustomerStateMessage(symbol: "hand.raised", title: "Please hand the device back",
                                     message: "Your technician needs to reload this job.",
                                     actionTitle: "Hand back to the technician") {}
                label("Public link ended")
                CustomerStateMessage(symbol: "link.badge.exclamationmark", title: "This estimate link has ended",
                                     message: "This estimate link is expired, replaced, or no longer current. Ask the company for a new link.",
                                     actionTitle: "Close") {}
                label("Inside a document")
                CustomerProblemBanner(message: "Payments couldn't be loaded. The invoice's paid amount is shown above.",
                                      actionTitle: "Try again") {}
                CustomerProblemBanner(message: Problem(title: "HTTP 503", status: 503, detail: nil).customerSentence(.openInvoice),
                                      actionTitle: "Try again") {}
                label("Your details")
                CustomerStateMessage(symbol: "person.crop.circle.badge.exclamationmark", title: "We couldn’t open your details",
                                     message: Problem(title: "Unexpected", status: 422, detail: "decode failure").customerSentence(.openDetails),
                                     actionTitle: "Try again") {}
            }
            .padding(.horizontal, Theme.gutter).padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle("Customer states")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.muted).padding(.top, 18)
    }
}

/// The job's status picker as the status chip opens it (a dispatched job's moves), shown open.
private struct SheetStatesGallery: View {
    var body: some View {
        Color.clear
            .background(Theme.background.ignoresSafeArea())
            .sheet(isPresented: .constant(true)) {
                ThorbisMenuCard(items: StatesPreviewFixtures.statusPickerItems, title: StatesPreviewFixtures.statusPickerTitle) { _ in }
            }
    }
}

/// The undo confirmation the estimate builder shows after a line is removed.
private struct ToastStatesGallery: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            LineRemovedToast(removed: StatesPreviewFixtures.removedLine, undo: {}, expire: {})
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle("Confirmations")
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum StatesPreviewFixtures {
    static let statusPickerTitle = "Change status"
    static var statusPickerItems: [ThorbisMenuItem] {
        [ThorbisMenuItem("On my way") {}, ThorbisMenuItem("Mark arrived") {}, ThorbisMenuItem("Start work") {},
         ThorbisMenuItem("Pause job…") {}, ThorbisMenuItem("Move back to scheduled") {}]
    }
    static var removedLine: RemovedLine {
        RemovedLine(line: EstimateRevisionLineDraft(description: "PEX crimp rings, 1-in.", quantity: "1", unitPrice: "15.13"), index: 0, optionID: nil)
    }
}

private struct LoadingStatesGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SkeletonSection(rows: 3, leading: true)
                SkeletonSection(rows: 2)
            }
            .paperCardMargin().padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle("Loading")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
