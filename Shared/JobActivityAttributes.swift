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
    /// The street line of the job's own service location; nil when the job records no site.
    let address: String?
    /// Which access facts the site has on record ("Gate code · Dog on site"), shown once on site.
    /// Labels only: the codes themselves never go on the Lock Screen.
    var access: String? = nil
    /// When the visit is booked, for "Booked 10:30 AM" while driving.
    var scheduledFor: Date? = nil

    /// Street first; without a recorded site the job's own title leads (BYR-1593).
    var headline: String { address ?? title }
    /// The problem (when the street leads) and the customer, under the headline.
    var subline: String {
        [address == nil ? nil : title, customer.isEmpty ? nil : customer].compactMap { $0 }.joined(separator: " · ")
    }
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

    /// A status word short enough for the minimal Dynamic Island.
    var shortLabel: String {
        switch status {
        case "en_route": "Driving"
        case "arrived": "On site"
        case "in_progress": "Working"
        case "paused": "Paused"
        default: label
        }
    }

    /// Whether the technician is at the site (access facts are only useful there).
    var isOnSite: Bool { ["arrived", "in_progress", "paused"].contains(status) }

    /// The one forward field step the card offers, or nil when the next move needs the app
    /// (pausing, resuming and finishing need the server's audit state and a wrap-up).
    var nextStep: JobNextStep? { JobNextStep.after(status) }

    /// 0 driving, 1 on site, 2 working; drives the three-step progress row.
    var step: Int {
        switch status {
        case "en_route": 0
        case "arrived": 1
        default: 2
        }
    }
}

/// The next forward field step for a job: On my way, Arrive or Start work.
struct JobNextStep: Equatable {
    /// The job status the step moves to (en_route, arrived or in_progress).
    let target: String
    let title: String
    let symbol: String

    /// The button's word on the Lock Screen and in the Dynamic Island: On my way → Arrived → Start.
    var buttonTitle: String {
        switch target {
        case "arrived": "Arrived"
        case "in_progress": "Start"
        default: title
        }
    }

    static func after(_ status: String) -> JobNextStep? {
        switch status {
        case "scheduled", "dispatched": JobNextStep(target: "en_route", title: "On my way", symbol: "car.fill")
        case "en_route": JobNextStep(target: "arrived", title: "Arrive", symbol: "mappin.and.ellipse")
        case "arrived": JobNextStep(target: "in_progress", title: "Start work", symbol: "wrench.and.screwdriver.fill")
        default: nil
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
