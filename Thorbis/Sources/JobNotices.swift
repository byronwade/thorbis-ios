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
    /// The newest 100 notices. `more` is true when the server has older ones past this page.
    func jobNotices(_ jobID: String) async throws -> (admission: String?, items: [JobNoticeStatus], more: Bool) {
        struct Page: Decodable { let admission: String?; let items: [JobNoticeStatus]; let nextCursor: String? }
        let key = try Self.pathSegment(jobID)
        let page: Page = try await send("GET", "/v1/jobs/\(key)/notices",
                                        queryItems: [URLQueryItem(name: "limit", value: "100")])
        return (page.admission, page.items, page.nextCursor != nil)
    }
}
