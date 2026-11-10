import SwiftUI

/// One booking or travel notice for a job (`GET /v1/jobs/:id/notices`, web job-detail JobNoticeSection).
struct JobNoticeStatus: Decodable, Identifiable, Hashable {
    let id: String
    let role: String
    let channel: String
    let stage: String?
    let status: String
    let reason: String?
    let scheduledFor: String
    let currentCycle: Bool?
    let createdAt: String

    /// The web's words (NOTICE_ROLE_LABELS, NOTICE_STATUS_WORDS, NOTICE_STAGE_WORDS).
    var who: String {
        let role = ["customer": "Customer", "technician": "Tech", "owner": "Owner", "dispatcher": "Dispatcher"][role] ?? role.capitalized
        return "\(role) \u{00B7} \(channel == "in_app" ? "In app" : "Email")"
    }
    var statusWord: String {
        ["queued": "Queued", "processing": "Sending", "sent": "Sent", "failed": "Not sent",
         "missing_contact": "No contact", "canceled": "Canceled", "unresolved": "Unconfirmed"][status]
            ?? status.replacingOccurrences(of: "_", with: " ").capitalized
    }
    var tint: Color? {
        switch status {
        case "sent": Theme.success
        case "failed", "missing_contact": Theme.destructive
        default: nil
        }
    }
    var line: String {
        let cycle = currentCycle == true ? "Latest booking" : currentCycle == false ? "Earlier booking" : "Booking"
        let stageWord = stage.flatMap { ["en_route": "On the way", "arrived": "Arrived", "started": "Started",
                                         "completed": "Complete", "canceled": "Canceled"][$0] }
        let when = JobFiltering.date(scheduledFor).map { "\($0.formatted(.dateTime.month(.abbreviated).day())) \($0.tradeTime)" }
        let why = reason.map { $0.replacingOccurrences(of: "_", with: " ") }
        // Which booking (and stage) on one line, when (and why) on the next: no dot left at a line end.
        let first = [cycle, stageWord].compactMap { $0 }.joined(separator: " \u{00B7} ")
        let second = [when, why].compactMap { $0 }.joined(separator: " \u{00B7} ")
        return second.isEmpty ? first : "\(first)\n\(second)"
    }
}

extension APIClient {
    func jobNotices(_ jobID: String) async throws -> (admission: String?, items: [JobNoticeStatus]) {
        struct Page: Decodable { let admission: String?; let items: [JobNoticeStatus] }
        let key = jobID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobID
        let page: Page = try await send("GET", "/v1/jobs/\(key)/notices",
                                        queryItems: [URLQueryItem(name: "limit", value: "100")])
        return (page.admission, page.items)
    }
}

/// Web parity: who was told about this booking and whether it reached them (role, channel and
/// status only, never an address or the message). Hidden when the workspace has booking notices
/// off, the read is refused, or the server is older.
struct JobNoticesSection: View {
    let jobID: String
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionController
    @State private var items: [JobNoticeStatus] = []
    @State private var admission: String?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(width: 0, height: 0)
            if loaded {
                let failed = items.filter { ["failed", "missing_contact"].contains($0.status) }.count
                JobPanelSection(title: "Notices", count: failed > 0 ? "\(failed) not sent" : items.isEmpty ? nil : "\(items.count)") {
                    if items.isEmpty {
                        JobPanelRow(title: admission == "not_scheduled" ? "No time booked yet" : "Nothing sent yet",
                                    subtitle: admission == "not_scheduled" ? "Booking notices go out once the job has a time."
                                                                           : "Booking and on-the-way notices show here once they go out.",
                                    titleSize: 15)
                    }
                    ForEach(items.prefix(8)) { notice in
                        JobPanelRow(title: notice.who, subtitle: notice.line, titleSize: 15) {
                            StatusWord(text: notice.statusWord, tint: notice.tint)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .task(id: "\(jobID)|\(session.generation)|\(session.isOffline)") { await load() }
    }

    private func load() async {
        guard !session.isOffline else { return }
        do {
            let page = try await api.jobNotices(jobID)
            items = page.items.sorted { $0.createdAt > $1.createdAt }
            admission = page.admission
            loaded = true
        } catch is CancellationError {
        } catch {
            // Notices off for this workspace, no access, or an older server: leave the section out.
            loaded = false
        }
    }
}
