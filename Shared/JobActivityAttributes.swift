import ActivityKit
import Foundation

/// The Lock Screen and Dynamic Island card for the job a technician is driving to or working on.
/// Shared by the app (which starts, updates and ends it) and the widget extension (which draws it).
struct JobActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The job lifecycle status: en_route, arrived, in_progress or paused.
        var status: String
        /// When the job entered this status, for the running timer.
        var since: Date
        /// The step is saved on the phone and has not reached the server yet.
        var waitingToSync: Bool
    }

    let jobID: String
    let jobNumber: String
    let title: String
    let customer: String
    let address: String?
}

extension JobActivityAttributes.ContentState {
    var label: String {
        switch status {
        case "en_route": "On my way"
        case "arrived": "On site"
        case "in_progress": "Working"
        case "paused": "Paused"
        default: status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var symbol: String {
        switch status {
        case "en_route": "car.fill"
        case "arrived": "mappin.and.ellipse"
        case "in_progress": "wrench.and.screwdriver.fill"
        case "paused": "pause.fill"
        default: "circle"
        }
    }

    /// 0 driving, 1 on site, 2 working; drives the three-step progress row.
    var step: Int {
        switch status {
        case "en_route": 0
        case "arrived": 1
        default: 2
        }
    }
}

enum JobActivityLink {
    /// Stands in for a job id: the job under way, else the next booked one.
    static let nextJob = "next"

    static func url(jobID: String) -> URL? { URL(string: "thorbis://job/\(jobID)") }

    static func jobID(from url: URL) -> String? {
        guard url.scheme == "thorbis", url.host() == "job" else { return nil }
        let id = url.pathComponents.dropFirst().first ?? ""
        return id.isEmpty ? nil : id
    }
}
