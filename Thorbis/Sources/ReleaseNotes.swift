import Foundation

/// What changed in each update, shown once in the What's new sheet (design.thorbis.com MA-19..MA-22).
///
/// How to add notes: the pull request that changes what people see adds a new entry at the TOP
/// of `all`, with an id that is never reused. Unshipped entries fold together in the sheet, so
/// two PRs in one build just means two entries. Write for the person doing the work (MA-21):
/// - `title`: what they can now do, at most 40 characters ("Mark arrived from the lock screen").
/// - `detail`: one sentence, at most 110 characters, in domain words. No ticket ids or code names.
/// - At most five highlights per entry; anything smaller goes in `fixes` as a count.
/// - `symbol` is an SF Symbol outline name. A change nobody can see gets no note.
/// `WhatsNewTests` checks every rule above.
enum ReleaseNotes {
    static let all: [ReleaseNote] = [
        ReleaseNote(
            id: "2026-10-28-job-screen",
            date: "2026-10-28",
            highlights: [
                .init(symbol: "ellipsis.circle", title: "Every job action in one menu",
                      detail: "Pause, reschedule, assign, deposit and wrap up now live in the ••• at the top right of a job."),
                .init(symbol: "person.2", title: "Call or text any contact on the job",
                      detail: "Every contact is listed with their own Call, Text and Email, and how they like to be reached."),
                .init(symbol: "key", title: "Gate codes, dogs and parking up front",
                      detail: "Getting in shows each code on its own line. Long press a code to copy it."),
                .init(symbol: "clock.arrow.circlepath", title: "See what happened on past visits",
                      detail: "A job lists the customer's earlier visits with the office's note from each one."),
                .init(symbol: "wrench.and.screwdriver", title: "Equipment and membership on the job",
                      detail: "Units at the site, their warranty and the customer's plan show without leaving the job."),
            ],
            fixes: 3
        ),
        ReleaseNote(
            id: "2026-10-28-whats-new",
            date: "2026-10-28",
            highlights: [
                .init(symbol: "sparkles", title: "See what changed after each update",
                      detail: "This sheet shows once after an update. Find it again any time in Settings."),
                .init(symbol: "magnifyingglass", title: "Find invoices by customer or number",
                      detail: "Search on Invoices now matches the customer's name and the invoice number."),
                .init(symbol: "arrow.clockwise", title: "Try again when a list fails to load",
                      detail: "Estimates, invoices, closeout and follow-ups offer Try again instead of a dead end."),
                .init(symbol: "hand.tap", title: "A tap you can feel when work is done",
                      detail: "Completing, sending, approving and getting paid now confirm with a light tap."),
                .init(symbol: "figure.walk.motion", title: "Calmer motion with Reduce Motion on",
                      detail: "Every animation now follows the Reduce Motion setting on your phone."),
            ],
            fixes: 6
        ),
    ]
}

struct ReleaseNote: Identifiable, Equatable, Sendable {
    /// Stable and never reused: the sheet remembers which ids a person has seen.
    let id: String
    /// The day the change merged, as yyyy-MM-dd.
    let date: String
    let highlights: [Highlight]
    /// Smaller fixes, shown only as a count.
    var fixes = 0

    struct Highlight: Equatable, Sendable {
        let symbol: String
        let title: String
        let detail: String
    }

    static let maxTitle = 40
    static let maxDetail = 110
    static let maxHighlights = 5

    /// Noon UTC, so the label shows the same day in every US time zone.
    var day: Date? { try? Date("\(date)T12:00:00Z", strategy: .iso8601) }

    /// "Oct 28"
    var dayLabel: String { day?.formatted(.dateTime.month(.abbreviated).day()) ?? date }
}
