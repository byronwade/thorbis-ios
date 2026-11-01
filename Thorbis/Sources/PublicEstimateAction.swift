import Foundation
import Combine

struct PublicEstimateAction: Decodable, Equatable {
    let kind: String
    let title: String
    let status: Status
    let revisionNumber: Int
    let contentHash: String
    let allowedActions: [String]
    let nonce: String?
    let totalAmount: Double
    let currency: String
    let html: String?
    let approvalWithoutSignatureAllowed: Bool?
    let scopeLines: [ScopeLine]?
    let options: [Option]?
    let consentVersion: String?
    let consentText: String?
    let acceptance: Acceptance?

    enum Status: String, Decodable, Equatable {
        case sent
        case approved
        case declined
        case changesRequested = "changes_requested"
    }

    struct ScopeLine: Decodable, Equatable, Identifiable {
        let id: String
        let description: String
        let quantity: Double
        let unitPrice: Double
    }

    struct Option: Decodable, Equatable, Identifiable {
        let id: String
        let title: String
        let description: String
        let totalAmount: Double
        let currency: String
    }

    struct Acceptance: Decodable, Equatable {
        let id: String
        let optionId: String?
        let signerName: String
        let acceptedAt: String
        let totalAmount: Double
    }

    var canApprovePlainly: Bool {
        status == .sent
            && nonce != nil
            && allowedActions.contains("approve")
            && approvalWithoutSignatureAllowed == true
            && options?.isEmpty != false
            && scopeLines?.isEmpty == false
    }

    var signingOffered: Bool {
        status == .sent
            && nonce != nil
            && allowedActions.contains("approve")
            && html != nil
            && consentText != nil
            && consentVersion != nil
    }

    func canApprove(signerName: String, consent: Bool, selectedOptionID: String?) -> Bool {
        let normalizedName = signerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard signingOffered, contentHash.count >= 15,
              consent, !normalizedName.isEmpty, normalizedName.count <= 120 else { return false }
        if let options, !options.isEmpty {
            return options.contains { $0.id == selectedOptionID }
        }
        return selectedOptionID == nil
    }

    func applying(_ patch: PublicEstimateActionPatch, after decision: PublicEstimateActionDecision) -> Self {
        let nextStatus = patch.status ?? decision.resultingStatus
        return Self(
            kind: patch.kind ?? kind,
            title: patch.title ?? title,
            status: nextStatus,
            revisionNumber: patch.revisionNumber ?? revisionNumber,
            contentHash: patch.contentHash ?? contentHash,
            allowedActions: patch.allowedActions ?? (nextStatus == .sent ? allowedActions : []),
            nonce: nextStatus == .sent ? patch.nonce ?? nonce : nil,
            totalAmount: patch.totalAmount ?? totalAmount,
            currency: patch.currency ?? currency,
            html: patch.html ?? html,
            approvalWithoutSignatureAllowed: patch.approvalWithoutSignatureAllowed ?? approvalWithoutSignatureAllowed,
            scopeLines: patch.scopeLines ?? scopeLines,
            options: patch.options ?? options,
            consentVersion: patch.consentVersion ?? consentVersion,
            consentText: patch.consentText ?? consentText,
            acceptance: patch.acceptance ?? acceptance
        )
    }

    var canDecline: Bool { status == .sent && nonce != nil && allowedActions.contains("decline") }
    var canRequestChanges: Bool { status == .sent && nonce != nil && allowedActions.contains("request_changes") }
}

struct PublicEstimateActionPatch: Decodable {
    let kind: String?
    let title: String?
    let status: PublicEstimateAction.Status?
    let revisionNumber: Int?
    let contentHash: String?
    let allowedActions: [String]?
    let nonce: String?
    let totalAmount: Double?
    let currency: String?
    let html: String?
    let approvalWithoutSignatureAllowed: Bool?
    let scopeLines: [PublicEstimateAction.ScopeLine]?
    let options: [PublicEstimateAction.Option]?
    let consentVersion: String?
    let consentText: String?
    let acceptance: PublicEstimateAction.Acceptance?
}

@MainActor
final class PublicEstimateActionModel: ObservableObject {
    @Published private(set) var action: PublicEstimateAction?
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var loadError: String?
    @Published private(set) var actionError: String?
    @Published private(set) var unavailableMessage: String?
    /// The failure behind `loadError` / `actionError` when it came from the server or the network,
    /// so the screen can say it in the customer's words instead of the raw text.
    private(set) var loadFailure: Error?
    private(set) var actionFailure: Error?
    @Published var selectedOptionID: String?
    @Published var signerName = ""
    @Published var consent = false
    @Published var changeMessage = ""
    private var currentToken: String?
    private var loadGeneration = 0
    private var flowGeneration = 0

    func load(api: APIClient, token: String) async {
        guard !(isLoading && currentToken == token) else { return }
        if currentToken != token {
            currentToken = token
            flowGeneration += 1
            action = nil
            selectedOptionID = nil
            signerName = ""
            consent = false
            changeMessage = ""
            actionError = nil
            loadError = nil
            unavailableMessage = nil
            isSubmitting = false
        }
        loadGeneration += 1
        let requestGeneration = loadGeneration
        isLoading = true
        loadError = nil
        loadFailure = nil
        actionError = nil
        actionFailure = nil
        unavailableMessage = nil
        defer {
            if requestGeneration == loadGeneration {
                isLoading = false
            }
        }
        do {
            let loaded = try await api.publicDocumentAction(token: token)
            guard requestGeneration == loadGeneration, currentToken == token else { return }
            action = loaded
        } catch is CancellationError {
            return
        } catch {
            guard requestGeneration == loadGeneration, currentToken == token else { return }
            if Self.isUnavailable(error) {
                unavailableMessage = "This estimate link is expired, replaced, or no longer current. Ask the company for a new link."
            } else {
                loadFailure = error
                loadError = error.localizedDescription
            }
            action = nil
        }
    }

    func submit(_ decision: PublicEstimateActionDecision, api: APIClient, token: String) async {
        guard !isSubmitting, currentToken == token, let current = action else { return }
        guard Self.matchesCurrentRevision(decision, action: current), Self.isAllowed(decision, by: current) else {
            actionFailure = nil
            actionError = "This estimate no longer allows that action. Reload the link and review the current estimate."
            return
        }
        let requestGeneration = flowGeneration
        isSubmitting = true
        actionError = nil
        actionFailure = nil
        defer {
            if requestGeneration == flowGeneration {
                isSubmitting = false
            }
        }
        do {
            let patch = try await api.decidePublicDocumentAction(token: token, decision: decision)
            guard requestGeneration == flowGeneration, currentToken == token else { return }
            action = current.applying(patch, after: decision)
            selectedOptionID = nil
            signerName = ""
            consent = false
            changeMessage = ""
        } catch is CancellationError {
            return
        } catch {
            guard requestGeneration == flowGeneration, currentToken == token else { return }
            if Self.isUnavailable(error) {
                action = nil
                selectedOptionID = nil
                signerName = ""
                consent = false
                unavailableMessage = "This estimate changed or this link can no longer be used. Ask the company for a current estimate link."
            } else {
                actionFailure = error
                actionError = error.localizedDescription
            }
        }
    }

    private static func isAllowed(_ decision: PublicEstimateActionDecision, by action: PublicEstimateAction) -> Bool {
        switch decision {
        case let .approve(_, _, contentHash, signerName, consentVersion, consent, optionID):
            return contentHash == action.contentHash
                && consentVersion == action.consentVersion
                && action.canApprove(signerName: signerName, consent: consent, selectedOptionID: optionID)
        case .approvePlainly:
            return action.canApprovePlainly
        case .decline:
            return action.canDecline
        case let .requestChanges(_, _, message):
            return action.canRequestChanges && (message?.count ?? 0) <= 500
        }
    }

    private static func matchesCurrentRevision(_ decision: PublicEstimateActionDecision, action: PublicEstimateAction) -> Bool {
        switch decision {
        case let .approve(revision, nonce, _, _, _, _, _),
             let .approvePlainly(revision, nonce),
             let .decline(revision, nonce),
             let .requestChanges(revision, nonce, _):
            return revision == action.revisionNumber && nonce == action.nonce
        }
    }

    private static func isUnavailable(_ error: Error) -> Bool {
        guard let problem = error as? Problem else { return false }
        return [401, 403, 404, 409, 410].contains(problem.status ?? 0)
    }
}

enum PublicEstimateActionDecision: Equatable {
    case approve(
        revisionNumber: Int,
        nonce: String,
        contentHash: String,
        signerName: String,
        consentVersion: String,
        consent: Bool,
        optionID: String?
    )
    case approvePlainly(revisionNumber: Int, nonce: String)
    case decline(revisionNumber: Int, nonce: String)
    case requestChanges(revisionNumber: Int, nonce: String, message: String?)

    var endpoint: String {
        switch self {
        case .approve, .approvePlainly: "approve"
        case .decline: "decline"
        case .requestChanges: "request-changes"
        }
    }

    var resultingStatus: PublicEstimateAction.Status {
        switch self {
        case .approve, .approvePlainly: .approved
        case .decline: .declined
        case .requestChanges: .changesRequested
        }
    }

    var body: PublicEstimateDecisionBody {
        switch self {
        case let .approve(revisionNumber, nonce, contentHash, signerName, consentVersion, consent, optionID):
            return PublicEstimateDecisionBody(
                revisionNumber: revisionNumber,
                nonce: nonce,
                contentHash: contentHash,
                optionId: optionID,
                signerName: signerName.trimmingCharacters(in: .whitespacesAndNewlines),
                consentVersion: consentVersion,
                consent: consent
            )
        case let .approvePlainly(revisionNumber, nonce), let .decline(revisionNumber, nonce):
            return PublicEstimateDecisionBody(revisionNumber: revisionNumber, nonce: nonce)
        case let .requestChanges(revisionNumber, nonce, message):
            let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
            return PublicEstimateDecisionBody(revisionNumber: revisionNumber, nonce: nonce, message: trimmed?.isEmpty == false ? trimmed : nil)
        }
    }
}

struct PublicEstimateDecisionBody: Encodable {
    let revisionNumber: Int
    let nonce: String
    var message: String? = nil
    var contentHash: String? = nil
    var optionId: String? = nil
    var signerName: String? = nil
    var consentVersion: String? = nil
    var consent: Bool? = nil
}

enum PublicEstimateActionLink {
    static func token(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil
        else { return nil }

        let parts = components.path.split(separator: "/").map(String.init)
        let candidate: String?
        if components.scheme?.lowercased() == "https",
           components.host?.lowercased() == "app.thorbis.com",
           parts.count == 3,
           parts[0] == "app",
           parts[1] == "d" {
            candidate = parts[2]
        } else if components.scheme?.lowercased() == "https",
                  components.host?.lowercased() == "app.thorbis.com",
                  parts.count == 2,
                  parts[0] == "d" {
            candidate = parts[1]
        } else if components.scheme?.lowercased() == "thorbis",
                  components.host?.lowercased() == "document",
                  parts.count == 1 {
            candidate = parts[0]
        } else {
            candidate = nil
        }
        guard let candidate, isSafeToken(candidate), candidate != "return" else { return nil }
        return candidate
    }

    static func apiPath(token: String, action: String? = nil) throws -> String {
        guard isSafeToken(token), token != "return" else {
            throw Problem(title: "Invalid estimate link", status: nil, detail: "This Thorbis link is not valid.")
        }
        let suffix = action.map { "/\($0)" } ?? ""
        return "/v1/public/document-actions/\(token)\(suffix)"
    }

    private static func isSafeToken(_ token: String) -> Bool {
        !token.isEmpty
            && token.count <= 256
            && token != "."
            && token != ".."
            && token.unicodeScalars.allSatisfy { scalar in
                (48...57).contains(scalar.value)
                    || (65...90).contains(scalar.value)
                    || (97...122).contains(scalar.value)
                    || scalar == "-"
                    || scalar == "_"
                    || scalar == "."
            }
    }
}

extension APIClient {
    func publicDocumentAction(token: String) async throws -> PublicEstimateAction {
        let path = try PublicEstimateActionLink.apiPath(token: token)
        return try await sendPublic("GET", path)
    }

    func decidePublicDocumentAction(
        token: String,
        decision: PublicEstimateActionDecision
    ) async throws -> PublicEstimateActionPatch {
        let path = try PublicEstimateActionLink.apiPath(token: token, action: decision.endpoint)
        return try await sendPublic("POST", path, body: decision.body)
    }
}
