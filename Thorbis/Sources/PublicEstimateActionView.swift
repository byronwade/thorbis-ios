import SwiftUI
import WebKit
import UIKit

struct PublicEstimateActionView: View {
    let token: String
    let onClose: () -> Void

    @EnvironmentObject private var api: APIClient
    @StateObject private var model = PublicEstimateActionModel()
    @FocusState private var focusedField: FocusedField?
    @State private var confirmsDecline = false

    private enum FocusedField: Hashable { case signer, message }

    private var selectedOption: PublicEstimateAction.Option? {
        model.action?.options?.first { $0.id == model.selectedOptionID }
    }

    private var approvalEnabled: Bool {
        guard let action = model.action, action.amountsAvailableForApproval else { return false }
        if action.signingOffered {
            return action.canApprove(signerName: model.signerName, consent: model.consent, selectedOptionID: model.selectedOptionID)
        }
        return action.canApprovePlainly
    }

    private var footerBottomPadding: CGFloat {
        #if DEBUG
        return PaperPreview.enabled ? 36 : 8
        #else
        return 8
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            brandBar
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.isLoading && model.action == nil {
                        CustomerSkeleton(caption: "Opening your estimate…")
                    } else if let message = model.unavailableMessage {
                        unavailableState(message)
                    } else if let message = model.loadError {
                        loadFailureState(message)
                    } else if let action = model.action {
                        estimateContent(action)
                    } else {
                        CustomerStateMessage(symbol: "doc.text.magnifyingglass", title: "This estimate isn’t available",
                                             message: "This link couldn’t be opened. Ask the company for a new link.",
                                             actionTitle: "Close", action: onClose)
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, PaperCardMetrics.margin)
                .padding(.top, 4)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.background)
        .task(id: token) { await model.load(api: api, token: token) }
        .thorbisConfirm("Decline this estimate?",
                        message: "The company will be notified that you declined this estimate.",
                        isPresented: $confirmsDecline,
                        actions: [ThorbisConfirmAction("Decline estimate", role: .destructive) { decline() }])
        .onChange(of: model.signerName) { _, value in
            if value.count > 120 { model.signerName = String(value.prefix(120)) }
        }
        .onChange(of: model.changeMessage) { _, value in
            if value.count > 500 { model.changeMessage = String(value.prefix(500)) }
        }
        .onChange(of: model.isSubmitting) { _, submitting in
            if submitting { UIAccessibility.post(notification: .announcement, argument: "Saving your estimate decision. Please wait.") }
        }
        .onChange(of: model.actionError) { _, message in
            if let message { UIAccessibility.post(notification: .announcement, argument: message) }
        }
        .onChange(of: model.action?.status) { _, status in
            guard let status, status != .sent else { return }
            let message: String = switch status {
            case .approved: "Estimate approved."
            case .declined: "Estimate declined."
            case .changesRequested: "Changes requested."
            case .sent: "Estimate sent."
            }
            UIAccessibility.post(notification: .announcement, argument: message)
        }
        .accessibilityIdentifier("public-estimate-action")
    }

    private var brandBar: some View {
        HStack(spacing: 9) {
            // Paper 39E draws no brand bar: the page is the company's estimate. Closing stays, as
            // Paper's quiet 44pt close circle (37) in the leading corner.
            Button(action: onClose) {
                PaperIcon(.closeLarge, size: 20, color: Theme.foreground)
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Close estimate")
            Spacer()
        }
        .padding(.horizontal, PaperCardMetrics.margin)
        .padding(.top, 2)
        .background(Theme.background)
    }

    /// Paper 39E: the brand commit sits right under the estimate, above "Ask for changes".
    @ViewBuilder
    private var approvalButton: some View {
        if let action = model.action,
           action.signingOffered || action.plainApprovalOffered {
            VStack(spacing: 6) {
                Button(action: approve) {
                    HStack(spacing: 8) {
                        if model.isSubmitting { ProgressView().tint(.white) }
                        Text(approvalTitle(action)).font(Theme.font(16, weight: .semibold))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(approvalEnabled ? Color.white : Theme.muted)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    // Paper v2: the commit is a brand pill.
                    .background(approvalEnabled ? Theme.brand : Theme.fill, in: Capsule())
                }
                .disabled(!approvalEnabled || model.isSubmitting)
                .accessibilityIdentifier("public-estimate-approve")
                .accessibilityHint(approvalEnabled ? "Records approval of this issued estimate." : (action.amountsAvailableForApproval ? "Choose an option, enter your name, and provide consent to continue." : "The amount cannot be verified. Ask the company for an updated estimate."))
                if !action.amountsAvailableForApproval {
                    Text("We can’t verify the estimate amount. Ask the company for an updated estimate.")
                        .font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.isSubmitting {
                    Text("Saving your decision. Wait for confirmation.")
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    @ViewBuilder
    private func estimateContent(_ action: PublicEstimateAction) -> some View {
        // Paper 39E: a centred hero. The quiet label, the price in the largest Bold, what it is for.
        VStack(alignment: .center, spacing: 2) {
            // Paper 39E shows no status over an estimate still waiting on the customer.
            if action.status != .sent { statusLabel(action.status) }
            // MF-01/CP-02: the price is the biggest thing on the estimate, labelled.
            // Paper 39E: the price is the hero (52 Bold), what it is for under it (15). Paper also
            // names the business above and "valid 30 days"; the link's payload carries neither.
            Text(money(selectedOption?.totalAmount ?? action.totalAmount, currency: selectedOption?.currency ?? action.currency))
                .font(Theme.paymentAmountFont()).tracking(Theme.paymentAmountTracking)
                .lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(Theme.foreground)
                .accessibilityIdentifier("public-estimate-total")
                .padding(.top, 6)
            Text(action.title)
                .font(Theme.font(15))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity)

        if let message = model.actionError {
            // The server's own words are for staff; a homeowner reads what happened and what to do.
            CustomerProblemBanner(message: model.actionFailure?.customerSentence(.approve, handBack: false) ?? message)
        }

        if let preview = action.html {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Issued estimate")
                IssuedEstimatePreview(html: preview)
                    .frame(height: 470)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .accessibilityLabel("Issued estimate document preview")
            }
        } else if let lines = action.scopeLines, !lines.isEmpty {
            // Paper 39E: the lines on one card with hairlines between, then the total row.
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.description).font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(quantity(line.quantity)) × \(money(line.unitPrice, currency: action.currency)) each")
                                .font(Theme.font(14)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Text(action.currency == "USD" ? (PublicEstimateMoney.lineTotal(quantity: line.quantity, unitPrice: line.unitPrice).map { PublicEstimateMoney.format(cents: $0) } ?? "Amount unavailable") : "Amount unavailable")
                            .font(Theme.font(16, weight: .medium)).foregroundStyle(Theme.foreground)
                    }
                    .padding(.vertical, 14)
                    if index != lines.count - 1 { WellDivider(leading: 0) }
                }
                WellDivider(leading: 0)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Total").font(Theme.font(15)).foregroundStyle(Theme.muted)
                    Spacer(minLength: 8)
                    Text(money(action.totalAmount, currency: action.currency))
                        .font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
                }
                .padding(.vertical, 14)
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }

        if action.status == .approved {
            statusCard(title: "Approved", symbol: "checkmark.circle.fill", color: Theme.success) {
                if let acceptance = action.acceptance {
                    Text("Your approval was saved for \(money(acceptance.totalAmount, currency: action.currency)). Signed by \(acceptance.signerName).")
                } else {
                    Text("The company has your approval for the issued revision.")
                }
            }
        } else if action.status == .declined {
            statusCard(title: "Declined", symbol: "xmark.circle.fill", color: Theme.muted) {
                Text("No further action is needed on this link.")
            }
        } else if action.status == .changesRequested {
            statusCard(title: "Changes requested", symbol: "bubble.left.and.bubble.right.fill", color: Theme.brand) {
                Text("The company will send a new estimate. This issued paper remains unchanged.")
            }
        } else {
            approvalForm(action)
            // Paper 39E: the actions 10 apart, 16 under the estimate.
            VStack(spacing: 10) {
                approvalButton
                customerActions(action)
            }
            .padding(.top, -2)
        }
    }

    @ViewBuilder
    private func approvalForm(_ action: PublicEstimateAction) -> some View {
        if action.signingOffered {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Review and approve")
                Text("Approval uses the issued scope and price. Your name records who approved it.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                if let options = action.options, !options.isEmpty {
                    Text("Choose one complete option")
                        .font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                    ForEach(options) { option in optionButton(option) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Full name").font(Theme.font(15, weight: .medium)).foregroundStyle(Theme.foreground)
                    TextField("Type your name", text: $model.signerName, prompt: .placeholder("Type your name"))
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focusedField, equals: .signer)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityLabel("Full name for electronic signature")
                }
                if let consentText = action.consentText {
                    Toggle(isOn: $model.consent) {
                        Text(consentText).font(Theme.font(15)).foregroundStyle(Theme.foreground)
                    }
                    .tint(Theme.brand)
                    .padding(16)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("public-estimate-consent")
                }
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        } else if action.canApprovePlainly {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Approve without signing")
                Text("This records your approval of the issued scope and price without an electronic signature.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                ForEach(action.scopeLines ?? []) { line in
                    Label("\(line.description) — \(quantity(line.quantity)) × \(money(line.unitPrice, currency: action.currency)) each", systemImage: "checkmark")
                        .font(Theme.font(15)).monospacedDigit().foregroundStyle(Theme.foreground)
                }
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    private func optionButton(_ option: PublicEstimateAction.Option) -> some View {
        let selected = model.selectedOptionID == option.id
        return Button { model.selectedOptionID = option.id } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(option.title).font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.foreground)
                        Spacer(minLength: 6)
                        Text(money(option.totalAmount, currency: option.currency)).moneyStyle(.total).foregroundStyle(Theme.foreground)
                    }
                    Text(option.description).font(Theme.font(15)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(selected ? Theme.brand : Theme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(selected ? Theme.brandSurface : Theme.fill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.brand, lineWidth: selected ? 1.5 : 0))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("estimate-option-\(option.id)")
        .disabled(model.isSubmitting)
    }

    @ViewBuilder
    private func customerActions(_ action: PublicEstimateAction) -> some View {
        if action.canRequestChanges || action.canDecline {
            // Paper 39E: on the canvas under the approval. The quiet "Ask for changes" pill, the box
            // for what to change, then "Decline" as red words.
            VStack(alignment: .leading, spacing: 10) {
                if action.canRequestChanges {
                    Button {
                        focusedField = nil
                        guard let nonce = action.nonce else { return }
                        Task {
                            await model.submit(.requestChanges(revisionNumber: action.revisionNumber, nonce: nonce, message: model.changeMessage), api: api, token: token)
                        }
                    } label: {
                        Text(model.isSubmitting ? "Sending request…" : "Ask for changes")
                            .font(Theme.font(16, weight: .semibold))
                            .foregroundStyle(Theme.foreground)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Theme.quietFill, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSubmitting)
                    .accessibilityIdentifier("public-estimate-request-changes")
                    TextField("Tell us what to change", text: $model.changeMessage, prompt: .placeholder("Tell us what to change"), axis: .vertical)
                        .lineLimit(3...5)
                        .focused($focusedField, equals: .message)
                        .font(Theme.font(16))
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .frame(minHeight: 96, alignment: .topLeading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityLabel("Message requesting estimate changes")
                    HStack {
                        Text("The company will send a new estimate.").font(Theme.font(13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text("\(model.changeMessage.count)/500").font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 4)
                }
                if action.canDecline {
                    Button(role: .destructive) { confirmsDecline = true } label: {
                        Text("Decline")
                            .font(Theme.font(16, weight: .semibold))
                            .foregroundStyle(Theme.destructive)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSubmitting)
                    .accessibilityLabel("Decline estimate")
                    .accessibilityIdentifier("public-estimate-decline")
                }
            }
        }
    }

    private func statusLabel(_ status: PublicEstimateAction.Status) -> some View {
        let (title, color): (String, Color) = switch status {
        case .sent: ("Sent", Theme.brand)
        case .approved: ("Approved", Theme.success)
        case .declined: ("Declined", Theme.muted)
        case .changesRequested: ("Changes requested", Theme.warning)
        }
        return Text(title.uppercased())
            .font(Theme.font(15, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color.opacity(0.11), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Estimate status: \(title)")
    }

    private func statusCard<Content: View>(title: String, symbol: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(Theme.font(15, weight: .semibold)).foregroundStyle(color)
            content().font(Theme.font(15)).foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// The link itself has ended: nothing here can fix it, so the one action is Close.
    private func unavailableState(_ message: String) -> some View {
        CustomerStateMessage(symbol: "link.badge.exclamationmark", title: "This estimate link has ended",
                             message: message, actionTitle: "Close", action: onClose)
    }

    private func loadFailureState(_ message: String) -> some View {
        CustomerStateMessage(symbol: (model.loadFailure.map { ProblemKind($0) } ?? .other).symbol,
                             title: "We couldn’t open this estimate",
                             message: model.loadFailure is DecodingError || (model.loadFailure as? Problem)?.title == "Invalid API response"
                                ? "We couldn’t verify this estimate. Ask the company for an updated estimate."
                                : (model.loadFailure?.customerSentence(.openEstimate, handBack: false)
                                    ?? "Opening your estimate didn’t work. Try again in a moment."),
                             actionTitle: "Try again") { Task { await model.load(api: api, token: token) } }
            .disabled(model.isLoading)
    }

    private func sectionTitle(_ value: String) -> some View {
        Text(value).font(Theme.font(15, weight: .semibold)).foregroundStyle(Theme.foreground)
    }

    private func approvalTitle(_ action: PublicEstimateAction) -> String {
        if model.isSubmitting { return "Saving approval…" }
        if !action.amountsAvailableForApproval { return "Amount unavailable" }
        if action.signingOffered, let options = action.options, !options.isEmpty, selectedOption == nil {
            return "Choose an option to approve"
        }
        let amount = selectedOption?.totalAmount ?? action.totalAmount
        // Paper 39E: "Approve · $340.00".
        return "Approve \u{00B7} \(money(amount, currency: selectedOption?.currency ?? action.currency))"
    }

    private func approve() {
        guard approvalEnabled, let action = model.action, let nonce = action.nonce else { return }
        focusedField = nil
        let decision: PublicEstimateActionDecision
        if action.signingOffered, let consentVersion = action.consentVersion {
            decision = .approve(
                revisionNumber: action.revisionNumber,
                nonce: nonce,
                contentHash: action.contentHash,
                signerName: model.signerName,
                consentVersion: consentVersion,
                consent: model.consent,
                optionID: model.selectedOptionID
            )
        } else {
            decision = .approvePlainly(revisionNumber: action.revisionNumber, nonce: nonce)
        }
        Task { await model.submit(decision, api: api, token: token) }
    }

    private func decline() {
        guard let action = model.action, let nonce = action.nonce else { return }
        Task {
            await model.submit(.decline(revisionNumber: action.revisionNumber, nonce: nonce), api: api, token: token)
        }
    }
}

private struct IssuedEstimatePreview: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        context.coordinator.load(html, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(html, in: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private var loadedHTML: String?

        func load(_ html: String, in webView: WKWebView) {
            guard loadedHTML != html else { return }
            loadedHTML = html
            webView.loadHTMLString(Self.sanitized(html), baseURL: nil)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType != .linkActivated,
                  let scheme = navigationAction.request.url?.scheme?.lowercased(),
                  ["about", "data"].contains(scheme)
            else { decisionHandler(.cancel); return }
            decisionHandler(.allow)
        }

        private static func sanitized(_ raw: String) -> String {
            var html = raw
            let patterns = [
                #"(?is)<\s*(script|iframe|object|embed|form)\b[^>]*>.*?<\s*/\s*\1\s*>"#,
                #"(?is)\s+on[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#,
                #"(?is)\s+(?:src|href)\s*=\s*(?:"https?://[^"]*"|'https?://[^']*'|https?://[^\s>]+)"#
            ]
            for pattern in patterns {
                guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(html.startIndex..<html.endIndex, in: html)
                html = expression.stringByReplacingMatches(in: html, range: range, withTemplate: "")
            }
            return html
        }
    }
}

private func money(_ amount: Double, currency: String) -> String {
    PublicEstimateMoney.format(amount, currency: currency) ?? "Amount unavailable"
}

private func quantity(_ amount: Double) -> String {
    amount.formatted(.number.precision(.fractionLength(0...2)))
}
