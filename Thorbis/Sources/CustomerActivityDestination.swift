import Foundation

/// Where one customer-activity item opens when tapped. The customer history feed
/// mixes records (`kind` + `subjectId`); this is the single place that decides which
/// in-app detail each kind leads to, so the feed — and any future feed that reuses it —
/// route the same way.
///
/// Kinds we can open get a `PaperRoute`; kinds with no standalone detail screen yet
/// (payment, contact, location) return `nil` and stay non-interactive rather than
/// taking the tech to a dead end. Those gaps are tracked in
/// docs/gaps/activity-feed-destinations.md.
extension CustomerHistoryEntry {
    var destination: PaperRoute? {
        switch kind {
        case "estimate": .estimate(subjectId)
        case "invoice": .invoice(subjectId)
        case "job": .job(subjectId)
        default: nil
        }
    }
}
