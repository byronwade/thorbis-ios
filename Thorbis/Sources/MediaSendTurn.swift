import Foundation

/// Which send loop on a job's photo screen holds Send now. One loop runs at a time. The loop
/// that holds the turn gives it back when it returns, whatever the session looks like by then,
/// and a loop that no longer holds it changes nothing.
struct MediaSendTurn: Equatable {
    private var issued = 0
    /// The loop that holds the turn, or nil when none is running.
    private(set) var holder: Int?

    var isSending: Bool { holder != nil }

    /// A number for a new loop, or nil while another loop has not returned yet.
    mutating func begin() -> Int? {
        guard holder == nil else { return nil }
        issued += 1
        holder = issued
        return issued
    }

    /// Called once the loop numbered `run` has returned.
    mutating func end(_ run: Int) {
        if holder == run { holder = nil }
    }
}
