import CryptoKit
import Foundation

/// Idempotency keys for billing schedule money requests (a deposit, Bill remainder, Release
/// retainage), kept on the phone until the server has answered with success. A request whose
/// answer was lost may still have issued an invoice, so the same request sent again, after the
/// sheet or the app was closed, carries the same key and the server answers with that invoice
/// instead of issuing a second one. This is the web's billing-money-intent.
///
/// Each key is filed under a SHA-256 digest of the person, the company, the path and the body,
/// so a different amount or command gets its own key, and no customer data is in a stored name.
/// A refusal keeps the key as well: the server undoes a refused command, so the key has no invoice
/// behind it and the same request sent later is a new one to the server. It cannot reach another
/// request, whose digest differs. Sign-out clears every key.
struct BillingMoneyIntents {
    /// What a request is bound to, apart from the person and the company.
    struct Request: Equatable {
        let path: String
        let body: [String]

        /// `POST /v1/billing-schedules/deposit-requests` with the job and the amount.
        static func deposit(jobID: String, amountCents: Int) -> Request {
            Request(path: "/v1/billing-schedules/deposit-requests", body: [jobID, String(amountCents), "USD"])
        }

        /// `bill-remainder` or `release-retainage` on one schedule; the key is its only body.
        static func scheduleCommand(scheduleID: String, command: String) -> Request {
            Request(path: "/v1/billing-schedules/\(scheduleID)/\(command)", body: [])
        }
    }

    private let defaults: UserDefaults
    private static let storageKey = "thorbis.billingMoneyIntents.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// The key to send: the one saved for this request, or a new one saved before it is returned.
    /// Nil when there is no person or company, or the key could not be saved, so the request is
    /// never sent with a key a retry would not find.
    func key(for request: Request, actorID: String?, organizationID: String?) -> String? {
        guard let actorID, let organizationID else { return nil }
        let digest = Self.digest(request, actorID: actorID, organizationID: organizationID)
        var all = load()
        if let saved = all[digest], !saved.isEmpty { return saved }
        let key = UUID().uuidString
        all[digest] = key
        defaults.set(all, forKey: Self.storageKey)
        guard load()[digest] == key else { return nil }
        return key
    }

    /// Call only after a 2xx. Removes the key only while it is still the one that was sent.
    func complete(_ request: Request, key: String, actorID: String?, organizationID: String?) {
        guard let actorID, let organizationID else { return }
        let digest = Self.digest(request, actorID: actorID, organizationID: organizationID)
        var all = load()
        guard all[digest] == key else { return }
        all[digest] = nil
        defaults.set(all, forKey: Self.storageKey)
    }

    func clearAll() { defaults.removeObject(forKey: Self.storageKey) }

    private func load() -> [String: String] {
        (defaults.dictionary(forKey: Self.storageKey) as? [String: String]) ?? [:]
    }

    /// Each part is prefixed with its length, so no two different requests read the same.
    private static func digest(_ request: Request, actorID: String, organizationID: String) -> String {
        let canonical = ([actorID, organizationID, request.path] + request.body)
            .map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
