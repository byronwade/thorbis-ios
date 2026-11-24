import SwiftUI

// The office call log (web Inbox › calls, apps/web features/inbox/server-calls.tsx).
// `GET /v1/calls` needs customer.view across the whole company and the call_recording feature;
// a narrower role gets 403 and sees no Calls tab content, as on the web. Their booking call
// reaches them on the job instead (JS-05).

struct CallLogPage: Decodable {
    let items: [BookingCallRecord]
    let nextCursor: String?
}

extension APIClient {
    func call(_ id: String) async throws -> BookingCallRecord {
        try await send("GET", "/v1/calls/\(try Self.callID(id))")
    }

    /// Links the call to the job it booked, or unlinks it with nil. The server checks job.edit.
    func linkCall(_ id: String, jobID: String?) async throws -> BookingCallRecord {
        struct Body: Encodable {
            let jobId: String?
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(jobId, forKey: .jobId)  // null unlinks, so it is always sent
            }
            enum CodingKeys: String, CodingKey { case jobId }
        }
        return try await send("POST", "/v1/calls/\(try Self.callID(id))/link", body: Body(jobId: jobID))
    }

    private static func callID(_ id: String) throws -> String {
        guard UUID(uuidString: id) != nil else { throw Problem(title: "Invalid call ID", status: nil, detail: id) }
        return id.lowercased()
    }
}

enum CallLogRules {
    /// The Calls tab shows for roles that can read the log; the server still decides (403 hides it).
    @MainActor static func available(_ session: SessionController) -> Bool {
        session.can("customer.view", feature: "call_recording")
    }

    /// The newest jobs on this phone, as the web's Link to job menu offers.
    static func linkableJobs(_ jobs: [Job], limit: Int = 20) -> [Job] {
        Array(jobs.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }.prefix(limit))
    }
}
