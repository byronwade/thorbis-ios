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
        guard let action = model.action else { return false }
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
            Rectangle().fill(Theme.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.isLoading && model.action == nil {
                        ProgressView("Opening estimate…")
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else if let message = model.unavailableMessage {
                        unavailableState(message)
                    } else if let message = model.loadError {
                        loadFailureState(message)
                    } else if let action = model.action {
                        estimateContent(action)
                    } else {
                        ContentUnavailableView("Estimate unavailable", systemImage: "doc.text.magnifyingglass", description: Text("This link could not be opened."))
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { approvalFooter }
        .task(id: token) { await model.load(api: api, token: token) }
        .confirmationDialog("Decline this estimate?", isPresented: $confirmsDecline, titleVisibility: .visible) {
            Button("Decline estimate", role: .destructive) { decline() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The company will be notified that you declined this estimate.")
        }
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
            ThorbisLogoLockup(markSize: 30, wordmarkSize: 16)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close estimate")
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(minHeight: 56)
        .background(Theme.surface)
    }

    @ViewBuilder
    private var approvalFooter: some View {
        if let action = model.action, action.signingOffered || action.canApprovePlainly {
            VStack(spacing: 5) {
                Button(action: approve) {
                    HStack(spacing: 8) {
                        if model.isSubmitting { ProgressView().tint(.white) }
                        Text(approvalTitle(action)).font(Theme.font(15, weight: .semibold))
                    }
                    .foregroundStyle(approvalEnabled ? Color.white : Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(approvalEnabled ? Theme.brand : Theme.fill, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!approvalEnabled || model.isSubmitting)
                .accessibilityIdentifier("public-estimate-approve")
                .accessibilityHint(approvalEnabled ? "Records approval of this issued estimate." : "Choose an option, enter your name, and provide consent to continue.")
                if model.isSubmitting {
                    Text("Saving your decision. Wait for confirmation.")
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, footerBottomPadding)
            .background(Theme.surface)
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        }
    }

    @ViewBuilder
    private func estimateContent(_ action: PublicEstimateAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            statusLabel(action.status)
            Text(action.title)
                .font(Theme.font(26, weight: .semibold))
                .tracking(-0.35)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text("Revision \(action.revisionNumber) · \(money(selectedOption?.totalAmount ?? action.totalAmount, currency: action.currency))")
                .font(Theme.monoFont(13, weight: .medium))
                .foregroundStyle(Theme.muted)
        }

        if let message = model.actionError {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(Theme.font(13))
                .foregroundStyle(Theme.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: 12))
        }

        if let preview = action.html {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Issued estimate")
                IssuedEstimatePreview(html: preview)
                    .frame(height: 470)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
                    .accessibilityLabel("Issued estimate document preview")
            }
        } else if let lines = action.scopeLines, !lines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Issued scope")
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(line.description).font(Theme.font(14, weight: .medium)).foregroundStyle(Theme.foreground)
                                Text("\(quantity(line.quantity)) × \(money(line.unitPrice, currency: action.currency)) each")
                                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 8)
                            Text(money(line.quantity * line.unitPrice, currency: action.currency))
                                .font(Theme.monoFont(13, weight: .medium)).foregroundStyle(Theme.foreground)
                        }
                        .padding(.vertical, 12)
                        if index != lines.count - 1 { Rectangle().fill(Theme.border).frame(height: 1) }
                    }
                }
                .padding(.horizontal, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
            }
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
            customerActions(action)
        }
    }

    @ViewBuilder
    private func approvalForm(_ action: PublicEstimateAction) -> some View {
        if action.signingOffered {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Review and approve")
                Text("Approval uses the issued scope and price. Your name records who approved it.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                if let options = action.options, !options.isEmpty {
                    Text("Choose one complete option")
                        .font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                    ForEach(options) { option in optionButton(option) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Full name").font(Theme.font(13, weight: .medium)).foregroundStyle(Theme.foreground)
                    TextField("Type your name", text: $model.signerName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focusedField, equals: .signer)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                        .accessibilityLabel("Full name for electronic signature")
                }
                if let consentText = action.consentText {
                    Toggle(isOn: $model.consent) {
                        Text(consentText).font(Theme.font(13)).foregroundStyle(Theme.foreground)
                    }
                    .tint(Theme.brand)
                    .padding(12)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("public-estimate-consent")
                }
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
        } else if action.canApprovePlainly {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Approve without signing")
                Text("This records your approval of the issued scope and price without an electronic signature.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                ForEach(action.scopeLines ?? []) { line in
                    Label("\(line.description) — \(quantity(line.quantity)) × \(money(line.unitPrice, currency: action.currency)) each", systemImage: "checkmark")
                        .font(Theme.font(13)).foregroundStyle(Theme.foreground)
                }
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
        }
    }

    private func optionButton(_ option: PublicEstimateAction.Option) -> some View {
        let selected = model.selectedOptionID == option.id
        return Button { model.selectedOptionID = option.id } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(option.title).font(Theme.font(14, weight: .semibold)).foregroundStyle(Theme.foreground)
                        Spacer(minLength: 6)
                        Text(money(option.totalAmount, currency: option.currency)).font(Theme.monoFont(13, weight: .medium)).foregroundStyle(Theme.foreground)
                    }
                    Text(option.description).font(Theme.font(12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(selected ? Theme.brand : Theme.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(selected ? Theme.brandSurface : Theme.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Theme.brand : Theme.border, lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
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
            VStack(alignment: .leading, spacing: 12) {
                if action.canRequestChanges {
                    sectionTitle("Request changes")
                    TextField("Tell the company what needs clarification", text: $model.changeMessage, axis: .vertical)
                        .lineLimit(3...5)
                        .focused($focusedField, equals: .message)
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                        .accessibilityLabel("Message requesting estimate changes")
                    HStack {
                        Text("The company will send a new estimate.").font(Theme.font(12)).foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(model.changeMessage.count)/500").font(Theme.monoFont(11)).foregroundStyle(Theme.muted)
                    }
                    Button {
                        focusedField = nil
                        guard let nonce = action.nonce else { return }
                        Task {
                            await model.submit(.requestChanges(revisionNumber: action.revisionNumber, nonce: nonce, message: model.changeMessage), api: api, token: token)
                        }
                    } label: {
                        Label(model.isSubmitting ? "Sending request…" : "Request changes", systemImage: "bubble.left")
                            .font(Theme.font(14, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSubmitting)
                    .accessibilityIdentifier("public-estimate-request-changes")
                }
                if action.canDecline {
                    Button(role: .destructive) { confirmsDecline = true } label: {
                        Label("Decline estimate", systemImage: "xmark.circle")
                            .font(Theme.font(14, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Theme.destructiveSurface, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSubmitting)
                    .accessibilityIdentifier("public-estimate-decline")
                }
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
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
            .font(Theme.monoFont(11, weight: .semibold))
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
            content().font(Theme.font(13)).foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func unavailableState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Estimate approval unavailable", systemImage: "link.badge.exclamationmark")
        } description: {
            Text(message)
        }
    }

    private func loadFailureState(_ message: String) -> some View {
        VStack(spacing: 12) {
            ContentUnavailableView("Couldn’t load estimate", systemImage: "wifi.exclamationmark", description: Text(message))
            Button("Try again") { Task { await model.load(api: api, token: token) } }
                .font(Theme.font(14, weight: .semibold))
                .frame(minWidth: 120, minHeight: 44)
                .background(Theme.brandSurface, in: RoundedRectangle(cornerRadius: 10))
                .disabled(model.isLoading)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func sectionTitle(_ value: String) -> some View {
        Text(value).font(Theme.font(16, weight: .semibold)).foregroundStyle(Theme.foreground)
    }

    private func approvalTitle(_ action: PublicEstimateAction) -> String {
        if model.isSubmitting { return "Saving approval…" }
        if action.signingOffered, let options = action.options, !options.isEmpty, selectedOption == nil {
            return "Choose an option to approve"
        }
        let amount = selectedOption?.totalAmount ?? action.totalAmount
        return "Approve \(money(amount, currency: selectedOption?.currency ?? action.currency))"
    }

    private func approve() {
        guard let action = model.action, let nonce = action.nonce else { return }
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
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(amount)"
}

private func quantity(_ amount: Double) -> String {
    amount.formatted(.number.precision(.fractionLength(0...2)))
}
